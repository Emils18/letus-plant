import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _fallbackImage =
      'https://images.unsplash.com/photo-1540420773420-3366772f4999?q=80&w=1200&auto=format&fit=crop';

  Future<bool> publishProduct({
    required Map<String, dynamic> productData,
    XFile? imageFile,
  }) async {
    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        debugPrint('ProductService error: No logged-in user.');
        return false;
      }

      final profile = await _supabase
          .from('users')
          .select('id, role, full_name, email')
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        debugPrint('ProductService error: User profile not found.');
        return false;
      }

      final role = profile['role']?.toString().toLowerCase();

      if (role != 'farmer') {
        debugPrint('ProductService error: User is not a farmer.');
        return false;
      }

      final farmerName = profile['full_name']?.toString().trim().isNotEmpty == true
          ? profile['full_name'].toString().trim()
          : 'Local Farmer';

      final name = productData['name']?.toString().trim() ?? '';
      final category = productData['category']?.toString().trim() ?? 'Fresh Lettuce';
      final badge = productData['badge']?.toString().trim() ?? 'AI Verified';
      final description = productData['description']?.toString().trim() ?? 'Fresh lettuce crop.';
      final location = productData['location']?.toString().trim() ?? 'Cebu Farm';

      final price = _toDouble(productData['price']);
      final stock = _toInt(productData['stock']);

      if (name.isEmpty || price <= 0 || stock <= 0) {
        debugPrint('ProductService error: Invalid product form data.');
        return false;
      }

      String? imageUrl = _fallbackImage;

      if (imageFile != null) {
        try {
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
          final bytes = await imageFile.readAsBytes();

          await _supabase.storage.from('products').uploadBinary(fileName, bytes);
          imageUrl = _supabase.storage.from('products').getPublicUrl(fileName);
        } catch (e) {
          debugPrint('Image upload failed, using fallback: $e');
        }
      }

      await _supabase.from('products').insert({
        'farmer_id': user.id,
        'farmer': farmerName,
        'farmer_name': farmerName,
        'name': name,
        'description': description,
        'category': category,
        'price': price,
        'stock': stock,
        'badge': badge,
        'freshness_info': description,
        'image_url': imageUrl,
        'image': imageUrl,
        'location': location,
        'status': 'Available',
        'updated_at': DateTime.now().toIso8601String(),
      });

      return true;
    } on PostgrestException catch (e) {
      debugPrint('ProductService database error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('ProductService error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    try {
      final response = await _supabase
          .from('products')
          .select('''
            id,
            farmer_id,
            farmer,
            farmer_name,
            name,
            description,
            category,
            price,
            stock,
            badge,
            freshness_info,
            image_url,
            image,
            location,
            status,
            archived_at,
            created_at,
            updated_at
          ''')
          .order('created_at', ascending: false);

      final products = List<Map<String, dynamic>>.from(response);

      return products.where((product) {
        final farmerId = product['farmer_id']?.toString().trim();
        final stock = _toInt(product['stock']);

        final active = product['archived_at'] == null &&
            product['status']?.toString().toLowerCase() != 'unlisted';
        product['status'] = !active
            ? 'Unlisted'
            : stock > 0
                ? 'Available'
                : 'Out of Stock';
        return farmerId != null && farmerId.isNotEmpty && active;
      }).toList();
    } on PostgrestException catch (e) {
      debugPrint('ProductService database error: ${e.message}');
      return [];
    } catch (e) {
      debugPrint('ProductService error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFarmerProducts() async {
    try {
      final user = _supabase.auth.currentUser;

      if (user == null) return [];

      final response = await _supabase
          .from('products')
          .select('''
            id,
            farmer_id,
            farmer,
            farmer_name,
            name,
            description,
            category,
            price,
            stock,
            badge,
            freshness_info,
            image_url,
            image,
            location,
            status,
            archived_at,
            created_at,
            updated_at
          ''')
          .eq('farmer_id', user.id)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('ProductService database error: ${e.message}');
      return [];
    } catch (e) {
      debugPrint('ProductService error: $e');
      return [];
    }
  }

  Future<bool> updateFarmerProduct({
    required int productId,
    required Map<String, dynamic> fields,
    XFile? imageFile,
    bool removeImage = false,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    try {
      final payload = Map<String, dynamic>.from(fields);
      if (imageFile != null) {
        final ext = imageFile.name.split('.').last;
        final path = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _supabase.storage.from('products').uploadBinary(path, await imageFile.readAsBytes());
        final url = _supabase.storage.from('products').getPublicUrl(path);
        payload['image'] = url;
        payload['image_url'] = url;
      } else if (removeImage) {
        payload['image'] = null;
        payload['image_url'] = null;
      }
      payload['status'] = _toInt(payload['stock']) > 0 ? 'Available' : 'Out of Stock';
      payload['updated_at'] = DateTime.now().toIso8601String();
      final result = await _supabase.from('products').update(payload)
          .eq('id', productId).eq('farmer_id', user.id).isFilter('archived_at', null)
          .select('id').maybeSingle();
      return result != null;
    } catch (e) {
      debugPrint('ProductService update failed: $e');
      return false;
    }
  }

  Future<bool> restockFarmerProduct(int productId, int amount) async {
    if (amount <= 0) return false;
    try {
      await _supabase.rpc('restock_farmer_product', params: {
        'p_product_id': productId,
        'p_quantity': amount,
      });
      return true;
    } catch (e) {
      debugPrint('ProductService restock failed: $e');
      return false;
    }
  }

  Future<bool> archiveFarmerProduct(int productId) async {
    try {
      await _supabase.rpc('archive_farmer_product', params: {'p_product_id': productId});
      return true;
    } catch (e) {
      debugPrint('ProductService archive failed: $e');
      return false;
    }
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value?.toString() ?? '0') ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '0') ?? 0;
  }
}

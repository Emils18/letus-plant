import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const int maxStock = 2147483647;

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

      final farmerName =
          profile['full_name']?.toString().trim().isNotEmpty == true
          ? profile['full_name'].toString().trim()
          : 'Local Farmer';

      final name = productData['name']?.toString().trim() ?? '';
      final category =
          productData['category']?.toString().trim() ?? 'Fresh Lettuce';
      final badge = productData['badge']?.toString().trim() ?? 'AI Verified';
      final description =
          productData['description']?.toString().trim() ??
          'Fresh lettuce crop.';
      final location =
          productData['location']?.toString().trim() ?? 'Cebu Farm';

      final price = _toDouble(productData['price']);
      final stock = _toInt(productData['stock']);

      if (name.isEmpty ||
          !price.isFinite ||
          price <= 0 ||
          stock <= 0 ||
          stock > maxStock) {
        debugPrint('ProductService error: Invalid product form data.');
        return false;
      }

      String? imageUrl = _fallbackImage;

      if (imageFile != null) {
        try {
          final fileName =
              '${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
          final bytes = await imageFile.readAsBytes();

          await _supabase.storage
              .from('products')
              .uploadBinary(fileName, bytes);
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
            created_at,
            updated_at
          ''')
          .or('status.is.null,status.eq.Available')
          .isFilter('archived_at', null)
          .order('created_at', ascending: false);

      final products = List<Map<String, dynamic>>.from(response);

      return products.where((product) {
        final farmerId = product['farmer_id']?.toString().trim();
        final stock = _toInt(product['stock']);

        return farmerId != null && farmerId.isNotEmpty && stock > 0;
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
            created_at,
            updated_at
          ''')
          .eq('farmer_id', user.id)
          .isFilter('archived_at', null)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      debugPrint('ProductService database error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('ProductService error: $e');
      rethrow;
    }
  }

  Future<bool> updateProduct({
    required Object productId,
    required int? originalStock,
    required Map<String, dynamic> productData,
    XFile? imageFile,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final profile = await _supabase
          .from('users')
          .select('role, full_name')
          .eq('id', user.id)
          .maybeSingle();
      if (profile?['role']?.toString().toLowerCase() != 'farmer') {
        debugPrint('ProductService update blocked: account is not a farmer.');
        return false;
      }

      final ownedProduct = await _supabase
          .from('products')
          .select('id')
          .eq('id', productId)
          .eq('farmer_id', user.id)
          .isFilter('archived_at', null)
          .maybeSingle();
      if (ownedProduct == null) return false;

      final name = productData['name']?.toString().trim() ?? '';
      final category =
          productData['category']?.toString().trim() ?? 'Fresh Lettuce';
      final description = productData['description']?.toString().trim() ?? '';
      final location = productData['location']?.toString().trim() ?? '';
      final price = _toDouble(productData['price']);
      final stock = _toInt(productData['stock']);
      if (name.isEmpty ||
          description.isEmpty ||
          !price.isFinite ||
          price <= 0 ||
          stock < 0 ||
          stock > maxStock) {
        debugPrint('ProductService update rejected: invalid product details.');
        return false;
      }

      String? imageUrl;
      if (imageFile != null) {
        final fileName =
            '${user.id}/${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
        await _supabase.storage
            .from('products')
            .uploadBinary(fileName, await imageFile.readAsBytes());
        imageUrl = _supabase.storage.from('products').getPublicUrl(fileName);
      }

      final farmerName =
          profile?['full_name']?.toString().trim().isNotEmpty == true
          ? profile!['full_name'].toString().trim()
          : 'Local Farmer';
      final stockChanged = stock != (originalStock ?? 0);
      var query = _supabase
          .from('products')
          .update({
            'farmer': farmerName,
            'farmer_name': farmerName,
            'name': name,
            'description': description,
            'freshness_info': description,
            'category': category,
            'price': price,
            'badge': productData['badge']?.toString() ?? 'AI Verified',
            'location': location,
            if (imageUrl != null) ...{'image_url': imageUrl, 'image': imageUrl},
            if (stockChanged) ...{
              'stock': stock,
              'status': stock > 0 ? 'Available' : 'Out of Stock',
            },
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', productId)
          .eq('farmer_id', user.id)
          .isFilter('archived_at', null);
      if (stockChanged) {
        query = originalStock == null
            ? query.isFilter('stock', null)
            : query.eq('stock', originalStock);
      }
      final updated = await query.select('id').maybeSingle();
      return updated != null;
    } on PostgrestException catch (e) {
      debugPrint('ProductService update database error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('ProductService update error: $e');
      return false;
    }
  }

  Future<int?> restockProduct({
    required Object productId,
    required int additionalStock,
  }) async {
    try {
      if (_supabase.auth.currentUser == null ||
          additionalStock <= 0 ||
          additionalStock > maxStock) {
        return null;
      }
      final newStock = await _supabase.rpc(
        'restock_farmer_product',
        params: {'p_product_id': productId, 'p_quantity': additionalStock},
      );
      return newStock == null ? null : _toInt(newStock);
    } on PostgrestException catch (e) {
      debugPrint('ProductService restock database error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('ProductService restock error: $e');
      return null;
    }
  }

  Future<bool?> archiveProduct(Object productId) async {
    try {
      if (_supabase.auth.currentUser == null) return null;
      final archived = await _supabase.rpc(
        'archive_farmer_product',
        params: {'p_product_id': productId},
      );
      if (archived is! Map) return null;
      return archived['has_order_history'] == true;
    } on PostgrestException catch (e) {
      debugPrint('ProductService archive database error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('ProductService archive error: $e');
      return null;
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

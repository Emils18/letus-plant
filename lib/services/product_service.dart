import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _fallbackImage =
      'https://images.unsplash.com/photo-1540420773420-3366772f4999?q=80&w=1200&auto=format&fit=crop';

  Future<bool> publishProduct(Map<String, dynamic> productData) async {
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
      final description = productData['description']?.toString().trim() ??
          'Fresh lettuce crop.';
      final location = productData['location']?.toString().trim() ?? 'Cebu Farm';

      final price = _toDouble(productData['price']);
      final stock = _toInt(productData['stock']);

      if (name.isEmpty || category.isEmpty || price <= 0 || stock <= 0) {
        debugPrint('ProductService error: Invalid product form data.');
        return false;
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
        'image_url': _fallbackImage,
        'image': _fallbackImage,
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
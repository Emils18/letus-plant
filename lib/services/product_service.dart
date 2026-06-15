import '../config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<bool> publishProduct(Map<String, dynamic> productData) async {
    if (AppConfig.isDemoMode) {
      await Future.delayed(const Duration(seconds: 2));
      return true; // Mock success
    }

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      await _supabase.from('products').insert({
        'name': productData['name'],
        'category': productData['category'],
        'price': productData['price'],
        'stock': productData['stock'],
        'farmer_id': user.id,
        'badge': productData['badge'],
        'freshnessInfo': productData['description'],
        'image': 'https://images.unsplash.com/photo-1540420773420-3366772f4999?q=80&w=1200', // Mock image until Storage is wired
      });
      return true;
    } catch (e) {
      print('Error publishing product: $e');
      return false;
    }
  }
}
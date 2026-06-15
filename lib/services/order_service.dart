import 'package:supabase_flutter/supabase_flutter.dart';

class OrderService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch orders assigned to the logged-in farmer
  Future<List<Map<String, dynamic>>> getFarmerOrders() async {
    try {
      final user = _supabase.auth.currentUser;
      
      // If dev bypass is active and no user is logged in, fetch all for testing
      if (user == null) {
        final response = await _supabase
            .from('orders')
            .select('*, order_items(*)')
            .order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(response);
      }

      // Fetch only farmer's orders
      final response = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('farmer_id', user.id)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching orders: $e');
      return [];
    }
  }

  /// Update the fulfillment status of an order
  Future<bool> updateOrderStatus(String orderId, String newStatus) async {
    try {
      await _supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);
      return true;
    } catch (e) {
      print('Error updating status: $e');
      return false;
    }
  }

  /// Placeholder for Proof of Payment / Delivery upload
  Future<bool> uploadProofImage(String orderId, String imagePath) async {
    // Future implementation: Upload to Supabase Storage, then update proof_image_url
    await Future.delayed(const Duration(seconds: 2)); // simulate upload
    return true;
  }
}
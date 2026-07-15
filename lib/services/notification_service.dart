import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<String?> createNotification({
    required String userId,
    required String orderId,
    required String title,
    required String message,
    required String type,
  }) async {
    try {
      print('TRYING TO CREATE NOTIFICATION...');
      print('receiver userId: $userId');
      print('orderId: $orderId');

      final data = await supabase
          .from('notifications')
          .insert({
            'user_id': userId,
            'order_id': orderId,
            'title': title,
            'message': message,
            'type': type,
            'is_read': false,
          })
          .select()
          .single();

      print('NOTIFICATION INSERTED: $data');

      return null;
    } on PostgrestException catch (e) {
      print('NOTIFICATION DATABASE ERROR: ${e.message}');
      print('DETAILS: ${e.details}');
      print('HINT: ${e.hint}');
      print('CODE: ${e.code}');
      return 'Notification database error: ${e.message}';
    } catch (e) {
      print('NOTIFICATION UNKNOWN ERROR: $e');
      return 'Notification error: $e';
    }
  }

  Future<List<Map<String, dynamic>>> getMyNotifications() async {
    final user = supabase.auth.currentUser;

    if (user == null) return [];

    try {
      final data = await supabase
          .from('notifications')
          .select('''
            *,
            orders(
              id,
              order_code,
              status,
              delivery_status,
              total_amount
            )
          ''')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(data);
    } on PostgrestException catch (e) {
      print('getMyNotifications database error: ${e.message}');
      return [];
    } catch (e) {
      print('getMyNotifications error: $e');
      return [];
    }
  }

  Future<int> getUnreadCount() async {
    final user = supabase.auth.currentUser;

    if (user == null) return 0;

    try {
      final data = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_read', false);

      return List.from(data).length;
    } catch (e) {
      print('getUnreadCount error: $e');
      return 0;
    }
  }

  Future<String?> markAsRead(String notificationId) async {
    final user = supabase.auth.currentUser;

    if (user == null) return 'Please login first.';

    try {
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId)
          .eq('user_id', user.id);

      return null;
    } on PostgrestException catch (e) {
      return 'Database error: ${e.message}';
    } catch (e) {
      return 'Mark as read error: $e';
    }
  }

  Future<String?> markAllAsRead() async {
    final user = supabase.auth.currentUser;

    if (user == null) return 'Please login first.';

    try {
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', user.id)
          .eq('is_read', false);

      return null;
    } on PostgrestException catch (e) {
      return 'Database error: ${e.message}';
    } catch (e) {
      return 'Mark all as read error: $e';
    }
  }
}
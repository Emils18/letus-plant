import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'order_detail_screen.dart';
import '../services/notification_service.dart';
import '../services/order_service.dart';

const _green = Color(0xFF2F6B3B);
const _ink = Color(0xFF1E2A1F);
const _page = Color(0xFFF6FBF7);

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _notificationService = NotificationService();
  final OrderService _orderService = OrderService();
  late Future<List<Map<String, dynamic>>> _notificationsFuture;
  bool _markingAllRead = false;

  @override
  void initState() {
    super.initState();
    _notificationsFuture = _notificationService.getMyNotifications();
  }

  Future<void> _refreshNotifications() async {
    setState(() {
      _notificationsFuture = _notificationService.getMyNotifications();
    });
    await _notificationsFuture;
  }

  Future<void> _markAllAsRead() async {
    if (_markingAllRead) return;
    setState(() => _markingAllRead = true);
    final error = await _notificationService.markAllAsRead();
    if (!mounted) return;
    setState(() => _markingAllRead = false);
    if (error != null) {
      _showMessage(error);
      return;
    }
    await _refreshNotifications();
  }

  Future<void> _openNotification(Map<String, dynamic> notification) async {
    final id = notification['id']?.toString() ?? '';
    if (id.isNotEmpty && notification['is_read'] != true) {
      final error = await _notificationService.markAsRead(id);
      if (!mounted) return;
      if (error != null) {
        _showMessage(error);
        return;
      }
      await _refreshNotifications();
    }

    final orderId = notification['order_id']?.toString();
    if (orderId != null && orderId.isNotEmpty) {
      final order = await _orderService.getFarmerOrderById(orderId);
      if (!mounted) return;
      if (order == null) {
        _showMessage(
          'Order details could not be loaded. Pull down to refresh and try again.',
        );
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => OrderDetailScreen(order: order),
        ),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(notification['title']?.toString() ?? 'Notification'),
        content: Text(
          notification['message']?.toString() ?? 'No additional details.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        backgroundColor: _page,
        elevation: 0,
        foregroundColor: _ink,
        centerTitle: true,
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: _ink,
            fontSize: 21,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _markingAllRead ? null : _markAllAsRead,
            child: Text(
              _markingAllRead ? 'Please wait' : 'Read All',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: _green,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _notificationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _green),
            );
          }
          if (snapshot.hasError) {
            return _emptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load notifications',
              message: 'Check your connection, then pull down to try again.',
            );
          }

          final notifications = snapshot.data ?? [];
          if (notifications.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshNotifications,
              color: _green,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                  _emptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'No notifications yet',
                    message:
                        'New orders and delivery updates will appear here.',
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshNotifications,
            color: _green,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              itemCount: notifications.length,
              itemBuilder: (context, index) =>
                  _notificationCard(notifications[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _notificationCard(Map<String, dynamic> notification) {
    final title = notification['title']?.toString() ?? 'Notification';
    final message = notification['message']?.toString() ?? '';
    final type = notification['type']?.toString() ?? '';
    final isRead = notification['is_read'] == true;
    final order = notification['orders'] is Map
        ? Map<String, dynamic>.from(notification['orders'] as Map)
        : <String, dynamic>{};
    final orderId =
        notification['order_id']?.toString() ?? order['id']?.toString() ?? '';
    final orderLabel =
        (order['order_code']?.toString().trim().isNotEmpty == true)
        ? order['order_code'].toString()
        : _shortId(orderId);
    final buyer = order['shipping_name']?.toString().trim().isNotEmpty == true
        ? order['shipping_name'].toString()
        : null;
    final phone = order['shipping_phone']?.toString().trim().isNotEmpty == true
        ? order['shipping_phone'].toString()
        : null;
    final address =
        order['shipping_address']?.toString().trim().isNotEmpty == true
        ? order['shipping_address'].toString()
        : null;
    final total = double.tryParse(order['total_amount']?.toString() ?? '');
    final status = order['status']?.toString();
    final created = DateTime.tryParse(
      notification['created_at']?.toString() ?? '',
    );
    final time = created == null
        ? ''
        : DateFormat('MMM d, yyyy • h:mm a').format(created.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isRead ? Colors.white : const Color(0xFFE8F3EA),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isRead ? const Color(0xFFE4EBE5) : const Color(0xFF71B97A),
          width: isRead ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () => _openNotification(notification),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(_iconForType(type), color: _green, size: 27),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: _ink,
                            ),
                          ),
                          if (time.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              time,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!isRead)
                      const Padding(
                        padding: EdgeInsets.only(top: 5),
                        child: CircleAvatar(radius: 5, backgroundColor: _green),
                      ),
                  ],
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.45,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (orderId.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ORDER  #$orderLabel',
                          style: const TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (buyer != null)
                          _detailLine(Icons.person_outline, 'Buyer: $buyer'),
                        if (phone != null)
                          _detailLine(Icons.phone_outlined, 'Phone: $phone'),
                        if (address != null)
                          _detailLine(
                            Icons.location_on_outlined,
                            'Location: $address',
                          ),
                        if (status != null || total != null) ...[
                          const SizedBox(height: 7),
                          Text(
                            '${status ?? 'Order update'}${total == null ? '' : '  •  ₱${total.toStringAsFixed(2)}'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _ink,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Tap to see full details',
                      style: TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(width: 5),
                    Icon(Icons.arrow_forward_rounded, color: _green, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailLine(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _green, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
  }) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 76, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  String _shortId(String id) =>
      id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();

  IconData _iconForType(String type) {
    if (type == 'new_order') return Icons.shopping_bag_rounded;
    if (type == 'delivery_update') return Icons.local_shipping_rounded;
    if (type == 'confirm_received') return Icons.verified_rounded;
    return Icons.notifications_rounded;
  }
}

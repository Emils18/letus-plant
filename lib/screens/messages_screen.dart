import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'order_chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  static const _green = Color(0xFF2F6B3B);
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _conversations;

  @override
  void initState() {
    super.initState();
    _conversations = _loadConversations();
  }

  Future<List<Map<String, dynamic>>> _loadConversations() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final rows = await _client.from('orders').select(
      'id, order_code, user_id, farmer_id, shipping_name, status, delivery_status, created_at',
    ).or('user_id.eq.${user.id},farmer_id.eq.${user.id}')
      .order('created_at', ascending: false);
    final orders = List<Map<String, dynamic>>.from(rows);
    final counterpartIds = orders.map((order) => order['user_id'] == user.id
        ? order['farmer_id']?.toString()
        : order['user_id']?.toString()).whereType<String>().where((id) => id.isNotEmpty).toSet();
    final names = <String, String>{};
    if (counterpartIds.isNotEmpty) {
      try {
        final profiles = await _client.from('users').select('id, full_name').inFilter('id', counterpartIds.toList());
        for (final profile in profiles) {
          final name = profile['full_name']?.toString().trim() ?? '';
          if (name.isNotEmpty) names[profile['id'].toString()] = name;
        }
      } catch (_) {
        // Use names saved with the order when profile access is restricted.
      }
      final farmerIds = orders.map((order) => order['farmer_id']?.toString()).whereType<String>().where((id) => id.isNotEmpty).toSet();
      if (farmerIds.isNotEmpty) {
        try {
          final products = await _client.from('products').select('farmer_id, farmer_name, farmer').inFilter('farmer_id', farmerIds.toList());
          for (final product in products) {
            final id = product['farmer_id']?.toString() ?? '';
            final name = (product['farmer_name'] ?? product['farmer'])?.toString().trim() ?? '';
            if (id.isNotEmpty && name.isNotEmpty) names.putIfAbsent(id, () => name);
          }
        } catch (_) {
          // Keep profile and order names as the fallback.
        }
      }
    }
    for (final order in orders) {
      final isBuyer = order['user_id'] == user.id;
      final peerId = (isBuyer ? order['farmer_id'] : order['user_id'])?.toString() ?? '';
      final savedName = isBuyer
          ? ''
          : order['shipping_name']?.toString().trim() ?? '';
      order['peer_name'] = names[peerId] ?? (savedName.isNotEmpty ? savedName : isBuyer ? 'Farmer' : 'Buyer');
      try {
        final latest = await _client.from('order_messages').select('message, created_at')
            .eq('order_id', order['id'].toString()).order('created_at', ascending: false).limit(1).maybeSingle();
        if (latest != null) order['latest_message'] = latest;
      } catch (_) {
        // Orders remain available even if a chat has not been created yet.
      }
    }
    return orders;
  }

  Future<void> _refresh() async {
    setState(() => _conversations = _loadConversations());
    await _conversations;
  }

  String _orderRef(Map<String, dynamic> order) {
    final code = order['order_code']?.toString().trim() ?? '';
    final id = code.isNotEmpty ? code : order['id']?.toString() ?? '';
    final segments = id.split(RegExp(r'[-\s]+')).where((part) => part.isNotEmpty).toList();
    final last = segments.isEmpty ? id : segments.last;
    return last.length > 10 ? last.substring(last.length - 10).toUpperCase() : last.toUpperCase();
  }

  String _timestamp(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '';
    final local = date.toLocal();
    final now = DateTime.now();
    return DateFormat(local.year == now.year && local.month == now.month && local.day == now.day ? 'h:mm a' : 'MMM d').format(local);
  }

  String _statusLabel(Map<String, dynamic> order) {
    final delivery = order['delivery_status']?.toString().trim() ?? '';
    final status = order['status']?.toString().trim() ?? '';
    if (delivery.isNotEmpty && delivery.toLowerCase() != 'pending') return delivery;
    return status.isNotEmpty ? status : 'Order';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3F7F3),
    appBar: AppBar(title: const Text('Messages', style: TextStyle(fontWeight: FontWeight.w800)), backgroundColor: Colors.white, foregroundColor: const Color(0xFF1E2A1F), elevation: 0),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _conversations,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: _green));
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.wifi_off_rounded, size: 48, color: _green), const SizedBox(height: 12), const Text('Conversations could not load.', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 8), Text(_loadErrorMessage(snapshot.error!), textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: _refresh, child: const Text('Try again'))])));
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.chat_bubble_outline_rounded, size: 56, color: _green), SizedBox(height: 14), Text('No conversations yet', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), SizedBox(height: 6), Text('Your order chats will appear here.', textAlign: TextAlign.center)])));
        return RefreshIndicator(color: _green, onRefresh: _refresh, child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 9),
          itemBuilder: (context, index) {
            final order = items[index];
            final latest = order['latest_message'] as Map<String, dynamic>?;
            final peer = order['peer_name']?.toString() ?? 'Conversation';
            final status = _statusLabel(order);
            return Material(color: Colors.white, borderRadius: BorderRadius.circular(18), child: InkWell(
              borderRadius: BorderRadius.circular(18), onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => OrderChatScreen(order: order, peerName: peer))),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13), child: Row(children: [
                CircleAvatar(radius: 25, backgroundColor: const Color(0xFFEAF5EB), child: Text(peer.isEmpty ? '?' : peer[0].toUpperCase(), style: const TextStyle(color: _green, fontWeight: FontWeight.w800, fontSize: 18))),
                const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Expanded(child: Text(peer, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1E2A1F)))), Text(_timestamp(latest?['created_at'] ?? order['created_at']), style: const TextStyle(fontSize: 11, color: Color(0xFF778078)))]),
                  const SizedBox(height: 3), Text(latest?['message']?.toString() ?? 'Order #${_orderRef(order)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Color(0xFF59645B))),
                  const SizedBox(height: 7), Row(children: [Text('Order #${_orderRef(order)}', style: const TextStyle(fontSize: 11, color: Color(0xFF778078))), const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFEAF5EB), borderRadius: BorderRadius.circular(12)), child: Text(status, style: const TextStyle(fontSize: 10, color: _green, fontWeight: FontWeight.w700)))])
                ])), const SizedBox(width: 6), const Icon(Icons.chevron_right_rounded, color: Color(0xFF7B887D))
              ])),
            ));
          },
        ));
      },
    ),
  );

  String _loadErrorMessage(Object error) {
    final details = error.toString();
    final normalized = details.toLowerCase();
    if (normalized.contains('order_messages') || normalized.contains('pgrst205')) {
      return 'Order chats are unavailable because the messaging table is missing. Apply the existing order_messages migration, then retry.';
    }
    if (normalized.contains('permission') || normalized.contains('rls') || normalized.contains('42501')) {
      return 'Supabase denied access to these orders. Check the existing order participant policies.';
    }
    return details.isNotEmpty
        ? details
        : 'Check your internet connection, then try again.';
  }
}

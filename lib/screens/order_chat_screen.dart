import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrderChatScreen extends StatefulWidget {
  const OrderChatScreen({
    super.key,
    required this.order,
    required this.peerName,
  });

  final Map<String, dynamic> order;
  final String peerName;

  @override
  State<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends State<OrderChatScreen> {
  static const _green = Color(0xFF2F6B3B);
  static const _ink = Color(0xFF1E2A1F);
  final _client = Supabase.instance.client;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  RealtimeChannel? _orderChannel;
  Timer? _statusPoll;
  Map<String, dynamic> _orderStatus = {};
  late String _peerName;
  bool _loading = true;
  bool _sending = false;
  bool _seenReceiptsAvailable = true;
  String? _error;

  String get _orderId => widget.order['id']?.toString() ?? '';
  String get _shortOrderReference {
    final code = widget.order['order_code']?.toString().trim() ?? '';
    final id = code.isNotEmpty ? code : _orderId;
    final segments = id
        .split(RegExp(r'[-\s]+'))
        .where((part) => part.isNotEmpty);
    final last = segments.isEmpty ? id : segments.last;
    if (code.isEmpty && last.length > 8) {
      return last.substring(0, 8).toUpperCase();
    }
    return last.length > 10
        ? last.substring(last.length - 10).toUpperCase()
        : last.toUpperCase();
  }

  String get _status => (_orderStatus['status'] ?? widget.order['status'] ?? '')
      .toString()
      .trim();
  String get _deliveryStatus =>
      (_orderStatus['delivery_status'] ?? widget.order['delivery_status'] ?? '')
          .toString()
          .trim();
  bool get _chatClosed {
    const terminal = {'delivered', 'received', 'completed'};
    return terminal.contains(_status.toLowerCase()) ||
        terminal.contains(_deliveryStatus.toLowerCase());
  }

  String get _statusLabel {
    const terminal = {'delivered', 'received', 'completed'};
    if (terminal.contains(_deliveryStatus.toLowerCase())) {
      return _titleCase(_deliveryStatus);
    }
    if (_deliveryStatus.isNotEmpty &&
        _deliveryStatus.toLowerCase() != 'pending') {
      return _titleCase(_deliveryStatus);
    }
    return _status.isNotEmpty ? _titleCase(_status) : 'Status unavailable';
  }

  static String _titleCase(String value) => value
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map(
        (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');

  @override
  void initState() {
    super.initState();
    _peerName = widget.peerName.trim().isEmpty
        ? 'Farmer'
        : widget.peerName.trim();
    _loadPeerName();
    _loadMessages();
    _refreshOrderStatus();
    _statusPoll = Timer.periodic(
      const Duration(seconds: 12),
      (_) => _refreshOrderStatus(),
    );
    _channel = _client.channel('order-chat-$_orderId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'order_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'order_id',
          value: _orderId,
        ),
        callback: (_) => _loadMessages(),
      )
      ..subscribe();
    _orderChannel = _client.channel('order-status-$_orderId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: _orderId,
        ),
        callback: (_) => _refreshOrderStatus(),
      )
      ..subscribe();
  }

  Future<void> _loadPeerName() async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) return;
    final farmerId = widget.order['farmer_id']?.toString();
    final isFarmer = farmerId == currentUserId;
    final peerId = isFarmer ? widget.order['user_id']?.toString() : farmerId;
    final fallback = isFarmer
        ? widget.order['shipping_name']?.toString()
        : (widget.order['farmer_name'] ??
                  widget.order['farmer'] ??
                  widget.peerName)
              ?.toString();
    var resolved = fallback?.trim() ?? '';
    if (peerId != null && peerId.isNotEmpty) {
      try {
        final profile = await _client
            .from('users')
            .select('full_name')
            .eq('id', peerId)
            .maybeSingle();
        final fullName = profile?['full_name']?.toString().trim() ?? '';
        if (fullName.isNotEmpty) resolved = fullName;
      } catch (_) {
        // Keep the order's saved name when profile access is unavailable.
      }
      if (!isFarmer && resolved.toLowerCase() == 'farmer') {
        try {
          final product = await _client
              .from('products')
              .select('farmer_name, farmer')
              .eq('farmer_id', peerId)
              .limit(1)
              .maybeSingle();
          final productName =
              (product?['farmer_name'] ?? product?['farmer'])
                  ?.toString()
                  .trim() ??
              '';
          if (productName.isNotEmpty) resolved = productName;
        } catch (_) {
          // The chat still opens with the supplied order name if products are private.
        }
      }
    }
    if (mounted && resolved.isNotEmpty) setState(() => _peerName = resolved);
  }

  @override
  void dispose() {
    if (_channel != null) _client.removeChannel(_channel!);
    if (_orderChannel != null) _client.removeChannel(_orderChannel!);
    _statusPoll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refreshOrderStatus() async {
    try {
      final result = await _client
          .from('orders')
          .select('status, delivery_status')
          .eq('id', _orderId)
          .maybeSingle();
      if (!mounted || result == null) return;
      setState(() => _orderStatus = Map<String, dynamic>.from(result));
    } catch (_) {
      // The order passed to this screen remains the fallback status.
    }
  }

  bool _missingReadAt(Object error) {
    final value = error.toString().toLowerCase();
    return value.contains('read_at') || value.contains('42703');
  }

  Future<void> _loadMessages() async {
    try {
      final data = await _client
          .from('order_messages')
          .select('id, order_id, sender_id, message, created_at, read_at')
          .eq('order_id', _orderId)
          .order('created_at');
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(data);
        _loading = false;
        _seenReceiptsAvailable = true;
        _error = null;
      });
      _scrollToLatest();
      final userId = _client.auth.currentUser?.id;
      if (userId != null) unawaited(_markIncomingMessagesSeen(userId));
    } catch (error) {
      if (_missingReadAt(error)) {
        try {
          final data = await _client
              .from('order_messages')
              .select('id, order_id, sender_id, message, created_at')
              .eq('order_id', _orderId)
              .order('created_at');
          if (!mounted) return;
          setState(() {
            _messages = List<Map<String, dynamic>>.from(data);
            _loading = false;
            _seenReceiptsAvailable = false;
            _error =
                'Apply the chat read receipts SQL update in Supabase to enable Seen.';
          });
          _scrollToLatest();
          return;
        } catch (fallbackError) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = fallbackError.toString().contains('order_messages')
                ? 'Chat database setup is required. Apply the order_messages migration, then retry.'
                : 'Messages could not load. Check your connection and try again.';
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().contains('order_messages')
            ? 'Chat database setup is required. Apply the order_messages migration, then retry.'
            : 'Messages could not load. Check your connection and try again.';
      });
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _markIncomingMessagesSeen(String userId) async {
    try {
      await _client
          .from('order_messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('order_id', _orderId)
          .neq('sender_id', userId)
          .isFilter('read_at', null);
    } catch (_) {
      // Read receipts are optional until the Supabase migration is applied.
    }
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    final user = _client.auth.currentUser;
    if (body.isEmpty || user == null || _sending || _chatClosed) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _client.from('order_messages').insert({
        'order_id': _orderId,
        'sender_id': user.id,
        'message': body,
      });
      _input.clear();
      await _loadMessages();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Message was not sent. Check your internet and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _timeLabel(String? value) {
    final date = DateTime.tryParse(value ?? '');
    return date == null ? '' : DateFormat.jm().format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final userId = _client.auth.currentUser?.id;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F3),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _peerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            Text(
              'Order #$_shortOrderReference',
              style: const TextStyle(fontSize: 12, color: Color(0xFF69766B)),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildOrderStatus(),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: _loadMessages,
                  child: const Text('RETRY'),
                ),
              ],
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _green))
                : _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) => _buildMessage(
                      _messages[index],
                      mine: _messages[index]['sender_id'] == userId,
                      isLastOutgoing:
                          _messages[index]['id'] == _lastOutgoingId(userId),
                    ),
                  ),
          ),
          if (_chatClosed)
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4DE),
                  border: Border.all(color: const Color(0xFFF0D99E)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      color: Color(0xFF875E15),
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Order delivered. This chat is closed, but you can still read messages.',
                        style: TextStyle(
                          color: Color(0xFF6E5018),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildComposer(),
        ],
      ),
    );
  }

  String? _lastOutgoingId(String? userId) {
    if (userId == null) return null;
    for (final message in _messages.reversed) {
      if (message['sender_id'] == userId) return message['id']?.toString();
    }
    return null;
  }

  Widget _buildOrderStatus() {
    final color = _chatClosed ? const Color(0xFF8A6117) : _green;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _chatClosed
              ? const Color(0xFFF0D99E)
              : const Color(0xFFDCE9DD),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _chatClosed
                ? Icons.task_alt_rounded
                : Icons.local_shipping_outlined,
            color: color,
            size: 23,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ORDER STATUS',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.1,
                    color: Color(0xFF758176),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusLabel,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _chatClosed
                  ? const Color(0xFFFFF2D6)
                  : const Color(0xFFEAF5EB),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _chatClosed ? 'CHAT CLOSED' : 'CHAT OPEN',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: const BoxDecoration(
              color: Color(0xFFE5F1E6),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              color: _green,
              size: 29,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Start the conversation',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _chatClosed
                ? 'This order is complete, so new messages are disabled.'
                : 'Send a message about this order.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6F7C71)),
          ),
        ],
      ),
    ),
  );

  Widget _buildMessage(
    Map<String, dynamic> item, {
    required bool mine,
    required bool isLastOutgoing,
  }) {
    final readAt = item['read_at']?.toString();
    final time = _timeLabel(item['created_at']?.toString());
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .78,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: mine ? _green : Colors.white,
                  border: mine
                      ? null
                      : Border.all(color: const Color(0xFFE1E9E2)),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(mine ? 18 : 5),
                    bottomRight: Radius.circular(mine ? 5 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .035),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  item['message']?.toString() ?? '',
                  style: TextStyle(
                    color: mine ? Colors.white : _ink,
                    fontSize: 15.5,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 5, right: 5),
            child: Text(
              [
                if (time.isNotEmpty) time,
                if (mine && isLastOutgoing)
                  readAt != null
                      ? 'Seen'
                      : (_seenReceiptsAvailable ? 'Sent' : 'Seen unavailable'),
              ].join(' · '),
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF748075),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE3EAE3))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Message $_peerName…',
                filled: true,
                fillColor: const Color(0xFFF3F7F3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            width: 48,
            child: IconButton.filled(
              tooltip: 'Send message',
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

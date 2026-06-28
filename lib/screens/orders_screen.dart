import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/order_service.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final OrderService _orderService = OrderService();
  final ImagePicker _imagePicker = ImagePicker();

  late Future<List<Map<String, dynamic>>> _ordersFuture;

  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _orderService.getFarmerOrders();
  }

  void _fetchOrders() {
    setState(() {
      _ordersFuture = _orderService.getFarmerOrders();
    });
  }

  Future<void> _refreshOrders() async {
    _fetchOrders();
    await _ordersFuture;
  }

  Future<void> _updateStatus({
    required String orderId,
    required String status,
  }) async {
    if (orderId.isEmpty) {
      _showMessage('Invalid order.', isError: true);
      return;
    }

    setState(() => _isUpdating = true);

    final error = await _orderService.updateFarmerOrderStatus(
      orderId: orderId,
      status: status,
    );

    if (!mounted) return;

    setState(() => _isUpdating = false);

    if (error != null) {
      _showMessage(error, isError: true);
      return;
    }

    _showMessage('Order marked as $status.');
    _fetchOrders();
  }

  Future<void> _submitDeliveryProof(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString();

    if (orderId == null || orderId.isEmpty) {
      _showMessage('Invalid order.', isError: true);
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    final pickedImage = await _imagePicker.pickImage(
      source: source,
      imageQuality: 80,
    );

    if (pickedImage == null) return;

    setState(() => _isUpdating = true);

    final result = await _orderService.submitDeliveryProof(
      orderId: orderId,
      proofImage: pickedImage,
    );

    if (!mounted) return;

    setState(() => _isUpdating = false);

    if (!result.success) {
      _showMessage(
        result.error ?? 'Failed to submit delivery proof.',
        isError: true,
      );
      return;
    }

    _showMessage('Delivery proof submitted. Order marked as Delivered.');
    _fetchOrders();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF2F6B3B),
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();

    return double.tryParse(value?.toString() ?? '0') ?? 0;
  }

  String _shortOrderId(Map<String, dynamic> order) {
    final orderCode = order['order_code']?.toString();

    if (orderCode != null && orderCode.isNotEmpty) {
      return orderCode;
    }

    final rawId = order['id']?.toString() ?? 'UNKNOWN';

    return rawId.length >= 8 ? rawId.substring(0, 8).toUpperCase() : rawId;
  }

  Color _statusColor(String status) {
    final value = status.toLowerCase();

    if (value.contains('completed') ||
        value.contains('received') ||
        value.contains('delivered') ||
        value.contains('paid')) {
      return const Color(0xFF2F6B3B);
    }

    if (value.contains('cancel')) {
      return Colors.redAccent;
    }

    if (value.contains('preparing') ||
        value.contains('confirmed') ||
        value.contains('shipped') ||
        value.contains('pending')) {
      return Colors.orange;
    }

    return Colors.blueGrey;
  }

  bool _canAccept(String status) {
    final value = status.toLowerCase();
    return value == 'pending';
  }

  bool _canPrepare(String status) {
    final value = status.toLowerCase();
    return value == 'confirmed';
  }

  bool _canShip(String status) {
    final value = status.toLowerCase();
    return value == 'preparing';
  }

  bool _canSubmitProof(String status) {
    final value = status.toLowerCase();
    return value == 'shipped';
  }

  bool _canCancel(String status) {
    final value = status.toLowerCase();

    return value == 'pending' ||
        value == 'confirmed' ||
        value == 'preparing';
  }

  bool _isFinalStatus(String status) {
    final value = status.toLowerCase();

    return value == 'delivered' ||
        value == 'completed' ||
        value == 'received' ||
        value == 'cancelled';
  }

  String _nextStepText(String status) {
    final value = status.toLowerCase();

    if (value == 'pending') return 'Next step: Accept the buyer order.';
    if (value == 'confirmed') return 'Next step: Mark order as Preparing.';
    if (value == 'preparing') return 'Next step: Mark order as Shipped.';
    if (value == 'shipped') return 'Next step: Submit delivery proof.';
    if (value == 'delivered') return 'Waiting for buyer to confirm received.';
    if (value == 'completed' || value == 'received') {
      return 'Order completed.';
    }
    if (value == 'cancelled') return 'Order cancelled.';

    return 'Review order status.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(
          color: Color(0xFF1E2A1F),
        ),
        title: const Text(
          'Farmer Orders',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF1E2A1F),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: Color(0xFF2F6B3B),
            ),
            onPressed: _isUpdating ? null : _fetchOrders,
          ),
        ],
      ),
      body: Stack(
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _ordersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF2F6B3B),
                  ),
                );
              }

              if (snapshot.hasError) {
                return _buildMessageState(
                  icon: Icons.error_outline_rounded,
                  title: 'Unable to load orders.',
                  subtitle: snapshot.error.toString(),
                  isError: true,
                );
              }

              final orders = snapshot.data ?? [];

              if (orders.isEmpty) {
                return _buildMessageState(
                  icon: Icons.inbox_rounded,
                  title: 'No orders yet.',
                  subtitle:
                      'Buyer orders for your published crops will appear here.',
                );
              }

              return RefreshIndicator(
                onRefresh: _refreshOrders,
                color: const Color(0xFF2F6B3B),
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    return _buildOrderCard(orders[index]);
                  },
                ),
              );
            },
          ),
          if (_isUpdating)
            Container(
              color: Colors.black.withValues(alpha: 0.12),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF2F6B3B),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderId = order['id']?.toString() ?? '';
    final shortId = _shortOrderId(order);
    final status = order['status']?.toString() ?? 'Pending';
    final paymentStatus = order['payment_status']?.toString() ?? 'Unpaid';
    final deliveryStatus = order['delivery_status']?.toString() ?? status;
    final total = _toDouble(order['total_amount']);
    final buyerEmail = order['email']?.toString() ?? 'No email';
    final shippingName = order['shipping_name']?.toString() ?? 'No recipient';
    final shippingPhone = order['shipping_phone']?.toString() ?? 'No phone';
    final shippingAddress =
        order['shipping_address']?.toString() ?? 'No address';
    final proofUrl = order['proof_image_url']?.toString() ??
        order['delivery_proof_url']?.toString();
    final confirmedReceived = order['confirmed_received'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 54,
                width: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF2F6B3B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Color(0xFF2F6B3B),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#$shortId',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E2A1F),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      buyerEmail,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '₱${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFF2F6B3B),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatusPill('Order: $status', _statusColor(status)),
              _buildStatusPill(
                'Payment: $paymentStatus',
                _statusColor(paymentStatus),
              ),
              _buildStatusPill(
                'Delivery: $deliveryStatus',
                _statusColor(deliveryStatus),
              ),
              if (confirmedReceived)
                _buildStatusPill(
                  'Buyer Received',
                  const Color(0xFF2F6B3B),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F3EA),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _nextStepText(status),
              style: const TextStyle(
                color: Color(0xFF2F6B3B),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildInfoBox(
            title: 'Shipping Details',
            lines: [
              'Recipient: $shippingName',
              'Phone: $shippingPhone',
              'Address: $shippingAddress',
            ],
          ),
          if (proofUrl != null && proofUrl.isNotEmpty) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                proofUrl,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 150,
                    alignment: Alignment.center,
                    color: const Color(0xFFE8F3EA),
                    child: const Text(
                      'Delivery proof unavailable',
                      style: TextStyle(
                        color: Color(0xFF2F6B3B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildActionButtons(
            orderId: orderId,
            status: status,
            order: order,
          ),
          if (_isFinalStatus(status)) ...[
            const SizedBox(height: 8),
            const Text(
              'No farmer action needed for this order.',
              style: TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons({
    required String orderId,
    required String status,
    required Map<String, dynamic> order,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_canAccept(status))
          _actionButton(
            label: 'Accept',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF2F6B3B),
            onPressed: () => _updateStatus(
              orderId: orderId,
              status: 'Confirmed',
            ),
          ),
        if (_canPrepare(status))
          _actionButton(
            label: 'Preparing',
            icon: Icons.inventory_2_rounded,
            color: Colors.orange,
            onPressed: () => _updateStatus(
              orderId: orderId,
              status: 'Preparing',
            ),
          ),
        if (_canShip(status))
          _actionButton(
            label: 'Shipped',
            icon: Icons.local_shipping_rounded,
            color: Colors.blueGrey,
            onPressed: () => _updateStatus(
              orderId: orderId,
              status: 'Shipped',
            ),
          ),
        if (_canSubmitProof(status))
          _actionButton(
            label: 'Submit Proof',
            icon: Icons.photo_camera_rounded,
            color: Colors.indigo,
            onPressed: () => _submitDeliveryProof(order),
          ),
        if (_canCancel(status))
          _actionButton(
            label: 'Cancel',
            icon: Icons.cancel_rounded,
            color: Colors.redAccent,
            onPressed: () => _updateStatus(
              orderId: orderId,
              status: 'Cancelled',
            ),
          ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: _isUpdating ? null : onPressed,
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildStatusPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildInfoBox({
    required String title,
    required List<String> lines,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FBF7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8F3EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1E2A1F),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required String title,
    required String subtitle,
    bool isError = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 80,
              color: isError ? Colors.redAccent : Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF1E2A1F),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
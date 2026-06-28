import 'package:flutter/material.dart';

import '../services/order_service.dart';

class OrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> order;

  const OrderDetailScreen({
    super.key,
    required this.order,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final OrderService _orderService = OrderService();

  late String currentStatus;
  bool isUpdating = false;

  final List<String> _statuses = const [
    'Pending',
    'Confirmed',
    'Preparing',
    'Shipped',
    'Delivered',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    currentStatus = widget.order['status']?.toString() ?? 'Pending';
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => isUpdating = true);

    final success = await _orderService.updateOrderStatus(
      widget.order['id'].toString(),
      newStatus,
    );

    if (!mounted) return;

    setState(() {
      if (success) {
        currentStatus = newStatus;
      }

      isUpdating = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Status updated to $newStatus.' : 'Status update failed.',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: success ? const Color(0xFF2F6B3B) : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    final rawOrderId = order['id']?.toString() ?? 'UNKNOWN';
    final orderId = rawOrderId.length >= 8
        ? rawOrderId.substring(0, 8).toUpperCase()
        : rawOrderId.toUpperCase();

    final customer = order['shipping_name']?.toString().trim().isNotEmpty == true
        ? order['shipping_name'].toString()
        : 'Guest Buyer';

    final address =
        order['shipping_address']?.toString().trim().isNotEmpty == true
            ? order['shipping_address'].toString()
            : 'Farm Pickup';

    final city = order['city']?.toString() ?? '';
    final postalCode = order['postal_code']?.toString() ?? '';
    final phone = order['shipping_phone']?.toString() ?? 'No phone provided';
    final email = order['email']?.toString() ?? 'No email provided';
    final total = order['total_amount']?.toString() ?? '0.00';
    final payment = order['payment_method']?.toString() ?? 'Cash on Delivery';
    final paymentStatus = order['payment_status']?.toString() ?? 'Unpaid';
    final deliveryMethod = order['delivery_method']?.toString() ?? 'Delivery';

    final orderItems = List<Map<String, dynamic>>.from(
      order['order_items'] ?? [],
    );

    final firstLetter = customer.isNotEmpty ? customer[0].toUpperCase() : 'B';

    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(
          color: Color(0xFF1E2A1F),
        ),
        title: Text(
          'Order #$orderId',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF1E2A1F),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomerCard(
              customer: customer,
              firstLetter: firstLetter,
              email: email,
              phone: phone,
              payment: payment,
              paymentStatus: paymentStatus,
              deliveryMethod: deliveryMethod,
              address: address,
              city: city,
              postalCode: postalCode,
            ),

            const SizedBox(height: 24),

            const Text(
              'Farmer-Owned Items',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E2A1F),
              ),
            ),

            const SizedBox(height: 12),

            _buildItemsCard(orderItems),

            const SizedBox(height: 24),

            const Text(
              'Fulfillment Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E2A1F),
              ),
            ),

            const SizedBox(height: 12),

            _buildStatusDropdown(),

            const SizedBox(height: 24),

            _buildTotalCard(total),

            const SizedBox(height: 24),

            const Text(
              'Proof of Action',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E2A1F),
              ),
            ),

            const SizedBox(height: 12),

            _buildProofPlaceholder(),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard({
    required String customer,
    required String firstLetter,
    required String email,
    required String phone,
    required String payment,
    required String paymentStatus,
    required String deliveryMethod,
    required String address,
    required String city,
    required String postalCode,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor:
                    const Color(0xFF2F6B3B).withValues(alpha: 0.1),
                child: Text(
                  firstLetter,
                  style: const TextStyle(
                    color: Color(0xFF2F6B3B),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E2A1F),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$deliveryMethod • $paymentStatus',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 32),

          _buildInfoRow(
            icon: Icons.email_rounded,
            label: 'Email',
            value: email,
          ),

          const SizedBox(height: 12),

          _buildInfoRow(
            icon: Icons.phone_rounded,
            label: 'Phone',
            value: phone,
          ),

          const SizedBox(height: 12),

          _buildInfoRow(
            icon: Icons.payments_rounded,
            label: 'Payment',
            value: payment,
          ),

          const SizedBox(height: 12),

          _buildInfoRow(
            icon: Icons.location_on_rounded,
            label: 'Delivery Address',
            value: '$address ${city.isNotEmpty ? '• $city' : ''} ${postalCode.isNotEmpty ? '• $postalCode' : ''}',
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCard(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: _cardDecoration(),
        child: Text(
          'No item details found.',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        children: items.map((item) {
          final productName =
              item['product_name']?.toString() ?? 'Lettuce Product';
          final quantity = item['quantity']?.toString() ?? '0';
          final price = item['price']?.toString() ?? '0';
          final subtotal = item['subtotal']?.toString() ?? '0';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF6FBF7),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F6B3B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.eco_rounded,
                    color: Color(0xFF2F6B3B),
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E2A1F),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Qty: $quantity • ₱$price each',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                Text(
                  '₱$subtotal',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2F6B3B),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: currentStatus,
          icon: isUpdating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF2F6B3B),
                  ),
                )
              : const Icon(Icons.arrow_drop_down),
          items: _statuses
              .map(
                (status) => DropdownMenuItem(
                  value: status,
                  child: Text(
                    status,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: isUpdating
              ? null
              : (val) {
                  if (val != null && val != currentStatus) {
                    _updateStatus(val);
                  }
                },
        ),
      ),
    );
  }

  Widget _buildTotalCard(String total) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2A1F),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Order Total',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '₱$total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProofPlaceholder() {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Proof upload will be connected later.'),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFF5DBB63).withValues(alpha: 0.25),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.add_a_photo_rounded,
              size: 40,
              color: Colors.green.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'Upload Delivery / Payment Proof',
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: const Color(0xFF2F6B3B),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E2A1F),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 15,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
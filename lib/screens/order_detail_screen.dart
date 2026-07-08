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

  @override
  void initState() {
    super.initState();
    currentStatus = widget.order['status']?.toString() ?? 'Pending';
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => isUpdating = true);

    final error = await _orderService.updateFarmerOrderStatus(
      orderId: widget.order['id'].toString(),
      status: newStatus,
    );

    if (!mounted) return;

    setState(() {
      if (error == null) {
        currentStatus = newStatus;
      }
      isUpdating = false;
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null ? 'Status updated to $newStatus.' : 'Update failed: $error',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: error == null ? const Color(0xFF2F6B3B) : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

    final address = order['shipping_address']?.toString().trim().isNotEmpty == true
        ? order['shipping_address'].toString()
        : 'Farm Pickup';

    final city = order['city']?.toString() ?? '';
    final postalCode = order['postal_code']?.toString() ?? '';
    final phone = order['shipping_phone']?.toString() ?? 'No phone provided';
    final email = order['email']?.toString() ?? 'No email provided';
    final total =
    double.tryParse(order['total_amount']?.toString() ?? '0') ?? 0;
    final payment = order['payment_method']?.toString() ?? 'Cash on Delivery';
    final paymentStatus = order['payment_status']?.toString() ?? 'Unpaid';
    final deliveryMethod = order['delivery_method']?.toString() ?? 'Delivery';

    final orderItems = List<Map<String, dynamic>>.from(order['order_items'] ?? []);

    final firstLetter = customer.isNotEmpty ? customer[0].toUpperCase() : 'B';

    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F)),
        title: Text('Order #$orderId', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E2A1F))),
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

            const Text('Farmer-Owned Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
            const SizedBox(height: 12),
            _buildItemsCard(orderItems),

            const SizedBox(height: 24),

            const Text('Fulfillment Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
            const SizedBox(height: 12),

            _buildStatusSection(),

            const SizedBox(height: 24),

_buildTotalCard(total.toStringAsFixed(2)),

            const SizedBox(height: 24),

            const Text('Proof of Action', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
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
                backgroundColor: const Color(0xFF2F6B3B).withValues(alpha: 0.1),
                child: Text(firstLetter, style: const TextStyle(color: Color(0xFF2F6B3B), fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(customer, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
                    const SizedBox(height: 4),
                    Text('$deliveryMethod • $paymentStatus', style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          _buildInfoRow(icon: Icons.email_rounded, label: 'Email', value: email),
          const SizedBox(height: 12),
          _buildInfoRow(icon: Icons.phone_rounded, label: 'Phone', value: phone),
          const SizedBox(height: 12),
          _buildInfoRow(icon: Icons.payments_rounded, label: 'Payment', value: payment),
          const SizedBox(height: 12),
          _buildInfoRow(icon: Icons.location_on_rounded, label: 'Delivery Address', value: '$address ${city.isNotEmpty ? '• $city' : ''} ${postalCode.isNotEmpty ? '• $postalCode' : ''}'),
        ],
      ),
    );
  }

  Widget _buildItemsCard(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: _cardDecoration(), child: Text('No item details found.', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold)));
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        children: items.map((item) {
          final productName = item['product_name']?.toString() ?? 'Lettuce Product';
          final quantity = item['quantity']?.toString() ?? '0';
         final price =
    double.tryParse(item['price']?.toString() ?? '0') ?? 0;
        final subtotal =
    double.tryParse(item['subtotal']?.toString() ?? '0') ?? 0;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFF6FBF7), borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                Container(height: 44, width: 44, decoration: BoxDecoration(color: const Color(0xFF2F6B3B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.eco_rounded, color: Color(0xFF2F6B3B))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
                      const SizedBox(height: 4),
                     Text('Qty: $quantity • ₱${price.toStringAsFixed(2)} each', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: 12)),
                    ],
                  ),
                ),
               Text('₱${subtotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2F6B3B))),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current Status: $currentStatus', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
          const SizedBox(height: 16),

          if (currentStatus.toLowerCase() == 'pending')
            ElevatedButton(
              onPressed: isUpdating ? null : () => _updateStatus('Confirmed'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(double.infinity, 50)),
              child: const Text('Accept Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),

          if (currentStatus.toLowerCase() == 'confirmed')
            ElevatedButton(
              onPressed: isUpdating ? null : () => _updateStatus('Preparing'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, minimumSize: const Size(double.infinity, 50)),
              child: const Text('Mark as Preparing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),

          if (currentStatus.toLowerCase() == 'preparing')
            ElevatedButton(
              onPressed: isUpdating ? null : () => _updateStatus('Shipped'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, minimumSize: const Size(double.infinity, 50)),
              child: const Text('Mark as Shipped', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),

          if (currentStatus.toLowerCase() == 'shipped')
            ElevatedButton(
              onPressed: isUpdating ? null : () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Proof upload coming soon')));
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, minimumSize: const Size(double.infinity, 50)),
              child: const Text('Submit Proof', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),

          if (['delivered', 'completed', 'received', 'cancelled'].contains(currentStatus.toLowerCase()))
            const Text('No further action needed.', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildTotalCard(String total) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: const Color(0xFF1E2A1F), borderRadius: BorderRadius.circular(24)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Order Total', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
          Text('₱$total', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildProofPlaceholder() {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Proof upload will be connected later.')));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF5DBB63).withValues(alpha: 0.25), width: 2),
        ),
        child: Column(
          children: [
            Icon(Icons.add_a_photo_rounded, size: 40, color: Colors.green.shade300),
            const SizedBox(height: 12),
            Text('Upload Delivery / Payment Proof', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2F6B3B)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E2A1F), height: 1.4)),
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
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15, offset: const Offset(0, 8))],
    );
  }
}
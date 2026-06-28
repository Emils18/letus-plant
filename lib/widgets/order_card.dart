import 'package:flutter/material.dart';

import '../screens/order_detail_screen.dart';

class OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;

  const OrderCard({
    super.key,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    final rawOrderId = order['id']?.toString() ?? 'UNKNOWN';
    final orderId = rawOrderId.length >= 8
        ? rawOrderId.substring(0, 8).toUpperCase()
        : rawOrderId.toUpperCase();

    final customer = order['shipping_name']?.toString().trim().isNotEmpty == true
        ? order['shipping_name'].toString()
        : 'Guest Buyer';

    final total = order['total_amount']?.toString() ?? '0.00';
    final status = order['status']?.toString() ?? 'Pending';
    final paymentStatus = order['payment_status']?.toString() ?? 'Unpaid';
    final deliveryMethod =
        order['delivery_method']?.toString() ?? 'Delivery';

    final orderItems = List<Map<String, dynamic>>.from(
      order['order_items'] ?? [],
    );

    final itemCount = orderItems.length;

    final statusColor = _getStatusColor(status);
    final firstLetter = customer.isNotEmpty ? customer[0].toUpperCase() : 'B';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrderDetailScreen(order: order),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '#$orderId',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.grey.shade400,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          const Color(0xFF2F6B3B).withValues(alpha: 0.1),
                      child: Text(
                        firstLetter,
                        style: const TextStyle(
                          color: Color(0xFF2F6B3B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E2A1F),
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            '$deliveryMethod • $paymentStatus • $itemCount item${itemCount == 1 ? '' : 's'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: paymentStatus == 'Paid'
                                  ? Colors.green
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    Text(
                      '₱$total',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2F6B3B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Delivered':
        return const Color(0xFF5DBB63);
      case 'Confirmed':
        return Colors.blue;
      case 'Preparing':
        return Colors.orange;
      case 'Shipped':
        return Colors.purple;
      case 'Cancelled':
        return Colors.redAccent;
      default:
        return Colors.blueGrey;
    }
  }
}
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/order_service.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final OrderService _orderService = OrderService();
  final ImagePicker _imagePicker = ImagePicker();
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _orderService.getFarmerOrders();
  }

  Future<void> _refreshOrders() async {
    setState(() {
      _ordersFuture = _orderService.getFarmerOrders();
    });
  }

  Future<void> _openOrderDetails(Map<String, dynamic> order) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => OrderDetailScreen(order: order)),
    );
    if (mounted) _refreshOrders();
  }

  Future<void> _submitProof(String orderId) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
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

    final result = await _orderService.submitDeliveryProof(
      orderId: orderId,
      proofImage: pickedImage,
    );

    if (!mounted) return;

    if (result.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Proof submitted!')));
      _refreshOrders();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: ${result.error}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'My Orders',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: Color(0xFF1E2A1F),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F)),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF2F6B3B)),
            );
          }

          if (snapshot.hasError || (snapshot.data ?? []).isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_rounded, size: 60, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No orders yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    'Buyer orders will appear here',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final orders = snapshot.data!;

          return RefreshIndicator(
            onRefresh: _refreshOrders,
            child: ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                final status = order['status']?.toString() ?? 'Pending';
                final orderId = order['id']?.toString() ?? '';
                final orderLabel =
                    order['order_code']?.toString().trim().isNotEmpty == true
                    ? order['order_code'].toString()
                    : orderId.length > 8
                    ? orderId.substring(0, 8).toUpperCase()
                    : orderId.toUpperCase();
                final total =
                    double.tryParse(order['total_amount']?.toString() ?? '0') ??
                    0;
                final deliveryMethod =
                    order['delivery_method']?.toString() ?? 'Delivery';

                final buyer =
                    order['shipping_name']?.toString().trim().isNotEmpty == true
                    ? order['shipping_name'].toString()
                    : 'Buyer name not provided';
                final phone =
                    order['shipping_phone']?.toString().trim().isNotEmpty ==
                        true
                    ? order['shipping_phone'].toString()
                    : 'Phone number not provided';
                final address =
                    order['shipping_address']?.toString().trim().isNotEmpty ==
                        true
                    ? order['shipping_address'].toString()
                    : 'Pickup / location not provided';

                return GestureDetector(
                  onTap: () => _openOrderDetails(order),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 15,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #$orderLabel',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 19,
                            color: Color(0xFF1E2A1F),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Buyer: $buyer',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E2A1F),
                          ),
                        ),
                        Text(
                          'Phone: $phone',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF59645B),
                          ),
                        ),
                        Text(
                          'Location: $address',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF59645B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Total: ₱${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2F6B3B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Delivery: $deliveryMethod',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          'Status: $status',
                          style: TextStyle(
                            color: _statusColor(status),
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Full Process Buttons (Green Theme)
                        if (status.toLowerCase() == 'pending')
                          ElevatedButton(
                            onPressed: () => _updateStatus(
                              order['id'].toString(),
                              'Confirmed',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2F6B3B),
                              minimumSize: const Size(double.infinity, 55),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'Accept Order',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),

                        if (status.toLowerCase() == 'confirmed')
                          ElevatedButton(
                            onPressed: () => _updateStatus(
                              order['id'].toString(),
                              'Preparing',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5DBB63),
                              minimumSize: const Size(double.infinity, 55),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'Mark as Preparing',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),

                        if (status.toLowerCase() == 'preparing')
                          ElevatedButton(
                            onPressed: () => _updateStatus(
                              order['id'].toString(),
                              'Shipped',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2F6B3B),
                              minimumSize: const Size(double.infinity, 55),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'Mark as Shipped',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),

                        if (status.toLowerCase() == 'shipped')
                          ElevatedButton(
                            onPressed: () =>
                                _submitProof(order['id'].toString()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5DBB63),
                              minimumSize: const Size(double.infinity, 55),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text(
                              'Submit Proof',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Tap order to view all details  ›',
                            style: TextStyle(
                              color: Color(0xFF2F6B3B),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _updateStatus(String orderId, String status) async {
    final error = await _orderService.updateFarmerOrderStatus(
      orderId: orderId,
      status: status,
    );

    if (error == null) {
      _refreshOrders();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $error')));
    }
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('delivered') || s.contains('completed'))
      return const Color(0xFF2F6B3B);
    if (s.contains('pending')) return Colors.orange;
    if (s.contains('cancel')) return Colors.red;
    return Colors.blueGrey;
  }
}

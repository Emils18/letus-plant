import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_service.dart';
import '../services/order_service.dart';
import 'scan_screen.dart';
import 'sell_crop_screen.dart';
import 'shared/health_logs_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final OrderService _orderService = OrderService();
  final ImagePicker _imagePicker = ImagePicker();

  late Future<List<Map<String, dynamic>>> _recentOrders;

  @override
  void initState() {
    super.initState();
    _recentOrders = _orderService.getFarmerOrders();
  }

  Future<void> _refreshOrders() async {
    setState(() {
      _recentOrders = _orderService.getFarmerOrders();
    });
  }

  Future<void> _logout(BuildContext context) async {
    await AuthService().signOut();

    if (!context.mounted) return;

    Navigator.popUntil(context, (route) => route.isFirst);
  }

  Future<void> _updateOrderStatus(
    String orderId,
    String newStatus,
  ) async {
    // Optimistic update → instant change, no jump
    setState(() {
      _recentOrders = _recentOrders.then((orders) {
        return orders.map((order) {
          if (order['id'].toString() == orderId) {
            return {
              ...order,
              'status': newStatus,
            };
          }

          return order;
        }).toList();
      });
    });

    final error = await _orderService.updateFarmerOrderStatus(
      orderId: orderId,
      status: newStatus,
    );

    if (error != null) {
      if (mounted) {
        _refreshOrders();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $error'),
        ),
      );
    }

    // Success: no _refreshOrders() → list stays in place
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
                onTap: () {
                  Navigator.pop(
                    context,
                    ImageSource.camera,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(
                    context,
                    ImageSource.gallery,
                  );
                },
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Proof submitted!'),
        ),
      );

      _refreshOrders();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed: ${result.error}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9F5),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshOrders,
          color: const Color(0xFF2F6B3B),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              22,
              20,
              22,
              32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ============================================================
                // MODERN FARMER HERO
                // ============================================================

                _fadeUp(
                  delay: 0,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF1E2A1F),
                          Color(0xFF2F6B3B),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2F6B3B)
                              .withValues(alpha: 0.20),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -35,
                          bottom: -45,
                          child: Icon(
                            Icons.eco_rounded,
                            size: 170,
                            color: Colors.white.withValues(
                              alpha: 0.05,
                            ),
                          ),
                        ),

                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  height: 54,
                                  width: 54,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Icon(
                                    Icons.eco_rounded,
                                    color: Color(0xFF82D68A),
                                    size: 31,
                                  ),
                                ),

                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(17),
                                  ),
                                  child: IconButton(
                                    onPressed: () => _logout(context),
                                    tooltip: 'Logout',
                                    icon: const Icon(
                                      Icons.logout_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 22),

                            const Text(
                              'Welcome back,',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFD8E8DA),
                                height: 1.2,
                              ),
                            ),

                            const SizedBox(height: 2),

                            const Text(
                              'Farmer',
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.05,
                                letterSpacing: -0.8,
                              ),
                            ),

                            const SizedBox(height: 10),

                            const Text(
                              'What would you like to do today?',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE7F1E8),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 34),

                // ============================================================
                // QUICK ACTIONS
                // ============================================================

                _fadeUp(
                  delay: 80,
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E2A1F),
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Choose what you want to do.',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7B847C),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Scan Disease
                _fadeUp(
                  delay: 140,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ScanScreen(),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.camera_alt_rounded,
                      size: 34,
                    ),
                    label: const Text(
                      'Scan Disease',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2F6B3B),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(
                        double.infinity,
                        84,
                      ),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Sell Crop
                _fadeUp(
                  delay: 210,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SellCropScreen(),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.storefront_rounded,
                      size: 34,
                    ),
                    label: const Text(
                      'Sell Crop',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5DBB63),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(
                        double.infinity,
                        84,
                      ),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 38),

                // ============================================================
                // RECENT ORDERS HEADER
                // ============================================================

                _fadeUp(
                  delay: 280,
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recent Orders',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1E2A1F),
                                letterSpacing: -0.6,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Manage your latest customer orders.',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7B847C),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 50,
                        width: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F3EA),
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          color: Color(0xFF2F6B3B),
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ============================================================
                // RECENT ORDERS LIST
                // ============================================================

                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _recentOrders,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 50,
                        ),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF2F6B3B),
                          ),
                        ),
                      );
                    }

                    List<Map<String, dynamic>> orders =
                        snapshot.data ?? [];

                    if (orders.isEmpty) {
                      return _fadeUp(
                        delay: 340,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 42,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: const Color(0xFFE7EEE8),
                            ),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.receipt_long_rounded,
                                size: 52,
                                color: Color(0xFF9AA49B),
                              ),
                              SizedBox(height: 14),
                              Text(
                                'No orders yet',
                                style: TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1E2A1F),
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'New customer orders will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF7B847C),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    orders.sort((a, b) {
                      final dateA = DateTime.tryParse(
                            a['created_at']?.toString() ?? '',
                          ) ??
                          DateTime(2000);

                      final dateB = DateTime.tryParse(
                            b['created_at']?.toString() ?? '',
                          ) ??
                          DateTime(2000);

                      return dateB.compareTo(dateA);
                    });

                    return Column(
                      children: orders.asMap().entries.map((entry) {
                        final index = entry.key;
                        final order = entry.value;

                        String product = 'Lettuce';

                        if (order['order_items'] != null &&
                            order['order_items'].isNotEmpty) {
                          final firstItem = order['order_items'][0];

                          if (firstItem['products'] != null) {
                            product = firstItem['products']['name']
                                    ?.toString() ??
                                'Lettuce';
                          }
                        }

                        final buyer =
                            order['shipping_name']?.toString() ??
                                'Buyer';

                        final phone =
                            order['shipping_phone']?.toString() ??
                                'No phone';

                        final location =
                            order['shipping_address']?.toString() ??
                                'Cebu';

                        final deliveryMethod =
                            order['delivery_method']?.toString() ??
                                'Delivery';

                        final status =
                            order['status']?.toString() ??
                                'Pending';

                        final total = double.tryParse(
                              order['total_amount']?.toString() ?? '0',
                            ) ??
                            0;

                        final orderId =
                            order['id']?.toString() ?? '';

                        final imageUrl =
                            order['image_url'] ??
                                order['product_image'] ??
                                'https://images.unsplash.com/photo-1540420773420-3366772f4999?q=80&w=1200&auto=format&fit=crop';

                        final isNewest =
                            orders.isNotEmpty &&
                                order == orders.first;

                        return _fadeUp(
                          delay: 340 + (index * 70),
                          child: Container(
                            margin: const EdgeInsets.only(
                              bottom: 20,
                            ),
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: isNewest
                                    ? const Color(0xFF5DBB63)
                                        .withValues(alpha: 0.35)
                                    : const Color(0xFFE8EFE9),
                                width: isNewest ? 1.5 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF1E2A1F)
                                      .withValues(alpha: 0.06),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                // Product Image + Main Information
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      child: Image.network(
                                        imageUrl,
                                        height: 92,
                                        width: 92,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (_, __, ___) {
                                          return Container(
                                            height: 92,
                                            width: 92,
                                            color: const Color(
                                              0xFFE8F3EA,
                                            ),
                                            child: const Icon(
                                              Icons.eco_rounded,
                                              color: Color(
                                                0xFF2F6B3B,
                                              ),
                                              size: 46,
                                            ),
                                          );
                                        },
                                      ),
                                    ),

                                    const SizedBox(width: 18),

                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  product,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      const TextStyle(
                                                    fontSize: 25,
                                                    fontWeight:
                                                        FontWeight.w900,
                                                    color: Color(
                                                      0xFF1E2A1F,
                                                    ),
                                                    letterSpacing: -0.4,
                                                  ),
                                                ),
                                              ),

                                              if (isNewest)
                                                Container(
                                                  padding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                    horizontal: 14,
                                                    vertical: 6,
                                                  ),
                                                  decoration:
                                                      BoxDecoration(
                                                    color: const Color(
                                                      0xFF5DBB63,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(
                                                      20,
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    'NEW',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),

                                          const SizedBox(height: 8),

                                          Text(
                                            'Buyer: $buyer',
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight:
                                                  FontWeight.w600,
                                              color: Color(0xFF7B847C),
                                              height: 1.35,
                                            ),
                                          ),

                                          Text(
                                            'Phone: $phone',
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight:
                                                  FontWeight.w500,
                                              color: Color(0xFF8A918B),
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 22),

                                // Delivery Method
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                    horizontal: 18,
                                  ),
                                  decoration: BoxDecoration(
                                    color: deliveryMethod
                                            .toLowerCase()
                                            .contains('pickup')
                                        ? const Color(0xFFFFF3CD)
                                        : const Color(0xFFE8F3EA),
                                    borderRadius:
                                        BorderRadius.circular(24),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        height: 42,
                                        width: 42,
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.65),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Icon(
                                          deliveryMethod
                                                  .toLowerCase()
                                                  .contains('pickup')
                                              ? Icons.store_rounded
                                              : Icons
                                                  .local_shipping_rounded,
                                          color: deliveryMethod
                                                  .toLowerCase()
                                                  .contains('pickup')
                                              ? Colors.orange
                                              : const Color(
                                                  0xFF2F6B3B,
                                                ),
                                          size: 27,
                                        ),
                                      ),

                                      const SizedBox(width: 13),

                                      Expanded(
                                        child: Text(
                                          deliveryMethod
                                                  .toLowerCase()
                                                  .contains('pickup')
                                              ? 'FARM PICKUP'
                                              : 'HOME DELIVERY',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight:
                                                FontWeight.w900,
                                            color: deliveryMethod
                                                    .toLowerCase()
                                                    .contains('pickup')
                                                ? Colors.orange
                                                : const Color(
                                                    0xFF2F6B3B,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 20),

                                // Location
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      height: 38,
                                      width: 38,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFE8F3EA,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(13),
                                      ),
                                      child: const Icon(
                                        Icons.location_on_rounded,
                                        color: Color(0xFF2F6B3B),
                                        size: 24,
                                      ),
                                    ),

                                    const SizedBox(width: 12),

                                    Expanded(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(
                                          top: 6,
                                        ),
                                        child: Text(
                                          location,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight:
                                                FontWeight.w600,
                                            color: Color(0xFF68736A),
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 22),

                                // Price + Status
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Order Total',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight:
                                                FontWeight.w700,
                                            color: Color(0xFF8A918B),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '₱${total.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 30,
                                            fontWeight:
                                                FontWeight.w900,
                                            color: Color(0xFF2F6B3B),
                                            letterSpacing: -0.4,
                                          ),
                                        ),
                                      ],
                                    ),

                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _statusColor(status)
                                            .withValues(alpha: 0.10),
                                        borderRadius:
                                            BorderRadius.circular(18),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight:
                                              FontWeight.w900,
                                          color:
                                              _statusColor(status),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // ==================================================
                                // EXISTING ACTION LOGIC — UNCHANGED
                                // ==================================================

                                if (status.toLowerCase() ==
                                        'pending' ||
                                    status.toLowerCase() ==
                                        'confirmed' ||
                                    status.toLowerCase() ==
                                        'preparing' ||
                                    status.toLowerCase() ==
                                        'shipped')
                                  const SizedBox(height: 22),

                                if (status.toLowerCase() ==
                                    'pending')
                                  ElevatedButton(
                                    onPressed: () {
                                      _updateOrderStatus(
                                        orderId,
                                        'Confirmed',
                                      );
                                    },
                                    style:
                                        ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF2F6B3B),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(
                                        double.infinity,
                                        68,
                                      ),
                                      elevation: 0,
                                      shape:
                                          RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(22),
                                      ),
                                    ),
                                    child: const Text(
                                      'Accept Order',
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight:
                                            FontWeight.w900,
                                      ),
                                    ),
                                  ),

                                if (status.toLowerCase() ==
                                    'confirmed')
                                  ElevatedButton(
                                    onPressed: () {
                                      _updateOrderStatus(
                                        orderId,
                                        'Preparing',
                                      );
                                    },
                                    style:
                                        ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF5DBB63),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(
                                        double.infinity,
                                        68,
                                      ),
                                      elevation: 0,
                                      shape:
                                          RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(22),
                                      ),
                                    ),
                                    child: const Text(
                                      'Mark as Preparing',
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight:
                                            FontWeight.w900,
                                      ),
                                    ),
                                  ),

                                if (status.toLowerCase() ==
                                    'preparing')
                                  ElevatedButton(
                                    onPressed: () {
                                      _updateOrderStatus(
                                        orderId,
                                        'Shipped',
                                      );
                                    },
                                    style:
                                        ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF2F6B3B),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(
                                        double.infinity,
                                        68,
                                      ),
                                      elevation: 0,
                                      shape:
                                          RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(22),
                                      ),
                                    ),
                                    child: const Text(
                                      'Mark as Shipped',
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight:
                                            FontWeight.w900,
                                      ),
                                    ),
                                  ),

                                if (status.toLowerCase() ==
                                    'shipped')
                                  ElevatedButton(
                                    onPressed: () {
                                      _submitProof(orderId);
                                    },
                                    style:
                                        ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF5DBB63),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(
                                        double.infinity,
                                        68,
                                      ),
                                      elevation: 0,
                                      shape:
                                          RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(22),
                                      ),
                                    ),
                                    child: const Text(
                                      'Submit Delivery Proof',
                                      style: TextStyle(
                                        fontSize: 21,
                                        fontWeight:
                                            FontWeight.w900,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Calm elder-friendly fade-up entrance
  Widget _fadeUp({
    required Widget child,
    int delay = 0,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: 0,
        end: 1,
      ),
      duration: Duration(
        milliseconds: 380 + delay,
      ),
      curve: Curves.easeOutCubic,
      builder: (context, value, animatedChild) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(
              0,
              14 * (1 - value),
            ),
            child: animatedChild,
          ),
        );
      },
      child: child,
    );
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();

    if (s.contains('delivered') ||
        s.contains('completed')) {
      return const Color(0xFF2F6B3B);
    }

    if (s.contains('pending')) {
      return Colors.orange;
    }

    if (s.contains('cancel')) {
      return Colors.red;
    }

    return Colors.blueGrey;
  }
}
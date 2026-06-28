import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
import 'shared/profile_screen.dart';

class BuyerHomeScreen extends StatefulWidget {
  const BuyerHomeScreen({super.key});

  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen> {
  final ProductService _productService = ProductService();
  final OrderService _orderService = OrderService();
  final AuthService _authService = AuthService();

  final TextEditingController _searchController = TextEditingController();

  int _currentIndex = 0;
  bool _isLoadingProducts = true;
  bool _isLoadingOrders = true;
  bool _isCheckingOut = false;

  String _selectedCategory = 'All';

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _orders = [];
  final List<Map<String, dynamic>> _cart = [];

  static const String _fallbackImage =
      'https://images.unsplash.com/photo-1540420773420-3366772f4999?q=80&w=1200&auto=format&fit=crop';

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadOrders();

    _searchController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoadingProducts = true);

    final products = await _productService.getProducts();

    if (!mounted) return;

    setState(() {
      _products = products;
      _isLoadingProducts = false;
    });
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoadingOrders = true);

    final orders = await _orderService.getBuyerOrders();

    if (!mounted) return;

    setState(() {
      _orders = orders;
      _isLoadingOrders = false;
    });
  }

  Future<void> _logout() async {
    await _authService.signOut();
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      _showMessage('Your cart is empty.', isError: true);
      return;
    }

    final info = await _showCheckoutDialog();

    if (info == null) return;

    setState(() => _isCheckingOut = true);

    final result = await _orderService.checkoutCart(
      cartItems: _cart,
      shippingName: info.shippingName,
      shippingPhone: info.shippingPhone,
      shippingAddress: info.shippingAddress,
      paymentMethod: info.paymentMethod,
    );

    if (!mounted) return;

    setState(() => _isCheckingOut = false);

    if (!result.success) {
      _showMessage(result.error ?? 'Checkout failed.', isError: true);
      return;
    }

    setState(() {
      _cart.clear();
      _currentIndex = 2;
    });

    await _loadOrders();

    _showMessage(
      result.orderCount > 1
          ? '${result.orderCount} orders placed successfully.'
          : 'Order placed successfully.',
    );
  }

  Future<void> _confirmReceived(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString();

    if (orderId == null || orderId.isEmpty) {
      _showMessage('Invalid order.', isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Confirm Received',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'Confirm that you already received this order?',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2F6B3B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final error = await _orderService.confirmReceived(orderId);

    if (!mounted) return;

    if (error != null) {
      _showMessage(error, isError: true);
      return;
    }

    _showMessage('Order marked as received.');
    await _loadOrders();
  }

  void _addToCart(Map<String, dynamic> product) {
    final productId = product['id'];

    final existingIndex = _cart.indexWhere(
      (item) => item['id'] == productId,
    );

    setState(() {
      if (existingIndex >= 0) {
        final currentQuantity = _cart[existingIndex]['quantity'] as int;
        final stock = _toInt(product['stock']);

        if (currentQuantity < stock) {
          _cart[existingIndex]['quantity'] = currentQuantity + 1;
        } else {
          _showMessage('Stock limit reached.', isError: true);
          return;
        }
      } else {
        _cart.add({
          ...product,
          'quantity': 1,
        });
      }
    });

    _showMessage('Added to cart.');
  }

  void _updateCartQuantity(dynamic productId, int delta) {
    setState(() {
      final index = _cart.indexWhere((item) => item['id'] == productId);

      if (index < 0) return;

      final currentQuantity = _cart[index]['quantity'] as int;
      final stock = _toInt(_cart[index]['stock']);
      final newQuantity = currentQuantity + delta;

      if (newQuantity <= 0) {
        _cart.removeAt(index);
        return;
      }

      if (newQuantity <= stock) {
        _cart[index]['quantity'] = newQuantity;
      }
    });
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
    });

    _showMessage('Cart cleared.');
  }

  double get _subtotal {
    return _cart.fold(0, (sum, item) {
      final price = _toDouble(item['price']);
      final quantity = item['quantity'] as int;

      return sum + (price * quantity);
    });
  }

  int get _cartCount {
    return _cart.fold(0, (sum, item) {
      return sum + (item['quantity'] as int);
    });
  }

  List<String> get _categories {
    final values = _products
        .map((product) => product['category']?.toString().trim())
        .where((category) => category != null && category.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();

    values.sort();

    return ['All', ...values];
  }

  List<Map<String, dynamic>> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();

    return _products.where((product) {
      final name = product['name']?.toString().toLowerCase() ?? '';
      final category = product['category']?.toString().toLowerCase() ?? '';
      final farmer = _farmerName(product).toLowerCase();
      final badge = product['badge']?.toString().toLowerCase() ?? '';
      final freshness = _freshnessInfo(product).toLowerCase();

      final matchesSearch = query.isEmpty ||
          name.contains(query) ||
          category.contains(query) ||
          farmer.contains(query) ||
          badge.contains(query) ||
          freshness.contains(query);

      final matchesCategory = _selectedCategory == 'All' ||
          category == _selectedCategory.toLowerCase();

      return matchesSearch && matchesCategory;
    }).toList();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF2F6B3B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Future<_CheckoutInfo?> _showCheckoutDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    String paymentMethod = 'Cash on Delivery';

    try {
      return await showDialog<_CheckoutInfo>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                title: const Text(
                  'Checkout',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F3EA),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          'Total: ₱${_subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFF2F6B3B),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Recipient Name',
                          prefixIcon: Icon(Icons.person_rounded),
                        ),
                      ),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone_rounded),
                        ),
                      ),
                      TextField(
                        controller: addressController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Delivery Address',
                          prefixIcon: Icon(Icons.location_on_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: paymentMethod,
                        items: const [
                          DropdownMenuItem(
                            value: 'Cash on Delivery',
                            child: Text('Cash on Delivery'),
                          ),
                          DropdownMenuItem(
                            value: 'GCash',
                            child: Text('GCash'),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            paymentMethod = value ?? 'Cash on Delivery';
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Payment Method',
                          prefixIcon: Icon(Icons.payments_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        _CheckoutInfo(
                          shippingName: nameController.text,
                          shippingPhone: phoneController.text,
                          shippingAddress: addressController.text,
                          paymentMethod: paymentMethod,
                        ),
                      );
                    },
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Place Order'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2F6B3B),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nameController.dispose();
      phoneController.dispose();
      addressController.dispose();
    }
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();

    return double.tryParse(value?.toString() ?? '0') ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;

    return int.tryParse(value?.toString() ?? '0') ?? 0;
  }

  String _productImage(Map<String, dynamic> product) {
    final value = product['image_url'] ??
        product['image'] ??
        product['product_image'] ??
        product['photo_url'];

    final imageUrl = value?.toString().trim();

    if (imageUrl == null || imageUrl.isEmpty) {
      return _fallbackImage;
    }

    return imageUrl;
  }

  String _freshnessInfo(Map<String, dynamic> product) {
    return product['freshnessInfo']?.toString() ??
        product['freshness_info']?.toString() ??
        product['description']?.toString() ??
        'Fresh lettuce crop from local farmer.';
  }

  String _farmerName(Map<String, dynamic> product) {
    return product['farmer']?.toString() ??
        product['farmer_name']?.toString() ??
        'Local Farmer';
  }

  Widget _safeProductImage(
    Map<String, dynamic> product, {
    double height = 180,
    double width = double.infinity,
    BorderRadius? borderRadius,
  }) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      child: Image.network(
        _productImage(product),
        height: height,
        width: width,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: height,
            width: width,
            color: const Color(0xFFE8F3EA),
            alignment: Alignment.center,
            child: const Icon(
              Icons.image_not_supported_rounded,
              color: Color(0xFF2F6B3B),
              size: 34,
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(String status) {
    final normalized = status.toLowerCase();

    if (normalized.contains('completed') ||
        normalized.contains('received') ||
        normalized.contains('delivered') ||
        normalized.contains('paid')) {
      return const Color(0xFF2F6B3B);
    }

    if (normalized.contains('cancel')) {
      return Colors.redAccent;
    }

    if (normalized.contains('preparing') ||
        normalized.contains('confirmed') ||
        normalized.contains('shipped') ||
        normalized.contains('pending')) {
      return Colors.orange;
    }

    return Colors.blueGrey;
  }

  String _shortOrderId(Map<String, dynamic> order) {
    final orderCode = order['order_code']?.toString();

    if (orderCode != null && orderCode.isNotEmpty) {
      return orderCode;
    }

    final rawId = order['id']?.toString() ?? 'UNKNOWN';

    return rawId.length >= 8 ? rawId.substring(0, 8).toUpperCase() : rawId;
  }

  bool _canConfirmReceived(Map<String, dynamic> order) {
    final status = order['status']?.toString().toLowerCase() ?? '';
    final deliveryStatus =
        order['delivery_status']?.toString().toLowerCase() ?? '';
    final confirmed = order['confirmed_received'] == true;

    return !confirmed &&
        (status.contains('delivered') ||
            status.contains('shipped') ||
            deliveryStatus.contains('delivered') ||
            deliveryStatus.contains('shipped'));
  }

  String _orderStepText(Map<String, dynamic> order) {
    final status = order['status']?.toString().toLowerCase() ?? '';

    if (status.contains('pending')) return 'Waiting for farmer to accept.';
    if (status.contains('confirmed')) return 'Farmer accepted your order.';
    if (status.contains('preparing')) return 'Farmer is preparing your order.';
    if (status.contains('shipped')) return 'Order is on the way.';
    if (status.contains('delivered')) return 'Delivered. Please confirm received.';
    if (status.contains('completed') || status.contains('received')) {
      return 'Order completed.';
    }
    if (status.contains('cancel')) return 'Order was cancelled.';

    return 'Order is being processed.';
  }

  void _openProductDetails(Map<String, dynamic> product) {
    final name = product['name']?.toString() ?? 'Lettuce Product';
    final farmer = _farmerName(product);
    final category = product['category']?.toString() ?? 'Fresh Lettuce';
    final badge = product['badge']?.toString() ?? 'Fresh Today';
    final price = _toDouble(product['price']);
    final stock = _toInt(product['stock']);
    final location = product['location']?.toString() ?? 'Cebu Farm';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.55,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF6FBF7),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(22),
                children: [
                  Center(
                    child: Container(
                      height: 5,
                      width: 48,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _safeProductImage(
                    product,
                    height: 230,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildBadge(badge),
                      _buildBadge(category),
                      _buildBadge('Stock: $stock'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFF1E2A1F),
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.storefront_rounded,
                        color: Color(0xFF2F6B3B),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          farmer,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFF2F6B3B),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          location,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _freshnessInfo(product),
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2A1F),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '₱${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color(0xFF5DBB63),
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: stock <= 0
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  _addToCart(product);
                                },
                          icon: const Icon(Icons.add_shopping_cart_rounded),
                          label: const Text(
                            'Add to Cart',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5DBB63),
                            foregroundColor: const Color(0xFF0A110D),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6FBF7),
        elevation: 0,
        foregroundColor: const Color(0xFF1E2A1F),
        title: const Text(
          'GreenGuard AI',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildMarketplaceTab(),
          _buildCartTab(),
          _buildOrdersTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFF5DBB63).withValues(alpha: 0.2),
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });

          if (index == 0) {
            _loadProducts();
          }

          if (index == 2) {
            _loadOrders();
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.storefront_rounded),
            label: 'Shop',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _cartCount > 0,
              label: Text(_cartCount.toString()),
              child: const Icon(Icons.shopping_cart_rounded),
            ),
            label: 'Cart',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_rounded),
            label: 'Orders',
          ),
        ],
      ),
    );
  }

  Widget _buildMarketplaceTab() {
    if (_isLoadingProducts) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF2F6B3B),
        ),
      );
    }

    final filteredProducts = _filteredProducts;

    return RefreshIndicator(
      color: const Color(0xFF2F6B3B),
      onRefresh: _loadProducts,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildShopHeader(),
          const SizedBox(height: 18),
          _buildSearchAndFilters(),
          const SizedBox(height: 18),
          if (_products.isEmpty)
            _buildEmptyState(
              icon: Icons.storefront_rounded,
              title: 'No products yet.',
              subtitle: 'Farmer-published crops will appear here.',
            )
          else if (filteredProducts.isEmpty)
            _buildEmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matching products.',
              subtitle: 'Try another search keyword or category.',
            )
          else
            ...filteredProducts.map(_buildProductCard),
        ],
      ),
    );
  }

  Widget _buildShopHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2A1F),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.eco_rounded,
            color: Color(0xFF5DBB63),
            size: 36,
          ),
          SizedBox(height: 14),
          Text(
            'Fresh Lettuce Marketplace',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Buy farmer-published crops verified through GreenGuard AI.',
            style: TextStyle(
              color: Colors.white70,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

Widget _buildSearchAndFilters() {
  final categories = _categories;
  final selectedCategory =
      categories.contains(_selectedCategory) ? _selectedCategory : 'All';

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 14,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Find Products',
          style: TextStyle(
            color: Color(0xFF1E2A1F),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 12),

        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search product or farmer...',
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF2F6B3B),
            ),
            suffixIcon: _searchController.text.trim().isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: const Color(0xFFF6FBF7),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
          ),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF6FBF7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE8F3EA),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedCategory,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF2F6B3B),
              ),
              items: categories.map((category) {
                return DropdownMenuItem<String>(
                  value: category,
                  child: Text(
                    category == 'All'
                        ? 'All Categories'
                        : category,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1E2A1F),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;

                setState(() {
                  _selectedCategory = value;
                });
              },
            ),
          ),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            const Icon(
              Icons.tune_rounded,
              size: 18,
              color: Color(0xFF2F6B3B),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${_filteredProducts.length} product result${_filteredProducts.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_selectedCategory != 'All' ||
                _searchController.text.trim().isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedCategory = 'All';
                    _searchController.clear();
                  });
                },
                child: const Text(
                  'Reset',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

  Widget _buildProductCard(Map<String, dynamic> product) {
    final name = product['name']?.toString() ?? 'Lettuce Product';
    final farmer = _farmerName(product);
    final category = product['category']?.toString() ?? 'Fresh Lettuce';
    final badge = product['badge']?.toString() ?? 'Fresh Today';
    final price = _toDouble(product['price']);
    final stock = _toInt(product['stock']);

    return GestureDetector(
      onTap: () => _openProductDetails(product),
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _safeProductImage(
                  product,
                  height: 180,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 14,
                  child: _buildBadge(badge),
                ),
                Positioned(
                  top: 14,
                  right: 14,
                  child: _buildBadge('Stock: $stock'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBadge(category),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E2A1F),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    farmer,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _freshnessInfo(product),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '₱${price.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2F6B3B),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _openProductDetails(product),
                        child: const Text(
                          'Details',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: stock <= 0 ? null : () => _addToCart(product),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2F6B3B),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          'Add',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartTab() {
    if (_cart.isEmpty) {
      return _buildEmptyState(
        icon: Icons.shopping_cart_rounded,
        title: 'Your cart is empty.',
        subtitle: 'Add lettuce products from the marketplace.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'My Cart',
                style: TextStyle(
                  color: Color(0xFF1E2A1F),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _clearCart,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ..._cart.map((item) {
          final name = item['name']?.toString() ?? 'Lettuce Product';
          final price = _toDouble(item['price']);
          final quantity = item['quantity'] as int;
          final subtotal = price * quantity;

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                _safeProductImage(
                  item,
                  height: 70,
                  width: 70,
                  borderRadius: BorderRadius.circular(16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E2A1F),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _farmerName(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₱${price.toStringAsFixed(2)} each',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Subtotal: ₱${subtotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF2F6B3B),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _updateCartQuantity(item['id'], -1),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                    Text(
                      quantity.toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _updateCartQuantity(item['id'], 1),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2A1F),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Subtotal',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '₱${_subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Color(0xFF5DBB63),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Orders are separated automatically by farmer owner.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isCheckingOut ? null : _checkout,
                  icon: _isCheckingOut
                      ? const SizedBox.shrink()
                      : const Icon(Icons.shopping_bag_rounded),
                  label: _isCheckingOut
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Color(0xFF0A110D),
                          ),
                        )
                      : const Text(
                          'Checkout',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5DBB63),
                    foregroundColor: const Color(0xFF0A110D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrdersTab() {
    if (_isLoadingOrders) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF2F6B3B),
        ),
      );
    }

    if (_orders.isEmpty) {
      return _buildEmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'No buyer orders yet.',
        subtitle: 'Your mobile orders will appear here after checkout.',
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF2F6B3B),
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];

          final orderId = _shortOrderId(order);
          final status = order['status']?.toString() ?? 'Pending';
          final paymentStatus = order['payment_status']?.toString() ?? 'Unpaid';
          final deliveryStatus = order['delivery_status']?.toString() ?? status;
          final total = _toDouble(order['total_amount']);
          final confirmedReceived = order['confirmed_received'] == true;
          final items = List<Map<String, dynamic>>.from(
            order['order_items'] ?? [],
          );
          final proofUrl = order['proof_image_url']?.toString() ??
              order['delivery_proof_url']?.toString();

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      height: 52,
                      width: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F6B3B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
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
                            '#$orderId',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E2A1F),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${items.length} item${items.length == 1 ? '' : 's'}',
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
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F3EA),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _orderStepText(order),
                    style: const TextStyle(
                      color: Color(0xFF2F6B3B),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildStatusPill(status),
                    _buildStatusPill('Payment: $paymentStatus'),
                    _buildStatusPill('Delivery: $deliveryStatus'),
                    if (confirmedReceived) _buildStatusPill('Received'),
                  ],
                ),
                if (proofUrl != null && proofUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      proofUrl,
                      height: 130,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 130,
                          width: double.infinity,
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
                if (_canConfirmReceived(order)) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmReceived(order),
                      icon: const Icon(Icons.verified_rounded),
                      label: const Text(
                        'Confirm Received',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2F6B3B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusPill(String text) {
    final color = _statusColor(text);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
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

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F3EA),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF2F6B3B),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 82,
              color: Colors.grey.shade300,
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

class _CheckoutInfo {
  final String shippingName;
  final String shippingPhone;
  final String shippingAddress;
  final String paymentMethod;

  const _CheckoutInfo({
    required this.shippingName,
    required this.shippingPhone,
    required this.shippingAddress,
    required this.paymentMethod,
  });
}
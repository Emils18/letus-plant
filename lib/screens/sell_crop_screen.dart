import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/product_service.dart';

class SellCropScreen extends StatefulWidget {
  const SellCropScreen({super.key});

  @override
  State<SellCropScreen> createState() => _SellCropScreenState();
}

class _SellCropScreenState extends State<SellCropScreen> {
  final ProductService _service = ProductService();
  final ImagePicker _picker = ImagePicker();

  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _locationController = TextEditingController();
  final _descController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _farmerProductsFuture;

  String _category = 'Fresh Lettuce';
  String _badge = 'AI Verified';
  bool _isLoading = false;
  XFile? _selectedImage;
  Uint8List? _imageBytes;
  Map<String, dynamic>? _editingProduct;
  String _editingImageUrl = '';
  String? _workingProductId;
  bool _showListings = true;
  String _inventorySearch = '';
int _inventoryVisible = 12;

  @override
  void initState() {
    super.initState();
    _farmerProductsFuture = _service.getFarmerProducts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _locationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose a photo'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (!mounted || source == null) return;
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 80);
      if (image == null || !mounted) return;
      if (await image.length() > 5 * 1024 * 1024) {
        if (mounted) {
          _showMessage('Choose a photo smaller than 5 MB.', isError: true);
        }
        return;
      }
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImage = image;
        _imageBytes = bytes;
      });
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Could not open this photo. Please try again.',
          isError: true,
        );
      }
    }
  }

  void _refreshProducts() {
    if (!mounted) return;
    setState(() => _farmerProductsFuture = _service.getFarmerProducts());
  }

  void _startEditing(Map<String, dynamic> product) {
    final category = product['category']?.toString() ?? 'Fresh Lettuce';
    setState(() {
      _showListings = false;
      _editingProduct = product;
      _editingImageUrl =
          (product['image_url'] ?? product['image'])?.toString() ?? '';
      _nameController.text = product['name']?.toString() ?? '';
      _priceController.text = product['price']?.toString() ?? '';
      _stockController.text = product['stock']?.toString() ?? '0';
      _locationController.text = product['location']?.toString() ?? '';
      _descController.text =
          (product['description'] ?? product['freshness_info'])?.toString() ??
          '';
      _category = category.isEmpty ? 'Fresh Lettuce' : category;
      _badge = product['badge']?.toString() ?? 'AI Verified';
      _selectedImage = null;
      _imageBytes = null;
    });
  }

  void _cancelEditing() {
    setState(() {
      _showListings = true;
      _editingProduct = null;
      _editingImageUrl = '';
      _nameController.clear();
      _priceController.clear();
      _stockController.clear();
      _locationController.clear();
      _descController.clear();
      _category = 'Fresh Lettuce';
      _badge = 'AI Verified';
      _selectedImage = null;
      _imageBytes = null;
    });
  }

  Future<void> _restockProduct(Map<String, dynamic> product) async {
    final formKey = GlobalKey<FormState>();
    final stock = int.tryParse(product['stock']?.toString() ?? '') ?? 0;
    int? quantity;
    final additionalStock = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Add crop stock'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current stock: $stock'),
                const SizedBox(height: 12),
                TextFormField(
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  onChanged: (value) => setDialogState(
                    () => quantity = int.tryParse(value.trim()),
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Units to add',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final units = int.tryParse(value?.trim() ?? '');
                    if (units == null || units <= 0) {
                      return 'Enter a positive whole number.';
                    }
                    if (units > ProductService.maxStock - stock) {
                      return 'The total stock is too large.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Estimated total: ${quantity != null && quantity! > 0 && quantity! <= ProductService.maxStock - stock ? stock + quantity! : stock}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(dialogContext, quantity);
              },
              child: const Text('Add stock'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || additionalStock == null) return;

    final id = product['id']?.toString() ?? '';
    setState(() => _workingProductId = id);
    final newStock = await _service.restockProduct(
      productId: product['id'],
      additionalStock: additionalStock,
    );
    if (!mounted) return;
    setState(() => _workingProductId = null);
    if (newStock == null) {
      _showMessage(
        'Could not update stock. Refresh the listing and try again.',
        isError: true,
      );
      return;
    }
    _refreshProducts();
    _showMessage('Stock updated. New quantity: $newStock');
  }

  Future<void> _deleteProduct(Map<String, dynamic> product) async {
    final name = product['name']?.toString() ?? 'this product';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this listing?'),
        content: Text(
          '“$name” will be removed from the marketplace. Existing orders and their history will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep listing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final id = product['id']?.toString() ?? '';
    setState(() => _workingProductId = id);
    final hasOrderHistory = await _service.archiveProduct(product['id']);
    if (!mounted) return;
    setState(() => _workingProductId = null);
    if (hasOrderHistory == null) {
      _showMessage(
        'Could not remove this listing. Refresh My Products and try again.',
        isError: true,
      );
      return;
    }
    if (_editingProduct?['id']?.toString() == id) _cancelEditing();
    _refreshProducts();
    _showMessage(
      hasOrderHistory
          ? 'Listing removed from sale. Its orders and order history were kept.'
          : 'Listing removed from sale.',
    );
  }

  Future<void> _publishProduct() async {
    final name = _nameController.text.trim();
    final priceText = _priceController.text.trim();
    final stock = int.tryParse(_stockController.text.trim());
    final location = _locationController.text.trim();
    final description = _descController.text.trim();

    final price = double.tryParse(priceText) ?? 0;

    final isEditing = _editingProduct != null;
    if (name.isEmpty ||
        location.isEmpty ||
        description.isEmpty ||
        !price.isFinite ||
        price <= 0 ||
        stock == null ||
        stock < 0 ||
        stock > ProductService.maxStock ||
        (!isEditing && stock == 0)) {
      _showMessage(
        'Enter a name, location, description, valid price, and valid stock quantity.',
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    final productData = {
      'name': name,
      'category': _category,
      'price': price,
      'stock': stock,
      'badge': _badge,
      'description': description,
      'location': location,
    };
    final success = isEditing
        ? await _service.updateProduct(
            productId: _editingProduct!['id'],
            originalStock: int.tryParse(
              _editingProduct!['stock']?.toString() ?? '',
            ),
            productData: productData,
            imageFile: _selectedImage,
          )
        : await _service.publishProduct(
            productData: productData,
            imageFile: _selectedImage,
          );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      _showMessage(
        isEditing
            ? 'Product updated successfully.'
            : 'Product published successfully!',
      );
      _cancelEditing();
      _refreshProducts();
    } else {
      _showMessage(
        isEditing
            ? 'Could not save. If stock changed, reopen the listing and try again.'
            : 'Failed to publish product. Try again.',
        isError: true,
      );
    }
  }

  Widget _buildExistingProducts() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _farmerProductsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: OutlinedButton.icon(
              onPressed: _refreshProducts,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry loading products'),
            ),
          );
        }

        final products = snapshot.data ?? <Map<String, dynamic>>[];

        final filtered = products.where((product) {
          final text =
              '${product['name'] ?? ''} ${product['category'] ?? ''}'
                  .toLowerCase();
          return text.contains(_inventorySearch.toLowerCase());
        }).toList();

        final available = products.where((product) =>
            (num.tryParse('${product['stock'] ?? 0}') ?? 0) > 0).length;

        final lowStock = products.where((product) {
          final stock = num.tryParse('${product['stock'] ?? 0}') ?? 0;
          return stock > 0 && stock <= 5;
        }).length;

        final busy = _workingProductId != null || _isLoading;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(23),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF173E29),
                    Color(0xFF2F6B3B),
                    Color(0xFF46945A),
                  ],
                ),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.inventory_2_rounded,
                    color: Color(0xFFD8F973),
                    size: 34,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Manage Your Harvest',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Your inventory. Your crops. Your control.',
                    style: TextStyle(color: Color(0xFFE1F1E2)),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(child: _inventoryMetric(
                        '${products.length}', 'Products')),
                      const SizedBox(width: 8),
                      Expanded(child: _inventoryMetric(
                        '$available', 'Available')),
                      const SizedBox(width: 8),
                      Expanded(child: _inventoryMetric(
                        '$lowStock', 'Low Stock')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              onChanged: (value) => setState(() {
                _inventorySearch = value;
                _inventoryVisible = 12;
              }),
              decoration: InputDecoration(
                hintText: 'Search your products...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${filtered.length} Listings',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF173E29),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : _refreshProducts,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(25),
                child: Center(
                  child: Text('No matching products found.'),
                ),
              ),
            ...filtered.take(_inventoryVisible).map((product) {
              final id = '${product['id'] ?? ''}';
              final stock =
                  num.tryParse('${product['stock'] ?? 0}') ?? 0;
              final price =
                  num.tryParse('${product['price'] ?? 0}') ?? 0;
              final image = '${product['image_url'] ??
                  product['image'] ?? ''}';
              final working = _workingProductId == id;

              return Container(
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFDDE9DC),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: .08),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 170,
                      width: double.infinity,
                      child: image.isEmpty
                          ? const ColoredBox(
                              color: Color(0xFFEAF5E9),
                              child: Icon(Icons.eco, size: 55),
                            )
                          : Image.network(
                              image,
                              fit: BoxFit.cover,
                              errorBuilder: (_, error, stack) =>
                                  const ColoredBox(
                                color: Color(0xFFEAF5E9),
                                child: Icon(Icons.eco, size: 55),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${product['category'] ?? 'Fresh Crops'}'
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF2F6B3B),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${product['name'] ?? 'Product'}',
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF173E29),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '₱${price.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF2F6B3B),
                                  ),
                                ),
                              ),
                              Text(
                                '$stock in stock',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          Wrap(
                            spacing: 9,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => _restockProduct(product),
                                icon: const Icon(Icons.add_box_outlined),
                                label: Text(
                                  working ? 'Working...' : 'Restock',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      const Color(0xFF2F6B3B),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => _startEditing(product),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Edit'),
                              ),
                              OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => _deleteProduct(product),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                label: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (filtered.length > _inventoryVisible)
              Center(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _inventoryVisible += 12),
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Show More Products'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _inventoryMetric(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFD8F973),
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }


  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF2F6B3B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
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
          'Crop Marketplace',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 24,
            color: Color(0xFF1E2A1F),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F), size: 32),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: [
                  const ButtonSegment(value: true, label: Text('My Products')),
                  ButtonSegment(
                    value: false,
                    label: Text(
                      _editingProduct == null ? 'Publish Crop' : 'Edit Product',
                    ),
                  ),
                ],
                showSelectedIcon: false,
                selected: {_showListings},
                onSelectionChanged: _isLoading || _workingProductId != null
                    ? null
                    : (selection) =>
                          setState(() => _showListings = selection.first),
              ),
            ),
            const SizedBox(height: 22),
            if (!_showListings) ...[
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2A1F),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF5DBB63),
                      size: 40,
                    ),
                    SizedBox(width: 20),
                    Expanded(
                      child: Text(
                        'Publish your lettuce crop to the shared GreenGuard AI marketplace.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),
            ],
            if (_showListings) ...[
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manage Products',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1E2A1F),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Edit details, add stock, or remove a listing.',
                          style: TextStyle(color: Color(0xFF5C6B5D)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh listings',
                    onPressed: _refreshProducts,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Color(0xFF2F6B3B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildExistingProducts(),
            ],
            if (!_showListings) ...[
              Text(
                _editingProduct == null
                    ? 'Publish New Crop'
                    : 'Edit Product Details',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E2A1F),
                ),
              ),
              if (_editingProduct != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Editing ${_editingProduct!['name'] ?? 'product'}',
                        style: const TextStyle(color: Color(0xFF5C6B5D)),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _cancelEditing,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel'),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              // Image Upload
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: _imageBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.memory(
                            _imageBytes!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.error,
                                  color: Colors.red,
                                  size: 48,
                                ),
                              );
                            },
                          ),
                        )
                      : _editingImageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.network(
                            _editingImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.grey,
                                    size: 48,
                                  ),
                                ),
                          ),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo_rounded,
                              size: 48,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Tap to upload product photo',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 24),

              _buildTextField(
                controller: _nameController,
                label: 'Product Name',
                icon: Icons.grass_rounded,
              ),

              const SizedBox(height: 24),

              _buildDropdown(),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _priceController,
                      label: 'Price (₱)',
                      icon: Icons.payments_rounded,
                      isNumber: true,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _buildTextField(
                      controller: _stockController,
                      label: 'Stock Qty',
                      icon: Icons.inventory_2_rounded,
                      isNumber: true,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              _buildTextField(
                controller: _locationController,
                label: 'Farm Location',
                icon: Icons.location_on_rounded,
              ),

              const SizedBox(height: 24),

              _buildTextField(
                controller: _descController,
                label: 'Description',
                icon: Icons.description_rounded,
                maxLines: 4,
              ),

              const SizedBox(height: 24),

              _buildBadgeSelector(),

              const SizedBox(height: 48),

              SizedBox(
                width: double.infinity,
                height: 72,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _publishProduct,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5DBB63),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 6,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 4,
                        )
                      : Text(
                          _editingProduct == null
                              ? 'Publish Product'
                              : 'Save Product Changes',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _category,
          isExpanded: true,
          icon: const Icon(
            Icons.arrow_drop_down_rounded,
            color: Color(0xFF2F6B3B),
            size: 32,
          ),
          items: [
            if (!const [
              'Fresh Lettuce',
              'Seeds',
              'Bundles',
            ].contains(_category))
              DropdownMenuItem(value: _category, child: Text(_category)),
            const DropdownMenuItem(
              value: 'Fresh Lettuce',
              child: Text(
                'Fresh Lettuce',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const DropdownMenuItem(
              value: 'Seeds',
              child: Text(
                'Seeds',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const DropdownMenuItem(
              value: 'Bundles',
              child: Text(
                'Bundles',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
          onChanged: (val) {
            if (val == null) return;
            setState(() => _category = val);
          },
        ),
      ),
    );
  }

  Widget _buildBadgeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _badge,
          isExpanded: true,
          icon: const Icon(
            Icons.arrow_drop_down_rounded,
            color: Color(0xFF2F6B3B),
            size: 32,
          ),
          items: const [
            DropdownMenuItem(
              value: 'AI Verified',
              child: Text(
                'AI Verified',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            DropdownMenuItem(
              value: 'Healthy',
              child: Text(
                'Healthy',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            DropdownMenuItem(
              value: 'Fresh Harvest',
              child: Text(
                'Fresh Harvest',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            DropdownMenuItem(
              value: 'Grade A',
              child: Text(
                'Grade A',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ],
          onChanged: (val) {
            if (val == null) return;
            setState(() => _badge = val);
          },
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isNumber = false,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        maxLines: maxLines,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E2A1F),
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 18),
          prefixIcon: Icon(icon, color: const Color(0xFF2F6B3B), size: 32),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 20,
          ),
        ),
      ),
    );
  }
}

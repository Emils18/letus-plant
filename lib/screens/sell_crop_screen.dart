import 'package:flutter/material.dart';

import '../services/product_service.dart';

class SellCropScreen extends StatefulWidget {
  const SellCropScreen({super.key});

  @override
  State<SellCropScreen> createState() => _SellCropScreenState();
}

class _SellCropScreenState extends State<SellCropScreen> {
  final ProductService _service = ProductService();

  final _nameController = TextEditingController(text: 'Fresh Lettuce');
  final _priceController = TextEditingController(text: '120');
  final _stockController = TextEditingController(text: '50');
  final _locationController = TextEditingController(text: 'Cebu Farm');
  final _descController = TextEditingController(
    text: 'AI verified lettuce crop. Fresh, healthy, and ready for sale.',
  );

  String _category = 'Fresh Lettuce';
  String _badge = 'AI Verified';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _locationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _publishProduct() async {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;
    final location = _locationController.text.trim();
    final description = _descController.text.trim();

    if (name.isEmpty ||
        location.isEmpty ||
        description.isEmpty ||
        _priceController.text.trim().isEmpty ||
        _stockController.text.trim().isEmpty) {
      _showMessage('Please complete all product fields.', isError: true);
      return;
    }

    if (price <= 0) {
      _showMessage('Please enter a valid product price.', isError: true);
      return;
    }

    if (stock <= 0) {
      _showMessage('Please enter a valid stock quantity.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final success = await _service.publishProduct({
      'name': name,
      'category': _category,
      'price': price,
      'stock': stock,
      'badge': _badge,
      'description': description,
      'location': location,
    });

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      _showMessage('Product published successfully.');
      Navigator.pop(context);
    } else {
      _showMessage('Failed to publish product.', isError: true);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Sell Crop',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Color(0xFF1E2A1F),
          ),
        ),
        iconTheme: const IconThemeData(
          color: Color(0xFF1E2A1F),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2A1F),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.verified_rounded,
                    color: Color(0xFF5DBB63),
                    size: 30,
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Publish your lettuce crop to the shared GreenGuard AI marketplace.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Product Info',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 16),

            _buildTextField(
              controller: _nameController,
              label: 'Product Name',
              icon: Icons.grass_rounded,
            ),

            const SizedBox(height: 16),

            _buildDropdown(),

            const SizedBox(height: 16),

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
                const SizedBox(width: 16),
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

            const SizedBox(height: 16),

            _buildTextField(
              controller: _locationController,
              label: 'Farm Location',
              icon: Icons.location_on_rounded,
            ),

            const SizedBox(height: 16),

            _buildTextField(
              controller: _descController,
              label: 'Description',
              icon: Icons.description_rounded,
              maxLines: 3,
            ),

            const SizedBox(height: 16),

            _buildBadgeSelector(),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _publishProduct,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5DBB63),
                  foregroundColor: const Color(0xFF0A110D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 4,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Color(0xFF0A110D),
                          strokeWidth: 3,
                        ),
                      )
                    : const Text(
                        'Publish Product',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
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
          ),
          items: const [
            DropdownMenuItem(
              value: 'Fresh Lettuce',
              child: Text(
                'Fresh Lettuce',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DropdownMenuItem(
              value: 'Premium Lettuce',
              child: Text(
                'Premium Lettuce',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DropdownMenuItem(
              value: 'Seeds',
              child: Text(
                'Seeds',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DropdownMenuItem(
              value: 'Bulk Orders',
              child: Text(
                'Bulk Orders',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          onChanged: (val) {
            if (val == null) return;

            setState(() {
              _category = val;
            });
          },
        ),
      ),
    );
  }

  Widget _buildBadgeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
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
          ),
          items: const [
            DropdownMenuItem(
              value: 'AI Verified',
              child: Text(
                'AI Verified',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DropdownMenuItem(
              value: 'Healthy',
              child: Text(
                'Healthy',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DropdownMenuItem(
              value: 'Fresh Harvest',
              child: Text(
                'Fresh Harvest',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DropdownMenuItem(
              value: 'Grade A',
              child: Text(
                'Grade A',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          onChanged: (val) {
            if (val == null) return;

            setState(() {
              _badge = val;
            });
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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E2A1F),
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 13,
          ),
          prefixIcon: Icon(
            icon,
            color: const Color(0xFF2F6B3B),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }
}
import 'dart:io';
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

  String _category = 'Fresh Lettuce';
  String _badge = 'AI Verified';
  bool _isLoading = false;
  XFile? _selectedImage;
  Uint8List? _imageBytes;   // For web + mobile preview

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
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _selectedImage = image;
        _imageBytes = bytes;
      });
    }
  }

  Future<void> _publishProduct() async {
    final name = _nameController.text.trim();
    final priceText = _priceController.text.trim();
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;
    final location = _locationController.text.trim();
    final description = _descController.text.trim();

    final price = double.tryParse(priceText) ?? 0;

    if (name.isEmpty || location.isEmpty || description.isEmpty || price <= 0 || stock <= 0) {
      _showMessage('Please complete all fields correctly.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final success = await _service.publishProduct(
      productData: {
        'name': name,
        'category': _category,
        'price': price,
        'stock': stock,
        'badge': _badge,
        'description': description,
        'location': location,
      },
      imageFile: _selectedImage,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      _showMessage('Product published successfully!');
      Navigator.pop(context);
    } else {
      _showMessage('Failed to publish product. Try again.', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
        title: const Text('Sell Crop', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Color(0xFF1E2A1F))),
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F), size: 32),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  Icon(Icons.verified_rounded, color: Color(0xFF5DBB63), size: 40),
                  SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      'Publish your lettuce crop to the shared GreenGuard AI marketplace.',
                      style: TextStyle(color: Colors.white, fontSize: 18, height: 1.4, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            const Text('Product Info', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),

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
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: _imageBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.memory(
                          _imageBytes!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(child: Icon(Icons.error, color: Colors.red, size: 48));
                          },
                        ),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_rounded, size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('Tap to upload product photo', style: TextStyle(fontSize: 18, color: Colors.grey)),
                        ],
                      ),
              ),
            ),
            

            const SizedBox(height: 24),

            _buildTextField(controller: _nameController, label: 'Product Name', icon: Icons.grass_rounded),

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

            _buildTextField(controller: _locationController, label: 'Farm Location', icon: Icons.location_on_rounded),

            const SizedBox(height: 24),

            _buildTextField(controller: _descController, label: 'Description', icon: Icons.description_rounded, maxLines: 4),

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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 6,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 4)
                    : const Text('Publish Product', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              ),
            ),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _category,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF2F6B3B), size: 32),
          items: const [
            DropdownMenuItem(value: 'Fresh Lettuce', child: Text('Fresh Lettuce', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            DropdownMenuItem(value: 'Seeds', child: Text('Seeds', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            DropdownMenuItem(value: 'Bundles', child: Text('Bundles', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _badge,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF2F6B3B), size: 32),
          items: const [
            DropdownMenuItem(value: 'AI Verified', child: Text('AI Verified', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            DropdownMenuItem(value: 'Healthy', child: Text('Healthy', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            DropdownMenuItem(value: 'Fresh Harvest', child: Text('Fresh Harvest', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            DropdownMenuItem(value: 'Grade A', child: Text('Grade A', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12)],
      ),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E2A1F)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 18),
          prefixIcon: Icon(icon, color: const Color(0xFF2F6B3B), size: 32),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      ),
    );
  }
}
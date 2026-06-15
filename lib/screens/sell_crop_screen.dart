import 'package:flutter/material.dart';
import '../services/product_service.dart';

class SellCropScreen extends StatefulWidget {
  const SellCropScreen({super.key});

  @override
  State<SellCropScreen> createState() => _SellCropScreenState();
}

class _SellCropScreenState extends State<SellCropScreen> {
  final ProductService _service = ProductService();
  
  // Auto-filled for Demo
  final _nameController = TextEditingController(text: 'Fresh Lettuce');
  final _priceController = TextEditingController(text: '120');
  final _stockController = TextEditingController(text: '50');
  final _locationController = TextEditingController(text: 'Cebu Farm');
  final _descController = TextEditingController(text: '100% Healthy. Optimal soil and light monitored.');
  
  String _category = 'Fresh Lettuce';
  bool _isLoading = false;

  void _publishProduct() async {
    setState(() => _isLoading = true);
    
    final success = await _service.publishProduct({
      'name': _nameController.text,
      'category': _category,
      'price': double.tryParse(_priceController.text) ?? 0,
      'stock': int.tryParse(_stockController.text) ?? 0,
      'badge': 'Grade A',
      'description': _descController.text,
      'location': _locationController.text,
    });

    setState(() => _isLoading = false);
    
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product published! (Demo Mode)'), backgroundColor: Color(0xFF2F6B3B)));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to publish product.'), backgroundColor: Colors.red));
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
        title: const Text('Sell Crop', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E2A1F))),
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1E2A1F), borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Color(0xFF5DBB63), size: 30),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Suggested from Demo Monitoring', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 4),
                        const Text('Scan is 100% Healthy. Suggested price: ₱120.', style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            const Text('Product Info', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            
            _buildTextField(controller: _nameController, label: 'Product Name', icon: Icons.grass_rounded),
            const SizedBox(height: 16),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _category,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF2F6B3B)),
                  items: ['Fresh Lettuce', 'Lettuce Seed'].map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                  onChanged: (val) => setState(() => _category = val!),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(child: _buildTextField(controller: _priceController, label: 'Price (₱)', icon: Icons.payments_rounded, isNumber: true)),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField(controller: _stockController, label: 'Stock Qty', icon: Icons.inventory_2_rounded, isNumber: true)),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(controller: _locationController, label: 'Farm Location', icon: Icons.location_on_rounded),
            const SizedBox(height: 16),
            _buildTextField(controller: _descController, label: 'Description', icon: Icons.description_rounded, maxLines: 3),
            
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _publishProduct,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5DBB63), foregroundColor: const Color(0xFF0A110D), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 4),
                child: _isLoading 
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Color(0xFF0A110D), strokeWidth: 3))
                  : const Text('Publish (Demo)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, bool isNumber = false, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)]),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E2A1F)),
        decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13), prefixIcon: Icon(icon, color: const Color(0xFF2F6B3B)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), filled: true, fillColor: Colors.white),
      ),
    );
  }
}
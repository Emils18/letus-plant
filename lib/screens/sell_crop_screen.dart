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
  List<Map<String, dynamic>> _myProducts = [];
  bool _loadingProducts = true;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _locationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final rows = await _service.getFarmerProducts();
    if (!mounted) return;
    setState(() { _myProducts = rows; _loadingProducts = false; });
  }

  Future<void> _editProduct(Map<String, dynamic> product) async {
    _nameController.text = '${product['name'] ?? ''}';
    _priceController.text = '${product['price'] ?? ''}';
    _stockController.text = '${product['stock'] ?? 0}';
    _locationController.text = '${product['location'] ?? ''}';
    _descController.text = '${product['description'] ?? ''}';
    setState(() { _category = '${product['category'] ?? 'Fresh Lettuce'}'; _imageBytes = null; _selectedImage = null; });
    final result = await showModalBottomSheet<bool>(context: context, isScrollControlled: true,
      builder: (context) => SafeArea(child: Padding(padding: EdgeInsets.only(left: 20,right: 20,top: 20,bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Product name')),
          TextField(controller: _descController, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
          TextField(controller: _priceController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price')),
          DropdownButtonFormField<String>(value: _category, decoration: const InputDecoration(labelText: 'Category'), items: const ['Fresh Lettuce','Seeds','Bundles'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(), onChanged:(v){if(v!=null)setState(()=>_category=v);}),
          TextField(controller: _stockController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock quantity')),
          TextButton.icon(onPressed: _pickImage, icon: const Icon(Icons.image), label: const Text('Replace photo')),
          if (_imageBytes != null) Image.memory(_imageBytes!,height:100),
          FilledButton(onPressed: () async { final stock=int.tryParse(_stockController.text); final price=double.tryParse(_priceController.text); if(_nameController.text.trim().isEmpty||_descController.text.trim().isEmpty||stock==null||stock<0||price==null||price<=0){_showMessage('Enter valid product details.',isError:true);return;} final ok=await _service.updateFarmerProduct(productId: int.parse('${product['id']}'),fields:{'name':_nameController.text.trim(),'description':_descController.text.trim(),'freshness_info':_descController.text.trim(),'price':price,'category':_category,'stock':stock},imageFile:_selectedImage); if(context.mounted) Navigator.pop(context,ok); }, child: const Text('Save changes')),
        ])))));
    if (result == true) { _showMessage('Product updated.'); await _loadProducts(); }
    else if (result == false) _showMessage('Could not update product.',isError:true);
  }

  Future<void> _restock(Map<String,dynamic> product) async {
    final controller=TextEditingController();
    final amount=await showDialog<int>(context:context,builder:(context)=>AlertDialog(title:const Text('Restock product'),content:TextField(controller:controller,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Units to add')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,int.tryParse(controller.text)),child:const Text('Add stock'))]));
    controller.dispose(); if(amount==null)return;
    final ok=await _service.restockFarmerProduct(int.parse('${product['id']}'),amount);
    if(ok){_showMessage('Stock updated.');await _loadProducts();}else _showMessage('Could not restock product.',isError:true);
  }

  Future<void> _unlist(Map<String,dynamic> product) async {
    final yes=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('Unlist product?'),content:const Text('This removes the listing from sale. Existing order history stays محفوظ.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Unlist'))]));
    if(yes!=true)return; final ok=await _service.archiveFarmerProduct(int.parse('${product['id']}'));
    if(ok){_showMessage('Product unlisted.');await _loadProducts();}else _showMessage('Could not unlist product.',isError:true);
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
            _buildManageListings(),
            const SizedBox(height: 28),
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

  Widget _buildManageListings() {
    return Card(color: Colors.white, child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('Manage Listings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
          IconButton(onPressed: _loadProducts, icon: const Icon(Icons.refresh))]),
        if (_loadingProducts) const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else if (_myProducts.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No products listed yet.'))
        else SizedBox(height: 310, child: ListView.separated(itemCount: _myProducts.length,
          separatorBuilder: (_, __) => const Divider(height: 12),
          itemBuilder: (context, index) {
            final p = _myProducts[index];
            final stock = int.tryParse('${p['stock'] ?? 0}') ?? 0;
            final archived = p['archived_at'] != null;
            final image = '${p['image_url'] ?? p['image'] ?? ''}';
            return Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFF6FBF7), borderRadius: BorderRadius.circular(14)),
              child: Column(children: [Row(children: [ClipRRect(borderRadius: BorderRadius.circular(10), child: image.isEmpty ? Container(width:64,height:64,color:Colors.green.shade100,child:const Icon(Icons.eco)) : Image.network(image,width:64,height:64,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(width:64,height:64,color:Colors.green.shade100,child:const Icon(Icons.broken_image)))),
                const SizedBox(width:12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,children:[Text('${p['name'] ?? 'Product'}',style:const TextStyle(fontWeight:FontWeight.w800)),Text('${p['category'] ?? ''} • ₱${p['price'] ?? 0}',style:const TextStyle(fontSize:13)),Text('Stock: $stock • ${archived ? 'Unlisted' : stock == 0 ? 'Out of Stock' : 'Available'}',style:TextStyle(color:archived||stock==0?Colors.red:Colors.green,fontWeight:FontWeight.w700))]))]),
                Wrap(spacing:8,children:[TextButton.icon(onPressed:archived?null:()=>_editProduct(p),icon:const Icon(Icons.edit),label:const Text('Edit')),TextButton.icon(onPressed:archived?null:()=>_restock(p),icon:const Icon(Icons.add_box),label:const Text('Restock')),TextButton.icon(onPressed:archived?null:()=>_unlist(p),icon:const Icon(Icons.archive),label:const Text('Unlist'))])
              ]));
          }))
      ])));
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

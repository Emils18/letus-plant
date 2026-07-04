import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sell_crop_screen.dart';

class PlantTrackingScreen extends StatefulWidget {
  const PlantTrackingScreen({super.key});

  @override
  State<PlantTrackingScreen> createState() => _PlantTrackingScreenState();
}

class _PlantTrackingScreenState extends State<PlantTrackingScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  Map<String, dynamic>? _latestProduct;

  @override
  void initState() {
    super.initState();
    _loadLatestProduct();
  }

  Future<void> _loadLatestProduct() async {
    setState(() => _loading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final response = await _supabase
          .from('products')
          .select()
          .eq('farmer_id', user.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      setState(() {
        _latestProduct = response;
      });
    } catch (e) {
      debugPrint('Error loading product: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _getBatchNumber() {
    if (_latestProduct == null) return 'NO BATCH';
    
    final id = _latestProduct!['id']?.toString() ?? '';
    if (id.length >= 6) {
      return 'BATCH #${id.substring(0, 6)}';
    } else if (id.isNotEmpty) {
      return 'BATCH #$id';
    } else {
      return 'BATCH #001';
    }
  }

  @override
  Widget build(BuildContext context) {
    final productName = _latestProduct?['name'] ?? 'No Product Yet';
    final location = _latestProduct?['location'] ?? 'Cebu Farm';
    
    String plantedDate = 'N/A';
    if (_latestProduct != null) {
      final createdAt = _latestProduct!['created_at']?.toString();
      if (createdAt != null && createdAt.length >= 10) {
        plantedDate = createdAt.substring(0, 10);
      }
    }

    final currentStageIndex = _latestProduct != null ? 3 : 0;
    final stages = ['Planted', 'Seedling', 'Growing', 'Harvest Ready', 'Harvested'];

    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('Crop Tracking', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E2A1F))),
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2F6B3B)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2F6B3B), Color(0xFF1E4A27)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2F6B3B).withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _getBatchNumber(),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          productName,
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildInfoCol('Planted', plantedDate, Icons.calendar_month_rounded),
                            _buildInfoCol('Location', location, Icons.location_on_rounded),
                            _buildInfoCol('Est. Harvest', 'Apr 30', Icons.shopping_basket_rounded),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  const Text('Growth Timeline', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      children: List.generate(stages.length, (index) {
                        final isCompleted = index <= currentStageIndex;
                        final isCurrent = index == currentStageIndex;
                        final isLast = index == stages.length - 1;

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Container(
                                  height: 28,
                                  width: 28,
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? const Color(0xFF5DBB63)
                                        : isCompleted
                                            ? const Color(0xFF2F6B3B)
                                            : Colors.grey.shade200,
                                    shape: BoxShape.circle,
                                    border: isCurrent
                                        ? Border.all(color: const Color(0xFF5DBB63).withValues(alpha: 0.3), width: 4)
                                        : null,
                                  ),
                                  child: isCompleted && !isCurrent
                                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                                      : isCurrent
                                          ? const Icon(Icons.grass_rounded, color: Colors.white, size: 14)
                                          : null,
                                ),
                                if (!isLast)
                                  Container(
                                    height: 40,
                                    width: 2,
                                    color: isCompleted ? const Color(0xFF2F6B3B) : Colors.grey.shade200,
                                  ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4, bottom: 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      stages[index],
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: isCurrent ? FontWeight.w900 : FontWeight.bold,
                                        color: isCurrent
                                            ? const Color(0xFF5DBB63)
                                            : isCompleted
                                                ? const Color(0xFF1E2A1F)
                                                : Colors.grey.shade400,
                                      ),
                                    ),
                                    if (isCurrent && stages[index] == 'Harvest Ready')
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: ElevatedButton.icon(
                                          onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (_) => const SellCropScreen()),
                                          ),
                                          icon: const Icon(Icons.storefront),
                                          label: const Text('Ready to Sell'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF5DBB63),
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCol(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 14),
            const SizedBox(width: 4),
            Text(label.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
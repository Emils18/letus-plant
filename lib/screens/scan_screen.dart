import 'package:flutter/material.dart';
import '../widgets/recommendation_card.dart';
import 'sell_crop_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _isScanning = false;
  bool _hasResult = false;
  String _result = "";
  String _recommendation = "";
  Color _resultColor = Colors.grey;

  void _simulateScan() async {
    setState(() {
      _isScanning = true;
      _hasResult = false;
    });

    await Future.delayed(const Duration(seconds: 2)); // Mock ESP32-CAM delay

    final results = [
      {"res": "Healthy", "rec": "Plant is in perfect condition. Ready for premium pricing.", "col": const Color(0xFF2F6B3B)},
      {"res": "Downy Mildew", "rec": "Fungal issue detected. Remove affected leaves and apply organic fungicide.", "col": Colors.redAccent},
      {"res": "Bacterial Leaf Spot", "rec": "Bacterial infection. Avoid overhead watering.", "col": Colors.orange},
      {"res": "Aphids", "rec": "Pest detected. Apply neem oil.", "col": Colors.brown},
    ];
    results.shuffle();
    final chosen = results.first;

    setState(() {
      _isScanning = false;
      _hasResult = true;
      _result = chosen["res"] as String;
      _recommendation = chosen["rec"] as String;
      _resultColor = chosen["col"] as Color;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('ESP32-CAM AI Scan', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E2A1F))),
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              height: 300,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.green.withValues(alpha: 0.2), width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20)],
              ),
              child: _isScanning
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Color(0xFF2F6B3B)),
                        const SizedBox(height: 16),
                        Text('Analyzing image from ESP32-CAM...', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
                      ],
                    )
                  : _hasResult
                      ? Center(child: Icon(Icons.image_rounded, size: 80, color: Colors.grey.shade300))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt_rounded, size: 60, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('Camera Ready', style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.bold)),
                          ],
                        ),
            ),
            const SizedBox(height: 32),

            if (_hasResult) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _resultColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _resultColor.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text('SCAN RESULT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _resultColor, letterSpacing: 2)),
                    const SizedBox(height: 8),
                    Text(_result, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _resultColor)),
                    const SizedBox(height: 16),
                    Text(DateTime.now().toString().substring(0, 16), style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              RecommendationCard(text: _recommendation, isUrgent: _result != "Healthy"),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SellCropScreen())),
                  icon: const Icon(Icons.storefront),
                  label: const Text('Use Result for Sell Crop Quality'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2A1F), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                ),
              ),
            ] else ...[
              const Text('Pathogen Scope Supported:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _badge('Healthy', Colors.green),
                  const SizedBox(width: 8),
                  _badge('Downy Mildew', Colors.red),
                  const SizedBox(width: 8),
                  _badge('Leaf Spot', Colors.orange),
                ],
              ),
              const SizedBox(height: 40),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _simulateScan,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Simulate Scan (Demo)'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5DBB63), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
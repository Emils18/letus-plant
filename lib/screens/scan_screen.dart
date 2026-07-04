import 'package:flutter/material.dart';

import '../services/monitoring_service.dart';
import 'plant_tracking_screen.dart';

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
  double _confidence = 0.0;
  Color _resultColor = Colors.grey;

  final List<Map<String, dynamic>> _supportedDiseases = [
    {
      "name": "Downy Mildew",
      "fullName": "Downy Mildew — Bremia lactucae",
      "rec": "Fungal issue detected. Remove affected leaves and apply organic fungicide.",
      "color": Colors.redAccent,
    },
    {
      "name": "Powdery Mildew",
      "fullName": "Powdery Mildew — Erysiphe cichoracearum",
      "rec": "Powdery mildew detected. Improve air circulation and apply appropriate treatment.",
      "color": Colors.orangeAccent,
    },
    {
      "name": "Septoria Blight",
      "fullName": "Septoria Blight — Septoria lactucae",
      "rec": "Septoria blight detected. Remove infected leaves and avoid overhead watering.",
      "color": Colors.deepOrange,
    },
  ];

  final MonitoringService _monitoringService = MonitoringService();

  void _simulateScan() async {
    setState(() {
      _isScanning = true;
      _hasResult = false;
    });

    await Future.delayed(const Duration(seconds: 2));

    final random = DateTime.now().millisecond % 4;
    late Map<String, dynamic> chosen;

    if (random == 3) {
      chosen = {
        "name": "Unknown Disease",
        "fullName": "Unknown / Out of Scope Disease",
        "rec": "Disease detected is outside current AI scope. Manual inspection recommended.",
        "color": Colors.grey,
      };
      _confidence = 0.45;
    } else {
      chosen = _supportedDiseases[random];
      _confidence = 0.82 + (random * 0.04);
    }

    // Save to Health Logs
    final success = await _monitoringService.saveHealthLogDemo(
      diseaseName: chosen["fullName"],
      confidence: _confidence,
    );

    setState(() {
      _isScanning = false;
      _hasResult = true;
      _result = chosen["fullName"] as String;
      _recommendation = chosen["rec"] as String;
      _resultColor = chosen["color"] as Color;
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
                      ? Center(child: Icon(Icons.check_circle, size: 80, color: _resultColor))
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
                    const Text('SCAN RESULT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 2)),
                    const SizedBox(height: 8),
                    Text(_result, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _resultColor)),
                    const SizedBox(height: 8),
                    Text("Confidence: ${(_confidence * 100).toStringAsFixed(1)}%", style: const TextStyle(fontSize: 14, color: Colors.orange, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text("Demo Mode", style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Text(DateTime.now().toString().substring(0, 16), style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(_recommendation, style: const TextStyle(fontSize: 14, height: 1.5)),
              ),
              const SizedBox(height: 24),

              // Button to go to Crop Tracking
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlantTrackingScreen()));
                  },
                  icon: const Icon(Icons.track_changes),
                  label: const Text('Go to Crop Tracking'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2F6B3B), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                ),
              ),
            ] else ...[
              const Text('Supported Diseases (Demo):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _badge('Downy Mildew', Colors.red),
                  _badge('Powdery Mildew', Colors.orange),
                  _badge('Septoria Blight', Colors.deepOrange),
                  _badge('Unknown (Other)', Colors.grey),
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
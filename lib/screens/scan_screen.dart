import 'package:flutter/material.dart';

import '../services/monitoring_service.dart';
import 'shared/health_logs_screen.dart'; // <-- Add this import

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
    {"name": "Downy Mildew", "fullName": "Downy Mildew — Bremia lactucae", "rec": "Remove affected leaves and apply organic fungicide.", "color": Colors.redAccent},
    {"name": "Powdery Mildew", "fullName": "Powdery Mildew — Erysiphe cichoracearum", "rec": "Improve air circulation and apply appropriate treatment.", "color": Colors.orangeAccent},
    {"name": "Septoria Blight", "fullName": "Septoria Blight — Septoria lactucae", "rec": "Remove infected leaves and avoid overhead watering.", "color": Colors.deepOrange},
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
      chosen = {"name": "Unknown Disease", "fullName": "Unknown / Out of Scope Disease", "rec": "Disease outside current AI scope. Manual inspection recommended.", "color": Colors.grey};
      _confidence = 0.45;
    } else {
      chosen = _supportedDiseases[random];
      _confidence = 0.82 + (random * 0.04);
    }

    await _monitoringService.saveHealthLogDemo(
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
        title: const Text('ESP32-CAM AI Scan', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: Color(0xFF1E2A1F))),
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F), size: 32),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            // Camera Box
            Container(
              height: 340,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3), width: 3),
              ),
              child: _isScanning
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF2F6B3B), strokeWidth: 6),
                        SizedBox(height: 24),
                        Text('Analyzing from ESP32-CAM...', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ],
                    )
                  : _hasResult
                      ? Center(child: Icon(Icons.check_circle, size: 120, color: _resultColor))
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt_rounded, size: 90, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('Camera Ready', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey)),
                          ],
                        ),
            ),

            const SizedBox(height: 40),

            // Result Section
            if (_hasResult) ...[
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: _resultColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  children: [
                    Text(_result, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _resultColor)),
                    const SizedBox(height: 12),
                    Text("Confidence: ${(_confidence * 100).toStringAsFixed(1)}%", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
                    const SizedBox(height: 8),
                    Text("Demo Mode • ${DateTime.now().toString().substring(0, 16)}", style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Text(_recommendation, style: const TextStyle(fontSize: 18, height: 1.5)),
              ),
            ] else ...[
              const Text('Supported Diseases (Demo)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _badge('Downy Mildew', Colors.red),
                  _badge('Powdery Mildew', Colors.orange),
                  _badge('Septoria Blight', Colors.deepOrange),
                  _badge('Unknown', Colors.grey),
                ],
              ),
              const SizedBox(height: 40),
            ],

            // Big Scan Button
            SizedBox(
              width: double.infinity,
              height: 76,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _simulateScan,
                icon: const Icon(Icons.play_arrow_rounded, size: 32),
                label: const Text('Simulate Scan (Demo)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5DBB63),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 6,
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Farm Status Section (Monitoring + Weather + Previous Scans)
            const Text('Farm Status', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
            const SizedBox(height: 16),

            // Monitoring
         Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Monitoring', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF2F6B3B))),
                  SizedBox(height: 12),
                  Text('Temperature: 24.5°C', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Soil Moisture: 45%', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Status: Normal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5DBB63))),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Weather
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Weather', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF2F6B3B))),
                  SizedBox(height: 12),
                  Text('24°C • Partly Cloudy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Humidity: 69%', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Good for lettuce', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF5DBB63))),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Previous Scans (Health Logs)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Previous Scans (Health Logs)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
                  const SizedBox(height: 12),
                  const Text('Septoria Blight — 90% • Yesterday', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text('Unknown Disease — 45% • 2 days ago', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text('Healthy — 95% • Last week', style: TextStyle(fontSize: 18)),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // NEW: Button to open full Health Logs page
            SizedBox(
              width: double.infinity,
              height: 70,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HealthLogsScreen())),
                icon: const Icon(Icons.history_rounded, size: 32),
                label: const Text('View All Health Logs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F6B3B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  elevation: 6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
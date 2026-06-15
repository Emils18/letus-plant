import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/monitoring_service.dart';
import '../widgets/sensor_card.dart';
import '../widgets/recommendation_card.dart';
import '../widgets/device_status_card.dart';
import 'scan_screen.dart';
import 'plant_tracking_screen.dart';
import 'sell_crop_screen.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  final MonitoringService _service = MonitoringService();
  Map<String, dynamic>? data;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final result = await _service.fetchSensorData();
    setState(() => data = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('Farm Monitoring', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E2A1F))),
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppConfig.isDemoMode ? Colors.amber.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppConfig.isDemoMode ? Colors.amber.shade200 : Colors.green.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(color: AppConfig.isDemoMode ? Colors.amber : Colors.green, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(AppConfig.isDemoMode ? 'DEMO' : 'LIVE', style: TextStyle(color: AppConfig.isDemoMode ? Colors.amber.shade700 : Colors.green, fontWeight: FontWeight.bold, fontSize: 10)),
              ],
            ),
          )
        ],
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2F6B3B)))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFF2F6B3B),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Device Status Horiz Scroll
                    SizedBox(
                      height: 90,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        children: const [
                          DeviceStatusCard(deviceName: 'ESP32 Board', icon: Icons.developer_board_rounded),
                          DeviceStatusCard(deviceName: 'Soil Sensor', icon: Icons.water_drop_rounded),
                          DeviceStatusCard(deviceName: 'LDR Sensor', icon: Icons.light_mode_rounded),
                          DeviceStatusCard(deviceName: 'ESP32-CAM', icon: Icons.camera_rounded),
                          DeviceStatusCard(deviceName: 'Weather API', icon: Icons.cloud_sync_rounded),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sensor Readings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 16),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.85,
                            children: [
                              SensorCard(title: 'Soil Moisture', status: data!['soil_status'], subtitle: data!['soil_value'], icon: Icons.water_drop_rounded, color: Colors.blue),
                              SensorCard(title: 'Light Level', status: data!['light_status'], subtitle: data!['light_value'], icon: Icons.light_mode_rounded, color: Colors.orange),
                              SensorCard(title: 'Plant Health', status: data!['plant_health'], subtitle: 'Scan Result', icon: Icons.biotech_rounded, color: const Color(0xFF2F6B3B)),
                              SensorCard(title: 'Crop Stage', status: data!['crop_stage'], subtitle: 'Growth Track', icon: Icons.grass_rounded, color: Colors.teal),
                            ],
                          ),
                          const SizedBox(height: 32),

                          const Text('Smart Recommendations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 16),
                          const RecommendationCard(text: 'Soil moisture is ideal. No watering required for the next 12 hours.'),
                          const RecommendationCard(text: 'Crop is Harvest Ready. Quality is Grade A based on AI scan.', isUrgent: true),

                          const SizedBox(height: 32),
                          const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 16),
                          
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen())),
                                  icon: const Icon(Icons.document_scanner),
                                  label: const Text('Scan Disease'),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0, side: BorderSide(color: Colors.indigo.withValues(alpha: 0.2))),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SellCropScreen())),
                                  icon: const Icon(Icons.storefront),
                                  label: const Text('Sell Crop'),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5DBB63), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 4),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlantTrackingScreen())),
                              child: const Text('View Growth Tracking', style: TextStyle(color: Color(0xFF2F6B3B), fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
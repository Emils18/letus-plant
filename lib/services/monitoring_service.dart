import '../config/app_config.dart';

class MonitoringService {
  Future<Map<String, dynamic>> fetchSensorData() async {
    if (AppConfig.isDemoMode) {
      await Future.delayed(const Duration(milliseconds: 600)); // Simulate network
      return {
        'soil_status': 'Ideal',
        'soil_value': '65%',
        'light_status': 'Ideal',
        'light_value': '850 lx',
        'plant_health': 'Healthy',
        'crop_stage': 'Harvest Ready',
        'last_sync': DateTime.now().subtract(const Duration(minutes: 2)).toIso8601String(),
      };
    }
    // TODO: Implement Supabase fetching for real ESP32 data here
    return {};
  }
}
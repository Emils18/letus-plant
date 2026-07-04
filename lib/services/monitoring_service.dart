import '../config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<bool> saveHealthLogDemo({
    required String diseaseName,
    required double confidence,
    String location = "Lapu-Lapu City, Cebu",
  }) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return false;

      await Supabase.instance.client.from('diagnostic_logs').insert({
        'user_id': user.id,
        'disease_name': diseaseName,
        'confidence_score': confidence,
        'temperature': 26.5,
        'weather_condition': 'Clear',
        'location': location,
        'device_id': 'DEMO_MODE',
        'captured_at': DateTime.now().toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      print('Demo health log save error: $e');
      return false;
    }
  }
}
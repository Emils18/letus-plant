import '../config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HealthLogSaveResult {
  const HealthLogSaveResult({
    required this.success,
    this.error,
    this.record,
  });

  final bool success;
  final String? error;
  final Map<String, dynamic>? record;
}

class MonitoringService {
  final SupabaseClient _supabase =
      Supabase.instance.client;

  Future<Map<String, dynamic>>
      fetchSensorData() async {
    if (AppConfig.isDemoMode) {
      await Future.delayed(
        const Duration(
          milliseconds: 600,
        ),
      );

      return {
        'soil_status': 'Ideal',
        'soil_value': '65%',
        'light_status': 'Ideal',
        'light_value': '850 lx',
        'plant_health': 'Healthy',
        'crop_stage': 'Harvest Ready',
        'last_sync': DateTime.now()
            .subtract(
              const Duration(
                minutes: 2,
              ),
            )
            .toIso8601String(),
      };
    }

    // Existing placeholder is intentionally preserved.
    // Real IoT sensor fetching can be connected here later.
    return {};
  }

  Future<HealthLogSaveResult>
      saveHealthLog({
    required String diseaseName,
    required double confidence,
    String location =
        'Lapu-Lapu City, Cebu',
    String deviceId =
        'GreenGuard-CAM-01',
    double? temperature,
    String? weatherCondition,
    String? imageUrl,
  }) async {
    final user =
        _supabase.auth.currentUser;

    if (user == null) {
      return const HealthLogSaveResult(
        success: false,
        error:
            'No logged-in farmer account.',
      );
    }

    final DateTime now =
        DateTime.now();

    final Map<String, dynamic>
        payload = {
      'user_id': user.id,
      'disease_name':
          diseaseName.trim(),
      'confidence_score':
          confidence,
      'location': location,
      'device_id': deviceId,
      'captured_at':
          now.toIso8601String(),
      'created_at':
          now.toIso8601String(),
    };

    if (temperature != null) {
      payload['temperature'] =
          temperature;
    }

    if (weatherCondition != null &&
        weatherCondition
            .trim()
            .isNotEmpty) {
      payload['weather_condition'] =
          weatherCondition.trim();
    }

    if (imageUrl != null &&
        imageUrl.trim().isNotEmpty) {
      payload['image_url'] =
          imageUrl.trim();
    }

    try {
      await _supabase
          .from(
            'diagnostic_logs',
          )
          .insert(
            payload,
          );

      return const HealthLogSaveResult(
        success: true,
      );
    } on PostgrestException catch (e) {
      return HealthLogSaveResult(
        success: false,
        error:
            'Database error: ${e.message}',
      );
    } catch (e) {
      return HealthLogSaveResult(
        success: false,
        error:
            'Health log save error: $e',
      );
    }
  }

  Future<bool> saveHealthLogDemo({
    required String diseaseName,
    required double confidence,
    String location =
        'Lapu-Lapu City, Cebu',
  }) async {
    final HealthLogSaveResult
        result =
        await saveHealthLog(
      diseaseName:
          diseaseName,
      confidence:
          confidence,
      temperature:
          26.5,
      weatherCondition:
          'Clear',
      location:
          location,
      deviceId:
          'DEMO_MODE',
    );

    return result.success;
  }
}

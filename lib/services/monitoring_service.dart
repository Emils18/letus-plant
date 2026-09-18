import 'dart:convert';

import 'package:http/http.dart' as http;
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

  // ============================================================
  // SOIL SENSOR ESP32
  // ============================================================
  //
  // IMPORTANT:
  // Replace this with the IP shown in the ESP32 Serial Monitor.
  //
  // Example:
  // ESP32 Soil IP: 192.168.254.123
  //
  // ============================================================

  static const String soilEsp32Ip =
      '10.175.35.214';

  static const String soilDeviceName =
      'GreenGuard-SOIL-01';

  // ============================================================
  // GET REAL SOIL SENSOR DATA
  // ============================================================

  Future<Map<String, dynamic>>
      fetchSensorData() async {
    try {
      final Uri uri = Uri.parse(
        'http://$soilEsp32Ip/soil',
      );

      final http.Response response =
          await http
              .get(
                uri,
              )
              .timeout(
                const Duration(
                  seconds: 4,
                ),
              );

      if (response.statusCode != 200) {
        return _offlineData();
      }

      final dynamic decoded =
          jsonDecode(
        response.body,
      );

      if (decoded
          is! Map<String, dynamic>) {
        return _offlineData();
      }

      if (decoded['success'] != true) {
        return _offlineData();
      }

      final int moisture =
          _readInt(
        decoded['soil_moisture'],
      );

      final String status =
          decoded['soil_status']
                  ?.toString()
                  .trim()
                  .toUpperCase() ??
              'UNKNOWN';

      final String deviceName =
          decoded['device']
                  ?.toString()
                  .trim() ??
              soilDeviceName;

      return {
        'connected': true,
        'device': deviceName,
        'soil_moisture': moisture,
        'soil_value': '$moisture%',
        'soil_status': status,
        'last_sync':
            DateTime.now()
                .toIso8601String(),
      };
    } catch (_) {
      return _offlineData();
    }
  }

  Map<String, dynamic>
      _offlineData() {
    return {
      'connected': false,
      'device': soilDeviceName,
      'soil_moisture': null,
      'soil_value': '--%',
      'soil_status': 'OFFLINE',
      'last_sync':
          DateTime.now()
              .toIso8601String(),
    };
  }

  int _readInt(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    return int.tryParse(
          value?.toString() ??
              '',
        ) ??
        0;
  }

  // ============================================================
  // HEALTH LOG
  // ============================================================

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
      'location':
          location,
      'device_id':
          deviceId,
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
    final HealthLogSaveResult result =
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
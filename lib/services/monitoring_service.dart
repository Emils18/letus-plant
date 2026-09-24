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
              .get(uri)
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

      if (!decoded.containsKey(
            'soil_moisture',
          ) ||
          !decoded.containsKey(
            'soil_status',
          )) {
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

      final String deviceIp =
          decoded['device_ip']
                  ?.toString()
                  .trim() ??
              soilEsp32Ip;

      return {
        'connected': true,
        'device': deviceName,
        'device_ip': deviceIp,
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

  // ============================================================
  // OFFLINE SOIL SENSOR DATA
  // ============================================================

  Map<String, dynamic>
      _offlineData() {
    return {
      'connected': false,
      'device': soilDeviceName,
      'device_ip': soilEsp32Ip,
      'soil_moisture': null,
      'soil_value': '--%',
      'soil_status': 'OFFLINE',
      'last_sync':
          DateTime.now()
              .toIso8601String(),
    };
  }

  // ============================================================
  // SAFE INTEGER
  // ============================================================

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
  // CREATE SCAN SESSION
  // ============================================================
  //
  // A session represents one batch of lettuce.
  //
  // Example:
  //
  // Session
  // ├── Lettuce 1
  // ├── Lettuce 2
  // ├── Lettuce 3
  // └── Done Scanning
  //
  // ============================================================

  Future<String> createScanSession() async {
    final user =
        _supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'No logged-in farmer account.',
      );
    }

    try {
      final dynamic data =
          await _supabase
              .from(
                'scan_sessions',
              )
              .insert({
                'user_id':
                    user.id,
                'started_at':
                    DateTime.now()
                        .toIso8601String(),
                'status':
                    'active',
              })
              .select(
                'id',
              )
              .single();

      return data['id']
          .toString();
    } on PostgrestException catch (e) {
      throw Exception(
        'Database error: ${e.message}',
      );
    } catch (e) {
      throw Exception(
        'Unable to start scan session: $e',
      );
    }
  }

  // ============================================================
  // SAVE ONE LETTUCE HEALTH LOG
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

    // Connect this lettuce to a scan session.
    String? scanSessionId,
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
      'user_id':
          user.id,

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

    // ==========================================================
    // SCAN SESSION
    // ==========================================================

    if (scanSessionId != null &&
        scanSessionId
            .trim()
            .isNotEmpty) {
      payload['scan_session_id'] =
          scanSessionId.trim();
    }

    // ==========================================================
    // TEMPERATURE
    // ==========================================================

    if (temperature != null) {
      payload['temperature'] =
          temperature;
    }

    // ==========================================================
    // WEATHER
    // ==========================================================

    if (weatherCondition != null &&
        weatherCondition
            .trim()
            .isNotEmpty) {
      payload['weather_condition'] =
          weatherCondition.trim();
    }

    // ==========================================================
    // LETTUCE PHOTO
    // ==========================================================

    if (imageUrl != null &&
        imageUrl
            .trim()
            .isNotEmpty) {
      payload['image_url'] =
          imageUrl.trim();
    }

    try {
      final dynamic data =
          await _supabase
              .from(
                'diagnostic_logs',
              )
              .insert(
                payload,
              )
              .select()
              .single();

      return HealthLogSaveResult(
        success: true,
        record:
            Map<String, dynamic>.from(
          data as Map,
        ),
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

  // ============================================================
  // COMPLETE SCAN SESSION
  // ============================================================
  //
  // Runs when farmer presses:
  //
  // DONE SCANNING
  //
  // ============================================================

  Future<void> completeScanSession({
    required String sessionId,
    required int totalScanned,
    required int healthyCount,
    required int downyCount,
    required int powderyCount,
    required int septoriaCount,
    required double healthyAverageConfidence,
    required double downyAverageConfidence,
    required double powderyAverageConfidence,
    required double septoriaAverageConfidence,
  }) async {
    final user =
        _supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'No logged-in farmer account.',
      );
    }

    final int notHealthyCount =
        downyCount +
        powderyCount +
        septoriaCount;

    final double healthyPercentage =
        totalScanned == 0
            ? 0.0
            : healthyCount /
                totalScanned *
                100.0;

    final double notHealthyPercentage =
        totalScanned == 0
            ? 0.0
            : notHealthyCount /
                totalScanned *
                100.0;

    try {
      await _supabase
          .from(
            'scan_sessions',
          )
          .update({
            'completed_at':
                DateTime.now()
                    .toIso8601String(),

            'total_scanned':
                totalScanned,

            'healthy_count':
                healthyCount,

            'not_healthy_count':
                notHealthyCount,

            'downy_mildew_count':
                downyCount,

            'powdery_mildew_count':
                powderyCount,

            'septoria_blight_count':
                septoriaCount,

            'healthy_percentage':
                healthyPercentage,

            'not_healthy_percentage':
                notHealthyPercentage,

            'healthy_avg_confidence':
                healthyAverageConfidence,

            'downy_avg_confidence':
                downyAverageConfidence,

            'powdery_avg_confidence':
                powderyAverageConfidence,

            'septoria_avg_confidence':
                septoriaAverageConfidence,

            'status':
                'completed',
          })
          .eq(
            'id',
            sessionId,
          )
          .eq(
            'user_id',
            user.id,
          );
    } on PostgrestException catch (e) {
      throw Exception(
        'Database error: ${e.message}',
      );
    } catch (e) {
      throw Exception(
        'Unable to complete scan session: $e',
      );
    }
  }

  // ============================================================
  // DEMO HEALTH LOG
  // ============================================================

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

  // ============================================================
  // GET ALL FARMER HEALTH LOGS
  // ============================================================

  Future<List<Map<String, dynamic>>>
      fetchHealthLogs() async {
    final user =
        _supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'No logged-in farmer account.',
      );
    }

    try {
      final dynamic data =
          await _supabase
              .from(
                'diagnostic_logs',
              )
              .select('*')
              .eq(
                'user_id',
                user.id,
              )
              .order(
                'created_at',
                ascending: false,
              );

      return List<Map<String, dynamic>>
          .from(
        data as List,
      );
    } on PostgrestException catch (e) {
      throw Exception(
        'Database error: ${e.message}',
      );
    } catch (e) {
      throw Exception(
        'Unable to load health logs: $e',
      );
    }
  }

  // ============================================================
  // GET HEALTH LOGS FROM ONE SESSION
  // ============================================================

  Future<List<Map<String, dynamic>>>
      fetchSessionHealthLogs(
    String sessionId,
  ) async {
    final user =
        _supabase.auth.currentUser;

    if (user == null) {
      throw Exception(
        'No logged-in farmer account.',
      );
    }

    try {
      final dynamic data =
          await _supabase
              .from(
                'diagnostic_logs',
              )
              .select('*')
              .eq(
                'user_id',
                user.id,
              )
              .eq(
                'scan_session_id',
                sessionId,
              )
              .order(
                'captured_at',
                ascending: true,
              );

      return List<Map<String, dynamic>>
          .from(
        data as List,
      );
    } on PostgrestException catch (e) {
      throw Exception(
        'Database error: ${e.message}',
      );
    } catch (e) {
      throw Exception(
        'Unable to load scan session: $e',
      );
    }
  }
}
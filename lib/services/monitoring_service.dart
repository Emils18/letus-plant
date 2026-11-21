import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/greenguard_network_config.dart';

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

  static const String _soilIpPreference = 'soil_esp32_ip';
  static String soilEsp32Ip = '';
  static RawDatagramSocket? _soilDiscoverySocket;
  static Future<void>? _soilDiscoveryStart;
  static final Set<String> _soilCandidatesBeingVerified = <String>{};

  static Future<void> loadSavedSoilAddress() async {
    final preferences = await SharedPreferences.getInstance();
    soilEsp32Ip = preferences.getString(_soilIpPreference) ?? '';
  }

  static Future<void> setSoilAddress(String address) async {
    final input = address.trim();
    final parsed = Uri.tryParse(
      input.startsWith('http://') || input.startsWith('https://')
          ? input
          : 'http://$input',
    );
    final cleaned = parsed?.host ?? '';
    final preferences = await SharedPreferences.getInstance();
    if (cleaned.isEmpty) {
      await preferences.remove(_soilIpPreference);
    } else {
      await preferences.setString(_soilIpPreference, cleaned);
    }
    soilEsp32Ip = cleaned;
  }

  static const String soilDeviceName = GreenGuardNetworkConfig.soilDeviceName;

  /// Receives the soil ESP32's existing UDP discovery announcements.
  /// An address is persisted only after its /soil endpoint returns a valid,
  /// fresh sensor payload.
  static Future<void> startSoilDiscovery() {
    if (_soilDiscoverySocket != null) return Future<void>.value();
    final starting = _soilDiscoveryStart;
    if (starting != null) return starting;

    final Future<void> start = _bindSoilDiscoverySocket();
    _soilDiscoveryStart = start;
    return start.whenComplete(() => _soilDiscoveryStart = null);
  }

  static Future<void> _bindSoilDiscoverySocket() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        GreenGuardNetworkConfig.soilDiscoveryPort,
        reuseAddress: true,
      );
      _soilDiscoverySocket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = socket.receive();
        if (packet == null) return;

        final message = utf8.decode(packet.data, allowMalformed: true).trim();
        final address = packet.address.address;
        if (message != GreenGuardNetworkConfig.soilDiscoveryMessage ||
            address.isEmpty ||
            address == '0.0.0.0') {
          return;
        }
        unawaited(_verifyAndRememberSoilAddress(address));
      }, onError: (Object error) {
        debugPrint('Soil ESP32 discovery listener error: $error');
        _soilDiscoverySocket?.close();
        _soilDiscoverySocket = null;
      });
    } catch (error) {
      debugPrint('Unable to listen for Soil ESP32 discovery: $error');
    }
  }

  static Future<void> _verifyAndRememberSoilAddress(String address) async {
    if (!_soilCandidatesBeingVerified.add(address)) return;
    try {
      final response = await http
          .get(Uri.parse('http://$address/soil'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return;

      final dynamic decoded = jsonDecode(response.body);
      if (!_isValidSoilPayload(decoded, expectedAddress: address)) return;

      await setSoilAddress(address);
      debugPrint('Live Soil ESP32 discovered at $address');
    } catch (_) {
      // A discovery packet alone never marks the device as connected.
    } finally {
      _soilCandidatesBeingVerified.remove(address);
    }
  }

  static bool _isValidSoilPayload(
    dynamic value, {
    String? expectedAddress,
  }) {
    if (value is! Map<String, dynamic>) return false;
    final int? moisture = _readInt(value['soil_moisture']);
    final int? raw = _readInt(value['soil_raw']);
    final String status = value['soil_status']?.toString().trim().toUpperCase() ?? '';
    final String reportedAddress = value['device_ip']?.toString().trim() ?? '';
    return moisture != null &&
        moisture >= 0 &&
        moisture <= 100 &&
        raw != null &&
        raw >= 0 &&
        raw <= 4095 &&
        reportedAddress.isNotEmpty &&
        (expectedAddress == null || reportedAddress == expectedAddress) &&
        const {'DRY', 'IDEAL', 'WET'}.contains(status);
  }

  // ============================================================
  // GET REAL SOIL SENSOR DATA
  // ============================================================

  Future<Map<String, dynamic>>
      fetchSensorData() async {
    unawaited(startSoilDiscovery());
    try {
      if (soilEsp32Ip.isEmpty) {
        return _offlineData();
      }
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

      if (!_isValidSoilPayload(decoded, expectedAddress: soilEsp32Ip)) {
        return _offlineData();
      }
      final int moisture = _readInt(decoded['soil_moisture'])!;
      final int rawValue = _readInt(decoded['soil_raw'])!;

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
        'soil_raw': rawValue,
        'soil_value': '$moisture%',
        'soil_status': status,
        'reading_is_live': true,
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
      'soil_raw': null,
      'soil_value': '--%',
      'soil_status': 'OFFLINE',
      'reading_is_live': false,
      'last_sync': null,
    };
  }

  // ============================================================
  // SAFE INTEGER
  // ============================================================

  static int? _readInt(
    dynamic value,
  ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    return int.tryParse(value?.toString() ?? '');
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

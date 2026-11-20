import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HealthLogSaveResult {
  const HealthLogSaveResult({required this.success, this.error, this.record});

  final bool success;
  final String? error;
  final Map<String, dynamic>? record;
}

class MonitoringService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ============================================================
  // SOIL SENSOR ESP32
  // ============================================================

  static const String defaultSoilEsp32Ip = '';
  static const String _soilIpPreference = 'soil_esp32_ip';
  static String soilEsp32Ip = defaultSoilEsp32Ip;
  static Future<void>? _addressLoad;
  static Future<Map<String, dynamic>>? _soilRequest;
  static RawDatagramSocket? _soilDiscoverySocket;
  static Future<void>? _soilDiscoverySocketStart;

  static final StreamController<String> _soilAnnouncements =
      StreamController<String>.broadcast();

  static Map<String, dynamic>? _lastGoodSoilReading;
  static int _consecutiveSoilFailures = 0;
  static DateTime? _lastDiscoveryAttempt;

  static const Duration _soilRequestTimeout = Duration(seconds: 2);
  static const Duration _discoveryProbeTimeout = Duration(milliseconds: 650);
  static const Duration _discoveryCooldown = Duration(seconds: 25);
  static const Duration _announcementWait = Duration(seconds: 7);

  static const int _discoveryConcurrency = 32;
  static const int _soilDiscoveryPort = 45821;

  static const String soilDiscoveryToken = 'GREENGUARD_SOIL_DISCOVERY_V1';

  static Future<void> loadSavedSoilAddress() {
    return _addressLoad ??= _loadSavedSoilAddress();
  }

  static Future<void> _loadSavedSoilAddress() async {
    final preferences = await SharedPreferences.getInstance();

    soilEsp32Ip =
        _normalizeIpv4(preferences.getString(_soilIpPreference) ?? '') ??
        defaultSoilEsp32Ip;
  }

  static Future<void> setSoilAddress(String address) async {
    final cleaned = _normalizeIpv4(address);

    if (cleaned == null) {
      throw const FormatException('Enter a valid ESP32 IPv4 address.');
    }

    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(_soilIpPreference, cleaned);

    soilEsp32Ip = cleaned;
    _lastGoodSoilReading = null;
    _consecutiveSoilFailures = 0;
  }

  static String? _normalizeIpv4(String value) {
    var cleaned = value.trim().replaceFirst(
      RegExp(r'^https?://', caseSensitive: false),
      '',
    );

    cleaned = cleaned.replaceFirst(
      RegExp(r'/soil/?$', caseSensitive: false),
      '',
    );

    cleaned = cleaned.replaceFirst(RegExp(r'/$'), '');

    final parts = cleaned.split('.');

    if (parts.length != 4 ||
        parts.any(
          (part) =>
              !RegExp(r'^\d+$').hasMatch(part) ||
              int.tryParse(part) == null ||
              int.parse(part) > 255,
        )) {
      return null;
    }

    return parts.map(int.parse).join('.');
  }

  static const String soilDeviceName = 'GreenGuard-SOIL-01';

  // ============================================================
  // GET REAL SOIL SENSOR DATA
  // ============================================================

  Future<Map<String, dynamic>> fetchSensorData({bool forceDiscovery = false}) {
    final currentRequest = _soilRequest;

    if (currentRequest != null) return currentRequest;

    late final Future<Map<String, dynamic>> request;

    request = _fetchSoilData(forceDiscovery: forceDiscovery).whenComplete(() {
      if (identical(_soilRequest, request)) {
        _soilRequest = null;
      }
    });

    _soilRequest = request;

    return request;
  }

  Future<Map<String, dynamic>> _fetchSoilData({
    required bool forceDiscovery,
  }) async {
    try {
      await loadSavedSoilAddress();
    } catch (error) {
      return _offlineData(
        state: 'ERROR',
        error: 'Could not load the saved sensor address: $error',
      );
    }

    final savedAddress = soilEsp32Ip;

    Object? addressError;
    Object? discoveryError;

    // Start listening before attempting discovery.
    try {
      await _ensureSoilDiscoveryListener();
    } catch (error) {
      discoveryError = error;
    }

    // First, try the previously discovered address.
    if (savedAddress.isNotEmpty && !forceDiscovery) {
      try {
        return await _readSoilAt(savedAddress, _soilRequestTimeout);
      } catch (error) {
        addressError = error;
      }
    }

    // Listen for the ESP32's current DHCP address.
    // The ESP32 sends GREENGUARD_SOIL_DISCOVERY_V1
    // to the hotspot's local broadcast address.
    if (_soilDiscoverySocket != null) {
      try {
        final reading = await _discoverFromAnnouncements(_announcementWait);

        if (reading != null) return reading;
      } catch (error) {
        discoveryError ??= error;
      }
    }

    // Fallback: scan the available private IPv4 subnet.
    final lastDiscovery = _lastDiscoveryAttempt;

    final shouldScanSubnet =
        forceDiscovery ||
        lastDiscovery == null ||
        DateTime.now().difference(lastDiscovery) >= _discoveryCooldown;

    if (shouldScanSubnet) {
      _lastDiscoveryAttempt = DateTime.now();

      try {
        final reading = await _discoverSoilSensor();

        if (reading != null) return reading;
      } catch (error) {
        discoveryError ??= error;
      }
    }

    // If manually requested, try the previously saved address again.
    if (savedAddress.isNotEmpty && forceDiscovery) {
      try {
        return await _readSoilAt(savedAddress, _soilRequestTimeout);
      } catch (error) {
        addressError = error;
      }
    }

    final error = _soilFailureMessage(
      savedAddress: savedAddress,
      addressError: addressError,
      discoveryError: discoveryError,
      discoveryWasSkipped: !shouldScanSubnet,
    );

    final hasBadResponse =
        _isDeviceResponseError(addressError) ||
        _isDeviceResponseError(discoveryError);

    return _offlineData(
      state: hasBadResponse ? 'ERROR' : 'DISCONNECTED',
      error: error,
    );
  }

  // ============================================================
  // UDP DISCOVERY LISTENER
  // ============================================================

  static Future<void> _ensureSoilDiscoveryListener() async {
    if (_soilDiscoverySocket != null) return;

    final pending = _soilDiscoverySocketStart;

    if (pending != null) return pending;

    late final Future<void> start;

    start = _bindSoilDiscoverySocket().whenComplete(() {
      if (identical(_soilDiscoverySocketStart, start)) {
        _soilDiscoverySocketStart = null;
      }
    });

    _soilDiscoverySocketStart = start;

    await start;
  }

  static Future<void> _bindSoilDiscoverySocket() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _soilDiscoveryPort,
      reuseAddress: true,
    );

    _soilDiscoverySocket = socket;

    socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;

        final packet = socket.receive();

        if (packet == null) return;

        final message = utf8.decode(packet.data, allowMalformed: true).trim();

        if (!isSoilDiscoveryAnnouncement(message)) return;

        // The sender address is the ESP32's current DHCP address.
        final address = _normalizeIpv4(packet.address.address);

        if (address != null) {
          _soilAnnouncements.add(address);
        }
      },
      onError: (Object error) {
        _soilDiscoverySocket = null;
      },
      onDone: () {
        _soilDiscoverySocket = null;
      },
      cancelOnError: false,
    );
  }

  static bool isSoilDiscoveryAnnouncement(String message) {
    return message.trim() == soilDiscoveryToken;
  }

  Future<Map<String, dynamic>?> _discoverFromAnnouncements(
    Duration timeout,
  ) async {
    if (_soilDiscoverySocket == null) return null;

    final completer = Completer<Map<String, dynamic>?>();

    final attemptedAddresses = <String>{};

    // Subscribe before waiting for the next ESP32 announcement.
    final subscription = _soilAnnouncements.stream.listen((address) async {
      if (completer.isCompleted) return;

      if (!attemptedAddresses.add(address)) return;

      try {
        // Verify the sender by requesting its actual soil endpoint.
        final reading = await _readSoilAt(address, _soilRequestTimeout);

        if (!completer.isCompleted) {
          completer.complete(reading);
        }
      } catch (_) {
        // Ignore other devices and invalid ESP32 responses.
      }
    });

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }

  // ============================================================
  // REQUEST SOIL DATA FROM ESP32
  // ============================================================

  Future<Map<String, dynamic>> _readSoilAt(
    String address,
    Duration timeout,
  ) async {
    final response = await http
        .get(Uri(scheme: 'http', host: address, path: '/soil'))
        .timeout(timeout);

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'ESP32 returned HTTP ${response.statusCode}.',
        uri: response.request?.url,
      );
    }

    final reading = parseSoilResponse(response.body, requestedIp: address);

    // Automatically remember the newly discovered IP.
    soilEsp32Ip = reading['device_ip'] as String;

    _lastGoodSoilReading = reading;
    _consecutiveSoilFailures = 0;

    try {
      final preferences = await SharedPreferences.getInstance();

      await preferences.setString(_soilIpPreference, soilEsp32Ip);
    } catch (_) {
      // A successful live reading remains useful even if
      // local preference storage fails.
    }

    return reading;
  }

  // ============================================================
  // PARSE REAL ESP32 RESPONSE
  // ============================================================

  static Map<String, dynamic> parseSoilResponse(
    String body, {
    required String requestedIp,
    DateTime? receivedAt,
  }) {
    final dynamic decoded;

    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const FormatException('ESP32 returned invalid JSON from /soil.');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'ESP32 /soil response must be a JSON object.',
      );
    }

    for (final key in const [
      'soil_moisture',
      'soil_raw',
      'soil_status',
      'device_ip',
    ]) {
      if (!decoded.containsKey(key) || decoded[key] == null) {
        throw FormatException('ESP32 /soil response is missing "$key".');
      }
    }

    final moisture = _readInt(decoded['soil_moisture'], field: 'soil_moisture');

    final rawValue = _readInt(decoded['soil_raw'], field: 'soil_raw');

    if (moisture < 0 || moisture > 100) {
      throw const FormatException('Soil moisture must be between 0 and 100%.');
    }

    if (rawValue < 0) {
      throw const FormatException('Raw soil reading cannot be negative.');
    }

    final status = decoded['soil_status'].toString().trim().toUpperCase();

    if (!const {'DRY', 'IDEAL', 'WET'}.contains(status)) {
      throw FormatException(
        'Unknown soil condition "$status"; expected DRY, IDEAL, or WET.',
      );
    }

    final reportedIp = _normalizeIpv4(decoded['device_ip'].toString());

    if (reportedIp == null) {
      throw FormatException(
        'ESP32 at $requestedIp returned an invalid device_ip address.',
      );
    }

    final updatedAt = (receivedAt ?? DateTime.now()).toIso8601String();

    return {
      'connected': true,
      'connection_state': 'CONNECTED',
      'error': null,
      'device': decoded['device']?.toString().trim().isNotEmpty == true
          ? decoded['device'].toString().trim()
          : soilDeviceName,
      'device_ip': reportedIp,
      'soil_moisture': moisture,
      'soil_raw': rawValue,
      'soil_value': '$moisture%',
      'soil_status': status,
      'last_sync': updatedAt,
      'last_successful_update': updatedAt,
      'stale': false,
    };
  }

  static int _readInt(dynamic value, {required String field}) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      if (value.isFinite && value == value.roundToDouble()) {
        return value.toInt();
      }

      throw FormatException('ESP32 field "$field" must be a whole number.');
    }

    final parsed = int.tryParse(value?.toString().trim() ?? '');

    if (parsed == null) {
      throw FormatException('ESP32 field "$field" is not an integer.');
    }

    return parsed;
  }

  bool _isDeviceResponseError(Object? error) {
    return error is FormatException || error is HttpException;
  }

  // ============================================================
  // SUBNET DISCOVERY FALLBACK
  // ============================================================

  Future<Map<String, dynamic>?> _discoverSoilSensor() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    final subnets = <String>{};
    final localAddresses = <String>{};

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final octets = _privateIpv4Octets(address.address);

        if (octets == null) continue;

        localAddresses.add(address.address);

        subnets.add('${octets[0]}.${octets[1]}.${octets[2]}');
      }
    }

    if (subnets.isEmpty) {
      throw const SocketException(
        'No private IPv4 network interface is available for local ESP32 discovery.',
      );
    }

    Object? invalidResponseError;

    for (final subnet in subnets) {
      final targets = <String>[];

      for (var host = 1; host <= 254; host++) {
        final ip = '$subnet.$host';

        if (!localAddresses.contains(ip)) {
          targets.add(ip);
        }
      }

      var nextIndex = 0;
      Map<String, dynamic>? found;

      Future<void> worker() async {
        while (found == null && nextIndex < targets.length) {
          final address = targets[nextIndex++];

          try {
            found = await _readSoilAt(address, _discoveryProbeTimeout);
          } on FormatException catch (error) {
            invalidResponseError ??= error;
          } catch (_) {
            // No listener, timeout, and non-success HTTP
            // responses are normal during discovery.
          }
        }
      }

      final workerCount = targets.length < _discoveryConcurrency
          ? targets.length
          : _discoveryConcurrency;

      await Future.wait(List.generate(workerCount, (_) => worker()));

      if (found != null) return found;
    }

    if (invalidResponseError != null) {
      throw invalidResponseError!;
    }

    return null;
  }

  static List<int>? _privateIpv4Octets(String value) {
    final parts = value.split('.');

    if (parts.length != 4) return null;

    final octets = parts.map(int.tryParse).toList();

    if (octets.any((part) => part == null)) {
      return null;
    }

    final ip = octets.cast<int>();

    final isPrivate =
        ip[0] == 10 ||
        (ip[0] == 172 && ip[1] >= 16 && ip[1] <= 31) ||
        (ip[0] == 192 && ip[1] == 168);

    if (!isPrivate || ip[0] == 0 || ip[0] == 127 || ip[0] >= 224) {
      return null;
    }

    return ip;
  }

  // ============================================================
  // SOIL CONNECTION ERROR
  // ============================================================

  String _soilFailureMessage({
    required String savedAddress,
    required Object? addressError,
    required Object? discoveryError,
    required bool discoveryWasSkipped,
  }) {
    final details = <String>[];

    if (savedAddress.isNotEmpty && addressError != null) {
      details.add(
        'Could not read http://$savedAddress/soil: '
        '${_describeError(addressError)}',
      );
    }

    if (discoveryError != null) {
      details.add(
        'Automatic discovery failed: '
        '${_describeError(discoveryError)}',
      );
    } else if (discoveryWasSkipped) {
      details.add('Automatic discovery will retry shortly.');
    } else {
      details.add(
        'No Soil ESP32 announcement or /soil response was found on this hotspot.',
      );
    }

    if (savedAddress.isEmpty) {
      details.add(
        'Check that the ESP32 is broadcasting its discovery announcement.',
      );
    }

    return details.join(' ');
  }

  String _describeError(Object error) {
    if (error is TimeoutException) {
      return 'request timed out.';
    }

    if (error is SocketException) {
      return error.message;
    }

    if (error is HttpException) {
      return error.message;
    }

    return error.toString().replaceFirst('Exception: ', '');
  }

  // ============================================================
  // OFFLINE DATA
  // ============================================================

  Map<String, dynamic> _offlineData({
    required String state,
    required String error,
  }) {
    final previous = _lastGoodSoilReading;

    _consecutiveSoilFailures++;

    return {
      ...?previous,
      'connected': false,
      'connection_state': state == 'ERROR'
          ? 'ERROR'
          : previous != null && _consecutiveSoilFailures == 1
          ? 'RECONNECTING'
          : state,
      'error': error,
      'device': previous?['device'] ?? soilDeviceName,
      'device_ip': previous?['device_ip'] ?? soilEsp32Ip,
      'soil_moisture': previous?['soil_moisture'],
      'soil_raw': previous?['soil_raw'],
      'soil_value': previous?['soil_value'] ?? '--%',
      'soil_status': previous?['soil_status'] ?? 'UNKNOWN',
      'last_sync': previous?['last_sync'],
      'last_successful_update': previous?['last_successful_update'],
      'stale': previous != null,
    };
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

  Future<String> createScanSession({DateTime? startedAt}) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged-in farmer account.');
    }

    try {
      final dynamic data = await _supabase
          .from('scan_sessions')
          .insert({
            'user_id': user.id,
            'started_at': (startedAt ?? DateTime.now())
                .toUtc()
                .toIso8601String(),
            'status': 'active',
          })
          .select('id')
          .single();

      return data['id'].toString();
    } on PostgrestException catch (e) {
      throw Exception('Database error: ${e.message}');
    } catch (e) {
      throw Exception('Unable to start scan session: $e');
    }
  }

  // ============================================================
  // SAVE ONE LETTUCE HEALTH LOG
  // ============================================================

  Future<HealthLogSaveResult> saveHealthLog({
    required String diseaseName,
    required double? confidence,
    String? location,
    String deviceId = 'GreenGuard-CAM-01',
    double? temperature,
    String? weatherCondition,
    String? imageUrl,
    String? scanSessionId,
    String? scanCaptureId,
    DateTime? capturedAt,
    Map<String, dynamic> report = const {},
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return const HealthLogSaveResult(
        success: false,
        error: 'No logged-in farmer account.',
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();

    final Map<String, dynamic> payload = {
      'user_id': user.id,
      'disease_name': diseaseName.trim(),
      'confidence_score': confidence,
      if (location != null && location.trim().isNotEmpty)
        'location': location.trim(),
      'device_id': deviceId,
      'captured_at': capturedAt?.toUtc().toIso8601String() ?? now,
      'created_at': now,
      'scan_capture_id': ?scanCaptureId,
      for (final field in [
        'pathogen_name',
        'disease_description',
        'pathogen_description',
        'treatment_recommendations',
        'selling_recommendation',
        'selling_explanation',
      ])
        if (report[field] != null) field: report[field],
    };

    // ==========================================================
    // SCAN SESSION
    // ==========================================================

    if (scanSessionId != null && scanSessionId.trim().isNotEmpty) {
      payload['scan_session_id'] = scanSessionId.trim();
    }

    // ==========================================================
    // TEMPERATURE
    // ==========================================================

    if (temperature != null) {
      payload['temperature'] = temperature;
    }

    // ==========================================================
    // WEATHER
    // ==========================================================

    if (weatherCondition != null && weatherCondition.trim().isNotEmpty) {
      payload['weather_condition'] = weatherCondition.trim();
    }

    // ==========================================================
    // LETTUCE PHOTO
    // ==========================================================

    if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      payload['image_url'] = imageUrl.trim();
    }

    try {
      final dynamic data = await _supabase
          .from('diagnostic_logs')
          .insert(payload)
          .select()
          .single();

      return HealthLogSaveResult(
        success: true,
        record: Map<String, dynamic>.from(data as Map),
      );
    } on PostgrestException catch (e) {
      if (e.code == '23505' && scanCaptureId != null) {
        try {
          final existing = await _supabase
              .from('diagnostic_logs')
              .select()
              .eq('user_id', user.id)
              .eq('scan_capture_id', scanCaptureId)
              .maybeSingle();
          if (existing != null) {
            return HealthLogSaveResult(success: true, record: existing);
          }
        } catch (error) {
          debugPrint('Unable to recover saved scan: $error');
        }
      }
      return HealthLogSaveResult(
        success: false,
        error: 'Database error: ${e.message}',
      );
    } catch (e) {
      return HealthLogSaveResult(
        success: false,
        error: 'Health log save error: $e',
      );
    }
  }

  // ============================================================
  // COMPLETE SCAN SESSION
  // ============================================================

  Future<DateTime> completeScanSession({
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
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged-in farmer account.');
    }

    final int notHealthyCount = downyCount + powderyCount + septoriaCount;

    final double healthyPercentage = totalScanned == 0
        ? 0.0
        : healthyCount / totalScanned * 100.0;

    final double notHealthyPercentage = totalScanned == 0
        ? 0.0
        : notHealthyCount / totalScanned * 100.0;

    try {
      final completedAt = DateTime.now().toUtc();
      final updated = await _supabase
          .from('scan_sessions')
          .update({
            'completed_at': completedAt.toIso8601String(),
            'total_scanned': totalScanned,
            'healthy_count': healthyCount,
            'not_healthy_count': notHealthyCount,
            'downy_mildew_count': downyCount,
            'powdery_mildew_count': powderyCount,
            'septoria_blight_count': septoriaCount,
            'healthy_percentage': healthyPercentage,
            'not_healthy_percentage': notHealthyPercentage,
            'healthy_avg_confidence': healthyAverageConfidence,
            'downy_avg_confidence': downyAverageConfidence,
            'powdery_avg_confidence': powderyAverageConfidence,
            'septoria_avg_confidence': septoriaAverageConfidence,
            'status': 'completed',
          })
          .eq('id', sessionId)
          .eq('user_id', user.id)
          .eq('status', 'active')
          .select('completed_at')
          .maybeSingle();
      if (updated != null) return completedAt;

      final completed = await _supabase
          .from('scan_sessions')
          .select('completed_at')
          .eq('id', sessionId)
          .eq('user_id', user.id)
          .eq('status', 'completed')
          .maybeSingle();
      final previous = DateTime.tryParse(
        completed?['completed_at']?.toString() ?? '',
      );
      if (previous != null) return previous;
      throw StateError('The scan session could not be found.');
    } on PostgrestException catch (e) {
      throw Exception('Database error: ${e.message}');
    } catch (e) {
      throw Exception('Unable to complete scan session: $e');
    }
  }

  // ============================================================
  // DEMO HEALTH LOG
  // ============================================================

  Future<bool> saveHealthLogDemo({
    required String diseaseName,
    required double confidence,
    String location = 'Lapu-Lapu City, Cebu',
  }) async {
    final HealthLogSaveResult result = await saveHealthLog(
      diseaseName: diseaseName,
      confidence: confidence,
      temperature: 26.5,
      weatherCondition: 'Clear',
      location: location,
      deviceId: 'DEMO_MODE',
    );

    return result.success;
  }

  // ============================================================
  // GET ALL FARMER HEALTH LOGS
  // ============================================================

  Future<List<Map<String, dynamic>>> fetchHealthLogs() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged-in farmer account.');
    }

    try {
      final dynamic data = await _supabase
          .from('diagnostic_logs')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(data as List);
    } on PostgrestException catch (e) {
      throw Exception('Database error: ${e.message}');
    } catch (e) {
      throw Exception('Unable to load health logs: $e');
    }
  }

  // ============================================================
  // GET HEALTH LOGS FROM ONE SESSION
  // ============================================================

  Future<List<Map<String, dynamic>>> fetchSessionHealthLogs(
    String sessionId,
  ) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged-in farmer account.');
    }

    try {
      final records = <Map<String, dynamic>>[];
      const pageSize = 250;
      for (var from = 0; ; from += pageSize) {
        final page = await _supabase
            .from('diagnostic_logs')
            .select()
            .eq('user_id', user.id)
            .eq('scan_session_id', sessionId)
            .order('captured_at', ascending: true)
            .order('id', ascending: true)
            .range(from, from + pageSize - 1);
        records.addAll(page);
        if (page.length < pageSize) return records;
      }
    } on PostgrestException catch (e) {
      throw Exception('Database error: ${e.message}');
    } catch (e) {
      throw Exception('Unable to load scan session: $e');
    }
  }
}

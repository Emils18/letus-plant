import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shared/scan_session_report_screen.dart';
import '../services/Esp_Cam.dart';
import '../services/monitoring_service.dart';
import 'shared/health_logs_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final EspCamService _espCamService = EspCamService();
  final MonitoringService _monitoringService = MonitoringService();

  StreamSubscription<EspCamDevice>? _cameraSubscription;
  StreamSubscription<Uint8List>? _mjpegSubscription;

  Timer? _soilTimer;

  Uint8List? _liveFrame;
  Uint8List? _capturedImage;

  Map<String, dynamic>? _scanResponse;
  Map<String, dynamic> _sensorData = {};

  bool _streamConnecting = false;
  bool _cameraConnected = false;
  bool _isSearching = true;
  bool _isCapturing = false;
  bool _isProcessing = false;
  bool _scanSaved = false;

  bool _soilLoading = true;
  bool _soilWasConnected = false;

  bool _scanCompleted = false;
  bool _scanAddedToSession = false;
  bool _sessionFinished = false;

  // AI Model Status
  bool _aiReady = false;
  bool _aiInitializing = true;
  String _aiStatusMessage = 'Checking Laptop AI Server...';

  String _cameraStatus = 'Waiting for GreenGuard-CAM-01...';

  final List<Map<String, dynamic>> _sessionScans = [];
  String? _sessionId;
  late DateTime _sessionStartedAt;

  static const String _scanImageBucket = 'diagnostic-images';

  final List<Map<String, dynamic>> _subjectTypes = [
    {'name': 'Not a Plant', 'color': Colors.grey},
    {'name': 'Plant', 'color': Colors.teal},
    {'name': 'Lettuce', 'color': const Color(0xFF2F6B3B)},
  ];

  final List<Map<String, dynamic>> _supportedDiseases = [
    {'name': 'Healthy', 'color': Colors.green},
    {'name': 'Downy Mildew', 'color': Colors.redAccent},
    {'name': 'Powdery Mildew', 'color': Colors.orangeAccent},
    {'name': 'Septoria Blight', 'color': Colors.deepOrange},
  ];

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();

    _cameraSubscription = _espCamService.cameraEvents.listen(_cameraRegistered);
    _startSoilMonitoring();
    _warmUpAi();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCamera();
    });
  }

  // Check Laptop Server status via /health
  Future<void> _warmUpAi() async {
    setState(() {
      _aiInitializing = true;
      _aiStatusMessage = 'Connecting to Laptop AI Server...';
    });

    bool ok = false;
    try {
      final response = await http
          .get(
            Uri.parse('${EspCamService.aiServerBaseUrl}/health'),
          )
          .timeout(const Duration(seconds: 4));
      ok = response.statusCode == 200;
    } catch (_) {
      ok = false;
    }

    if (!mounted) return;
    setState(() {
      _aiInitializing = false;
      _aiReady = ok;
      _aiStatusMessage =
          ok ? 'AI Server Online (Laptop)' : 'AI Server Offline (Start server.py)';
    });
  }

  @override
  void dispose() {
    _soilTimer?.cancel();
    _mjpegSubscription?.cancel();
    _cameraSubscription?.cancel();
    unawaited(_espCamService.stopMjpegStream());
    super.dispose();
  }

  void _startSoilMonitoring() {
    unawaited(_loadSoilData());
    _soilTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_loadSoilData());
    });
  }

  Future<void> _loadSoilData() async {
    final Map<String, dynamic> data = await _monitoringService.fetchSensorData();
    if (!mounted) return;

    final bool connected = data['connected'] == true;
    final bool newlyConnected = connected && !_soilWasConnected;

    setState(() {
      _sensorData = data;
      _soilLoading = false;
      _soilWasConnected = connected;
    });

    if (newlyConnected) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '🌱 Soil Sensor Detected\nGreenGuard is now receiving live soil moisture data.',
            style: TextStyle(fontWeight: FontWeight.w700, height: 1.4),
          ),
          backgroundColor: Color(0xFF2F6B3B),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  String _soilMeaning(String status) {
    switch (status.toUpperCase()) {
      case 'DRY':
        return 'The soil is dry and needs water.';
      case 'IDEAL':
        return 'The soil has enough moisture. No watering is needed right now.';
      case 'WET':
        return 'The soil has too much water. Avoid adding more water.';
      case 'OFFLINE':
        return 'The soil sensor is not connected. Check the ESP32 power and Wi-Fi.';
      default:
        return 'GreenGuard is checking the soil condition.';
    }
  }

  Color _soilStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'DRY':
        return Colors.orange;
      case 'IDEAL':
        return const Color(0xFF2F6B3B);
      case 'WET':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Future<void> _initializeCamera() async {
    await _espCamService.startDiscoveryServer();
    if (!mounted) return;

    setState(() {
      _isSearching = true;
      _cameraStatus = 'Searching for GreenGuard-CAM-01...';
    });

    final bool connected = await _espCamService.checkConnection();
    if (!mounted) return;

    if (connected) {
      _setCameraConnected();
      return;
    }

    setState(() {
      _cameraConnected = false;
      _isSearching = true;
      _cameraStatus = 'Waiting for camera. Turn on your hotspot, then power the ESP32-CAM.';
    });
  }

  Future<void> _cameraRegistered(EspCamDevice device) async {
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _cameraStatus = '${device.deviceId} found. Connecting...';
    });

    final bool connected = await _espCamService.checkConnection();
    if (!mounted) return;

    if (connected) {
      _setCameraConnected();
    }
  }

  void _setCameraConnected() {
    if (!mounted) return;
    setState(() {
      _cameraConnected = true;
      _isSearching = false;
      _cameraStatus = 'GreenGuard-CAM-01 connected.';
    });

    // Start video stream IMMEDIATELY so it never spins forever!
    _startPreview();
  }

  Future<void> _prepareBestCamera() async {
    await _stopPreview();
    final settings = await _espCamService.updateSettings(preset: 'best', xclkMHz: 28);
    if (!mounted) return;

    if (settings == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera connected, but recommended settings could not be applied.'),
        ),
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (mounted && _cameraConnected && _capturedImage == null) {
      await _startPreview();
    }
  }

  Future<void> _searchAgain() async {
    await _stopPreview();
    _espCamService.forgetCamera();
    if (!mounted) return;

    setState(() {
      _capturedImage = null;
      _liveFrame = null;
      _cameraConnected = false;
      _isSearching = true;
      _cameraStatus = 'Searching for GreenGuard-CAM-01...';
    });

    await _initializeCamera();
  }

  Future<void> _stopPreview() async {
    if (_mjpegSubscription != null) {
      await _mjpegSubscription!.cancel();
      _mjpegSubscription = null;
    }
    await _espCamService.stopMjpegStream();
  }

  Future<void> _startPreview() async {
    await _stopPreview();
    if (!mounted || !_cameraConnected || _capturedImage != null || _isCapturing) return;

    setState(() {
      _streamConnecting = true;
    });

    _mjpegSubscription = _espCamService.mjpegStream().listen(
      (Uint8List frame) {
        if (!mounted || _isCapturing || _capturedImage != null) return;
        setState(() {
          _liveFrame = frame;
          _streamConnecting = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _streamConnecting = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _streamConnecting = false;
        });
      },
    );
  }

Future<void> _takePhoto() async {
    if (!_cameraConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ESP32-CAM is not connected.')),
      );
      return;
    }

    setState(() {
      _isCapturing = true;
      _capturedImage = null;
      _scanResponse = null; // Clears old result card so it never shows fake answer!
      _scanSaved = false;
      _scanCompleted = false;
      _scanAddedToSession = false;
    });

    // 1. Try high-res capture from camera
    Uint8List? image = await _espCamService.capturePhoto();

    // 2. If capture endpoint timed out, fallback to current live frame
    image ??= _liveFrame;

    if (!mounted) return;

    if (image == null || image.isEmpty) {
      setState(() {
        _isCapturing = false;
      });
      await _startPreview();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo capture failed. No frame received.')),
      );
      return;
    }

    setState(() {
      _capturedImage = image;
      _isCapturing = false;
    });

    // Immediately send REAL frame to Python server
    await _usePhoto();
  }

  Future<void> _retakePhoto() async {
    if (_isProcessing) return;
    setState(() {
      _capturedImage = null;
      _liveFrame = null;
      _scanResponse = null;
      _scanSaved = false;
      _scanCompleted = false;
      _scanAddedToSession = false;
      _isProcessing = false;
    });
    await _startPreview();
  }

  Future<String?> _uploadScanPhoto(Uint8List imageBytes) async {
    final SupabaseClient supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null || _sessionId == null) return null;

    final int scanNumber = _sessionScans.length + 1;
    final String fileName = 'lettuce_${scanNumber.toString().padLeft(3, '0')}.jpg';
    final String path = '${user.id}/${_sessionId!}/$fileName';

    try {
      await supabase.storage.from(_scanImageBucket).uploadBinary(
            path,
            imageBytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      return supabase.storage.from(_scanImageBucket).getPublicUrl(path);
    } catch (e) {
      debugPrint('Scan photo upload failed: $e');
      return null;
    }
  }

  Future<void> _usePhoto() async {
    final Uint8List? image = _capturedImage;
    if (image == null || image.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image found to scan. Take photo first.')),
      );
      return;
    }
    if (_isProcessing || _scanCompleted) return;

    setState(() {
      _isProcessing = true;
      _scanResponse = null; // Clears screen while waiting for Python!
    });

    debugPrint('>>> SENDING REAL PHOTO TO PYTHON SERVER (${image.length} bytes)...');

    final Map<String, dynamic> response = await _espCamService.scanPhotoWithAi(image);
    if (!mounted) return;

    Map<String, dynamic> finalResponse = {...response};
    final bool success = response['success'] == true;
    final bool diagnosisAvailable = response['diagnosis_available'] == true;

    bool saved = false;
    String? saveError;
    String? imageUrl;

    if (success && diagnosisAvailable) {
      if (_sessionId == null) {
        try {
          _sessionId = await _monitoringService.createScanSession();
          _sessionStartedAt = DateTime.now();
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _isProcessing = false;
            _scanResponse = finalResponse;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unable to start scan session: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      }

      final dynamic rawResult = response['result'];
      if (rawResult is Map<String, dynamic>) {
        final String diseaseName = (rawResult['display_name'] ?? rawResult['class_name'] ?? 'Unknown Result')
            .toString()
            .replaceAll('_', ' ')
            .trim();

        final double confidence = _readDoubleValue(rawResult['confidence']);
        imageUrl = await _uploadScanPhoto(image);

        final HealthLogSaveResult saveResult = await _monitoringService.saveHealthLog(
          diseaseName: diseaseName,
          confidence: confidence,
          location: 'Lapu-Lapu City, Cebu',
          deviceId: 'GreenGuard-CAM-01',
          imageUrl: imageUrl,
          scanSessionId: _sessionId,
        );

        if (!mounted) return;
        saved = saveResult.success;
        saveError = saveResult.error;

        if (saved && !_scanAddedToSession) {
          _sessionScans.add({
            'scan_session_id': _sessionId,
            'disease_name': diseaseName,
            'confidence': confidence,
            'image_bytes': Uint8List.fromList(image),
            'image_url': imageUrl,
            'database_saved': true,
            'captured_at': DateTime.now().toIso8601String(),
          });
          _scanAddedToSession = true;
        }

        finalResponse = {
          ...response,
          'database_saved': saved,
          'database_error': saveError,
          'image_url': imageUrl,
          'scan_session_id': _sessionId,
          'session_scan_number': _sessionScans.length,
        };
      }
    } else {
      finalResponse = {
        ...response,
        'database_saved': false,
      };
    }

    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _scanResponse = finalResponse;
      _scanSaved = saved;
      _scanCompleted = saved;
    });

    final String message;
    if (!success) {
      message = response['message']?.toString() ?? 'GreenGuard scan failed.';
    } else if (!diagnosisAvailable) {
      message = response['message']?.toString() ?? 'No lettuce diagnosis was produced.';
    } else if (saved) {
      message = 'Lettuce #${_sessionScans.length} saved. You can scan the next lettuce.';
    } else {
      message = 'The diagnosis is ready, but it was not saved${saveError == null ? '. Please tap Use Photo again.' : ': $saveError'}';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: saved ? const Color(0xFF2F6B3B) : Colors.redAccent,
      ),
    );
  }

  Future<void> _scanNextLettuce() async {
    if (_isProcessing) return;
    setState(() {
      _capturedImage = null;
      _liveFrame = null;
      _scanResponse = null;
      _scanSaved = false;
      _scanCompleted = false;
      _scanAddedToSession = false;
      _isProcessing = false;
    });
    await _startPreview();
  }

  Future<void> _finishScanning() async {
    if (_sessionScans.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan at least one lettuce before finishing the session.')),
      );
      return;
    }

    final String? sessionId = _sessionId;
    if (sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The scan session was not created. Please try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    await _stopPreview();
    if (!mounted) return;

    int healthyCount = 0;
    int downyCount = 0;
    int powderyCount = 0;
    int septoriaCount = 0;
    double healthyConfidenceTotal = 0.0;
    double downyConfidenceTotal = 0.0;
    double powderyConfidenceTotal = 0.0;
    double septoriaConfidenceTotal = 0.0;

    for (final Map<String, dynamic> scan in _sessionScans) {
      final String disease = (scan['disease_name'] ?? '').toString().toLowerCase().replaceAll('_', ' ').trim();
      double confidence = _readDoubleValue(scan['confidence']);
      if (confidence > 1.0) confidence /= 100.0;

      if (disease == 'healthy') {
        healthyCount++;
        healthyConfidenceTotal += confidence;
      } else if (disease == 'downy mildew') {
        downyCount++;
        downyConfidenceTotal += confidence;
      } else if (disease == 'powdery mildew') {
        powderyCount++;
        powderyConfidenceTotal += confidence;
      } else if (disease == 'septoria blight' || disease == 'septoria leaf spot') {
        septoriaCount++;
        septoriaConfidenceTotal += confidence;
      }
    }

    final double healthyAverage = healthyCount == 0 ? 0.0 : healthyConfidenceTotal / healthyCount;
    final double downyAverage = downyCount == 0 ? 0.0 : downyConfidenceTotal / downyCount;
    final double powderyAverage = powderyCount == 0 ? 0.0 : powderyConfidenceTotal / powderyCount;
    final double septoriaAverage = septoriaCount == 0 ? 0.0 : septoriaConfidenceTotal / septoriaCount;

    try {
      await _monitoringService.completeScanSession(
        sessionId: sessionId,
        totalScanned: _sessionScans.length,
        healthyCount: healthyCount,
        downyCount: downyCount,
        powderyCount: powderyCount,
        septoriaCount: septoriaCount,
        healthyAverageConfidence: healthyAverage,
        downyAverageConfidence: downyAverage,
        powderyAverageConfidence: powderyAverage,
        septoriaAverageConfidence: septoriaAverage,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('The final report could not be saved: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!mounted) return;
    final DateTime completedAt = DateTime.now();

    setState(() {
      _sessionFinished = true;
    });

    final bool? startNewSession = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanSessionReportScreen(
          scans: List<Map<String, dynamic>>.from(_sessionScans),
          startedAt: _sessionStartedAt,
          completedAt: completedAt,
        ),
      ),
    );

    if (!mounted) return;
    if (startNewSession == true) {
      await _startNewSession();
    }
  }

  Future<void> _startNewSession() async {
    setState(() {
      _sessionScans.clear();
      _sessionId = null;
      _sessionStartedAt = DateTime.now();
      _sessionFinished = false;
      _capturedImage = null;
      _liveFrame = null;
      _scanResponse = null;
      _scanSaved = false;
      _scanCompleted = false;
      _scanAddedToSession = false;
      _isProcessing = false;
    });
    await _startPreview();
  }

  double _readDoubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _normalizeDiseaseName(String value) {
    return value.replaceAll('_', ' ').trim();
  }

  String _pathogenForDisease(String diseaseName) {
    final String normalized = diseaseName.toLowerCase().replaceAll('_', ' ').trim();
    if (normalized == 'downy mildew') return 'Bremia lactucae';
    if (normalized == 'powdery mildew') return 'Erysiphe cichoracearum';
    if (normalized == 'septoria blight' || normalized == 'septoria leaf spot') return 'Septoria lactucae';
    if (normalized == 'healthy') return 'None detected';
    return 'Not available';
  }

  String _descriptionForDisease(String diseaseName) {
    final String normalized = diseaseName.toLowerCase().replaceAll('_', ' ').trim();
    if (normalized == 'healthy') return 'No visible signs of disease were found. The lettuce looks healthy based on this scan.';
    if (normalized == 'downy mildew') return 'Causes yellow spots on the leaves and may form mold underneath the leaf.';
    if (normalized == 'powdery mildew') return 'Looks like white powder on the leaves and can spread across the plant.';
    if (normalized == 'septoria blight' || normalized == 'septoria leaf spot') return 'Causes small brown or dark spots that can grow and damage the leaves.';
    return 'GreenGuard completed the lettuce health scan.';
  }

  String _pathogenDescriptionForDisease(String diseaseName) {
    final String normalized = diseaseName.toLowerCase().replaceAll('_', ' ').trim();
    if (normalized == 'healthy') return 'No supported disease-causing pathogen was detected in this lettuce image.';
    if (normalized == 'downy mildew') return 'Bremia lactucae is a disease-causing microorganism that infects lettuce leaves. It grows well in cool, wet, and humid conditions.';
    if (normalized == 'powdery mildew') return 'Erysiphe cichoracearum is a fungus that grows on plant surfaces and can look like white powder on the leaves.';
    if (normalized == 'septoria blight' || normalized == 'septoria leaf spot') return 'Septoria lactucae is a fungus that infects lettuce leaves and causes brown or dark leaf spots.';
    return 'No pathogen information is available.';
  }

  Color _resultColor(String diseaseName) {
    final String normalized = diseaseName.toLowerCase().replaceAll('_', ' ').trim();
    if (normalized == 'healthy') return const Color(0xFF5DBB63);
    if (normalized == 'downy mildew') return Colors.redAccent;
    if (normalized == 'powdery mildew') return Colors.orangeAccent;
    if (normalized.contains('septoria')) return Colors.deepOrange;
    return Colors.grey;
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );
  }

  // AI STATUS BADGE (Pings Laptop /health endpoint)
  Widget _buildAiStatusBadge() {
    Color bg;
    Color fg;
    IconData icon;

    if (_aiInitializing) {
      bg = Colors.amber.withValues(alpha: 0.12);
      fg = Colors.orange[800]!;
      icon = Icons.sync_rounded;
    } else if (_aiReady) {
      bg = const Color(0xFFEAF7EC);
      fg = const Color(0xFF2F6B3B);
      icon = Icons.bolt_rounded;
    } else {
      bg = Colors.red.withValues(alpha: 0.10);
      fg = Colors.redAccent;
      icon = Icons.error_outline_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          _aiInitializing
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _aiStatusMessage,
              style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          if (!_aiInitializing && !_aiReady)
            GestureDetector(
              onTap: _warmUpAi,
              child: Text(
                'Retry',
                style: TextStyle(color: fg, fontWeight: FontWeight.w900, decoration: TextDecoration.underline),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cameraBox() {
    if (_isCapturing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF2F6B3B)),
            SizedBox(height: 20),
            Text(
              'Capturing high-quality image...',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_capturedImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(_capturedImage!, fit: BoxFit.contain, gaplessPlayback: true),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'CAPTURED',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      );
    }

    if (_cameraConnected) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_liveFrame != null)
            Image.memory(
              _liveFrame!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            )
          else
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF2F6B3B)),
                  SizedBox(height: 14),
                  Text(
                    'Starting live stream...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey),
                  ),
                ],
              ),
            ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF2F6B3B).withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isSearching)
            const SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(color: Color(0xFF2F6B3B)),
            )
          else
            const Icon(Icons.camera_alt_rounded, size: 80, color: Colors.grey),
          const SizedBox(height: 18),
          Text(
            _isSearching ? 'Searching for camera...' : 'Camera Offline',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildScanResultCard() {
    final Map<String, dynamic>? response = _scanResponse;
    if (response == null) return const SizedBox.shrink();

    final bool success = response['success'] == true;
    final bool diagnosisAvailable = response['diagnosis_available'] == true;

    final dynamic rawSubject = response['subject'];
    final Map<String, dynamic> subject = rawSubject is Map<String, dynamic> ? rawSubject : <String, dynamic>{};
    final String subjectLabel = subject['label']?.toString() ?? 'Unknown';

    if (!success) {
      final String message = response['message']?.toString() ?? 'GreenGuard could not complete the scan.';
      return _simpleMessageCard(
        icon: Icons.error_outline_rounded,
        title: 'Scan Failed',
        message: message,
        color: Colors.redAccent,
        canCopy: true,
      );
    }

    if (!diagnosisAvailable) {
      final String message = response['message']?.toString() ?? 'No lettuce diagnosis is available.';
      return _simpleMessageCard(
        icon: Icons.center_focus_weak_rounded,
        title: 'Detected: $subjectLabel',
        message: message,
        color: Colors.teal,
        canCopy: false,
      );
    }

    final dynamic rawResult = response['result'];
    final Map<String, dynamic> result = rawResult is Map<String, dynamic> ? rawResult : <String, dynamic>{};
    final String diseaseName = _normalizeDiseaseName((result['display_name'] ?? result['class_name'] ?? 'Unknown Result').toString());
    final double confidencePercent = result['confidence_percent'] is num
        ? (result['confidence_percent'] as num).toDouble()
        : _readDoubleValue(result['confidence']) * 100.0;

    final String pathogen = _pathogenForDisease(diseaseName);
    final Color color = _resultColor(diseaseName);
    final bool databaseSaved = response['database_saved'] == true;
    final String? databaseError = response['database_error']?.toString();

    final dynamic rawEnhancement = response['enhancement'];
    final Map<String, dynamic> enhancement = rawEnhancement is Map<String, dynamic> ? rawEnhancement : <String, dynamic>{};
    final List<dynamic> operations = enhancement['operations'] is List ? enhancement['operations'] as List<dynamic> : <dynamic>[];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  diseaseName.toLowerCase() == 'healthy' ? Icons.verified_rounded : Icons.health_and_safety_rounded,
                  color: color,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Lettuce Health Result', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(diseaseName, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            diseaseName.toLowerCase() == 'healthy' ? 'Pathogen: None detected' : 'Pathogen: $pathogen',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1E2A1F)),
          ),
          const SizedBox(height: 8),
          Text(
            'Confidence: ${confidencePercent.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F)),
          ),
          const SizedBox(height: 8),
          Text('Detected: $subjectLabel', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('What does this mean?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
                const SizedBox(height: 7),
                Text(_descriptionForDisease(diseaseName), style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600, color: Color(0xFF465248))),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                const Text('What is this pathogen?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
                const SizedBox(height: 7),
                Text(_pathogenDescriptionForDisease(diseaseName), style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w600, color: Color(0xFF465248))),
              ],
            ),
          ),
          if (operations.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Photo Improvement: Complete', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2F6B3B))),
          ],
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: databaseSaved ? const Color(0xFFEAF7EC) : const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  databaseSaved ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: databaseSaved ? const Color(0xFF2F6B3B) : Colors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    databaseSaved
                        ? 'Photo and health result saved.'
                        : databaseError == null
                            ? 'The result has not been saved yet.'
                            : 'Save failed: $databaseError',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _simpleMessageCard({
    required IconData icon,
    required String title,
    required String message,
    required Color color,
    bool canCopy = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(fontSize: 15, height: 1.5)),
          if (canCopy) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: message));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('📋 Error log copied to clipboard!'),
                      backgroundColor: Color(0xFF2F6B3B),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy Error Log'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color.withValues(alpha: 0.12),
                  foregroundColor: color,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPipelineCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_rounded, color: Color(0xFF2F6B3B)),
              SizedBox(width: 8),
              Expanded(
                child: Text('How GreenGuard Checks Your Photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('After you choose Use Photo:', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text(
            '1. Improve Photo\n2. Check Plant\n3. Check Lettuce Health',
            style: TextStyle(color: Color(0xFF2F6B3B), fontWeight: FontWeight.w900, height: 1.5),
          ),
          const SizedBox(height: 16),
          const Text('What GreenGuard Sees', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _subjectTypes.map((subject) => _badge(subject['name'] as String, subject['color'] as Color)).toList(),
          ),
          const SizedBox(height: 18),
          const Text('Possible Health Results', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _supportedDiseases.map((disease) => _badge(disease['name'] as String, disease['color'] as Color)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionStatusCard() {
    final int total = _sessionScans.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4EB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFB7D9B9)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF2F6B3B),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.inventory_2_rounded, color: Colors.white),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Scan Session',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F)),
                ),
                const SizedBox(height: 4),
                Text(
                  total == 0 ? 'No lettuce scanned yet.' : '$total lettuce ${total == 1 ? 'has' : 'have'} been scanned.',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF68736A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoActions() {
    if (_sessionFinished) {
      return SizedBox(
        width: double.infinity,
        height: 64,
        child: ElevatedButton.icon(
          onPressed: _startNewSession,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('Start New Scan Session', style: TextStyle(fontWeight: FontWeight.w900)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2F6B3B),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      );
    }

    if (_scanCompleted) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _scanNextLettuce,
              icon: const Icon(Icons.add_a_photo_rounded),
              label: const Text('Scan Next Lettuce', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 64),
                backgroundColor: const Color(0xFF5DBB63),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _finishScanning,
              icon: const Icon(Icons.assessment_rounded),
              label: const Text('Done Scanning', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 64),
                backgroundColor: const Color(0xFF1E2A1F),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        ],
      );
    }

    if (_capturedImage == null) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 68,
            child: ElevatedButton.icon(
              onPressed: !_cameraConnected || _isCapturing || _isProcessing ? null : _takePhoto,
              icon: _isCapturing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Icon(Icons.camera_alt_rounded, size: 28),
              label: Text(
                _isCapturing ? 'Capturing...' : 'Take Photo',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5DBB63),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              ),
            ),
          ),
          if (_sessionScans.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: OutlinedButton.icon(
                onPressed: _finishScanning,
                icon: const Icon(Icons.assessment_rounded),
                label: const Text('Done Scanning', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isProcessing ? null : _retakePhoto,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retake', style: TextStyle(fontWeight: FontWeight.w900)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 62)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isProcessing || _scanCompleted ? null : _usePhoto,
            icon: _isProcessing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_rounded),
            label: Text(
              _isProcessing ? 'Analyzing...' : 'Use Photo',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 62),
              backgroundColor: const Color(0xFF2F6B3B),
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool soilConnected = !_soilLoading && _sensorData['connected'] == true;
    final String soilValue = _soilLoading ? 'Loading...' : (_sensorData['soil_value'] ?? '--%').toString();
    final String soilStatus = _soilLoading ? 'CONNECTING' : (_sensorData['soil_status'] ?? 'OFFLINE').toString().toUpperCase();
    final String soilConnection = _soilLoading ? 'CONNECTING' : soilConnected ? 'CONNECTED' : 'OFFLINE';
    final String soilMeaning = _soilMeaning(soilStatus);
    final Color soilColor = _soilStatusColor(soilStatus);

    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6FBF7),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F)),
        title: const Text(
          'Lettuce Health Scan',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 21, color: Color(0xFF1E2A1F)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            // AI ENGINE STATUS INDICATOR
            _buildAiStatusBadge(),

            const SizedBox(height: 14),

            // CAMERA
            Container(
              height: 320,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFB7D9B9), width: 2),
              ),
              child: _cameraBox(),
            ),

            const SizedBox(height: 18),

            // CAMERA STATUS
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _cameraConnected ? Icons.check_circle : Icons.wifi_tethering,
                        color: _cameraConnected ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _cameraConnected ? 'Camera Connected' : 'ESP32-CAM Setup',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(_cameraStatus, style: const TextStyle(fontSize: 15, height: 1.4)),
                  if (!_cameraConnected) ...[
                    const SizedBox(height: 14),
                    const Text(
                      '1. Turn ON your phone hotspot\n2. Open GreenGuard\n3. Power the ESP32-CAM\n4. Wait for automatic connection',
                      style: TextStyle(fontSize: 14, height: 1.6),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _searchAgain,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_cameraConnected ? 'Reconnect' : 'Search Again'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildSessionStatusCard(),

            const SizedBox(height: 16),

            _buildPhotoActions(),

            if (_scanResponse != null) ...[
              const SizedBox(height: 22),
              _buildScanResultCard(),
            ],

            const SizedBox(height: 22),

            _buildPipelineCard(),

            const SizedBox(height: 38),

            // FARM STATUS
            const Text(
              'Farm Status',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F)),
            ),

            const SizedBox(height: 16),

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
                  const Text(
                    'Monitoring',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF2F6B3B)),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Icon(
                        soilConnected ? Icons.check_circle_rounded : _soilLoading ? Icons.sync_rounded : Icons.error_outline_rounded,
                        color: soilConnected ? const Color(0xFF2F6B3B) : _soilLoading ? Colors.orange : Colors.grey,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Soil Sensor: $soilConnection',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: soilConnected ? const Color(0xFF2F6B3B) : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text('Temperature: 24.5°C', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Soil Moisture: $soilValue', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Condition: ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(soilStatus, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: soilColor)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: soilColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: soilColor.withValues(alpha: 0.20)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('What does this mean?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
                        const SizedBox(height: 6),
                        Text(soilMeaning, style: const TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // HEALTH LOGS
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HealthLogsScreen()),
                  );
                },
                icon: const Icon(Icons.history_rounded),
                label: const Text('View All Health Logs', style: TextStyle(fontWeight: FontWeight.w900)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F6B3B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
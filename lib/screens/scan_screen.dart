import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/lettuce_scan_report.dart';
import '../widgets/lettuce_scan_report_card.dart';
import 'shared/scan_session_report_screen.dart';
import '../services/Esp_Cam.dart';
import '../services/monitoring_service.dart';
import 'shared/health_logs_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.droneManual = false});

  final bool droneManual;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final EspCamService _espCamService = EspCamService();
  final MonitoringService _monitoringService = MonitoringService();

  StreamSubscription<EspCamDevice>? _cameraSubscription;
  StreamSubscription<Uint8List>? _mjpegSubscription;

  Timer? _soilTimer;
  Timer? _aiHealthTimer;

  Uint8List? _liveFrame;
  Uint8List? _capturedImage;

  Map<String, dynamic>? _scanResponse;
  Map<String, dynamic> _sensorData = {};

  bool _streamConnecting = false;
  bool _cameraConnected = false;
  bool _isSearching = true;
  bool _isCapturing = false;
  bool _isProcessing = false;

  bool _soilLoading = true;
  bool _soilWasConnected = false;

  bool _scanCompleted = false;
  bool _sessionFinished = false;
  bool _finishingSession = false;
  bool _reportOpen = false;

  // AI Model Status
  bool _aiReady = false;
  bool _aiInitializing = true;
  String _aiStatusMessage = 'Checking Laptop AI Server...';

  String _cameraStatus = 'Waiting for GreenGuard-CAM-01...';

  final List<Map<String, dynamic>> _sessionScans = [];
  String? _sessionId;
  late DateTime _sessionStartedAt;
  DateTime? _sessionCompletedAt;
  String? _captureId;
  DateTime? _capturedAt;
  String? _uploadedImageUrl;
  Map<String, dynamic>? _pendingDiagnosis;

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

    _aiHealthTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _warmUpAi(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCamera();
    });
  }

  // Check GreenGuard AI Server status via /health
  Future<void> _warmUpAi() async {
    if (!mounted) return;

    if (!_aiReady) {
      setState(() {
        _aiInitializing = true;
        _aiStatusMessage = 'Connecting to AI Server...';
      });
    }

    final String? server = await EspCamService.refreshAiServer();

    if (!mounted) return;
    setState(() {
      _aiInitializing = false;
      _aiReady = server != null;
      if (server != null) {
        _aiStatusMessage = 'AI Online — VPS Cloud';
      } else {
        _aiStatusMessage = 'AI Server Offline';
      }
    });
  }

  @override
  void dispose() {
    _soilTimer?.cancel();
    _aiHealthTimer?.cancel();
    _mjpegSubscription?.cancel();
    _cameraSubscription?.cancel();
    unawaited(_espCamService.stopMjpegStream());
    super.dispose();
  }

  void _startSoilMonitoring() {
    unawaited(_loadSoilData());
    _soilTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_loadSoilData());
    });
  }

  Future<void> _loadSoilData() async {
    final Map<String, dynamic> data = await _monitoringService
        .fetchSensorData();
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
      _cameraStatus =
          'Waiting for camera. Turn on your hotspot, then power the ESP32-CAM.';
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
    final settings = await _espCamService.updateSettings(
      preset: 'best',
      xclkMHz: 28,
    );
    if (!mounted) return;

    if (settings == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera connected, but recommended settings could not be applied.',
          ),
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
    if (!mounted ||
        !_cameraConnected ||
        _capturedImage != null ||
        _isCapturing) {
      return;
    }

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
    if (_isCapturing ||
        _isProcessing ||
        _finishingSession ||
        _sessionFinished) {
      return;
    }
    if (!_cameraConnected) {
      _showScanMessage('ESP32-CAM is not connected.', error: true);
      return;
    }

    setState(() {
      _isCapturing = true;
      _clearPhoto();
    });

    final image = await _espCamService.capturePhoto() ?? _liveFrame;
    if (!mounted) return;
    if (image == null || image.isEmpty) {
      setState(() => _isCapturing = false);
      await _startPreview();
      if (mounted) {
        _showScanMessage('No photo received. Try again.', error: true);
      }
      return;
    }

    setState(() {
      _capturedImage = image;
      _capturedAt = DateTime.now().toUtc();
      _captureId = _newCaptureId();
      _isCapturing = false;
    });

    await _usePhoto();
  }

  String _newCaptureId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void _clearPhoto() {
    _capturedImage = null;
    _capturedAt = null;
    _captureId = null;
    _uploadedImageUrl = null;
    _pendingDiagnosis = null;
    _scanResponse = null;
    _scanCompleted = false;
  }

  Future<void> _prepareNextPhoto() async {
    if (_isProcessing || _isCapturing || _finishingSession) return;
    setState(() {
      _clearPhoto();
      _liveFrame = null;
    });
    await _startPreview();
  }

  Future<String> _uploadScanPhoto(
    Uint8List imageBytes,
    String captureId,
  ) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw StateError('Sign in to save the photo.');

    final bucket = supabase.storage.from(_scanImageBucket);
    final path = '${user.id}/${_sessionId!}/$captureId.jpg';
    try {
      await bucket.uploadBinary(
        path,
        imageBytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );
    } on StorageException catch (error) {
      // A request can succeed remotely even if the phone lost the response.
      if (error.statusCode != '409' && error.error != 'Duplicate') rethrow;
    }
    return bucket.getPublicUrl(path);
  }

  Future<void> _usePhoto() async {
    if (_isProcessing ||
        _scanCompleted ||
        _finishingSession ||
        _sessionFinished) {
      return;
    }
    final image = _capturedImage;
    final captureId = _captureId;
    final capturedAt = _capturedAt;
    if (image == null || captureId == null || capturedAt == null) return;

    setState(() {
      _isProcessing = true;
      _scanResponse = null;
    });

    Map<String, dynamic> response = {};
    Map<String, dynamic>? report;
    var saved = false;
    String? saveError;

    try {
      response =
          _pendingDiagnosis ?? await _espCamService.scanPhotoWithAi(image);
      if (!mounted) return;
      final rawResult = response['result'];
      if (response['success'] == true &&
          response['diagnosis_available'] == true &&
          rawResult is Map<String, dynamic>) {
        _pendingDiagnosis = response;
        final diseaseName = LettuceScanReport.diseaseName({
          'disease_name': rawResult['display_name'] ?? rawResult['class_name'],
        });
        final confidence = LettuceScanReport.confidence({
          'confidence': rawResult['confidence'],
          'score': rawResult['confidence_percent'] == null
              ? null
              : '${rawResult['confidence_percent']}%',
        });
        final guidance = await LettuceScanReport.guidance(diseaseName);
        final weather = LettuceScanReport.text(response, ['weather_condition']);
        final temperature = double.tryParse(
          LettuceScanReport.text(response, ['temperature', 'temp']),
        );
        report = {
          ...guidance,
          'disease_name': diseaseName,
          'confidence_score': confidence,
          'captured_at': capturedAt.toIso8601String(),
          'image_bytes': image,
          'weather_condition': weather,
          'temperature': temperature,
        };

        if (!LettuceScanReport.diseaseNames.containsKey(
              LettuceScanReport.diseaseKey(diseaseName),
            ) ||
            confidence == null) {
          throw StateError(
            'The AI returned an incomplete diagnosis. Retake the photo.',
          );
        }
        if (_sessionId == null) {
          _sessionStartedAt = capturedAt;
          _sessionId = await _monitoringService.createScanSession(
            startedAt: capturedAt,
          );
        }
        final imageUrl = _uploadedImageUrl ??= await _uploadScanPhoto(
          image,
          captureId,
        );
        final saveResult = await _monitoringService.saveHealthLog(
          diseaseName: diseaseName,
          confidence: confidence,
          weatherCondition: weather,
          temperature: temperature,
          deviceId: 'GreenGuard-CAM-01',
          imageUrl: imageUrl,
          scanSessionId: _sessionId,
          scanCaptureId: captureId,
          capturedAt: capturedAt,
          report: guidance,
        );

        final savedRecord = saveResult.record;
        if (saveResult.success && savedRecord != null) {
          // Keep URLs in the batch instead of retaining every photo in memory.
          if (!_sessionScans.any(
            (scan) => scan['scan_capture_id'] == captureId,
          )) {
            _sessionScans.add(savedRecord);
          }
          report = {...savedRecord, 'image_bytes': image};
          saved = true;
        } else {
          saveError = saveResult.error ?? 'The scan could not be saved.';
        }
      }
    } catch (error) {
      debugPrint('Lettuce capture could not be saved: $error');
      saveError = error is StateError
          ? error.message
          : 'The photo or result could not be saved. Check your connection and try again.';
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _scanCompleted = saved;
          _scanResponse = {
            ...response,
            'report': ?report,
            'database_saved': saved,
            'database_error': ?saveError,
          };
        });
      }
    }

    if (!mounted) return;
    if (saved) {
      _showScanMessage('Photo ${_sessionScans.length} saved.');
    } else if (saveError != null) {
      _showScanMessage(saveError, error: true);
    } else {
      _showScanMessage(
        response['message']?.toString() ?? 'No lettuce diagnosis was produced.',
        error: true,
      );
    }
  }

  void _showScanMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade800 : const Color(0xff2f6b3b),
      ),
    );
  }

  Future<void> _finishScanning() async {
    if (_finishingSession ||
        _isProcessing ||
        _isCapturing ||
        _sessionFinished) {
      return;
    }
    final sessionId = _sessionId;
    if (_sessionScans.isEmpty || sessionId == null) return;

    setState(() => _finishingSession = true);
    DateTime completedAt;
    List<Map<String, dynamic>> savedScans;
    try {
      savedScans = await _monitoringService.fetchSessionHealthLogs(sessionId);
      if (savedScans.isEmpty) throw StateError('No saved photos were found.');
      final scansByDisease = <String, List<Map<String, dynamic>>>{
        for (final key in LettuceScanReport.diseaseNames.keys) key: [],
      };
      for (final scan in savedScans) {
        final key = LettuceScanReport.diseaseKey(
          LettuceScanReport.diseaseName(scan),
        );
        scansByDisease[key]?.add(scan);
      }

      int count(String key) => scansByDisease[key]!.length;
      double average(String key) {
        final values = scansByDisease[key]!
            .map(LettuceScanReport.confidence)
            .whereType<double>()
            .toList();
        return values.isEmpty
            ? 0
            : values.reduce((a, b) => a + b) / values.length;
      }

      completedAt = await _monitoringService.completeScanSession(
        sessionId: sessionId,
        totalScanned: savedScans.length,
        healthyCount: count('healthy'),
        downyCount: count('downy mildew'),
        powderyCount: count('powdery mildew'),
        septoriaCount: count('septoria blight'),
        healthyAverageConfidence: average('healthy'),
        downyAverageConfidence: average('downy mildew'),
        powderyAverageConfidence: average('powdery mildew'),
        septoriaAverageConfidence: average('septoria blight'),
      );
    } catch (error) {
      debugPrint('Unable to finish scan session: $error');
      if (mounted) {
        setState(() => _finishingSession = false);
        _showScanMessage(
          'The final report could not be saved. Try again.',
          error: true,
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _sessionScans
        ..clear()
        ..addAll(savedScans);
      _sessionCompletedAt = completedAt;
      _sessionFinished = true;
      _finishingSession = false;
    });
    await _stopPreview();
    if (mounted) await _openFinalReport();
  }

  Future<void> _openFinalReport() async {
    if (_reportOpen) return;
    _reportOpen = true;
    try {
      final startNewSession = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ScanSessionReportScreen(
            scans: List<Map<String, dynamic>>.of(_sessionScans),
            startedAt: _sessionStartedAt,
            completedAt: _sessionCompletedAt,
          ),
        ),
      );
      if (mounted && startNewSession == true) await _startNewSession();
    } finally {
      _reportOpen = false;
    }
  }

  Future<void> _startNewSession() async {
    setState(() {
      _sessionScans.clear();
      _sessionId = null;
      _sessionStartedAt = DateTime.now();
      _sessionCompletedAt = null;
      _sessionFinished = false;
      _clearPhoto();
      _liveFrame = null;
    });
    await _startPreview();
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
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // AI STATUS BADGE (Pings VPS /health endpoint)
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
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          if (!_aiInitializing && !_aiReady)
            GestureDetector(
              onTap: _warmUpAi,
              child: Text(
                'Retry',
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w900,
                  decoration: TextDecoration.underline,
                ),
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
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    if (_capturedImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            _capturedImage!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
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
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                    ),
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
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
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
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanResultCard() {
    final response = _scanResponse;
    if (response == null) return const SizedBox.shrink();

    final report = response['report'];
    if (report is Map<String, dynamic>) {
      final saved = response['database_saved'] == true;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            saved ? 'Photo and result saved' : 'Result not saved',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: saved ? const Color(0xff2f6b3b) : Colors.red.shade800,
            ),
          ),
          if (!saved)
            Text(
              response['database_error']?.toString() ??
                  'Tap Try Again to save this result.',
            ),
          const SizedBox(height: 8),
          LettuceScanReportCard(
            key: ValueKey(_captureId),
            scan: report,
            photoNumber: saved ? _sessionScans.length : null,
          ),
        ],
      );
    }

    final subject = response['subject'];
    final subjectLabel = subject is Map ? subject['label']?.toString() : null;
    final success = response['success'] == true;
    return _simpleMessageCard(
      icon: success
          ? Icons.center_focus_weak_rounded
          : Icons.error_outline_rounded,
      title: success ? subjectLabel ?? 'No diagnosis' : 'Scan failed',
      message:
          response['database_error']?.toString() ??
          response['message']?.toString() ??
          'GreenGuard could not complete the scan.',
      color: success ? Colors.teal : Colors.red.shade800,
      canCopy: !success,
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
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E2A1F),
                  ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                child: Text(
                  'How GreenGuard Checks Your Photo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'After you take a photo:',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text(
            '1. Improve Photo\n2. Check Plant\n3. Check Lettuce Health',
            style: TextStyle(
              color: Color(0xFF2F6B3B),
              fontWeight: FontWeight.w900,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'What GreenGuard Sees',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _subjectTypes
                .map(
                  (subject) => _badge(
                    subject['name'] as String,
                    subject['color'] as Color,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 18),
          const Text(
            'Possible Health Results',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _supportedDiseases
                .map(
                  (disease) => _badge(
                    disease['name'] as String,
                    disease['color'] as Color,
                  ),
                )
                .toList(),
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E2A1F),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  total == 0
                      ? 'No lettuce scanned yet.'
                      : '$total lettuce ${total == 1 ? 'has' : 'have'} been scanned.',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF68736A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoActions() {
    const green = Color(0xff2f6b3b);
    const minSize = Size.fromHeight(56);
    final busy = _isCapturing || _isProcessing || _finishingSession;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sessionFinished) ...[
          FilledButton.icon(
            onPressed: _openFinalReport,
            icon: const Icon(Icons.assessment_outlined),
            label: const Text('View final report'),
            style: FilledButton.styleFrom(
              backgroundColor: green,
              minimumSize: minSize,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _startNewSession,
            style: OutlinedButton.styleFrom(
              foregroundColor: green,
              minimumSize: minSize,
            ),
            child: const Text('Start a new session'),
          ),
        ] else ...[
          if (_capturedImage == null) ...[
            FilledButton.icon(
              onPressed: !_cameraConnected || busy ? null : _takePhoto,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(_isCapturing ? 'Taking photo…' : 'Take photo'),
              style: FilledButton.styleFrom(
                backgroundColor: green,
                minimumSize: minSize,
              ),
            ),
          ] else if (_scanCompleted) ...[
            OutlinedButton.icon(
              onPressed: busy ? null : _prepareNextPhoto,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Scan another lettuce'),
              style: OutlinedButton.styleFrom(
                foregroundColor: green,
                minimumSize: minSize,
              ),
            ),
          ] else ...[
            if (_isProcessing) ...[
              const LinearProgressIndicator(color: green),
              const SizedBox(height: 8),
              const Text(
                'Checking and saving the photo…',
                style: TextStyle(fontSize: 16),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: busy ? null : _usePhoto,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  _pendingDiagnosis == null
                      ? 'Try scan again'
                      : 'Try saving again',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  minimumSize: minSize,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: busy ? null : _prepareNextPhoto,
                style: OutlinedButton.styleFrom(
                  foregroundColor: green,
                  minimumSize: minSize,
                ),
                child: const Text('Retake photo'),
              ),
            ],
          ],
          if (_sessionScans.isNotEmpty) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy ? null : _finishScanning,
              icon: const Icon(Icons.assessment_outlined),
              label: Text(
                _finishingSession
                    ? 'Saving final report…'
                    : 'Done & Generate Report',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff1e2a1f),
                minimumSize: minSize,
              ),
            ),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool soilConnected =
        !_soilLoading && _sensorData['connected'] == true;
    final String soilValue = _soilLoading
        ? 'Loading...'
        : (_sensorData['soil_value'] ?? '--%').toString();
    final String soilStatus = _soilLoading
        ? 'CONNECTING'
        : (_sensorData['soil_status'] ?? 'OFFLINE').toString().toUpperCase();
    final String soilConnection = _soilLoading
        ? 'CONNECTING'
        : soilConnected
        ? 'CONNECTED'
        : 'OFFLINE';
    final String soilMeaning = _soilMeaning(soilStatus);
    final Color soilColor = _soilStatusColor(soilStatus);

    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6FBF7),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F)),
        title: Text(
          widget.droneManual ? 'Drone Manual Scan' : 'Lettuce Health Scan',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 21,
            color: Color(0xFF1E2A1F),
          ),
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
                        _cameraConnected
                            ? Icons.check_circle
                            : Icons.wifi_tethering,
                        color: _cameraConnected ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _cameraConnected
                              ? 'Camera Connected'
                              : 'ESP32-CAM Setup',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _cameraStatus,
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
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
                      label: Text(
                        _cameraConnected ? 'Reconnect' : 'Search Again',
                      ),
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
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E2A1F),
              ),
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
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2F6B3B),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Icon(
                        soilConnected
                            ? Icons.check_circle_rounded
                            : _soilLoading
                            ? Icons.sync_rounded
                            : Icons.error_outline_rounded,
                        color: soilConnected
                            ? const Color(0xFF2F6B3B)
                            : _soilLoading
                            ? Colors.orange
                            : Colors.grey,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Soil Sensor: $soilConnection',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: soilConnected
                                ? const Color(0xFF2F6B3B)
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Temperature: 24.5°C',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Soil Moisture: $soilValue',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Condition: ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        soilStatus,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: soilColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: soilColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: soilColor.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'What does this mean?',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1E2A1F),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          soilMeaning,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                label: const Text(
                  'View All Health Logs',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F6B3B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
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

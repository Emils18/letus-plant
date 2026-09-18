import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/Esp_Cam.dart';
import '../services/monitoring_service.dart';
import 'shared/health_logs_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
  });

  @override
  State<ScanScreen> createState() =>
      _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final EspCamService _espCamService =
      EspCamService();

  final MonitoringService _monitoringService =
      MonitoringService();

  StreamSubscription<EspCamDevice>?
      _cameraSubscription;

  StreamSubscription<Uint8List>?
      _mjpegSubscription;

  Uint8List? _liveFrame;
  Uint8List? _capturedImage;

  EspCamSettings? _cameraSettings;

  bool _streamConnecting = false;
  bool _cameraConnected = false;
  bool _isSearching = true;
  bool _isCapturing = false;
  bool _settingsBusy = false;
  bool _isProcessing = false;
  bool _scanSaved = false;

  Timer? _soilTimer;

  Map<String, dynamic> _sensorData = {};

  bool _soilLoading = true;

  // Used so the in-app connection message
  // only appears when the sensor changes
  // from offline -> connected.
  bool _soilWasConnected = false;

  Map<String, dynamic>? _scanResponse;

  String _cameraStatus =
      'Waiting for GreenGuard-CAM-01...';

  final List<Map<String, dynamic>>
      _subjectTypes = [
    {
      'name': 'Not a Plant',
      'color': Colors.grey,
    },
    {
      'name': 'Plant',
      'color': Colors.teal,
    },
    {
      'name': 'Lettuce',
      'color': Color(0xFF2F6B3B),
    },
  ];

  final List<Map<String, dynamic>>
      _supportedDiseases = [
    {
      'name': 'Healthy',
      'color': Colors.green,
    },
    {
      'name': 'Downy Mildew',
      'color': Colors.redAccent,
    },
    {
      'name': 'Powdery Mildew',
      'color': Colors.orangeAccent,
    },
    {
      'name': 'Septoria Blight',
      'color': Colors.deepOrange,
    },
  ];

  @override
  void initState() {
    super.initState();

    _cameraSubscription =
        _espCamService.cameraEvents.listen(
      _cameraRegistered,
    );

    _startSoilMonitoring();

    WidgetsBinding.instance
        .addPostFrameCallback(
      (_) {
        _initializeCamera();
      },
    );
  }

  @override
  void dispose() {
    if (_mjpegSubscription != null) {
      unawaited(
        _mjpegSubscription!.cancel(),
      );
    }

    if (_cameraSubscription != null) {
      unawaited(
        _cameraSubscription!.cancel(),
      );
    }

    unawaited(
      _espCamService.stopMjpegStream(),
    );

    _soilTimer?.cancel();

    super.dispose();
  }

  // ============================================================
  // SOIL MONITORING
  // ============================================================

  void _startSoilMonitoring() {
    unawaited(
      _loadSoilData(),
    );

    // Refresh the real ESP32 soil data every 1 second.
    _soilTimer = Timer.periodic(
      const Duration(
        seconds: 1,
      ),
      (_) {
        unawaited(
          _loadSoilData(),
        );
      },
    );
  }

  Future<void> _loadSoilData() async {
    final Map<String, dynamic> data =
        await _monitoringService
            .fetchSensorData();

    if (!mounted) return;

    final bool isConnected =
        data['connected'] == true;

    final bool showConnectedMessage =
        isConnected &&
        !_soilWasConnected;

    setState(() {
      _sensorData = data;
      _soilLoading = false;
      _soilWasConnected =
          isConnected;
    });

    // ============================================================
    // IN-APP MESSAGE ONLY
    // ============================================================
    //
    // This is NOT an Android/system notification.
    // It stays inside GreenGuard.
    //
    // It only appears when the sensor changes:
    //
    // OFFLINE -> CONNECTED
    //
    // ============================================================

    if (showConnectedMessage &&
        mounted) {
      ScaffoldMessenger.of(context)
          .hideCurrentSnackBar();

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            '🌱 Soil Sensor Detected\n'
            'GreenGuard is now receiving live soil moisture data.',
            style: TextStyle(
              fontWeight:
                  FontWeight.w700,
              height: 1.4,
            ),
          ),
          backgroundColor:
              Color(
            0xFF2F6B3B,
          ),
          duration:
              Duration(
            seconds: 3,
          ),
        ),
      );
    }
  }

  // ============================================================
  // SIMPLE SOIL EXPLANATIONS
  // ============================================================
  //
  // These explanations are intentionally simple
  // so farmers and elderly users can understand them.
  //
  // ============================================================

  String _soilMeaning(
    String status,
  ) {
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

  Color _soilStatusColor(
    String status,
  ) {
    switch (status.toUpperCase()) {
      case 'DRY':
        return Colors.orange;

      case 'IDEAL':
        return const Color(
          0xFF2F6B3B,
        );

      case 'WET':
        return Colors.blue;

      default:
        return Colors.grey;
    }
  }

  // ============================================================
  // CAMERA CONNECTION
  // ============================================================

  Future<void> _initializeCamera() async {
    await _espCamService
        .startDiscoveryServer();

    if (!mounted) return;

    setState(() {
      _isSearching = true;

      _cameraStatus =
          'Searching for GreenGuard-CAM-01...';
    });

    final bool connected =
        await _espCamService
            .checkConnection();

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

  Future<void> _cameraRegistered(
    EspCamDevice device,
  ) async {
    if (!mounted) return;

    setState(() {
      _isSearching = true;

      _cameraStatus =
          '${device.deviceId} found. Connecting...';
    });

    final bool connected =
        await _espCamService
            .checkConnection();

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

      _cameraStatus =
          'GreenGuard-CAM-01 connected.';
    });

    unawaited(
      _loadCameraSettings(),
    );

    unawaited(
      _startPreview(),
    );
  }

  Future<void> _searchAgain() async {
    await _stopPreview();

    _espCamService.forgetCamera();

    if (!mounted) return;

    setState(() {
      _capturedImage = null;
      _liveFrame = null;
      _cameraSettings = null;

      _cameraConnected = false;
      _isSearching = true;

      _cameraStatus =
          'Searching for GreenGuard-CAM-01...';
    });

    await _initializeCamera();
  }

  Future<void> _stopPreview() async {
    if (_mjpegSubscription != null) {
      await _mjpegSubscription!.cancel();

      _mjpegSubscription = null;
    }

    await _espCamService
        .stopMjpegStream();
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

    _mjpegSubscription =
        _espCamService
            .mjpegStream()
            .listen(
      (Uint8List frame) {
        if (!mounted ||
            _isCapturing ||
            _capturedImage != null) {
          return;
        }

        setState(() {
          _liveFrame = frame;
          _streamConnecting = false;
        });
      },
      onError: (Object error) {
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

  Future<void> _loadCameraSettings() async {
    final EspCamSettings? settings =
        await _espCamService
            .getCameraSettings();

    if (!mounted ||
        settings == null) {
      return;
    }

    setState(() {
      _cameraSettings = settings;
    });
  }

  Future<void> _applyCameraChange(
    Future<EspCamSettings?>
        Function() action,
  ) async {
    if (_settingsBusy) return;

    setState(() {
      _settingsBusy = true;
    });

    await _stopPreview();

    await Future<void>.delayed(
      const Duration(
        milliseconds: 180,
      ),
    );

    final EspCamSettings? settings =
        await action();

    if (!mounted) return;

    setState(() {
      _settingsBusy = false;

      if (settings != null) {
        _cameraSettings =
            settings;
      }
    });

    if (settings == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Camera setting could not be updated.',
          ),
        ),
      );
    }

    if (_capturedImage == null &&
        _cameraConnected) {
      await Future<void>.delayed(
        const Duration(
          milliseconds: 180,
        ),
      );

      if (mounted) {
        await _startPreview();
      }
    }
  }

  Future<void> _setPreset(
    String preset,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        preset: preset,
      ),
    );
  }

  Future<void> _changeXclk(
    int change,
  ) async {
    final EspCamSettings? settings =
        _cameraSettings;

    if (settings == null) return;

    final int next =
        (settings.xclkMHz + change)
            .clamp(
              20,
              28,
            );

    if (next ==
        settings.xclkMHz) {
      return;
    }

    setState(() {
      _cameraSettings =
          settings.copyWith(
        xclkMHz: next,
      );
    });

    await _applyCameraChange(
      () => _espCamService
          .setXclkMHz(
        next,
      ),
    );
  }

  Future<void> _saveBrightness(
    int value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        brightness: value,
      ),
    );
  }

  Future<void> _saveContrast(
    int value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        contrast: value,
      ),
    );
  }

  Future<void> _saveSaturation(
    int value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        saturation: value,
      ),
    );
  }

  Future<void> _setSpecialEffect(
    int value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        specialEffect: value,
      ),
    );
  }

  Future<void> _setAwb(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        awb: value,
      ),
    );
  }

  Future<void> _setAwbGain(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        awbGain: value,
      ),
    );
  }

  Future<void> _setWbMode(
    int value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        wbMode: value,
      ),
    );
  }

  Future<void> _setAec(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        aec: value,
      ),
    );
  }

  Future<void> _setAec2(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        aec2: value,
      ),
    );
  }

  Future<void> _saveAeLevel(
    int value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        aeLevel: value,
      ),
    );
  }

  Future<void> _setAgc(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        agc: value,
      ),
    );
  }

  Future<void> _setGainCeiling(
    int value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        gainCeiling: value,
      ),
    );
  }

  Future<void> _setBpc(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        bpc: value,
      ),
    );
  }

  Future<void> _setWpc(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        wpc: value,
      ),
    );
  }

  Future<void> _setRawGma(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        rawGma: value,
      ),
    );
  }

  Future<void> _setLensCorrection(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        lensCorrection: value,
      ),
    );
  }

  Future<void> _setDcw(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        dcw: value,
      ),
    );
  }

  Future<void> _setMirror(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        hMirror: value,
      ),
    );
  }

  Future<void> _setVerticalFlip(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        vFlip: value,
      ),
    );
  }

  Future<void> _setColorBar(
    bool value,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .updateSettings(
        colorBar: value,
      ),
    );
  }

  Future<void> _setFlashLevel(
    String level,
  ) async {
    await _applyCameraChange(
      () => _espCamService
          .setFlashLevel(
        level,
      ),
    );
  }

  Future<void>
      _resetCameraSettings() async {
    await _applyCameraChange(
      () => _espCamService
          .resetRecommendedSettings(),
    );
  }

  // ============================================================
  // TAKE PHOTO
  // ============================================================

  Future<void> _takePhoto() async {
    if (!_cameraConnected) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'ESP32-CAM is not connected.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _isCapturing = true;

      _capturedImage = null;
      _liveFrame = null;
      _scanResponse = null;
      _scanSaved = false;
    });

    await _stopPreview();

    await Future<void>.delayed(
      const Duration(
        milliseconds: 300,
      ),
    );

    final Uint8List? image =
        await _espCamService
            .capturePhoto();

    if (!mounted) return;

    if (image == null ||
        image.isEmpty) {
      setState(() {
        _isCapturing = false;
      });

      await _startPreview();

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Photo capture failed. Please try again.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _capturedImage = image;
      _isCapturing = false;
    });
  }

  Future<void> _retakePhoto() async {
    if (_isProcessing) {
      return;
    }

    setState(() {
      _capturedImage = null;
      _liveFrame = null;
      _scanResponse = null;
      _scanSaved = false;
      _isProcessing = false;
    });

    await _startPreview();
  }

  // ============================================================
  // USE PHOTO / AI SCAN
  // ============================================================

  Future<void> _usePhoto() async {
    final Uint8List? image =
        _capturedImage;

    if (image == null ||
        image.isEmpty ||
        _isProcessing) {
      return;
    }

    if (_scanSaved &&
        _scanResponse != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'This scan is already saved. Retake the photo for a new scan.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _isProcessing = true;
      _scanResponse = null;
    });

    final Map<String, dynamic>
        response =
        await _espCamService
            .scanPhotoWithAi(
      image,
    );

    if (!mounted) return;

    Map<String, dynamic>
        finalResponse = {
      ...response,
    };

    final bool success =
        response['success'] == true;

    final bool diagnosisAvailable =
        response[
                'diagnosis_available'] ==
            true;

    bool saved = false;
    String? saveError;

    if (success &&
        diagnosisAvailable) {
      final dynamic rawResult =
          response['result'];

      if (rawResult
          is Map<String, dynamic>) {
        final String diseaseName =
            (
              rawResult[
                      'display_name'] ??
                  rawResult[
                      'class_name'] ??
                  'Unknown Result'
            )
                .toString()
                .replaceAll(
                  '_',
                  ' ',
                )
                .trim();

        final double confidence =
            _readDoubleValue(
          rawResult['confidence'],
        );

        final HealthLogSaveResult
            saveResult =
            await _monitoringService
                .saveHealthLog(
          diseaseName:
              diseaseName,
          confidence:
              confidence,
          location:
              'Lapu-Lapu City, Cebu',
          deviceId:
              'GreenGuard-CAM-01',
        );

        if (!mounted) return;

        saved =
            saveResult.success;

        saveError =
            saveResult.error;

        finalResponse = {
          ...response,
          'database_saved':
              saved,
          'database_error':
              saveError,
        };
      }
    } else {
      finalResponse = {
        ...response,
        'database_saved':
            false,
      };
    }

    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _scanResponse =
          finalResponse;
      _scanSaved = saved;
    });

    final String message;

    if (!success) {
      message =
          response['message']
                  ?.toString() ??
              'GreenGuard scan failed.';
    } else if (!diagnosisAvailable) {
      message =
          response['message']
                  ?.toString() ??
              'No lettuce diagnosis was produced.';
    } else if (saved) {
      message =
          'Lettuce health check complete and saved to Health Logs.';
    } else {
      message =
          'Lettuce health check complete, but the Health Log could not be saved${saveError == null ? '.' : ': $saveError'}';
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          message,
        ),
        backgroundColor:
            success
                ? const Color(
                    0xFF2F6B3B,
                  )
                : Colors.redAccent,
      ),
    );
  }

  double _readDoubleValue(
    dynamic value,
  ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ??
              '',
        ) ??
        0.0;
  }

  String _normalizeDiseaseName(
    String value,
  ) {
    return value
        .replaceAll(
          '_',
          ' ',
        )
        .trim();
  }

  String _pathogenForDisease(
    String diseaseName,
  ) {
    final String normalized =
        diseaseName
            .toLowerCase()
            .replaceAll(
              '_',
              ' ',
            )
            .trim();

    if (normalized ==
        'downy mildew') {
      return 'Bremia lactucae';
    }

    if (normalized ==
        'powdery mildew') {
      return 'Erysiphe cichoracearum';
    }

    if (normalized ==
            'septoria blight' ||
        normalized ==
            'septoria leaf spot') {
      return 'Septoria lactucae';
    }

    if (normalized ==
        'healthy') {
      return 'No pathogen detected';
    }

    return 'Not available';
  }

  Color _resultColor(
    String diseaseName,
  ) {
    final String normalized =
        diseaseName
            .toLowerCase()
            .replaceAll(
              '_',
              ' ',
            )
            .trim();

    if (normalized ==
        'healthy') {
      return const Color(
        0xFF5DBB63,
      );
    }

    if (normalized ==
        'downy mildew') {
      return Colors.redAccent;
    }

    if (normalized ==
        'powdery mildew') {
      return Colors.orangeAccent;
    }

    if (normalized.contains(
      'septoria',
    )) {
      return Colors.deepOrange;
    }

    return Colors.grey;
  }

  Widget _badge(
    String label,
    Color color,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.10,
        ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight:
              FontWeight.w800,
        ),
      ),
    );
  }

  // ============================================================
  // SCAN RESULT CARD
  // ============================================================

  Widget _buildScanResultCard() {
    final Map<String, dynamic>?
        response =
        _scanResponse;

    if (response == null) {
      return const SizedBox.shrink();
    }

    final bool success =
        response['success'] == true;

    final bool diagnosisAvailable =
        response[
                'diagnosis_available'] ==
            true;

    final dynamic rawSubject =
        response['subject'];

    final Map<String, dynamic>
        subject =
        rawSubject
                is Map<String, dynamic>
            ? rawSubject
            : <String, dynamic>{};

    final String subjectLabel =
        subject['label']
                ?.toString() ??
            'Unknown';

    if (!success) {
      final String message =
          response['message']
                  ?.toString() ??
              'GreenGuard could not complete the scan.';

      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.all(
          22,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(
            24,
          ),
          border: Border.all(
            color: Colors.redAccent
                .withValues(
              alpha: 0.35,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons
                      .error_outline_rounded,
                  color:
                      Colors.redAccent,
                  size: 30,
                ),
                SizedBox(
                  width: 10,
                ),
                Text(
                  'Scan Failed',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.w900,
                    color: Color(
                      0xFF1E2A1F,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    if (!diagnosisAvailable) {
      final String message =
          response['message']
                  ?.toString() ??
              'No lettuce diagnosis is available.';

      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.all(
          22,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(
            24,
          ),
          border: Border.all(
            color: Colors.grey
                .withValues(
              alpha: 0.25,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons
                      .center_focus_weak_rounded,
                  color: Colors.teal,
                  size: 30,
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: Text(
                    'Detected: $subjectLabel',
                    style:
                        const TextStyle(
                      fontSize: 20,
                      fontWeight:
                          FontWeight
                              .w900,
                      color: Color(
                        0xFF1E2A1F,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            const Text(
              'No health result was saved because GreenGuard could not confirm lettuce in the photo.',
              style: TextStyle(
                fontWeight:
                    FontWeight.w700,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    final dynamic rawResult =
        response['result'];

    final Map<String, dynamic>
        result =
        rawResult
                is Map<String, dynamic>
            ? rawResult
            : <String, dynamic>{};

    final String diseaseName =
        _normalizeDiseaseName(
      (
        result['display_name'] ??
            result['class_name'] ??
            'Unknown Result'
      ).toString(),
    );

    final double confidencePercent =
        result['confidence_percent']
                is num
            ? (
                result[
                        'confidence_percent']
                    as num
              ).toDouble()
            : _readDoubleValue(
                  result[
                      'confidence'],
                ) *
                100.0;

    final String pathogen =
        _pathogenForDisease(
      diseaseName,
    );

    final Color color =
        _resultColor(
      diseaseName,
    );

    final bool databaseSaved =
        response['database_saved'] ==
            true;

    final String? databaseError =
        response['database_error']
            ?.toString();

    final dynamic rawEnhancement =
        response['enhancement'];

    final Map<String, dynamic>
        enhancement =
        rawEnhancement
                is Map<String, dynamic>
            ? rawEnhancement
            : <String, dynamic>{};

    final List<dynamic> operations =
        enhancement['operations']
                is List
            ? enhancement[
                    'operations']
                as List<dynamic>
            : <dynamic>[];

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(
        24,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          26,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.28,
          ),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration:
                    BoxDecoration(
                  color:
                      color.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius:
                      BorderRadius
                          .circular(
                    16,
                  ),
                ),
                child: Icon(
                  diseaseName
                              .toLowerCase() ==
                          'healthy'
                      ? Icons
                          .verified_rounded
                      : Icons
                          .health_and_safety_rounded,
                  color: color,
                  size: 30,
                ),
              ),
              const SizedBox(
                width: 14,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    const Text(
                      'Lettuce Health Result',
                      style:
                          TextStyle(
                        fontSize: 13,
                        fontWeight:
                            FontWeight
                                .w800,
                        color:
                            Colors.grey,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      diseaseName,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight:
                            FontWeight
                                .w900,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 20,
          ),
          Text(
            'Pathogen: $pathogen',
            style: const TextStyle(
              fontSize: 16,
              fontWeight:
                  FontWeight.w800,
              color: Color(
                0xFF1E2A1F,
              ),
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          Text(
            'Confidence: ${confidencePercent.toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 20,
              fontWeight:
                  FontWeight.w900,
              color: Color(
                0xFF1E2A1F,
              ),
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          Text(
            'Detected: $subjectLabel',
            style: const TextStyle(
              fontSize: 15,
              fontWeight:
                  FontWeight.w700,
              color: Colors.grey,
            ),
          ),
          if (operations.isNotEmpty) ...[
            const SizedBox(
              height: 14,
            ),
            const Text(
              'Photo Improvement: Complete',
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    FontWeight.w700,
                color: Color(
                  0xFF2F6B3B,
                ),
              ),
            ),
          ],
          const SizedBox(
            height: 18,
          ),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets
                    .symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration:
                BoxDecoration(
              color: databaseSaved
                  ? const Color(
                      0xFFEAF7EC,
                    )
                  : const Color(
                      0xFFFFF4E5,
                    ),
              borderRadius:
                  BorderRadius
                      .circular(
                14,
              ),
            ),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Icon(
                  databaseSaved
                      ? Icons
                          .cloud_done_rounded
                      : Icons
                          .cloud_off_rounded,
                  color: databaseSaved
                      ? const Color(
                          0xFF2F6B3B,
                        )
                      : Colors
                          .orangeAccent,
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: Text(
                    databaseSaved
                        ? 'Saved to Health Logs.'
                        : databaseError ==
                                null
                            ? 'Health result is ready, but it was not saved to Health Logs.'
                            : 'Diagnosis is available, but database save failed: $databaseError',
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight
                              .w700,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(
    String title,
  ) {
    return Align(
      alignment:
          Alignment.centerLeft,
      child: Padding(
        padding:
            const EdgeInsets.only(
          top: 10,
          bottom: 8,
        ),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight:
                FontWeight.w900,
            color:
                Color(0xFF1E2A1F),
          ),
        ),
      ),
    );
  }

  Widget _settingsSlider({
    required String title,
    required int value,
    required ValueChanged<int>
        localUpdate,
    required ValueChanged<int>
        saveValue,
  }) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight.w700,
                ),
              ),
            ),
            Text(
              value > 0
                  ? '+$value'
                  : '$value',
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w900,
                color:
                    Color(0xFF2F6B3B),
              ),
            ),
          ],
        ),
        Slider(
          value:
              value.toDouble(),
          min: -2,
          max: 2,
          divisions: 4,
          activeColor:
              const Color(
            0xFF2F6B3B,
          ),
          onChanged:
              _settingsBusy
                  ? null
                  : (double value) {
                      localUpdate(
                        value.round(),
                      );
                    },
          onChangeEnd:
              _settingsBusy
                  ? null
                  : (double value) {
                      saveValue(
                        value.round(),
                      );
                    },
        ),
      ],
    );
  }

  Widget _settingsSwitch({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool>
        onChanged,
  }) {
    return SwitchListTile(
      contentPadding:
          EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style: const TextStyle(
          fontWeight:
              FontWeight.w800,
        ),
      ),
      subtitle:
          subtitle == null
              ? null
              : Text(
                  subtitle,
                ),
      value: value,
      activeThumbColor:
          const Color(
        0xFF2F6B3B,
      ),
      onChanged:
          _settingsBusy
              ? null
              : onChanged,
    );
  }

  // ============================================================
  // CAMERA SETTINGS CARD
  // ============================================================

  Widget _buildCameraSettingsCard() {
    final EspCamSettings?
        settings =
        _cameraSettings;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          22,
        ),
      ),
      child: ExpansionTile(
        leading: const Icon(
          Icons.tune_rounded,
          color:
              Color(0xFF2F6B3B),
        ),
        title: const Text(
          'Camera Settings',
          style: TextStyle(
            fontWeight:
                FontWeight.w900,
          ),
        ),
        subtitle:
            settings == null
                ? const Text(
                    'Loading settings...',
                  )
                : Text(
                    '${settings.preset.toUpperCase()} • '
                    '${settings.xclkMHz} MHz • '
                    '${settings.previewResolution}',
                  ),
        childrenPadding:
            const EdgeInsets.fromLTRB(
          18,
          0,
          18,
          20,
        ),
        children: [
          if (settings == null)
            const Padding(
              padding:
                  EdgeInsets.all(
                20,
              ),
              child:
                  CircularProgressIndicator(),
            )
          else ...[
            _sectionTitle(
              'Performance',
            ),

            Container(
              padding:
                  const EdgeInsets.all(
                14,
              ),
              decoration:
                  BoxDecoration(
                color:
                    const Color(
                  0xFFF3F8F3,
                ),
                borderRadius:
                    BorderRadius.circular(
                  16,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            Text(
                              'XCLK MHz',
                              style:
                                  TextStyle(
                                fontWeight:
                                    FontWeight
                                        .w900,
                              ),
                            ),
                            SizedBox(
                              height: 3,
                            ),
                            Text(
                              'Camera clock frequency',
                              style:
                                  TextStyle(
                                fontSize:
                                    12,
                                color:
                                    Colors
                                        .grey,
                              ),
                            ),
                          ],
                        ),
                      ),

                      IconButton(
                        onPressed:
                            _settingsBusy ||
                                    settings.xclkMHz <=
                                        20
                                ? null
                                : () =>
                                    _changeXclk(
                                      -1,
                                    ),
                        icon:
                            const Icon(
                          Icons
                              .remove_circle_outline_rounded,
                        ),
                      ),

                      Container(
                        width: 78,
                        alignment:
                            Alignment
                                .center,
                        padding:
                            const EdgeInsets
                                .symmetric(
                          vertical: 10,
                        ),
                        decoration:
                            BoxDecoration(
                          color:
                              Colors
                                  .white,
                          borderRadius:
                              BorderRadius
                                  .circular(
                            12,
                          ),
                          border:
                              Border.all(
                            color:
                                const Color(
                              0xFFB7D9B9,
                            ),
                          ),
                        ),
                        child: Text(
                          '${settings.xclkMHz} MHz',
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight
                                    .w900,
                            color:
                                Color(
                              0xFF2F6B3B,
                            ),
                          ),
                        ),
                      ),

                      IconButton(
                        onPressed:
                            _settingsBusy ||
                                    settings.xclkMHz >=
                                        28
                                ? null
                                : () =>
                                    _changeXclk(
                                      1,
                                    ),
                        icon:
                            const Icon(
                          Icons
                              .add_circle_outline_rounded,
                        ),
                      ),
                    ],
                  ),

                  const Divider(),

                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Live Resolution',
                          style:
                              TextStyle(
                            fontWeight:
                                FontWeight
                                    .w800,
                          ),
                        ),
                      ),
                      Text(
                        settings
                            .previewResolution,
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight
                                  .w900,
                          color:
                              Color(
                            0xFF2F6B3B,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Still Capture',
                          style:
                              TextStyle(
                            fontWeight:
                                FontWeight
                                    .w800,
                          ),
                        ),
                      ),
                      Text(
                        settings
                            .captureResolution,
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight
                                  .w900,
                          color:
                              Color(
                            0xFF2F6B3B,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 14,
            ),

            _sectionTitle(
              'Preset',
            ),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label:
                      const Text(
                    'Stable',
                  ),
                  selected:
                      settings.preset ==
                          'stable',
                  onSelected:
                      _settingsBusy
                          ? null
                          : (_) =>
                              _setPreset(
                                'stable',
                              ),
                ),
                ChoiceChip(
                  label:
                      const Text(
                    'Fast',
                  ),
                  selected:
                      settings.preset ==
                          'fast',
                  onSelected:
                      _settingsBusy
                          ? null
                          : (_) =>
                              _setPreset(
                                'fast',
                              ),
                ),
                ChoiceChip(
                  label:
                      const Text(
                    'Balanced',
                  ),
                  selected:
                      settings.preset ==
                          'balanced',
                  onSelected:
                      _settingsBusy
                          ? null
                          : (_) =>
                              _setPreset(
                                'balanced',
                              ),
                ),
                ChoiceChip(
                  label:
                      const Text(
                    'Best',
                  ),
                  selected:
                      settings.preset ==
                          'best',
                  onSelected:
                      _settingsBusy
                          ? null
                          : (_) =>
                              _setPreset(
                                'best',
                              ),
                ),
              ],
            ),

            const Divider(
              height: 30,
            ),

            _sectionTitle(
              'Image',
            ),

            _settingsSlider(
              title:
                  'Brightness',
              value:
                  settings.brightness,
              localUpdate:
                  (int value) {
                setState(() {
                  _cameraSettings =
                      settings.copyWith(
                    brightness:
                        value,
                  );
                });
              },
              saveValue:
                  _saveBrightness,
            ),

            _settingsSlider(
              title:
                  'Contrast',
              value:
                  settings.contrast,
              localUpdate:
                  (int value) {
                setState(() {
                  _cameraSettings =
                      settings.copyWith(
                    contrast:
                        value,
                  );
                });
              },
              saveValue:
                  _saveContrast,
            ),

            _settingsSlider(
              title:
                  'Saturation',
              value:
                  settings.saturation,
              localUpdate:
                  (int value) {
                setState(() {
                  _cameraSettings =
                      settings.copyWith(
                    saturation:
                        value,
                  );
                });
              },
              saveValue:
                  _saveSaturation,
            ),

            const SizedBox(
              height: 8,
            ),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Special Effect',
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight
                              .w800,
                    ),
                  ),
                ),

                DropdownButton<int>(
                  value:
                      settings
                          .specialEffect,
                  onChanged:
                      _settingsBusy
                          ? null
                          : (
                              int?
                                  value,
                            ) {
                              if (value !=
                                  null) {
                                _setSpecialEffect(
                                  value,
                                );
                              }
                            },
                  items:
                      const [
                    DropdownMenuItem(
                      value: 0,
                      child: Text(
                        'None',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child: Text(
                        'Negative',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 2,
                      child: Text(
                        'Grayscale',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 3,
                      child: Text(
                        'Red Tint',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 4,
                      child: Text(
                        'Green Tint',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 5,
                      child: Text(
                        'Blue Tint',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 6,
                      child: Text(
                        'Sepia',
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const Divider(
              height: 30,
            ),

            _sectionTitle(
              'White Balance',
            ),

            _settingsSwitch(
              title: 'AWB',
              subtitle:
                  'Automatic white balance',
              value:
                  settings.awb,
              onChanged:
                  _setAwb,
            ),

            _settingsSwitch(
              title:
                  'AWB Gain',
              value:
                  settings.awbGain,
              onChanged:
                  _setAwbGain,
            ),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'WB Mode',
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight
                              .w800,
                    ),
                  ),
                ),

                DropdownButton<int>(
                  value:
                      settings.wbMode,
                  onChanged:
                      _settingsBusy
                          ? null
                          : (
                              int?
                                  value,
                            ) {
                              if (value !=
                                  null) {
                                _setWbMode(
                                  value,
                                );
                              }
                            },
                  items:
                      const [
                    DropdownMenuItem(
                      value: 0,
                      child: Text(
                        'Auto',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child: Text(
                        'Sunny',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 2,
                      child: Text(
                        'Cloudy',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 3,
                      child: Text(
                        'Office',
                      ),
                    ),
                    DropdownMenuItem(
                      value: 4,
                      child: Text(
                        'Home',
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const Divider(
              height: 30,
            ),

            _sectionTitle(
              'Exposure',
            ),

            _settingsSwitch(
              title:
                  'AEC Sensor',
              value:
                  settings.aec,
              onChanged:
                  _setAec,
            ),

            _settingsSwitch(
              title:
                  'AEC DSP',
              value:
                  settings.aec2,
              onChanged:
                  _setAec2,
            ),

            _settingsSlider(
              title:
                  'AE Level',
              value:
                  settings.aeLevel,
              localUpdate:
                  (int value) {
                setState(() {
                  _cameraSettings =
                      settings.copyWith(
                    aeLevel:
                        value,
                  );
                });
              },
              saveValue:
                  _saveAeLevel,
            ),

            const Divider(
              height: 30,
            ),

            _sectionTitle(
              'Gain',
            ),

            _settingsSwitch(
              title: 'AGC',
              subtitle:
                  'Automatic gain control',
              value:
                  settings.agc,
              onChanged:
                  _setAgc,
            ),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Gain Ceiling',
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight
                              .w800,
                    ),
                  ),
                ),

                DropdownButton<int>(
                  value:
                      settings
                          .gainCeiling,
                  onChanged:
                      _settingsBusy
                          ? null
                          : (
                              int?
                                  value,
                            ) {
                              if (value !=
                                  null) {
                                _setGainCeiling(
                                  value,
                                );
                              }
                            },
                  items:
                      const [
                    DropdownMenuItem(
                      value: 0,
                      child:
                          Text('2x'),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child:
                          Text('4x'),
                    ),
                    DropdownMenuItem(
                      value: 2,
                      child:
                          Text('8x'),
                    ),
                    DropdownMenuItem(
                      value: 3,
                      child:
                          Text('16x'),
                    ),
                    DropdownMenuItem(
                      value: 4,
                      child:
                          Text('32x'),
                    ),
                    DropdownMenuItem(
                      value: 5,
                      child:
                          Text('64x'),
                    ),
                    DropdownMenuItem(
                      value: 6,
                      child:
                          Text('128x'),
                    ),
                  ],
                ),
              ],
            ),

            const Divider(
              height: 30,
            ),

            _sectionTitle(
              'Sensor Processing',
            ),

            _settingsSwitch(
              title:
                  'BPC',
              subtitle:
                  'Black pixel correction',
              value:
                  settings.bpc,
              onChanged:
                  _setBpc,
            ),

            _settingsSwitch(
              title:
                  'WPC',
              subtitle:
                  'White pixel correction',
              value:
                  settings.wpc,
              onChanged:
                  _setWpc,
            ),

            _settingsSwitch(
              title:
                  'Raw GMA',
              value:
                  settings.rawGma,
              onChanged:
                  _setRawGma,
            ),

            _settingsSwitch(
              title:
                  'Lens Correction',
              value:
                  settings
                      .lensCorrection,
              onChanged:
                  _setLensCorrection,
            ),

            _settingsSwitch(
              title: 'DCW',
              value:
                  settings.dcw,
              onChanged:
                  _setDcw,
            ),

            const Divider(
              height: 30,
            ),

            _sectionTitle(
              'Flash Level',
            ),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final String level
                    in <String>[
                  'off',
                  'low',
                  'medium',
                  'high',
                  'max',
                ])
                  ChoiceChip(
                    label: Text(
                      level ==
                              'off'
                          ? 'Off'
                          : level[0]
                                  .toUpperCase() +
                              level.substring(
                                1,
                              ),
                    ),
                    selected:
                        settings.flashLevel ==
                            level,
                    onSelected:
                        _settingsBusy
                            ? null
                            : (_) =>
                                _setFlashLevel(
                                  level,
                                ),
                  ),
              ],
            ),

            const Divider(
              height: 30,
            ),

            _sectionTitle(
              'Orientation',
            ),

            _settingsSwitch(
              title: 'Mirror',
              value:
                  settings.hMirror,
              onChanged:
                  _setMirror,
            ),

            _settingsSwitch(
              title:
                  'Vertical Flip',
              value:
                  settings.vFlip,
              onChanged:
                  _setVerticalFlip,
            ),

            const Divider(
              height: 30,
            ),

            _sectionTitle(
              'Diagnostic',
            ),

            _settingsSwitch(
              title:
                  'Color Bar',
              subtitle:
                  'Sensor test pattern',
              value:
                  settings.colorBar,
              onChanged:
                  _setColorBar,
            ),

            const SizedBox(
              height: 12,
            ),

            SizedBox(
              width:
                  double.infinity,
              child:
                  OutlinedButton.icon(
                onPressed:
                    _settingsBusy
                        ? null
                        : _resetCameraSettings,
                icon:
                    const Icon(
                  Icons
                      .restart_alt_rounded,
                ),
                label:
                    const Text(
                  'Reset Recommended',
                ),
              ),
            ),

            if (_settingsBusy) ...[
              const SizedBox(
                height: 16,
              ),
              const LinearProgressIndicator(),
            ],
          ],
        ],
      ),
    );
  }

  // ============================================================
  // CAMERA BOX
  // ============================================================

  Widget _cameraBox() {
    if (_isCapturing) {
      return const Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color:
                  Color(0xFF2F6B3B),
            ),
            SizedBox(
              height: 20,
            ),
            Text(
              'Capturing high-quality image...',
              style: TextStyle(
                fontSize: 17,
                fontWeight:
                    FontWeight.w700,
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
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration:
                  BoxDecoration(
                color:
                    Colors.black
                        .withValues(
                  alpha: 0.65,
                ),
                borderRadius:
                    BorderRadius.circular(
                  18,
                ),
              ),
              child:
                  const Text(
                'CAPTURED',
                style: TextStyle(
                  color:
                      Colors.white,
                  fontWeight:
                      FontWeight
                          .w900,
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
              fit:
                  BoxFit.contain,
              gaplessPlayback:
                  true,
              filterQuality:
                  FilterQuality.low,
            )
          else
            Center(
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment
                        .center,
                children: [
                  const CircularProgressIndicator(
                    color:
                        Color(
                      0xFF2F6B3B,
                    ),
                  ),
                  const SizedBox(
                    height: 14,
                  ),
                  Text(
                    _streamConnecting
                        ? 'Starting live stream...'
                        : 'Waiting for live video...',
                    style:
                        const TextStyle(
                      fontSize:
                          16,
                      fontWeight:
                          FontWeight
                              .w700,
                      color:
                          Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

          if (_cameraSettings
                  ?.flashEnabled ==
              true)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal:
                      10,
                  vertical:
                      7,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      Colors.amber,
                  borderRadius:
                      BorderRadius
                          .circular(
                    18,
                  ),
                ),
                child: Row(
                  mainAxisSize:
                      MainAxisSize
                          .min,
                  children: [
                    const Icon(
                      Icons
                          .flash_on_rounded,
                      color:
                          Colors.white,
                      size: 18,
                    ),
                    const SizedBox(
                      width: 5,
                    ),
                    Text(
                      _cameraSettings!
                          .flashLevel
                          .toUpperCase(),
                      style:
                          const TextStyle(
                        color:
                            Colors
                                .white,
                        fontWeight:
                            FontWeight
                                .w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration:
                  BoxDecoration(
                color:
                    const Color(
                  0xFF2F6B3B,
                ).withValues(
                  alpha: 0.90,
                ),
                borderRadius:
                    BorderRadius.circular(
                  18,
                ),
              ),
              child:
                  const Text(
                'LIVE',
                style: TextStyle(
                  color:
                      Colors.white,
                  fontWeight:
                      FontWeight
                          .w900,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          if (_isSearching)
            const SizedBox(
              width: 42,
              height: 42,
              child:
                  CircularProgressIndicator(
                color:
                    Color(
                  0xFF2F6B3B,
                ),
              ),
            )
          else
            const Icon(
              Icons
                  .camera_alt_rounded,
              size: 80,
              color:
                  Colors.grey,
            ),

          const SizedBox(
            height: 18,
          ),

          Text(
            _isSearching
                ? 'Searching for camera...'
                : 'Camera Offline',
            style:
                const TextStyle(
              fontSize: 19,
              fontWeight:
                  FontWeight.w800,
              color:
                  Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GREEN GUARD PIPELINE CARD
  // ============================================================

  Widget _buildPipelineCard() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(
        18,
      ),
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          22,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
         const Row(
  crossAxisAlignment:
      CrossAxisAlignment.start,
  children: [
    Icon(
      Icons.auto_awesome_rounded,
      color: Color(
        0xFF2F6B3B,
      ),
    ),

    SizedBox(
      width: 8,
    ),

    Expanded(
      child: Text(
        'How GreenGuard Checks Your Photo',
        softWrap: true,
        style: TextStyle(
          fontSize: 18,
          fontWeight:
              FontWeight.w900,
          height: 1.2,
        ),
      ),
    ),
  ],
),

          const SizedBox(
            height: 14,
          ),

          const Text(
            'After you choose Use Photo:',
            style:
                TextStyle(
              fontWeight:
                  FontWeight.w700,
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          const Text(
            '1. Improve Photo\n'
            '2. Check Plant\n'
            '3. Check Lettuce Health',
            style:
                TextStyle(
              color:
                  Color(
                0xFF2F6B3B,
              ),
              fontWeight:
                  FontWeight.w900,
              height: 1.5,
            ),
          ),

          const SizedBox(
            height: 16,
          ),

          const Text(
            'What GreenGuard Sees',
            style:
                TextStyle(
              fontWeight:
                  FontWeight.w900,
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                _subjectTypes.map(
              (
                Map<String, dynamic>
                    subject,
              ) {
                return _badge(
                  subject['name']
                      as String,
                  subject['color']
                      as Color,
                );
              },
            ).toList(),
          ),

          const SizedBox(
            height: 18,
          ),

          const Text(
            'Possible Health Results',
            style:
                TextStyle(
              fontWeight:
                  FontWeight.w900,
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                _supportedDiseases
                    .map(
              (
                Map<String, dynamic>
                    disease,
              ) {
                return _badge(
                  disease['name']
                      as String,
                  disease['color']
                      as Color,
                );
              },
            ).toList(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PHOTO ACTIONS
  // ============================================================

  Widget _buildPhotoActions() {
    if (_capturedImage == null) {
      return SizedBox(
        width: double.infinity,
        height: 68,
        child:
            ElevatedButton.icon(
          onPressed:
              !_cameraConnected ||
                      _isCapturing ||
                      _isProcessing
                  ? null
                  : _takePhoto,
          icon: _isCapturing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color:
                        Colors.white,
                  ),
                )
              : const Icon(
                  Icons
                      .camera_alt_rounded,
                  size: 28,
                ),
          label: Text(
            _isCapturing
                ? 'Capturing...'
                : 'Take Photo',
            style:
                const TextStyle(
              fontSize: 19,
              fontWeight:
                  FontWeight.w900,
            ),
          ),
          style:
              ElevatedButton.styleFrom(
            backgroundColor:
                const Color(
              0xFF5DBB63,
            ),
            foregroundColor:
                Colors.white,
            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius
                      .circular(
                22,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child:
              OutlinedButton.icon(
            onPressed:
                _isProcessing
                    ? null
                    : _retakePhoto,
            icon: const Icon(
              Icons
                  .refresh_rounded,
            ),
            label:
                const Text(
              'Retake',
              style: TextStyle(
                fontWeight:
                    FontWeight
                        .w900,
              ),
            ),
            style:
                OutlinedButton
                    .styleFrom(
              minimumSize:
                  const Size(
                0,
                62,
              ),
            ),
          ),
        ),
        const SizedBox(
          width: 12,
        ),
        Expanded(
          child:
              ElevatedButton.icon(
            onPressed:
                _isProcessing ||
                        _scanSaved
                    ? null
                    : _usePhoto,
            icon: _isProcessing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child:
                        CircularProgressIndicator(
                      strokeWidth:
                          2.5,
                      color:
                          Colors.white,
                    ),
                  )
                : Icon(
                    _scanSaved
                        ? Icons
                            .cloud_done_rounded
                        : Icons
                            .check_circle_rounded,
                  ),
            label: Text(
              _isProcessing
                  ? 'Analyzing...'
                  : _scanSaved
                      ? 'Saved'
                      : 'Use Photo',
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight
                        .w900,
              ),
            ),
            style:
                ElevatedButton
                    .styleFrom(
              minimumSize:
                  const Size(
                0,
                62,
              ),
              backgroundColor:
                  const Color(
                0xFF2F6B3B,
              ),
              foregroundColor:
                  Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SCREEN
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final bool soilConnected =
        !_soilLoading &&
        _sensorData['connected'] == true;

    final String soilValue =
        _soilLoading
            ? 'Loading...'
            : (_sensorData['soil_value']
                    ?.toString() ??
                '--%');

    final String soilStatus =
        _soilLoading
            ? 'CONNECTING'
            : (_sensorData['soil_status']
                    ?.toString()
                    .toUpperCase() ??
                'OFFLINE');

    final String soilConnection =
        _soilLoading
            ? 'CONNECTING'
            : soilConnected
                ? 'CONNECTED'
                : 'OFFLINE';

    final String soilMeaning =
        _soilMeaning(
      soilStatus,
    );

    final Color soilColor =
        _soilStatusColor(
      soilStatus,
    );

    return Scaffold(
      backgroundColor:
          const Color(
        0xFFF6FBF7,
      ),
      appBar: AppBar(
        backgroundColor:
            const Color(
          0xFFF6FBF7,
        ),
        elevation: 0,
        centerTitle: true,
        iconTheme:
            const IconThemeData(
          color:
              Color(
            0xFF1E2A1F,
          ),
        ),
        title: const Text(
          'Lettuce Health Scan',
          style: TextStyle(
            fontWeight:
                FontWeight.w900,
            fontSize: 21,
            color:
                Color(
              0xFF1E2A1F,
            ),
          ),
        ),
      ),

      body:
          SingleChildScrollView(
        padding:
            const EdgeInsets.all(
          22,
        ),
        child: Column(
          children: [
            Container(
              height: 320,
              width:
                  double.infinity,
              clipBehavior:
                  Clip.antiAlias,
              decoration:
                  BoxDecoration(
                color:
                    Colors.white,
                borderRadius:
                    BorderRadius
                        .circular(
                  28,
                ),
                border:
                    Border.all(
                  color:
                      const Color(
                    0xFFB7D9B9,
                  ),
                  width: 2,
                ),
              ),
              child:
                  _cameraBox(),
            ),

            const SizedBox(
              height: 18,
            ),

            Container(
              width:
                  double.infinity,
              padding:
                  const EdgeInsets.all(
                18,
              ),
              decoration:
                  BoxDecoration(
                color:
                    Colors.white,
                borderRadius:
                    BorderRadius
                        .circular(
                  22,
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _cameraConnected
                            ? Icons
                                .check_circle
                            : Icons
                                .wifi_tethering,
                        color:
                            _cameraConnected
                                ? Colors
                                    .green
                                : Colors
                                    .orange,
                      ),

                      const SizedBox(
                        width: 10,
                      ),

                      Expanded(
                        child: Text(
                          _cameraConnected
                              ? 'Camera Connected'
                              : 'ESP32-CAM Setup',
                          style:
                              const TextStyle(
                            fontSize:
                                18,
                            fontWeight:
                                FontWeight
                                    .w900,
                          ),
                        ),
                      ),

                      if (_cameraSettings !=
                          null)
                        Text(
                          '${_cameraSettings!.xclkMHz} MHz',
                          style:
                              const TextStyle(
                            color:
                                Color(
                              0xFF2F6B3B,
                            ),
                            fontWeight:
                                FontWeight
                                    .w900,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(
                    height: 10,
                  ),

                  Text(
                    _cameraStatus,
                    style:
                        const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),

                  if (!_cameraConnected) ...[
                    const SizedBox(
                      height: 14,
                    ),
                    const Text(
                      '1. Turn ON your phone hotspot\n'
                      '2. Open GreenGuard\n'
                      '3. Power the ESP32-CAM\n'
                      '4. Wait for automatic connection',
                      style:
                          TextStyle(
                        fontSize:
                            14,
                        height:
                            1.6,
                      ),
                    ),
                  ],

                  const SizedBox(
                    height: 16,
                  ),

                  SizedBox(
                    width:
                        double.infinity,
                    child:
                        OutlinedButton.icon(
                      onPressed:
                          _searchAgain,
                      icon:
                          const Icon(
                        Icons
                            .refresh_rounded,
                      ),
                      label: Text(
                        _cameraConnected
                            ? 'Reconnect'
                            : 'Search Again',
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_cameraConnected) ...[
              const SizedBox(
                height: 16,
              ),
              _buildCameraSettingsCard(),
            ],

            const SizedBox(
              height: 20,
            ),

            _buildPhotoActions(),

            if (_scanResponse != null) ...[
              const SizedBox(
                height: 22,
              ),
              _buildScanResultCard(),
            ],

            const SizedBox(
              height: 22,
            ),

            _buildPipelineCard(),

            const SizedBox(
              height: 38,
            ),

            const Text(
              'Farm Status',
              style: TextStyle(
                fontSize: 24,
                fontWeight:
                    FontWeight.w900,
                color:
                    Color(
                  0xFF1E2A1F,
                ),
              ),
            ),

            const SizedBox(
              height: 16,
            ),

            Container(
              width:
                  double.infinity,
              padding:
                  const EdgeInsets.all(
                24,
              ),
              decoration:
                  BoxDecoration(
                color:
                    Colors.white,
                borderRadius:
                    BorderRadius
                        .circular(
                  24,
                ),
              ),
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  const Text(
                    'Monitoring',
                    style:
                        TextStyle(
                      fontSize: 22,
                      fontWeight:
                          FontWeight
                              .w900,
                      color:
                          Color(
                        0xFF2F6B3B,
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 18,
                  ),

                  Row(
                    children: [
                      Icon(
                        soilConnected
                            ? Icons
                                .check_circle_rounded
                            : _soilLoading
                                ? Icons
                                    .sync_rounded
                                : Icons
                                    .error_outline_rounded,
                        color:
                            soilConnected
                                ? const Color(
                                    0xFF2F6B3B,
                                  )
                                : _soilLoading
                                    ? Colors.orange
                                    : Colors.grey,
                        size: 26,
                      ),

                      const SizedBox(
                        width: 10,
                      ),

                      Expanded(
                        child: Text(
                          'Soil Sensor: $soilConnection',
                          style:
                              TextStyle(
                            fontSize: 17,
                            fontWeight:
                                FontWeight
                                    .w900,
                            color:
                                soilConnected
                                    ? const Color(
                                        0xFF2F6B3B,
                                      )
                                    : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 18,
                  ),

                  const Text(
                    'Temperature: 24.5°C',
                    style:
                        TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight
                              .bold,
                    ),
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  Text(
                    'Soil Moisture: $soilValue',
                    style:
                        const TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight
                              .bold,
                    ),
                  ),

                  const SizedBox(
                    height: 8,
                  ),

                  Row(
                    children: [
                      const Text(
                        'Condition: ',
                        style:
                            TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight
                                  .bold,
                        ),
                      ),

                      Text(
                        soilStatus,
                        style:
                            TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight
                                  .w900,
                          color:
                              soilColor,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 18,
                  ),

                  Container(
                    width:
                        double.infinity,
                    padding:
                        const EdgeInsets.all(
                      16,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          soilColor.withValues(
                        alpha: 0.08,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        16,
                      ),
                      border:
                          Border.all(
                        color:
                            soilColor.withValues(
                          alpha: 0.20,
                        ),
                      ),
                    ),
                    child:
                        Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        const Text(
                          'What does this mean?',
                          style:
                              TextStyle(
                            fontSize: 15,
                            fontWeight:
                                FontWeight
                                    .w900,
                            color:
                                Color(
                              0xFF1E2A1F,
                            ),
                          ),
                        ),

                        const SizedBox(
                          height: 6,
                        ),

                        Text(
                          soilMeaning,
                          style:
                              const TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            fontWeight:
                                FontWeight
                                    .w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 16,
            ),

            SizedBox(
              width:
                  double.infinity,
              height: 64,
              child:
                  ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const HealthLogsScreen(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons
                      .history_rounded,
                ),
                label:
                    const Text(
                  'View All Health Logs',
                ),
                style:
                    ElevatedButton
                        .styleFrom(
                  backgroundColor:
                      const Color(
                    0xFF2F6B3B,
                  ),
                  foregroundColor:
                      Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
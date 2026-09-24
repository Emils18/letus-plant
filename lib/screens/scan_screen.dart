import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  String _cameraStatus =
      'Waiting for GreenGuard-CAM-01...';

  // ============================================================
  // CURRENT SCAN SESSION
  // ============================================================

  final List<Map<String, dynamic>>
      _sessionScans = [];

  String? _sessionId;

  late DateTime _sessionStartedAt;

  static const String _scanImageBucket =
      'diagnostic-images';

  // ============================================================
  // SUBJECTS / DISEASES
  // ============================================================

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
      'color': const Color(0xFF2F6B3B),
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

  // ============================================================
  // START
  // ============================================================

  @override
  void initState() {
    super.initState();

    _sessionStartedAt =
        DateTime.now();

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

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _soilTimer?.cancel();

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

    super.dispose();
  }

  // ============================================================
  // SOIL SENSOR
  // ============================================================

  void _startSoilMonitoring() {
    unawaited(
      _loadSoilData(),
    );

    _soilTimer =
        Timer.periodic(
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

    final bool connected =
        data['connected'] == true;

    final bool newlyConnected =
        connected &&
        !_soilWasConnected;

    setState(() {
      _sensorData = data;
      _soilLoading = false;
      _soilWasConnected = connected;
    });

    if (newlyConnected) {
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
              Color(0xFF2F6B3B),
          duration:
              Duration(seconds: 3),
        ),
      );
    }
  }

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

    // Automatically use the camera settings we selected:
    //
    // Preset: BEST
    // Clock: 28 MHz
    //
    // Farmers do not need to adjust camera settings manually.

    unawaited(
      _prepareBestCamera(),
    );
  }

  Future<void> _prepareBestCamera() async {
    await _stopPreview();

    final settings =
        await _espCamService
            .updateSettings(
      preset: 'best',
      xclkMHz: 28,
    );

    if (!mounted) return;

    if (settings == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Camera connected, but recommended settings could not be applied.',
          ),
        ),
      );
    }

    await Future<void>.delayed(
      const Duration(
        milliseconds: 180,
      ),
    );

    if (mounted &&
        _cameraConnected &&
        _capturedImage == null) {
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

      _cameraStatus =
          'Searching for GreenGuard-CAM-01...';
    });

    await _initializeCamera();
  }

  // ============================================================
  // CAMERA PREVIEW
  // ============================================================

  Future<void> _stopPreview() async {
    if (_mjpegSubscription != null) {
      await _mjpegSubscription!
          .cancel();

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
      (
        Uint8List frame,
      ) {
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
      onError: (
        Object error,
      ) {
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
      _scanCompleted = false;
      _scanAddedToSession = false;
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

  // ============================================================
  // SAVE SCAN PHOTO
  // ============================================================

  Future<String?> _uploadScanPhoto(
    Uint8List imageBytes,
  ) async {
    final SupabaseClient supabase =
        Supabase.instance.client;

    final user =
        supabase.auth.currentUser;

    if (user == null ||
        _sessionId == null) {
      return null;
    }

    final int scanNumber =
        _sessionScans.length + 1;

    // Example:
    //
    // user-id/
    //   session-id/
    //     lettuce_001.jpg
    //     lettuce_002.jpg
    //
    // Upsert allows the same photo slot to be retried without
    // creating duplicate files.

    final String fileName =
        'lettuce_${scanNumber.toString().padLeft(3, '0')}.jpg';

    final String path =
        '${user.id}/${_sessionId!}/$fileName';

    try {
      await supabase.storage
          .from(
            _scanImageBucket,
          )
          .uploadBinary(
            path,
            imageBytes,
            fileOptions:
                const FileOptions(
              contentType:
                  'image/jpeg',
              upsert: true,
            ),
          );

      return supabase.storage
          .from(
            _scanImageBucket,
          )
          .getPublicUrl(
            path,
          );
    } catch (e) {
      debugPrint(
        'Scan photo upload failed: $e',
      );

      return null;
    }
  }

  // ============================================================
  // USE PHOTO / AI DIAGNOSIS
  // ============================================================

  Future<void> _usePhoto() async {
    final Uint8List? image =
        _capturedImage;

    if (image == null ||
        image.isEmpty ||
        _isProcessing ||
        _scanCompleted) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _scanResponse = null;
    });

    // ==========================================================
    // RUN GREENGUARD AI
    // ==========================================================

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
    String? imageUrl;

    // ==========================================================
    // VALID LETTUCE DIAGNOSIS
    // ==========================================================

    if (success &&
        diagnosisAvailable) {
      // ========================================================
      // CREATE REAL SUPABASE SCAN SESSION
      // ========================================================
      //
      // This only happens once:
      // when the first valid lettuce is diagnosed.
      //
      // All following lettuce scans use the same UUID.
      //
      // ========================================================

      if (_sessionId == null) {
        try {
          _sessionId =
              await _monitoringService
                  .createScanSession();

          _sessionStartedAt =
              DateTime.now();
        } catch (e) {
          if (!mounted) return;

          setState(() {
            _isProcessing = false;
            _scanResponse =
                finalResponse;
          });

          ScaffoldMessenger.of(context)
              .showSnackBar(
            SnackBar(
              content: Text(
                'Unable to start scan session: $e',
              ),
              backgroundColor:
                  Colors.redAccent,
            ),
          );

          return;
        }
      }

      final dynamic rawResult =
          response['result'];

      if (rawResult
          is Map<String, dynamic>) {
        // ======================================================
        // DISEASE NAME
        // ======================================================

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

        // ======================================================
        // CONFIDENCE
        // ======================================================

        final double confidence =
            _readDoubleValue(
          rawResult['confidence'],
        );

        // ======================================================
        // SAVE PHOTO FIRST
        // ======================================================

        imageUrl =
            await _uploadScanPhoto(
          image,
        );

        // Every accepted lettuce scan must have its photo.
        //
        // If the photo does not save, we DO NOT count the
        // lettuce yet.

        if (imageUrl == null) {
          if (!mounted) return;

          finalResponse = {
            ...response,
            'database_saved':
                false,
            'database_error':
                'The lettuce photo could not be saved.',
          };

          setState(() {
            _isProcessing = false;
            _scanResponse =
                finalResponse;

            _scanSaved = false;
            _scanCompleted = false;
          });

          ScaffoldMessenger.of(context)
              .showSnackBar(
            const SnackBar(
              content: Text(
                'The lettuce photo could not be saved. Please tap Use Photo again.',
              ),
              backgroundColor:
                  Colors.redAccent,
            ),
          );

          return;
        }

        // ======================================================
        // SAVE DIAGNOSTIC LOG
        // ======================================================

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

          // Saved lettuce photo.
          imageUrl:
              imageUrl,

          // REAL SUPABASE SESSION UUID.
          scanSessionId:
              _sessionId,
        );

        if (!mounted) return;

        saved =
            saveResult.success;

        saveError =
            saveResult.error;

        // ======================================================
        // ADD TO CURRENT SESSION
        // ======================================================
        //
        // Only count the lettuce when:
        //
        // 1. AI diagnosis succeeded
        // 2. Photo was saved
        // 3. Diagnostic log was saved
        //
        // ======================================================

        if (saved &&
            !_scanAddedToSession) {
          _sessionScans.add(
            <String, dynamic>{
              'scan_session_id':
                  _sessionId,
              'disease_name':
                  diseaseName,
              'confidence':
                  confidence,
              'image_bytes':
                  Uint8List.fromList(
                image,
              ),
              'image_url':
                  imageUrl,
              'database_saved':
                  true,
              'captured_at':
                  DateTime.now()
                      .toIso8601String(),
            },
          );

          _scanAddedToSession = true;
        }

        finalResponse = {
          ...response,

          'database_saved':
              saved,

          'database_error':
              saveError,

          'image_url':
              imageUrl,

          'scan_session_id':
              _sessionId,

          'session_scan_number':
              _sessionScans.length,
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

      // Scan Next only becomes available when this lettuce
      // was successfully stored.
      _scanCompleted = saved;
    });

    // ==========================================================
    // MESSAGE
    // ==========================================================

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
          'Lettuce #${_sessionScans.length} saved. You can scan the next lettuce.';
    } else {
      message =
          'The diagnosis is ready, but it was not saved'
          '${saveError == null ? '. Please tap Use Photo again.' : ': $saveError'}';
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          message,
        ),
        backgroundColor:
            saved
                ? const Color(
                    0xFF2F6B3B,
                  )
                : Colors.redAccent,
      ),
    );
  }

  // ============================================================
  // SCAN NEXT LETTUCE
  // ============================================================

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

  // ============================================================
  // DONE SCANNING
  // ============================================================

  Future<void> _finishScanning() async {
    if (_sessionScans.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Scan at least one lettuce before finishing the session.',
          ),
        ),
      );

      return;
    }

    final String? sessionId =
        _sessionId;

    if (sessionId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'The scan session was not created. Please try again.',
          ),
          backgroundColor:
              Colors.redAccent,
        ),
      );

      return;
    }

    await _stopPreview();

    if (!mounted) return;

    // ==========================================================
    // COUNT RESULTS
    // ==========================================================

    int healthyCount = 0;
    int downyCount = 0;
    int powderyCount = 0;
    int septoriaCount = 0;

    double healthyConfidenceTotal =
        0.0;

    double downyConfidenceTotal =
        0.0;

    double powderyConfidenceTotal =
        0.0;

    double septoriaConfidenceTotal =
        0.0;

    for (final Map<String, dynamic>
        scan in _sessionScans) {
      final String disease =
          (
            scan['disease_name'] ??
                ''
          )
              .toString()
              .toLowerCase()
              .replaceAll(
                '_',
                ' ',
              )
              .trim();

      double confidence =
          _readDoubleValue(
        scan['confidence'],
      );

      // Store confidence averages in 0.0 - 1.0 format.

      if (confidence > 1.0) {
        confidence =
            confidence / 100.0;
      }

      if (disease == 'healthy') {
        healthyCount++;

        healthyConfidenceTotal +=
            confidence;
      } else if (disease ==
          'downy mildew') {
        downyCount++;

        downyConfidenceTotal +=
            confidence;
      } else if (disease ==
          'powdery mildew') {
        powderyCount++;

        powderyConfidenceTotal +=
            confidence;
      } else if (disease ==
              'septoria blight' ||
          disease ==
              'septoria leaf spot') {
        septoriaCount++;

        septoriaConfidenceTotal +=
            confidence;
      }
    }

    // ==========================================================
    // AVERAGE CONFIDENCE
    // ==========================================================

    final double healthyAverage =
        healthyCount == 0
            ? 0.0
            : healthyConfidenceTotal /
                healthyCount;

    final double downyAverage =
        downyCount == 0
            ? 0.0
            : downyConfidenceTotal /
                downyCount;

    final double powderyAverage =
        powderyCount == 0
            ? 0.0
            : powderyConfidenceTotal /
                powderyCount;

    final double septoriaAverage =
        septoriaCount == 0
            ? 0.0
            : septoriaConfidenceTotal /
                septoriaCount;

    // ==========================================================
    // SAVE FINAL REPORT TO SUPABASE
    // ==========================================================

    try {
      await _monitoringService
          .completeScanSession(
        sessionId:
            sessionId,

        totalScanned:
            _sessionScans.length,

        healthyCount:
            healthyCount,

        downyCount:
            downyCount,

        powderyCount:
            powderyCount,

        septoriaCount:
            septoriaCount,

        healthyAverageConfidence:
            healthyAverage,

        downyAverageConfidence:
            downyAverage,

        powderyAverageConfidence:
            powderyAverage,

        septoriaAverageConfidence:
            septoriaAverage,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'The final report could not be saved: $e',
          ),
          backgroundColor:
              Colors.redAccent,
        ),
      );

      return;
    }

    if (!mounted) return;

    final DateTime completedAt =
        DateTime.now();

    setState(() {
      _sessionFinished = true;
    });

    // ==========================================================
    // SHOW FINAL REPORT
    // ==========================================================

    final bool? startNewSession =
        await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ScanSessionReportScreen(
          scans:
              List<Map<String, dynamic>>
                  .from(
            _sessionScans,
          ),
          startedAt:
              _sessionStartedAt,
          completedAt:
              completedAt,
        ),
      ),
    );

    if (!mounted) return;

    if (startNewSession == true) {
      await _startNewSession();
    }
  }

  // ============================================================
  // START NEW SESSION
  // ============================================================

  Future<void> _startNewSession() async {
    setState(() {
      _sessionScans.clear();

      _sessionId = null;

      _sessionStartedAt =
          DateTime.now();

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

  // ============================================================
  // SAFE NUMBER CONVERSION
  // ============================================================

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

  // ============================================================
  // DISEASE NAME
  // ============================================================

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

  // ============================================================
  // PATHOGEN
  // ============================================================

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

    if (normalized == 'healthy') {
      return 'None detected';
    }

    return 'Not available';
  }

  // ============================================================
  // SIMPLE DESCRIPTION FOR FARMERS / ELDERLY USERS
  // ============================================================

  String _descriptionForDisease(
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

    if (normalized == 'healthy') {
      return 'No visible signs of disease were found. '
          'The lettuce looks healthy based on this scan.';
    }

    if (normalized ==
        'downy mildew') {
      return 'Causes yellow spots on the leaves and may form '
          'mold underneath the leaf.';
    }

    if (normalized ==
        'powdery mildew') {
      return 'Looks like white powder on the leaves and can '
          'spread across the plant.';
    }

    if (normalized ==
            'septoria blight' ||
        normalized ==
            'septoria leaf spot') {
      return 'Causes small brown or dark spots that can grow '
          'and damage the leaves.';
    }

    return 'GreenGuard completed the lettuce health scan.';
  }


String _pathogenDescriptionForDisease(
  String diseaseName,
) {
  final String normalized =
      diseaseName
          .toLowerCase()
          .replaceAll('_', ' ')
          .trim();

  if (normalized == 'healthy') {
    return 'No supported disease-causing pathogen was detected '
        'in this lettuce image.';
  }

  if (normalized == 'downy mildew') {
    return 'Bremia lactucae is a disease-causing microorganism '
        'that infects lettuce leaves. It grows well in cool, '
        'wet, and humid conditions.';
  }

  if (normalized == 'powdery mildew') {
    return 'Erysiphe cichoracearum is a fungus that grows on '
        'plant surfaces and can look like white powder on the leaves.';
  }

  if (normalized == 'septoria blight' ||
      normalized == 'septoria leaf spot') {
    return 'Septoria lactucae is a fungus that infects lettuce '
        'leaves and causes brown or dark leaf spots.';
  }

  return 'No pathogen information is available.';
}
  // ============================================================
  // RESULT COLOR
  // ============================================================

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

    if (normalized == 'healthy') {
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

  // ============================================================
  // SMALL BADGE
  // ============================================================

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
  // CAMERA VIEW
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
            SizedBox(height: 20),
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

    // ==========================================================
    // CAPTURED IMAGE
    // ==========================================================

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
                  const EdgeInsets
                      .symmetric(
                horizontal: 12,
                vertical: 7,
              ),
              decoration:
                  BoxDecoration(
                color: Colors.black
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
                  color: Colors.white,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // ==========================================================
    // LIVE CAMERA
    // ==========================================================

    if (_cameraConnected) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_liveFrame != null)
            Image.memory(
              _liveFrame!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality:
                  FilterQuality.low,
            )
          else
            Center(
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
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
                      fontSize: 16,
                      fontWeight:
                          FontWeight.w700,
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
              padding:
                  const EdgeInsets
                      .symmetric(
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
                  color: Colors.white,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // ==========================================================
    // CAMERA OFFLINE
    // ==========================================================

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
                    Color(0xFF2F6B3B),
              ),
            )
          else
            const Icon(
              Icons.camera_alt_rounded,
              size: 80,
              color: Colors.grey,
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
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // RESULT CARD
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

    final Map<String, dynamic> subject =
        rawSubject
                is Map<String, dynamic>
            ? rawSubject
            : <String, dynamic>{};

    final String subjectLabel =
        subject['label']
                ?.toString() ??
            'Unknown';

    // ==========================================================
    // FAILED SCAN
    // ==========================================================

    if (!success) {
      final String message =
          response['message']
                  ?.toString() ??
              'GreenGuard could not complete the scan.';

      return _simpleMessageCard(
        icon:
            Icons.error_outline_rounded,
        title:
            'Scan Failed',
        message:
            message,
        color:
            Colors.redAccent,
      );
    }

    // ==========================================================
    // NO LETTUCE DIAGNOSIS
    // ==========================================================

    if (!diagnosisAvailable) {
      final String message =
          response['message']
                  ?.toString() ??
              'No lettuce diagnosis is available.';

      return _simpleMessageCard(
        icon:
            Icons
                .center_focus_weak_rounded,
        title:
            'Detected: $subjectLabel',
        message:
            message,
        color:
            Colors.teal,
      );
    }

    final dynamic rawResult =
        response['result'];

    final Map<String, dynamic> result =
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
                  result['confidence'],
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
          // ====================================================
          // RESULT TITLE
          // ====================================================

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
                      BorderRadius.circular(
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            FontWeight.w800,
                        color: Colors.grey,
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
                            FontWeight.w900,
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

          // ====================================================
          // PATHOGEN
          // ====================================================

          Text(
            diseaseName
                        .toLowerCase() ==
                    'healthy'
                ? 'Pathogen: None detected'
                : 'Pathogen: $pathogen',
            style:
                const TextStyle(
              fontSize: 16,
              fontWeight:
                  FontWeight.w800,
              color:
                  Color(0xFF1E2A1F),
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          // ====================================================
          // CONFIDENCE
          // ====================================================

          Text(
            'Confidence: ${confidencePercent.toStringAsFixed(1)}%',
            style:
                const TextStyle(
              fontSize: 20,
              fontWeight:
                  FontWeight.w900,
              color:
                  Color(0xFF1E2A1F),
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          Text(
            'Detected: $subjectLabel',
            style:
                const TextStyle(
              fontSize: 15,
              fontWeight:
                  FontWeight.w700,
              color: Colors.grey,
            ),
          ),

          const SizedBox(
            height: 16,
          ),

          // ====================================================
          // SIMPLE ELDER-FRIENDLY DESCRIPTION
          // ====================================================

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
                  color.withValues(
                alpha: 0.07,
              ),
              borderRadius:
                  BorderRadius.circular(
                16,
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                const Text(
                  'What does this mean?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.w900,
                    color:
                        Color(
                      0xFF1E2A1F,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 7,
                ),

                Text(
                  _descriptionForDisease(
                    diseaseName,
                  ),
                  style:
                      const TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    fontWeight:
                        FontWeight.w600,
                    color:
                        Color(
                      0xFF465248,
                    ),
                  ),
                ),


const SizedBox(
  height: 16,
),

const Divider(),

const SizedBox(
  height: 12,
),

const Text(
  'What is this pathogen?',
  style: TextStyle(
    fontSize: 16,
    fontWeight:
        FontWeight.w900,
    color:
        Color(
      0xFF1E2A1F,
    ),
  ),
),

const SizedBox(
  height: 7,
),

Text(
  _pathogenDescriptionForDisease(
    diseaseName,
  ),
  style:
      const TextStyle(
    fontSize: 16,
    height: 1.5,
    fontWeight:
        FontWeight.w600,
    color:
        Color(
      0xFF465248,
    ),
  ),
),


              ],
            ),
          ),

          if (operations.isNotEmpty) ...[
            const SizedBox(
              height: 14,
            ),

            const Text(
              'Photo Improvement: Complete',
              style:
                  TextStyle(
                fontSize: 13,
                fontWeight:
                    FontWeight.w700,
                color:
                    Color(
                  0xFF2F6B3B,
                ),
              ),
            ),
          ],

          const SizedBox(
            height: 18,
          ),

          // ====================================================
          // DATABASE STATUS
          // ====================================================

          Container(
            width:
                double.infinity,
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
                  BorderRadius.circular(
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
                      : Colors.orange,
                ),

                const SizedBox(
                  width: 10,
                ),

                Expanded(
                  child: Text(
                    databaseSaved
                        ? 'Photo and health result saved.'
                        : databaseError ==
                                null
                            ? 'The result has not been saved yet.'
                            : 'Save failed: $databaseError',
                    style:
                        const TextStyle(
                      fontSize: 14,
                      fontWeight:
                          FontWeight.w700,
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

  Widget _simpleMessageCard({
    required IconData icon,
    required String title,
    required String message,
    required Color color,
  }) {
    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(
        22,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.white,
        borderRadius:
            BorderRadius.circular(
          24,
        ),
        border:
            Border.all(
          color:
              color.withValues(
            alpha: 0.30,
          ),
        ),
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 30,
              ),

              const SizedBox(
                width: 10,
              ),

              Expanded(
                child:
                    Text(
                  title,
                  style:
                      const TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.w900,
                    color:
                        Color(
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
            style:
                const TextStyle(
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GREEN GUARD PIPELINE
  // ============================================================

  Widget _buildPipelineCard() {
    return Container(
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
            BorderRadius.circular(
          22,
        ),
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment:
                CrossAxisAlignment
                    .start,
            children: [
              Icon(
                Icons
                    .auto_awesome_rounded,
                color:
                    Color(
                  0xFF2F6B3B,
                ),
              ),

              SizedBox(
                width: 8,
              ),

              Expanded(
                child: Text(
                  'How GreenGuard Checks Your Photo',
                  style:
                      TextStyle(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.w900,
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
                _subjectTypes
                    .map(
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
  // CURRENT SESSION STATUS
  // ============================================================

  Widget _buildSessionStatusCard() {
    final int total =
        _sessionScans.length;

    return Container(
      width:
          double.infinity,
      padding:
          const EdgeInsets.all(
        18,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xFFEAF4EB,
        ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
        border:
            Border.all(
          color:
              const Color(
            0xFFB7D9B9,
          ),
        ),
      ),
      child:
          Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration:
                BoxDecoration(
              color:
                  const Color(
                0xFF2F6B3B,
              ),
              borderRadius:
                  BorderRadius.circular(
                14,
              ),
            ),
            child:
                const Icon(
              Icons
                  .inventory_2_rounded,
              color:
                  Colors.white,
            ),
          ),

          const SizedBox(
            width: 13,
          ),

          Expanded(
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                const Text(
                  'Current Scan Session',
                  style:
                      TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.w900,
                    color:
                        Color(
                      0xFF1E2A1F,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 4,
                ),

                Text(
                  total == 0
                      ? 'No lettuce scanned yet.'
                      : '$total lettuce ${total == 1 ? 'has' : 'have'} been scanned.',
                  style:
                      const TextStyle(
                    fontSize: 14,
                    fontWeight:
                        FontWeight.w700,
                    color:
                        Color(
                      0xFF68736A,
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

  // ============================================================
  // PHOTO ACTION BUTTONS
  // ============================================================

  Widget _buildPhotoActions() {
    // ==========================================================
    // SESSION ALREADY FINISHED
    // ==========================================================

    if (_sessionFinished) {
      return SizedBox(
        width:
            double.infinity,
        height: 64,
        child:
            ElevatedButton.icon(
          onPressed:
              _startNewSession,
          icon:
              const Icon(
            Icons
                .restart_alt_rounded,
          ),
          label:
              const Text(
            'Start New Scan Session',
            style:
                TextStyle(
              fontWeight:
                  FontWeight.w900,
            ),
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
            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(
                20,
              ),
            ),
          ),
        ),
      );
    }

    // ==========================================================
    // CURRENT LETTUCE IS SAVED
    // ==========================================================

    if (_scanCompleted) {
      return Row(
        children: [
          Expanded(
            child:
                ElevatedButton.icon(
              onPressed:
                  _scanNextLettuce,
              icon:
                  const Icon(
                Icons
                    .add_a_photo_rounded,
              ),
              label:
                  const Text(
                'Scan Next Lettuce',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
              style:
                  ElevatedButton
                      .styleFrom(
                minimumSize:
                    const Size(
                  0,
                  64,
                ),
                backgroundColor:
                    const Color(
                  0xFF5DBB63,
                ),
                foregroundColor:
                    Colors.white,
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
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
                  _finishScanning,
              icon:
                  const Icon(
                Icons
                    .assessment_rounded,
              ),
              label:
                  const Text(
                'Done Scanning',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
              style:
                  ElevatedButton
                      .styleFrom(
                minimumSize:
                    const Size(
                  0,
                  64,
                ),
                backgroundColor:
                    const Color(
                  0xFF1E2A1F,
                ),
                foregroundColor:
                    Colors.white,
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // ==========================================================
    // NO PHOTO YET
    // ==========================================================

    if (_capturedImage == null) {
      return Column(
        children: [
          SizedBox(
            width:
                double.infinity,
            height: 68,
            child:
                ElevatedButton.icon(
              onPressed:
                  !_cameraConnected ||
                          _isCapturing ||
                          _isProcessing
                      ? null
                      : _takePhoto,
              icon:
                  _isCapturing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child:
                              CircularProgressIndicator(
                            strokeWidth:
                                2.5,
                            color:
                                Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons
                              .camera_alt_rounded,
                          size: 28,
                        ),
              label:
                  Text(
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
                  ElevatedButton
                      .styleFrom(
                backgroundColor:
                    const Color(
                  0xFF5DBB63,
                ),
                foregroundColor:
                    Colors.white,
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    22,
                  ),
                ),
              ),
            ),
          ),

          if (_sessionScans
              .isNotEmpty) ...[
            const SizedBox(
              height: 12,
            ),

            SizedBox(
              width:
                  double.infinity,
              height: 58,
              child:
                  OutlinedButton.icon(
                onPressed:
                    _finishScanning,
                icon:
                    const Icon(
                  Icons
                      .assessment_rounded,
                ),
                label:
                    const Text(
                  'Done Scanning',
                  style:
                      TextStyle(
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    // ==========================================================
    // PHOTO CAPTURED
    // ==========================================================

    return Row(
      children: [
        Expanded(
          child:
              OutlinedButton.icon(
            onPressed:
                _isProcessing
                    ? null
                    : _retakePhoto,
            icon:
                const Icon(
              Icons.refresh_rounded,
            ),
            label:
                const Text(
              'Retake',
              style:
                  TextStyle(
                fontWeight:
                    FontWeight.w900,
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
                        _scanCompleted
                    ? null
                    : _usePhoto,
            icon:
                _isProcessing
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
                    : const Icon(
                        Icons
                            .check_circle_rounded,
                      ),
            label:
                Text(
              _isProcessing
                  ? 'Analyzing...'
                  : 'Use Photo',
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w900,
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
  // MAIN SCREEN
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final bool soilConnected =
        !_soilLoading &&
        _sensorData['connected'] ==
            true;

    final String soilValue =
        _soilLoading
            ? 'Loading...'
            : (
                  _sensorData[
                          'soil_value'] ??
                      '--%'
                )
                .toString();

    final String soilStatus =
        _soilLoading
            ? 'CONNECTING'
            : (
                  _sensorData[
                          'soil_status'] ??
                      'OFFLINE'
                )
                .toString()
                .toUpperCase();

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
        title:
            const Text(
          'Lettuce Health Scan',
          style:
              TextStyle(
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
        child:
            Column(
          children: [
            // ==================================================
            // CAMERA
            // ==================================================

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
                    BorderRadius.circular(
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

            // ==================================================
            // CAMERA STATUS
            // ==================================================

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
                    BorderRadius.circular(
                  22,
                ),
              ),
              child:
                  Column(
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
                                ? Colors.green
                                : Colors.orange,
                      ),

                      const SizedBox(
                        width: 10,
                      ),

                      Expanded(
                        child:
                            Text(
                          _cameraConnected
                              ? 'Camera Connected'
                              : 'ESP32-CAM Setup',
                          style:
                              const TextStyle(
                            fontSize: 18,
                            fontWeight:
                                FontWeight.w900,
                          ),
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
                        fontSize: 14,
                        height: 1.6,
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
                      label:
                          Text(
                        _cameraConnected
                            ? 'Reconnect'
                            : 'Search Again',
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            // ==================================================
            // SESSION COUNT
            // ==================================================

            _buildSessionStatusCard(),

            const SizedBox(
              height: 16,
            ),

            // ==================================================
            // PHOTO BUTTONS
            // ==================================================

            _buildPhotoActions(),

            // ==================================================
            // AI RESULT
            // ==================================================

            if (_scanResponse !=
                null) ...[
              const SizedBox(
                height: 22,
              ),

              _buildScanResultCard(),
            ],

            const SizedBox(
              height: 22,
            ),

            // ==================================================
            // AI INFORMATION
            // ==================================================

            _buildPipelineCard(),

            const SizedBox(
              height: 38,
            ),

            // ==================================================
            // FARM STATUS
            // ==================================================

            const Text(
              'Farm Status',
              style:
                  TextStyle(
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
                    BorderRadius.circular(
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
                          FontWeight.w900,
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
                        child:
                            Text(
                          'Soil Sensor: $soilConnection',
                          style:
                              TextStyle(
                            fontSize: 17,
                            fontWeight:
                                FontWeight.w900,
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
                          FontWeight.bold,
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
                          FontWeight.bold,
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
                              FontWeight.bold,
                        ),
                      ),

                      Text(
                        soilStatus,
                        style:
                            TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight.w900,
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
                          soilColor
                              .withValues(
                        alpha: 0.08,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        16,
                      ),
                      border:
                          Border.all(
                        color:
                            soilColor
                                .withValues(
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
                                FontWeight.w900,
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
                                FontWeight.w600,
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

            // ==================================================
            // HEALTH LOGS
            // ==================================================

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
                icon:
                    const Icon(
                  Icons.history_rounded,
                ),
                label:
                    const Text(
                  'View All Health Logs',
                  style:
                      TextStyle(
                    fontWeight:
                        FontWeight.w900,
                  ),
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
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// FINAL SCAN SESSION REPORT SCREEN
// ============================================================


  class ScanSessionReportScreen
    extends StatelessWidget {
  const ScanSessionReportScreen({
    super.key,
    required this.scans,
    required this.startedAt,
    required this.completedAt,
  });

  final List<Map<String, dynamic>> scans;
  final DateTime startedAt;
  final DateTime completedAt;

  // ============================================================
  // NORMALIZE
  // ============================================================

  String _normalize(
    String value,
  ) {
    return value
        .toLowerCase()
        .replaceAll('_', ' ')
        .trim();
  }

  String _diseaseName(
    Map<String, dynamic> scan,
  ) {
    return (scan['disease_name'] ?? 'Unknown')
        .toString()
        .replaceAll('_', ' ')
        .trim();
  }

  // ============================================================
  // CONFIDENCE
  // ============================================================

  double _confidence(
    Map<String, dynamic> scan,
  ) {
    final dynamic raw =
        scan['confidence'];

    final double value =
        raw is num
            ? raw.toDouble()
            : double.tryParse(
                  raw?.toString() ?? '',
                ) ??
                0.0;

    return value > 1.0
        ? value / 100.0
        : value;
  }

  // ============================================================
  // DISEASE MATCH
  // ============================================================

  bool _matches(
    Map<String, dynamic> scan,
    String disease,
  ) {
    final String current =
        _normalize(
      _diseaseName(scan),
    );

    final String target =
        _normalize(disease);

    if (target == 'septoria blight') {
      return current == 'septoria blight' ||
          current == 'septoria leaf spot';
    }

    return current == target;
  }

  int _count(
    String disease,
  ) {
    return scans
        .where(
          (scan) => _matches(
            scan,
            disease,
          ),
        )
        .length;
  }

  // ============================================================
  // AVERAGE CONFIDENCE
  // ============================================================

  double _averageConfidence(
    String disease,
  ) {
    final List<Map<String, dynamic>>
        matching =
        scans
            .where(
              (scan) => _matches(
                scan,
                disease,
              ),
            )
            .toList();

    if (matching.isEmpty) {
      return 0.0;
    }

    double total = 0.0;

    for (final scan in matching) {
      total += _confidence(scan);
    }

    return total / matching.length;
  }

  double _percent(
    int count,
  ) {
    if (scans.isEmpty) {
      return 0.0;
    }

    return count / scans.length * 100;
  }

  // ============================================================
  // PATHOGEN NAME
  // ============================================================

  String _pathogen(
    String disease,
  ) {
    switch (disease) {
      case 'Healthy':
        return 'None detected';

      case 'Downy Mildew':
        return 'Bremia lactucae';

      case 'Powdery Mildew':
        return 'Erysiphe cichoracearum';

      case 'Septoria Blight':
        return 'Septoria lactucae';

      default:
        return 'Not available';
    }
  }

  // ============================================================
  // SIMPLE DISEASE DESCRIPTION
  // ============================================================

  String _description(
    String disease,
  ) {
    switch (disease) {
      case 'Healthy':
        return 'No visible signs of the supported diseases were found. '
            'The lettuce looks healthy based on this GreenGuard scan.';

      case 'Downy Mildew':
        return 'This disease can cause yellow or pale spots on the leaves '
            'and mold-like growth underneath.';

      case 'Powdery Mildew':
        return 'This disease usually looks like white powder on the leaves '
            'and can spread across the plant.';

      case 'Septoria Blight':
        return 'This disease causes small brown or dark spots that may grow '
            'and damage the lettuce leaves.';

      default:
        return 'GreenGuard completed the lettuce health scan.';
    }
  }

  // ============================================================
  // WHAT IS THE PATHOGEN?
  // ============================================================

  String _pathogenDescription(
    String disease,
  ) {
    switch (disease) {
      case 'Healthy':
        return 'No supported disease-causing pathogen was detected '
            'in this lettuce image.';

      case 'Downy Mildew':
        return 'Bremia lactucae is a disease-causing microorganism '
            'that infects lettuce leaves. It grows well in cool, '
            'wet, and humid conditions.';

      case 'Powdery Mildew':
        return 'Erysiphe cichoracearum is a fungus that grows on '
            'plant surfaces and can appear like white powder '
            'on the leaves.';

      case 'Septoria Blight':
        return 'Septoria lactucae is a fungus that infects lettuce '
            'leaves and causes brown or dark leaf spots.';

      default:
        return 'No pathogen information is available.';
    }
  }

  // ============================================================
  // COLOR
  // ============================================================

  Color _diseaseColor(
    String disease,
  ) {
    switch (disease) {
      case 'Healthy':
        return const Color(
          0xFF5DBB63,
        );

      case 'Downy Mildew':
        return Colors.redAccent;

      case 'Powdery Mildew':
        return Colors.orange;

      case 'Septoria Blight':
        return Colors.deepOrange;

      default:
        return Colors.grey;
    }
  }

  // ============================================================
  // SELLABLE
  // ============================================================

  bool _isHealthy(
    String disease,
  ) {
    return _normalize(disease) ==
        'healthy';
  }

  // ============================================================
  // DATE
  // ============================================================

  String _formatDateTime(
    DateTime value,
  ) {
    final DateTime local =
        value.toLocal();

    final String hour =
        local.hour
            .toString()
            .padLeft(
              2,
              '0',
            );

    final String minute =
        local.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '${local.month}/${local.day}/${local.year} '
        '$hour:$minute';
  }

  // ============================================================
  // FINAL REPORT
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final int total =
        scans.length;

    final int healthy =
        _count('Healthy');

    final int downy =
        _count('Downy Mildew');

    final int powdery =
        _count('Powdery Mildew');

    final int septoria =
        _count('Septoria Blight');

    final int notHealthy =
        downy +
        powdery +
        septoria;

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
        title:
            const Text(
          'Final Scan Report',
          style:
              TextStyle(
            fontSize: 21,
            fontWeight:
                FontWeight.w900,
            color:
                Color(
              0xFF1E2A1F,
            ),
          ),
        ),
      ),

      body: ListView(
        padding:
            const EdgeInsets.all(
          20,
        ),
        children: [
          // ====================================================
          // HEADER
          // ====================================================

          Container(
            width:
                double.infinity,
            padding:
                const EdgeInsets.all(
              24,
            ),
            decoration:
                BoxDecoration(
              gradient:
                  const LinearGradient(
                begin:
                    Alignment.topLeft,
                end:
                    Alignment.bottomRight,
                colors: [
                  Color(
                    0xFF1E2A1F,
                  ),
                  Color(
                    0xFF2F6B3B,
                  ),
                ],
              ),
              borderRadius:
                  BorderRadius.circular(
                28,
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.assessment_rounded,
                  size: 42,
                  color: Colors.white,
                ),

                const SizedBox(
                  height: 14,
                ),

                const Text(
                  'Lettuce Scan Summary',
                  style:
                      TextStyle(
                    fontSize: 25,
                    fontWeight:
                        FontWeight.w900,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(
                  height: 8,
                ),

                Text(
                  'Started: ${_formatDateTime(startedAt)}\n'
                  'Completed: ${_formatDateTime(completedAt)}',
                  style:
                      const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontWeight:
                        FontWeight.w600,
                    color:
                        Color(
                      0xFFDDE9DF,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: 20,
          ),

          // ====================================================
          // TOTAL
          // ====================================================

          _summaryCard(
            title:
                'Total Lettuce Scanned',
            value:
                '$total',
            subtitle:
                '100% of this scan session',
            icon:
                Icons.inventory_2_rounded,
            color:
                const Color(
              0xFF2F6B3B,
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          Row(
            children: [
              Expanded(
                child:
                    _summaryCard(
                  title:
                      'Healthy / Sellable',
                  value:
                      '$healthy',
                  subtitle:
                      '${_percent(healthy).toStringAsFixed(1)}%',
                  icon:
                      Icons
                          .check_circle_rounded,
                  color:
                      const Color(
                    0xFF5DBB63,
                  ),
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                child:
                    _summaryCard(
                  title:
                      'Not Healthy',
                  value:
                      '$notHealthy',
                  subtitle:
                      '${_percent(notHealthy).toStringAsFixed(1)}%',
                  icon:
                      Icons
                          .warning_amber_rounded,
                  color:
                      Colors.redAccent,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 28,
          ),

          // ====================================================
          // HEALTH BREAKDOWN
          // ====================================================

          const Text(
            'Health Breakdown',
            style:
                TextStyle(
              fontSize: 23,
              fontWeight:
                  FontWeight.w900,
              color:
                  Color(
                0xFF1E2A1F,
              ),
            ),
          ),

          const SizedBox(
            height: 6,
          ),

          const Text(
            'GreenGuard counted every successfully saved lettuce scan.',
            style:
                TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight:
                  FontWeight.w600,
            ),
          ),

          const SizedBox(
            height: 16,
          ),

          _diseaseCard(
            name: 'Healthy',
            count: healthy,
          ),

          _diseaseCard(
            name: 'Downy Mildew',
            count: downy,
          ),

          _diseaseCard(
            name: 'Powdery Mildew',
            count: powdery,
          ),

          _diseaseCard(
            name: 'Septoria Blight',
            count: septoria,
          ),

          const SizedBox(
            height: 20,
          ),

          // ====================================================
          // INDIVIDUAL CAPTURED LETTUCE
          // ====================================================

          const Text(
            'Captured Lettuce',
            style:
                TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.w900,
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
            '$total saved ${total == 1 ? 'capture' : 'captures'} in this report.',
            style:
                const TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight:
                  FontWeight.w600,
            ),
          ),

          const SizedBox(
            height: 14,
          ),

          ...scans.asMap().entries.map(
            (entry) {
              final int index =
                  entry.key;

              final Map<String, dynamic>
                  scan =
                  entry.value;

              return _lettuceScanCard(
                scan:
                    scan,
                number:
                    index + 1,
              );
            },
          ),

          const SizedBox(
            height: 12,
          ),

          // ====================================================
          // IMPORTANT NOTE
          // ====================================================

          Container(
            padding:
                const EdgeInsets.all(
              17,
            ),
            decoration:
                BoxDecoration(
              color:
                  const Color(
                0xFFEAF4EB,
              ),
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
            ),
            child:
                const Text(
              'Healthy / Sellable is an estimate based only on the '
              'lettuce diseases supported by GreenGuard. Other plant '
              'quality problems may still require visual inspection.',
              style:
                  TextStyle(
                fontSize: 14,
                height: 1.5,
                fontWeight:
                    FontWeight.w700,
                color:
                    Color(
                  0xFF2F6B3B,
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 24,
          ),

          // ====================================================
          // NEW SESSION
          // ====================================================

          SizedBox(
            height: 64,
            child:
                ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              icon:
                  const Icon(
                Icons.restart_alt_rounded,
              ),
              label:
                  const Text(
                'Start New Scan Session',
                style:
                    TextStyle(
                  fontSize: 17,
                  fontWeight:
                      FontWeight.w900,
                ),
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
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          // ====================================================
          // CANCEL / CLOSE REPORT
          // ====================================================

          SizedBox(
            height: 58,
            child:
                OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              icon:
                  const Icon(
                Icons.close_rounded,
              ),
              label:
                  const Text(
                'Cancel / Close Report',
                style:
                    TextStyle(
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
              style:
                  OutlinedButton.styleFrom(
                foregroundColor:
                    const Color(
                  0xFF1E2A1F,
                ),
                side:
                    const BorderSide(
                  color:
                      Color(
                    0xFF1E2A1F,
                  ),
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    18,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 20,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUMMARY CARD
  // ============================================================

  Widget _summaryCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      constraints:
          const BoxConstraints(
        minHeight: 150,
      ),
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
        border:
            Border.all(
          color:
              color.withValues(
            alpha: 0.18,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 31,
            color: color,
          ),

          const SizedBox(
            height: 9,
          ),

          Text(
            value,
            textAlign:
                TextAlign.center,
            style:
                const TextStyle(
              fontSize: 28,
              fontWeight:
                  FontWeight.w900,
              color:
                  Color(
                0xFF1E2A1F,
              ),
            ),
          ),

          const SizedBox(
            height: 4,
          ),

          Text(
            title,
            textAlign:
                TextAlign.center,
            style:
                const TextStyle(
              fontSize: 13,
              fontWeight:
                  FontWeight.w800,
              color:
                  Color(
                0xFF68736A,
              ),
            ),
          ),

          const SizedBox(
            height: 4,
          ),

          Text(
            subtitle,
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              fontSize: 13,
              fontWeight:
                  FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DISEASE CARD
  // ============================================================

  Widget _diseaseCard({
    required String name,
    required int count,
  }) {
    final Color color =
        _diseaseColor(
      name,
    );

    final double average =
        _averageConfidence(
      name,
    );

    return Container(
      width:
          double.infinity,
      margin:
          const EdgeInsets.only(
        bottom: 14,
      ),
      padding:
          const EdgeInsets.all(
        20,
      ),
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          23,
        ),
        border:
            Border.all(
          color:
              color.withValues(
            alpha: 0.18,
          ),
        ),
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration:
                    BoxDecoration(
                  color:
                      color.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    15,
                  ),
                ),
                child:
                    Icon(
                  name == 'Healthy'
                      ? Icons
                          .verified_rounded
                      : Icons
                          .warning_amber_rounded,
                  color: color,
                ),
              ),

              const SizedBox(
                width: 13,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style:
                          const TextStyle(
                        fontSize: 19,
                        fontWeight:
                            FontWeight.w900,
                        color:
                            Color(
                          0xFF1E2A1F,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 3,
                    ),

                    Text(
                      name == 'Healthy'
                          ? 'Pathogen: None detected'
                          : 'Pathogen: ${_pathogen(name)}',
                      style:
                          const TextStyle(
                        fontSize: 13,
                        fontStyle:
                            FontStyle.italic,
                        color:
                            Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          Row(
            children: [
              Expanded(
                child:
                    _metric(
                  'Count',
                  '$count',
                ),
              ),

              Expanded(
                child:
                    _metric(
                  'Percentage',
                  '${_percent(count).toStringAsFixed(1)}%',
                ),
              ),

              Expanded(
                child:
                    _metric(
                  'Avg. Confidence',
                  count == 0
                      ? 'N/A'
                      : '${(average * 100).toStringAsFixed(1)}%',
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          // ====================================================
          // WHAT DOES THIS MEAN?
          // ====================================================

          Container(
            width:
                double.infinity,
            padding:
                const EdgeInsets.all(
              14,
            ),
            decoration:
                BoxDecoration(
              color:
                  color.withValues(
                alpha: 0.06,
              ),
              borderRadius:
                  BorderRadius.circular(
                14,
              ),
            ),
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'What does this mean?',
                  style:
                      TextStyle(
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w900,
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
                  _description(
                    name,
                  ),
                  style:
                      const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    fontWeight:
                        FontWeight.w600,
                    color:
                        Color(
                      0xFF68736A,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                const Text(
                  'What is this pathogen?',
                  style:
                      TextStyle(
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w900,
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
                  _pathogenDescription(
                    name,
                  ),
                  style:
                      const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    fontWeight:
                        FontWeight.w600,
                    color:
                        Color(
                      0xFF68736A,
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

  // ============================================================
  // INDIVIDUAL LETTUCE CARD
  // ============================================================

  Widget _lettuceScanCard({
    required Map<String, dynamic> scan,
    required int number,
  }) {
    final String disease =
        _diseaseName(
      scan,
    );

    final double confidence =
        _confidence(
      scan,
    );

    final bool healthy =
        _isHealthy(
      disease,
    );

    final Color color =
        healthy
            ? const Color(
                0xFF5DBB63,
              )
            : _diseaseColor(
                disease,
              );

    final dynamic rawImage =
        scan['image_bytes'];

    final Uint8List? image =
        rawImage is Uint8List
            ? rawImage
            : null;

    return Container(
      width:
          double.infinity,
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      padding:
          const EdgeInsets.all(
        14,
      ),
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          20,
        ),
        border:
            Border.all(
          color:
              color.withValues(
            alpha: 0.20,
          ),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius:
                BorderRadius.circular(
              14,
            ),
            child:
                image == null
                    ? Container(
                        width: 88,
                        height: 88,
                        color:
                            const Color(
                          0xFFEAF4EB,
                        ),
                        child:
                            const Icon(
                          Icons.eco_rounded,
                          color:
                              Color(
                            0xFF2F6B3B,
                          ),
                          size: 40,
                        ),
                      )
                    : Image.memory(
                        image,
                        width: 88,
                        height: 88,
                        fit:
                            BoxFit.cover,
                      ),
          ),

          const SizedBox(
            width: 14,
          ),

          Expanded(
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Lettuce #$number',
                  style:
                      const TextStyle(
                    fontSize: 14,
                    fontWeight:
                        FontWeight.w800,
                    color:
                        Colors.grey,
                  ),
                ),

                const SizedBox(
                  height: 3,
                ),

                Text(
                  disease,
                  style:
                      TextStyle(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.w900,
                    color: color,
                  ),
                ),

                const SizedBox(
                  height: 4,
                ),

                Text(
                  'Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
                  style:
                      const TextStyle(
                    fontSize: 13,
                    fontWeight:
                        FontWeight.w700,
                    color:
                        Color(
                      0xFF68736A,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        color.withValues(
                      alpha: 0.10,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                  ),
                  child:
                      Text(
                    healthy
                        ? 'SELLABLE ESTIMATE'
                        : 'NOT HEALTHY',
                    style:
                        TextStyle(
                      fontSize: 11,
                      fontWeight:
                          FontWeight.w900,
                      color: color,
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

  // ============================================================
  // SMALL METRIC
  // ============================================================

  Widget _metric(
    String label,
    String value,
  ) {
    return Column(
      children: [
        Text(
          value,
          textAlign:
              TextAlign.center,
          style:
              const TextStyle(
            fontSize: 17,
            fontWeight:
                FontWeight.w900,
            color:
                Color(
              0xFF1E2A1F,
            ),
          ),
        ),

        const SizedBox(
          height: 3,
        ),

        Text(
          label,
          textAlign:
              TextAlign.center,
          style:
              const TextStyle(
            fontSize: 11,
            fontWeight:
                FontWeight.w700,
            color:
                Colors.grey,
          ),
        ),
      ],
    );
  }
}
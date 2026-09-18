import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ============================================================
// JSON HELPERS
// ============================================================

int _readInt(
  dynamic value,
  int fallback,
) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(
        value?.toString() ?? '',
      ) ??
      fallback;
}

bool _readBool(
  dynamic value,
  bool fallback,
) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final String text =
      value?.toString().toLowerCase() ?? '';

  if (text == 'true' ||
      text == '1' ||
      text == 'on') {
    return true;
  }

  if (text == 'false' ||
      text == '0' ||
      text == 'off') {
    return false;
  }

  return fallback;
}

// ============================================================
// ESP32-CAM DEVICE
// ============================================================

class EspCamDevice {
  final String deviceId;
  final String host;

  const EspCamDevice({
    required this.deviceId,
    required this.host,
  });
}

// ============================================================
// ESP32-CAM SETTINGS MODEL
// ============================================================

class EspCamSettings {
  final String preset;

  // Performance.
  final int xclkMHz;

  final String previewResolution;
  final String captureResolution;

  // Basic image.
  final int brightness;
  final int contrast;
  final int saturation;

  // Effects.
  final int specialEffect;

  // White balance.
  final bool awb;
  final bool awbGain;
  final int wbMode;

  // Exposure.
  final bool aec;
  final bool aec2;
  final int aeLevel;

  // Gain.
  final bool agc;
  final int gainCeiling;

  // Image processing.
  final bool bpc;
  final bool wpc;
  final bool rawGma;
  final bool lensCorrection;
  final bool dcw;

  // Diagnostic.
  final bool colorBar;

  // Flash.
  final String flashLevel;
  final int flashPwm;

  // Orientation.
  final bool hMirror;
  final bool vFlip;

  const EspCamSettings({
    required this.preset,
    required this.xclkMHz,
    required this.previewResolution,
    required this.captureResolution,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.specialEffect,
    required this.awb,
    required this.awbGain,
    required this.wbMode,
    required this.aec,
    required this.aec2,
    required this.aeLevel,
    required this.agc,
    required this.gainCeiling,
    required this.bpc,
    required this.wpc,
    required this.rawGma,
    required this.lensCorrection,
    required this.dcw,
    required this.colorBar,
    required this.flashLevel,
    required this.flashPwm,
    required this.hMirror,
    required this.vFlip,
  });

  bool get flashEnabled =>
      flashLevel != 'off' ||
      flashPwm > 0;

  factory EspCamSettings.fromJson(
    Map<String, dynamic> json,
  ) {
    return EspCamSettings(
      preset:
          json['preset']?.toString() ??
              'stable',

      xclkMHz:
          _readInt(
        json['xclk_mhz'],
        28,
      ),

      previewResolution:
          json['preview_resolution']
                  ?.toString() ??
              '480x320',

      captureResolution:
          json['capture_resolution']
                  ?.toString() ??
              '1600x1200',

      brightness:
          _readInt(
        json['brightness'],
        0,
      ),

      contrast:
          _readInt(
        json['contrast'],
        0,
      ),

      saturation:
          _readInt(
        json['saturation'],
        0,
      ),

      specialEffect:
          _readInt(
        json['special_effect'],
        0,
      ),

      awb:
          _readBool(
        json['awb'],
        true,
      ),

      awbGain:
          _readBool(
        json['awb_gain'],
        true,
      ),

      wbMode:
          _readInt(
        json['wb_mode'],
        0,
      ),

      aec:
          _readBool(
        json['aec'],
        true,
      ),

      aec2:
          _readBool(
        json['aec2'],
        false,
      ),

      aeLevel:
          _readInt(
        json['ae_level'],
        0,
      ),

      agc:
          _readBool(
        json['agc'],
        true,
      ),

      gainCeiling:
          _readInt(
        json['gain_ceiling'],
        2,
      ),

      bpc:
          _readBool(
        json['bpc'],
        true,
      ),

      wpc:
          _readBool(
        json['wpc'],
        true,
      ),

      rawGma:
          _readBool(
        json['raw_gma'],
        true,
      ),

      lensCorrection:
          _readBool(
        json['lens_correction'],
        true,
      ),

      dcw:
          _readBool(
        json['dcw'],
        true,
      ),

      colorBar:
          _readBool(
        json['color_bar'],
        false,
      ),

      flashLevel:
          json['flash_level']
                  ?.toString() ??
              'off',

      flashPwm:
          _readInt(
        json['flash_pwm'],
        0,
      ),

      hMirror:
          _readBool(
        json['hmirror'],
        false,
      ),

      vFlip:
          _readBool(
        json['vflip'],
        false,
      ),
    );
  }

  EspCamSettings copyWith({
    String? preset,
    int? xclkMHz,
    String? previewResolution,
    String? captureResolution,
    int? brightness,
    int? contrast,
    int? saturation,
    int? specialEffect,
    bool? awb,
    bool? awbGain,
    int? wbMode,
    bool? aec,
    bool? aec2,
    int? aeLevel,
    bool? agc,
    int? gainCeiling,
    bool? bpc,
    bool? wpc,
    bool? rawGma,
    bool? lensCorrection,
    bool? dcw,
    bool? colorBar,
    String? flashLevel,
    int? flashPwm,
    bool? hMirror,
    bool? vFlip,
  }) {
    return EspCamSettings(
      preset:
          preset ??
              this.preset,

      xclkMHz:
          xclkMHz ??
              this.xclkMHz,

      previewResolution:
          previewResolution ??
              this.previewResolution,

      captureResolution:
          captureResolution ??
              this.captureResolution,

      brightness:
          brightness ??
              this.brightness,

      contrast:
          contrast ??
              this.contrast,

      saturation:
          saturation ??
              this.saturation,

      specialEffect:
          specialEffect ??
              this.specialEffect,

      awb:
          awb ??
              this.awb,

      awbGain:
          awbGain ??
              this.awbGain,

      wbMode:
          wbMode ??
              this.wbMode,

      aec:
          aec ??
              this.aec,

      aec2:
          aec2 ??
              this.aec2,

      aeLevel:
          aeLevel ??
              this.aeLevel,

      agc:
          agc ??
              this.agc,

      gainCeiling:
          gainCeiling ??
              this.gainCeiling,

      bpc:
          bpc ??
              this.bpc,

      wpc:
          wpc ??
              this.wpc,

      rawGma:
          rawGma ??
              this.rawGma,

      lensCorrection:
          lensCorrection ??
              this.lensCorrection,

      dcw:
          dcw ??
              this.dcw,

      colorBar:
          colorBar ??
              this.colorBar,

      flashLevel:
          flashLevel ??
              this.flashLevel,

      flashPwm:
          flashPwm ??
              this.flashPwm,

      hMirror:
          hMirror ??
              this.hMirror,

      vFlip:
          vFlip ??
              this.vFlip,
    );
  }
}

// ============================================================
// ESP32-CAM SERVICE
// ============================================================

class EspCamService {
  EspCamService._();

  static final EspCamService _instance =
      EspCamService._();

  factory EspCamService() =>
      _instance;

  static const int discoveryPort =
      8765;

  // GreenGuard AI Flask server running on the laptop.
  // Change only this value if the laptop IPv4 address changes.
  static const String aiServerBaseUrl =
    'http://172.21.109.132:5000';

  HttpServer? _discoveryServer;

  http.Client? _streamClient;

  String? _cameraHost;

  String _deviceId =
      'GreenGuard-CAM-01';

  final StreamController<EspCamDevice>
      _cameraController =
      StreamController<EspCamDevice>
          .broadcast();

  Stream<EspCamDevice>
      get cameraEvents =>
          _cameraController.stream;

  bool get hasCamera =>
      _cameraHost != null;

  String? get cameraHost =>
      _cameraHost;

  // ============================================================
  // URLS
  // ============================================================

  String? get baseUrl {
    if (_cameraHost == null) {
      return null;
    }

    return 'http://$_cameraHost';
  }

  String? get statusUrl {
    final String? url =
        baseUrl;

    if (url == null) {
      return null;
    }

    return '$url/status';
  }

  String? get streamUrl {
    if (_cameraHost == null) {
      return null;
    }

    return 'http://$_cameraHost:81/stream';
  }

  String? get previewUrl {
    final String? url =
        baseUrl;

    if (url == null) {
      return null;
    }

    return '$url/preview';
  }

  String? get captureUrl {
    final String? url =
        baseUrl;

    if (url == null) {
      return null;
    }

    return '$url/capture';
  }

  String? get settingsUrl {
    final String? url =
        baseUrl;

    if (url == null) {
      return null;
    }

    return '$url/settings';
  }

  String? get flashUrl {
    final String? url =
        baseUrl;

    if (url == null) {
      return null;
    }

    return '$url/flash';
  }

  String? get resetSettingsUrl {
    final String? url =
        baseUrl;

    if (url == null) {
      return null;
    }

    return '$url/reset-settings';
  }

  // ============================================================
  // DISCOVERY SERVER
  // ============================================================

  Future<void>
      startDiscoveryServer() async {
    if (_discoveryServer != null) {
      return;
    }

    try {
      _discoveryServer =
          await HttpServer.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        shared: true,
      );

      debugPrint(
        'GreenGuard discovery server listening on port $discoveryPort',
      );

      _discoveryServer!.listen(
        _handleDiscoveryRequest,
        onError: (
          Object error,
        ) {
          debugPrint(
            'ESP32 discovery error: $error',
          );
        },
      );
    } catch (e) {
      debugPrint(
        'Unable to start discovery server: $e',
      );
    }
  }

  Future<void> _handleDiscoveryRequest(
    HttpRequest request,
  ) async {
    request.response.headers.set(
      'Access-Control-Allow-Origin',
      '*',
    );

    request.response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS',
    );

    request.response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type',
    );

    if (request.method == 'OPTIONS') {
      request.response.statusCode =
          HttpStatus.noContent;

      await request.response.close();

      return;
    }

    if (request.uri.path !=
            '/register' ||
        request.method !=
            'POST') {
      request.response.statusCode =
          HttpStatus.notFound;

      await request.response.close();

      return;
    }

    try {
      final String body =
          await utf8.decoder
              .bind(
                request,
              )
              .join();

      final dynamic decoded =
          jsonDecode(
        body,
      );

      String? announcedIp;
      String? announcedDevice;

      if (decoded
          is Map<String, dynamic>) {
        announcedIp =
            decoded['ip']
                ?.toString();

        announcedDevice =
            decoded['device']
                ?.toString();
      }

      final String remoteIp =
          request.connectionInfo
                  ?.remoteAddress
                  .address ??
              '';

      final String finalHost =
          announcedIp != null &&
                  announcedIp.isNotEmpty
              ? announcedIp
              : remoteIp;

      if (finalHost.isEmpty) {
        throw Exception(
          'Camera IP unavailable.',
        );
      }

      _cameraHost =
          finalHost;

      if (announcedDevice != null &&
          announcedDevice.isNotEmpty) {
        _deviceId =
            announcedDevice;
      }

      debugPrint(
        'Camera discovered: $_deviceId @ $_cameraHost',
      );

      _cameraController.add(
        EspCamDevice(
          deviceId:
              _deviceId,
          host:
              finalHost,
        ),
      );

      request.response.statusCode =
          HttpStatus.ok;

      request.response.headers
              .contentType =
          ContentType.json;

      request.response.write(
        jsonEncode({
          'accepted': true,
        }),
      );

      await request.response.close();
    } catch (e) {
      request.response.statusCode =
          HttpStatus.badRequest;

      await request.response.close();
    }
  }

  // ============================================================
  // CONNECTION
  // ============================================================

  Future<bool>
      checkConnection() async {
    if (_cameraHost != null) {
      if (await _checkHost(
        _cameraHost!,
      )) {
        return true;
      }
    }

    if (await _checkHost(
      'greenguard-cam.local',
    )) {
      _cameraHost =
          'greenguard-cam.local';

      return true;
    }

    return false;
  }

  Future<bool> _checkHost(
    String host,
  ) async {
    try {
      final Uri uri =
          Uri.parse(
        'http://$host/status'
        '?t=${DateTime.now().millisecondsSinceEpoch}',
      );

      final http.Response response =
          await http
              .get(
                uri,
              )
              .timeout(
                const Duration(
                  seconds: 3,
                ),
              );

      if (response.statusCode ==
          200) {
        _cameraHost = host;

        return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // GET CAMERA SETTINGS
  // ============================================================

  Future<EspCamSettings?>
      getCameraSettings() async {
    final String? url =
        settingsUrl;

    if (url == null) {
      return null;
    }

    return _getSettings(
      Uri.parse(
        '$url'
        '?t=${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
  }

  // ============================================================
  // UPDATE CAMERA SETTINGS
  // ============================================================

  Future<EspCamSettings?>
      updateSettings({
    String? preset,

    // Performance.
    int? xclkMHz,

    // Basic.
    int? brightness,
    int? contrast,
    int? saturation,

    // Effects.
    int? specialEffect,

    // White balance.
    bool? awb,
    bool? awbGain,
    int? wbMode,

    // Exposure.
    bool? aec,
    bool? aec2,
    int? aeLevel,

    // Gain.
    bool? agc,
    int? gainCeiling,

    // Processing.
    bool? bpc,
    bool? wpc,
    bool? rawGma,
    bool? lensCorrection,
    bool? dcw,

    // Diagnostic.
    bool? colorBar,

    // Orientation.
    bool? hMirror,
    bool? vFlip,
  }) async {
    final String? url =
        settingsUrl;

    if (url == null) {
      return null;
    }

    final Map<String, String>
        parameters = {
      't': DateTime.now()
          .millisecondsSinceEpoch
          .toString(),
    };

    if (preset != null) {
      parameters['preset'] =
          preset;
    }

    if (xclkMHz != null) {
      parameters['xclk'] =
          xclkMHz
              .clamp(
                20,
                28,
              )
              .toString();
    }

    if (brightness != null) {
      parameters['brightness'] =
          brightness
              .clamp(
                -2,
                2,
              )
              .toString();
    }

    if (contrast != null) {
      parameters['contrast'] =
          contrast
              .clamp(
                -2,
                2,
              )
              .toString();
    }

    if (saturation != null) {
      parameters['saturation'] =
          saturation
              .clamp(
                -2,
                2,
              )
              .toString();
    }

    if (specialEffect != null) {
      parameters['special_effect'] =
          specialEffect
              .clamp(
                0,
                6,
              )
              .toString();
    }

    if (awb != null) {
      parameters['awb'] =
          awb ? '1' : '0';
    }

    if (awbGain != null) {
      parameters['awb_gain'] =
          awbGain ? '1' : '0';
    }

    if (wbMode != null) {
      parameters['wb_mode'] =
          wbMode
              .clamp(
                0,
                4,
              )
              .toString();
    }

    if (aec != null) {
      parameters['aec'] =
          aec ? '1' : '0';
    }

    if (aec2 != null) {
      parameters['aec2'] =
          aec2 ? '1' : '0';
    }

    if (aeLevel != null) {
      parameters['ae_level'] =
          aeLevel
              .clamp(
                -2,
                2,
              )
              .toString();
    }

    if (agc != null) {
      parameters['agc'] =
          agc ? '1' : '0';
    }

    if (gainCeiling != null) {
      parameters['gain_ceiling'] =
          gainCeiling
              .clamp(
                0,
                6,
              )
              .toString();
    }

    if (bpc != null) {
      parameters['bpc'] =
          bpc ? '1' : '0';
    }

    if (wpc != null) {
      parameters['wpc'] =
          wpc ? '1' : '0';
    }

    if (rawGma != null) {
      parameters['raw_gma'] =
          rawGma ? '1' : '0';
    }

    if (lensCorrection != null) {
      parameters['lens_correction'] =
          lensCorrection
              ? '1'
              : '0';
    }

    if (dcw != null) {
      parameters['dcw'] =
          dcw ? '1' : '0';
    }

    if (colorBar != null) {
      parameters['color_bar'] =
          colorBar ? '1' : '0';
    }

    if (hMirror != null) {
      parameters['hmirror'] =
          hMirror ? '1' : '0';
    }

    if (vFlip != null) {
      parameters['vflip'] =
          vFlip ? '1' : '0';
    }

    final Uri uri =
        Uri.parse(
      url,
    ).replace(
      queryParameters:
          parameters,
    );

    return _getSettings(
      uri,
    );
  }

  // ============================================================
  // XCLK
  // ============================================================

  Future<EspCamSettings?>
      setXclkMHz(
    int mhz,
  ) {
    return updateSettings(
      xclkMHz:
          mhz.clamp(
        20,
        28,
      ),
    );
  }

  // ============================================================
  // FLASH LEVEL
  // ============================================================

  Future<EspCamSettings?>
      setFlashLevel(
    String level,
  ) async {
    final String? url =
        flashUrl;

    if (url == null) {
      return null;
    }

    final String safeLevel;

    switch (
        level.toLowerCase()) {
      case 'low':
      case 'medium':
      case 'high':
      case 'max':
        safeLevel =
            level.toLowerCase();
        break;

      default:
        safeLevel = 'off';
    }

    final Uri uri =
        Uri.parse(
      url,
    ).replace(
      queryParameters: {
        'level':
            safeLevel,
        't': DateTime.now()
            .millisecondsSinceEpoch
            .toString(),
      },
    );

    return _getSettings(
      uri,
    );
  }

  // ============================================================
  // RESET SETTINGS
  // ============================================================

  Future<EspCamSettings?>
      resetRecommendedSettings() async {
    final String? url =
        resetSettingsUrl;

    if (url == null) {
      return null;
    }

    return _getSettings(
      Uri.parse(
        '$url'
        '?t=${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
  }

  // ============================================================
  // SETTINGS HTTP HELPER
  // ============================================================

  Future<EspCamSettings?> _getSettings(
    Uri uri,
  ) async {
    try {
      final http.Response response =
          await http
              .get(
                uri,
              )
              .timeout(
                const Duration(
                  seconds: 6,
                ),
              );

      if (response.statusCode !=
          200) {
        debugPrint(
          'Camera settings HTTP ${response.statusCode}',
        );

        return null;
      }

      final dynamic decoded =
          jsonDecode(
        response.body,
      );

      if (decoded
          is! Map<String, dynamic>) {
        return null;
      }

      return EspCamSettings.fromJson(
        decoded,
      );
    } catch (e) {
      debugPrint(
        'Camera settings error: $e',
      );

      return null;
    }
  }

  // ============================================================
  // MJPEG JPEG MARKER
  // ============================================================

  int _findJpegMarker(
    List<int> data,
    int first,
    int second, [
    int start = 0,
  ]) {
    for (
      int i = start;
      i < data.length - 1;
      i++
    ) {
      if (data[i] == first &&
          data[i + 1] ==
              second) {
        return i;
      }
    }

    return -1;
  }

  // ============================================================
  // MJPEG LIVE STREAM
  // ============================================================

  Stream<Uint8List>
      mjpegStream() async* {
    final String? url =
        streamUrl;

    if (url == null) {
      return;
    }

    await stopMjpegStream();

    final http.Client client =
        http.Client();

    _streamClient =
        client;

    try {
      final http.Request request =
          http.Request(
        'GET',
        Uri.parse(
          '$url'
          '?t=${DateTime.now().millisecondsSinceEpoch}',
        ),
      );

      final http.StreamedResponse
          response =
          await client
              .send(
                request,
              )
              .timeout(
                const Duration(
                  seconds: 8,
                ),
              );

      if (response.statusCode !=
          200) {
        throw Exception(
          'MJPEG stream HTTP '
          '${response.statusCode}',
        );
      }

      final List<int> buffer =
          <int>[];

      await for (
        final List<int> chunk
            in response.stream
      ) {
        // Stop processing if this
        // client is no longer active.
        if (!identical(
          _streamClient,
          client,
        )) {
          break;
        }

        buffer.addAll(
          chunk,
        );

        while (true) {
          final int start =
              _findJpegMarker(
            buffer,
            0xFF,
            0xD8,
          );

          if (start < 0) {
            if (buffer.length >
                2 * 1024 * 1024) {
              buffer.clear();
            }

            break;
          }

          final int end =
              _findJpegMarker(
            buffer,
            0xFF,
            0xD9,
            start + 2,
          );

          if (end < 0) {
            if (start > 0) {
              buffer.removeRange(
                0,
                start,
              );
            }

            break;
          }

          final Uint8List frame =
              Uint8List.fromList(
            buffer.sublist(
              start,
              end + 2,
            ),
          );

          buffer.removeRange(
            0,
            end + 2,
          );

          yield frame;
        }
      }
    } catch (e) {
      debugPrint(
        'MJPEG stream ended: $e',
      );
    } finally {
      if (identical(
        _streamClient,
        client,
      )) {
        _streamClient =
            null;
      }

      client.close();
    }
  }

  // ============================================================
  // STOP MJPEG
  // ============================================================

  Future<void>
      stopMjpegStream() async {
    final http.Client? client =
        _streamClient;

    _streamClient =
        null;

    client?.close();

    await Future<void>.delayed(
      const Duration(
        milliseconds: 180,
      ),
    );
  }

  // ============================================================
  // STILL CAPTURE
  // ============================================================

  Future<Uint8List?>
      capturePhoto() async {
    final String? url =
        captureUrl;

    if (url == null) {
      return null;
    }

    try {
      final Uri uri =
          Uri.parse(
        '$url'
        '?t=${DateTime.now().millisecondsSinceEpoch}',
      );

      final http.Response response =
          await http
              .get(
                uri,
              )
              .timeout(
                const Duration(
                  seconds: 25,
                ),
              );

      if (response.statusCode ==
              200 &&
          response
              .bodyBytes
              .isNotEmpty) {
        return Uint8List.fromList(
          response.bodyBytes,
        );
      }

      debugPrint(
        'Capture HTTP ${response.statusCode}',
      );

      return null;
    } catch (e) {
      debugPrint(
        'Capture error: $e',
      );

      return null;
    }
  }

  // ============================================================
  // FORGET CAMERA
  // ============================================================


// ============================================================
// GREENGUARD AI SCAN
// ============================================================

  Future<Map<String, dynamic>> scanPhotoWithAi(
    Uint8List imageBytes,
  ) async {
    final Uri uri = Uri.parse(
      '$aiServerBaseUrl/scan',
    );

    try {
      final http.MultipartRequest request =
          http.MultipartRequest(
        'POST',
        uri,
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename:
              'greenguard_capture.jpg',
        ),
      );

      final http.StreamedResponse
          streamedResponse =
          await request.send().timeout(
                const Duration(
                  seconds: 45,
                ),
              );

      final http.Response response =
          await http.Response.fromStream(
        streamedResponse,
      );

      dynamic decoded;

      try {
        decoded = jsonDecode(
          response.body,
        );
      } catch (_) {
        return {
          'success': false,
          'http_status':
              response.statusCode,
          'message':
              'GreenGuard AI server returned an invalid response.',
          'raw_response':
              response.body,
        };
      }

      if (decoded
          is Map<String, dynamic>) {
        return {
          ...decoded,
          'http_status':
              response.statusCode,
        };
      }

      return {
        'success': false,
        'http_status':
            response.statusCode,
        'message':
            'Invalid AI server response.',
      };
    } catch (e) {
      debugPrint(
        'GreenGuard AI scan error: $e',
      );

      return {
        'success': false,
        'network_error': true,
        'message':
            'Unable to connect to GreenGuard AI server at $aiServerBaseUrl.',
      };
    }
  }


  void forgetCamera() {
    unawaited(
      stopMjpegStream(),
    );

    _cameraHost =
        null;
  }
}
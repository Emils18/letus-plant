import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/inav_diagnostics_service.dart';
import 'scan_screen.dart';
import 'mission_procedure_screen.dart';

const Color _green = Color(0xFF2F6B3B);
const Color _ink = Color(0xFF1E2A1F);
const Color _page = Color(0xFFF6FBF7);

/// Scan Disease mode chooser. Both scan modes reuse the existing camera,
/// diagnosis, persistence, and session workflow.
class ScanModeScreen extends StatelessWidget {
  const ScanModeScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Scan Disease'),
        backgroundColor: _page,
        foregroundColor: _ink,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Choose a scanning mode',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use the existing camera and diagnosis workflow in either mode.',
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 20),
          _ModeCard(
            icon: Icons.map_rounded,
            title: 'Automatic Flight Plan',
            subtitle:
                'Plan and save waypoints on a live satellite map. Flight launch remains locked until hardware command paths are verified.',
            onTap: () => _open(context, const MissionProcedureScreen()),
          ),
          const SizedBox(height: 14),
          _ModeCard(
            icon: Icons.flight_takeoff_rounded,
            title: 'Drone Manual Scan',
            subtitle:
                'Choose when to capture an image using the existing camera and AI workflow.',
            onTap: () => _open(context, const ScanScreen(droneManual: true)),
          ),
          const SizedBox(height: 14),
          _ModeCard(
            icon: Icons.route_rounded,
            title: 'Drone readiness check',
            subtitle:
                'Read live flight-controller diagnostics before planning a route.',
            onTap: () => _open(context, const DroneReadinessScreen()),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFEAF7EC),
                foregroundColor: _green,
                child: Icon(icon),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _green),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Readiness { waiting, checking, ready, blocked, skipped, notVerified }

/// Sequential, read-only diagnostics over the actual ESP32 UDP/TCP bridge.
/// It never sends arming, motor, calibration or navigation commands.
class DroneReadinessScreen extends StatefulWidget {
  const DroneReadinessScreen({super.key});

  @override
  State<DroneReadinessScreen> createState() => _DroneReadinessScreenState();
}

class _DroneReadinessScreenState extends State<DroneReadinessScreen> {
  final InavDiagnosticsService _service = InavDiagnosticsService();
  Timer? _pollTimer;
  bool _connecting = false;
  bool _polling = false;
  bool _diagnosticStarted = false;
  bool _gpsSkipped = false;
  int _countdown = 10;
  Timer? _countdownTimer;
  int? _gpsCountdown;
  Timer? _gpsCountdownTimer;
  bool _gpsWindowTimedOut = false;
  String _connection = 'DISCONNECTED';
  String _message = 'Power on the drone controller and ESP32 to begin.';
  String? _host;
  String? _fcVariant;
  String? _fcVersion;
  String? _apiVersion;
  String? _lastUpdated;
  String? _gpsText;
  String? _batteryText;
  String? _receiverText;
  String? _armingText;
  int? _sensorFlags;
  _Readiness _fcState = _Readiness.waiting;
  _Readiness _telemetryState = _Readiness.waiting;
  _Readiness _gpsState = _Readiness.waiting;
  _Readiness _batteryState = _Readiness.waiting;
  _Readiness _receiverState = _Readiness.waiting;
  _Readiness _sensorsState = _Readiness.notVerified;
  String? _error;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _gpsCountdownTimer?.cancel();
    _service.dispose();
    super.dispose();
  }

  String _ascii(List<int> bytes) =>
      String.fromCharCodes(bytes).replaceAll('\u0000', '').trim();

  Future<void> _startDiagnostics() async {
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _diagnosticStarted = true;
      _connection = 'CONNECTING';
      _fcState = _Readiness.checking;
      _error = null;
      _message = 'Connecting to the drone. Keep the controller powered on.';
      _countdown = 10;
    });
    _beginCountdown();
    try {
      final host = await _service.discover(
        timeout: const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() {
        _host = host;
        _connection = 'ESP32 FOUND';
        _message = 'Flight controller response is being verified.';
      });
      await _service.connect(host);

      final api = (await _service.request(1)).payload;
      final variant = (await _service.request(2)).payload;
      final version = (await _service.request(3)).payload;
      if (api.length < 3 || variant.length < 4 || version.length < 3) {
        throw const FormatException(
          'Flight controller returned incomplete identification data.',
        );
      }
      final fcVariant = _ascii(variant);
      if (fcVariant != 'INAV') {
        throw FormatException(
          'Unsupported flight controller response: $fcVariant',
        );
      }
      if (!mounted) return;
      setState(() {
        _fcVariant = fcVariant;
        _apiVersion = '${api[1]}.${api[2]}';
        _fcVersion = '${version[0]}.${version[1]}.${version[2]}';
        _fcState = _Readiness.ready;
        _connection = 'INAV CONNECTED';
        _message =
            'Flight controller identified. Reading live aircraft status.';
      });
      _stopCountdown();
      await _pollTelemetry();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _pollTelemetry();
      });
    } catch (error) {
      _stopCountdown();
      await _service.disconnect();
      if (!mounted) return;
      setState(() {
        _connection = 'NOT VERIFIED';
        _fcState = _Readiness.notVerified;
        _error = error is TimeoutException
            ? 'No response within 10 seconds. Check power and Wi-Fi, then retry.'
            : 'Flight controller could not be verified. Check the ESP32 connection and retry.';
        _message =
            'TCP connection alone does not verify the flight controller.';
      });
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _beginCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _countdown <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _countdown--);
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _startGpsCheckWindow() {
    _gpsCountdownTimer?.cancel();
    setState(() {
      _gpsCountdown = 10;
      _gpsWindowTimedOut = false;
    });
    _gpsCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _gpsCountdown == null || _gpsCountdown! <= 1) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _gpsCountdown = 0;
            _gpsWindowTimedOut = true;
          });
        }
        return;
      }
      setState(() => _gpsCountdown = _gpsCountdown! - 1);
    });
  }

  Future<void> _pollTelemetry() async {
    if (_polling || !_service.connected) return;
    _polling = true;
    try {
      final status = (await _service.request(
        150,
        timeout: const Duration(seconds: 2),
      )).payload;
      if (status.length < 13) {
        throw const FormatException('Short INAV status response.');
      }
      final sensorFlags = status[4] | (status[5] << 8);
      final armingFlags = status.length >= 15
          ? status[13] | (status[14] << 8)
          : null;

      final gpsReply = (await _service.request(
        106,
        timeout: const Duration(seconds: 2),
      )).payload;
      String gpsText = 'GPS payload unavailable';
      var gpsReady = false;
      if (gpsReply.length >= 16) {
        final data = ByteData.sublistView(gpsReply);
        final fix = gpsReply[0];
        final sats = gpsReply[1];
        final lat = data.getInt32(2, Endian.little) / 10000000;
        final lon = data.getInt32(6, Endian.little) / 10000000;
        final alt = data.getInt16(10, Endian.little);
        gpsReady = fix >= 2 && sats >= 6;
        gpsText =
            'Fix $fix • $sats satellites • ${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)} • $alt m';
      }

      final analog = (await _service.request(
        110,
        timeout: const Duration(seconds: 2),
      )).payload;
      final batteryText = analog.isNotEmpty
          ? 'Voltage ${(analog[0] / 10).toStringAsFixed(1)} V${analog.length >= 7 ? ' • Current ${(ByteData.sublistView(Uint8List.fromList(analog)).getInt16(5, Endian.little) / 100).toStringAsFixed(2)} A' : ' • Current monitoring unavailable'}'
          : 'Battery telemetry unavailable';

      final rc = (await _service.request(
        105,
        timeout: const Duration(seconds: 2),
      )).payload;
      final receiverReady =
          rc.length >= 8 &&
          rc.length.isEven &&
          List<int>.generate(
            rc.length ~/ 2,
            (i) => rc[i * 2] | (rc[i * 2 + 1] << 8),
          ).any((value) => value >= 900 && value <= 2100);

      if (!mounted) return;
      setState(() {
        _sensorFlags = sensorFlags;
        _armingText = armingFlags == null
            ? 'Arming-disable flags unavailable in this response.'
            : armingFlags == 0
            ? 'No arming-disable flags reported.'
            : 'INAV arming-disable flags: 0x${armingFlags.toRadixString(16).padLeft(4, '0').toUpperCase()}';
        _gpsText = gpsText;
        if (gpsReady) {
          _gpsCountdownTimer?.cancel();
          _gpsCountdown = null;
          _gpsWindowTimedOut = false;
        } else if (_gpsCountdown == null && !_gpsWindowTimedOut) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _gpsCountdown == null && !_gpsWindowTimedOut) {
              _startGpsCheckWindow();
            }
          });
        }
        _gpsState = gpsReady
            ? _Readiness.ready
            : _gpsSkipped
            ? _Readiness.skipped
            : _Readiness.blocked;
        _batteryText = batteryText;
        _batteryState = analog.isNotEmpty && analog[0] > 0
            ? _Readiness.ready
            : _Readiness.notVerified;
        _receiverText = receiverReady
            ? 'RC channel data is present; link quality cannot be inferred from channel values alone.'
            : 'No valid RC channel values received.';
        _receiverState = receiverReady
            ? _Readiness.notVerified
            : _Readiness.blocked;
        _sensorsState = (sensorFlags & 0x03) == 0x03
            ? _Readiness.ready
            : _Readiness.blocked;
        _telemetryState = _Readiness.ready;
        _lastUpdated = TimeOfDay.now().format(context);
        _connection = 'INAV CONNECTED';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connection = 'CONNECTION LOST';
        _telemetryState = _Readiness.notVerified;
        _error =
            'Flight-controller telemetry stopped. Reconnect and rerun diagnostics.';
      });
      _pollTimer?.cancel();
      _pollTimer = null;
      await _service.disconnect();
    } finally {
      _polling = false;
    }
  }

  void _skipGps() {
    setState(() {
      _gpsSkipped = true;
      _gpsState = _Readiness.skipped;
    });
  }

  void _retryGps() {
    if (_gpsState == _Readiness.skipped) {
      setState(() => _gpsSkipped = false);
    }
    _startGpsCheckWindow();
  }

  Widget _check(String label, _Readiness state, String? detail) {
    final color = switch (state) {
      _Readiness.ready => _green,
      _Readiness.blocked => Colors.red.shade800,
      _Readiness.skipped => Colors.blueGrey,
      _Readiness.checking => Colors.orange.shade800,
      _Readiness.notVerified => Colors.orange.shade800,
      _Readiness.waiting => Colors.grey.shade600,
    };
    final status = switch (state) {
      _Readiness.ready => 'READY',
      _Readiness.blocked => 'BLOCKED',
      _Readiness.skipped => 'SKIPPED',
      _Readiness.checking => 'CHECKING',
      _Readiness.notVerified => 'NOT VERIFIED',
      _Readiness.waiting => 'WAITING',
    };
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(
          state == _Readiness.ready ? Icons.check_circle : Icons.info_outline,
          color: color,
        ),
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w900, color: _ink),
        ),
        subtitle: detail == null
            ? null
            : Text(detail, style: const TextStyle(height: 1.35)),
        trailing: Text(
          status,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Drone Automatic Scan'),
        backgroundColor: _page,
        foregroundColor: _ink,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFD9A6)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AUTOMATIC DRONE INSPECTION',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'GreenGuard will check the connection and read available flight data. No motor or flight commands are sent by this diagnostic procedure.',
                  style: TextStyle(fontSize: 14, height: 1.45, color: _ink),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Connection: $_connection',
            style: const TextStyle(fontWeight: FontWeight.w900, color: _ink),
          ),
          if (_host != null) Text('ESP32: $_host'),
          if (_fcVariant != null)
            Text(
              '$_fcVariant • Firmware ${_fcVersion ?? 'unknown'} • API ${_apiVersion ?? 'unknown'}',
            ),
          Text(_message),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: Colors.red.shade800,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (!_diagnosticStarted || _fcState != _Readiness.ready)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _connecting ? null : _startDiagnostics,
                icon: _connecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  _connecting
                      ? 'CHECKING • $_countdown'
                      : _diagnosticStarted
                      ? 'RETRY CONNECTION'
                      : 'START DIAGNOSTIC',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          if (_diagnosticStarted) ...[
            const SizedBox(height: 12),
            _check(
              'INAV flight-controller identity',
              _fcState,
              _fcVariant == null
                  ? 'UDP discovery, TCP, and valid MSP identity response are required.'
                  : '$_fcVariant firmware ${_fcVersion ?? ''}; API ${_apiVersion ?? ''}.',
            ),
            _check(
              'Live INAV telemetry',
              _telemetryState,
              _lastUpdated == null
                  ? 'Waiting for a valid status response.'
                  : 'Updated $_lastUpdated.',
            ),
            _check(
              'Sensors detected',
              _sensorsState,
              _sensorFlags == null
                  ? 'Sensor state not verified.'
                  : 'Gyro: ${(_sensorFlags! & 0x01) != 0 ? 'detected' : 'not detected'} • Accelerometer: ${(_sensorFlags! & 0x02) != 0 ? 'detected' : 'not detected'} • Barometer: ${(_sensorFlags! & 0x04) != 0 ? 'detected' : 'not detected'} • Compass: ${(_sensorFlags! & 0x08) != 0 ? 'detected' : 'not detected'}. Presence does not verify calibration quality.',
            ),
            _check('Battery telemetry', _batteryState, _batteryText),
            _check('RC channel data', _receiverState, _receiverText),
            _check(
              'GPS fix',
              _gpsState,
              _gpsText ?? 'Waiting for live GPS response.',
            ),
            if (_gpsState != _Readiness.ready) ...[
              const Text(
                'Move the drone outdoors to an open area, then place it on a flat stable surface. GPS continues to be monitored in the background.',
                style: TextStyle(fontSize: 13, height: 1.4, color: _ink),
              ),
              if (_gpsCountdown != null && _gpsCountdown! > 0)
                Text(
                  'GPS CHECK • $_gpsCountdown seconds',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _green,
                  ),
                )
              else if (_gpsWindowTimedOut)
                const Text(
                  'GPS STILL SEARCHING • check continues in background',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.orange,
                  ),
                ),
              if (_gpsWindowTimedOut)
                OutlinedButton(
                  onPressed: _retryGps,
                  child: const Text('RETRY GPS CHECK'),
                ),
            ],
            if (_gpsState != _Readiness.ready && !_gpsSkipped)
              OutlinedButton(
                onPressed: _skipGps,
                child: const Text('SKIP GPS FOR NON-GPS DIAGNOSTICS'),
              ),
            if (_armingText != null) ...[
              const SizedBox(height: 10),
              Text(
                _armingText!,
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const _ReadinessRow(
              label: 'Waypoint navigation and return-to-home',
              detail:
                  'A GPS fix alone is insufficient. Navigation configuration, home position, and failsafe behavior have not been verified by the app.',
              status: 'NOT VERIFIED',
            ),
            const _ReadinessRow(
              label: 'Configured and active flight modes',
              detail:
                  'This diagnostics client does not yet read mode-range configuration or active mode flags.',
              status: 'NOT VERIFIED',
            ),
            const SizedBox(height: 12),
            const _ReadinessRow(
              label: 'Four-motor bench test',
              detail:
                  'Read-only diagnostics only. No verified motor-test and stop-acknowledgement path is available, so motors are not started.',
              status: 'NOT IMPLEMENTED',
            ),
            const _ReadinessRow(
              label: '0.30 m hover and automatic landing',
              detail:
                  'Sensor detection does not prove altitude hold, horizontal position hold, or a controlled landing path.',
              status: 'NOT VERIFIED',
            ),
            const _ReadinessRow(
              label: 'Failsafe',
              detail:
                  'Use of INAV failsafe settings has not been independently verified.',
              status: 'NOT VERIFIED',
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.emergency_rounded),
              label: const Text('EMERGENCY STOP — NOT CONNECTED'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade900,
                disabledForegroundColor: Colors.red.shade900,
                side: BorderSide(color: Colors.red.shade700, width: 2),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No stop command is sent. The app has no verified emergency-stop path; follow the aircraft operator procedure if it is powered.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Drone Manual Scan remains available through the existing camera and diagnosis flow.',
            style: TextStyle(fontSize: 14, height: 1.45, color: _ink),
          ),
        ],
      ),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({
    required this.label,
    required this.detail,
    required this.status,
  });

  final String label;
  final String detail;
  final String status;

  @override
  Widget build(BuildContext context) {
    final bool unavailable = status == 'UNAVAILABLE';
    final bool reported = status == 'REPORTED';
    final Color color = unavailable
        ? Colors.red.shade800
        : reported
        ? _green
        : Colors.orange.shade800;
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              unavailable
                  ? Icons.block_rounded
                  : reported
                  ? Icons.info_outline_rounded
                  : Icons.help_outline_rounded,
              color: color,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              status,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

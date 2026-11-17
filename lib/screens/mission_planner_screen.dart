import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/flight_mission.dart';
import '../services/Esp_Cam.dart';
import '../services/inav_diagnostics_service.dart';

const _green = Color(0xFF47D16C);
const _panel = Color(0xE91A211E);

/// Map-first mission editor. It intentionally has no flight-command path:
/// this project has no verified MSP mission upload or multicopter launch path.
class MissionPlannerScreen extends StatefulWidget {
  const MissionPlannerScreen({super.key});

  @override
  State<MissionPlannerScreen> createState() => _MissionPlannerScreenState();
}

class _MissionPlannerScreenState extends State<MissionPlannerScreen> {
  static const _tileKey = 'mission_map_tile_template';
  final _service = InavDiagnosticsService();
  final _cameraService = EspCamService();
  FlightMission _mission = const FlightMission();
  final List<FlightMission> _undo = [];
  final List<FlightMission> _redo = [];
  Timer? _telemetryTimer;
  LatLngD? _drone;
  LatLngD? _phone;
  String _connection = 'ESP32 NOT CONNECTED';
  String _heading = 'Heading unavailable';
  double? _headingDegrees;
  String _battery = 'BATTERY UNAVAILABLE';
  bool _cameraReady = false;
  bool _checkingCamera = false;
  bool _busy = false;
  int _zoom = 17;
  LatLngD _center = const LatLngD(14.5995, 120.9842);
  String _tileTemplate =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  int? _selected;

  @override
  void initState() {
    super.initState();
    _restore();
    _checkCamera();
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _service.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final mission = prefs.getString('saved_flight_mission');
    final template = prefs.getString(_tileKey);
    if (!mounted) return;
    setState(() {
      if (mission != null) {
        try {
          _mission = FlightMission.decode(mission);
        } catch (_) {}
      }
      if (template != null &&
          template.contains('{z}') &&
          template.contains('{x}') &&
          template.contains('{y}')) {
        _tileTemplate = template;
      }
    });
    _locatePhone();
  }

  void _remember() {
    _undo.add(_mission);
    if (_undo.length > 30) _undo.removeAt(0);
    _redo.clear();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_flight_mission', _mission.encode());
    if (mounted) _toast('Mission saved on this device.');
  }

  Future<void> _locatePhone() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _phone = LatLngD(position.latitude, position.longitude));
      if (_drone == null && _mission.waypoints.isEmpty) {
        setState(() => _center = _phone!);
      }
    } catch (_) {}
  }

  Future<void> _checkCamera() async {
    if (_checkingCamera) return;
    _checkingCamera = true;
    final ready = await _cameraService.checkConnection();
    if (mounted) setState(() => _cameraReady = ready);
    _checkingCamera = false;
  }

  Future<void> _connect() async {
    if (_busy || _service.connected) return;
    setState(() {
      _busy = true;
      _connection = 'DISCOVERING ESP32…';
    });
    try {
      final host = await _service.discover(timeout: const Duration(seconds: 8));
      await _service.connect(host);
      final variant = (await _service.request(2)).payload;
      if (String.fromCharCodes(variant).replaceAll('\u0000', '').trim() !=
          'INAV') {
        throw const FormatException(
          'The bridge did not identify an INAV flight controller.',
        );
      }
      if (!mounted) return;
      setState(() {
        _connection = 'INAV CONNECTED • READ ONLY';
      });
      await _readGps();
      _telemetryTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _readGps(),
      );
    } catch (error) {
      await _service.disconnect();
      if (mounted) setState(() => _connection = 'CONNECTION NOT VERIFIED');
      if (mounted) _toast('Could not verify the flight controller: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readGps() async {
    if (!_service.connected) return;
    try {
      final bytes = (await _service.request(106)).payload;
      if (bytes.length < 16) {
        throw const FormatException('GPS telemetry is incomplete.');
      }
      final data = ByteData.sublistView(Uint8List.fromList(bytes));
      final fix = bytes[0];
      final sats = bytes[1];
      final point = LatLngD(
        data.getInt32(2, Endian.little) / 1e7,
        data.getInt32(6, Endian.little) / 1e7,
      );
      final analog = (await _service.request(110)).payload;
      final battery = analog.isNotEmpty && analog[0] > 0
          ? 'BATTERY ${(analog[0] / 10).toStringAsFixed(1)} V'
          : 'BATTERY TELEMETRY UNAVAILABLE';
      if (!mounted) return;
      if (fix < 2 || sats < 5 || point.latitude == 0 && point.longitude == 0) {
        setState(() {
          _drone = null;
          _headingDegrees = null;
          _heading = 'HEADING UNAVAILABLE';
          _connection = 'INAV CONNECTED • GPS NO FIX';
        });
      } else {
        double? heading;
        final status = (await _service.request(150)).payload;
        final attitude = (await _service.request(108)).payload;
        if (status.length >= 6 && attitude.length >= 6) {
          final sensorFlags = status[4] | (status[5] << 8);
          final rawHeading = ByteData.sublistView(
            Uint8List.fromList(attitude),
          ).getInt16(4, Endian.little);
          if ((sensorFlags & 0x08) != 0 &&
              rawHeading >= 0 &&
              rawHeading < 360) {
            heading = rawHeading.toDouble();
          }
        }
        setState(() {
          _drone = point;
          _center = point;
          _headingDegrees = heading;
          _heading = heading == null
              ? 'HEADING UNAVAILABLE'
              : '${heading.toStringAsFixed(0)}°';
          _battery = battery;
          _connection = 'INAV CONNECTED • GPS FIX • $sats SAT';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _connection = 'TELEMETRY STALE';
        _drone = null;
      });
      _telemetryTimer?.cancel();
      _telemetryTimer = null;
    }
  }

  void _addWaypoint(LatLngD point) {
    _remember();
    setState(() {
      _mission = _mission.copyWith(
        waypoints: [
          ..._mission.waypoints,
          MissionPoint(
            latitude: point.latitude,
            longitude: point.longitude,
            altitudeMeters: _mission.altitudeMeters,
            speedMetersPerSecond: _mission.speedMetersPerSecond,
            hoverSeconds: _mission.hoverSeconds,
          ),
        ],
      );
      _selected = _mission.waypoints.length - 1;
    });
    final index = _mission.waypoints.length - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && index < _mission.waypoints.length) _editPoint(index);
    });
  }

  void _moveWaypoint(int index, LatLngD point) {
    final list = [..._mission.waypoints];
    final old = list[index];
    list[index] = MissionPoint(
      latitude: point.latitude,
      longitude: point.longitude,
      altitudeMeters: old.altitudeMeters,
      speedMetersPerSecond: old.speedMetersPerSecond,
      hoverSeconds: old.hoverSeconds,
    );
    setState(() => _mission = _mission.copyWith(waypoints: list));
  }

  void _editPoint(int index) {
    final item = _mission.waypoints[index];
    final alt = TextEditingController(
      text: (item.altitudeMeters / 0.3048).toStringAsFixed(0),
    );
    final speed = TextEditingController(
      text: item.speedMetersPerSecond.toStringAsFixed(1),
    );
    final hover = TextEditingController(text: item.hoverSeconds.toString());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF202823),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WAYPOINT ${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            _field(alt, 'Altitude (1–6 feet)', decimal: true),
            _field(speed, 'Speed (m/s)', decimal: true),
            _field(hover, 'Position hold (seconds)'),
            Row(
              children: [
                IconButton(
                  onPressed: index == 0
                      ? null
                      : () {
                          _remember();
                          final points = [..._mission.waypoints];
                          final p = points.removeAt(index);
                          points.insert(index - 1, p);
                          setState(() {
                            _mission = _mission.copyWith(waypoints: points);
                            _selected = index - 1;
                          });
                          Navigator.pop(context);
                        },
                  icon: const Icon(Icons.arrow_upward, color: Colors.white),
                ),
                IconButton(
                  onPressed: index >= _mission.waypoints.length - 1
                      ? null
                      : () {
                          _remember();
                          final points = [..._mission.waypoints];
                          final p = points.removeAt(index);
                          points.insert(index + 1, p);
                          setState(() {
                            _mission = _mission.copyWith(waypoints: points);
                            _selected = index + 1;
                          });
                          Navigator.pop(context);
                        },
                  icon: const Icon(Icons.arrow_downward, color: Colors.white),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    _remember();
                    final points = [..._mission.waypoints]..removeAt(index);
                    setState(() {
                      _mission = _mission.copyWith(waypoints: points);
                      _selected = null;
                    });
                    Navigator.pop(context);
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  label: const Text(
                    'DELETE',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final a = double.tryParse(alt.text);
                    final s = double.tryParse(speed.text);
                    final h = int.tryParse(hover.text);
                    if (a == null ||
                        s == null ||
                        h == null ||
                        h < 1 ||
                        h > 10 ||
                        a < 1 ||
                        a > 6) {
                      _toast(
                        'Waypoint altitude must be 1–6 ft and wait must be 1–10 seconds.',
                      );
                      return;
                    }
                    _remember();
                    final points = [..._mission.waypoints];
                    points[index] = MissionPoint(
                      latitude: item.latitude,
                      longitude: item.longitude,
                      altitudeMeters: a * 0.3048,
                      speedMetersPerSecond: s,
                      hoverSeconds: h,
                    );
                    setState(
                      () => _mission = _mission.copyWith(waypoints: points),
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('SAVE'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool decimal = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.white10,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  void _settings() {
    var returnHome = _mission.returnHome;
    var landOnCompletion = _mission.landOnCompletion;
    var capturePhotos = _mission.capturePhotoAtEachWaypoint;
    final name = TextEditingController(text: _mission.name);
    final takeoff = TextEditingController(
      text: (_mission.takeoffAltitudeMeters / 0.3048).toStringAsFixed(0),
    );
    final alt = TextEditingController(
      text: (_mission.altitudeMeters / 0.3048).toStringAsFixed(0),
    );
    final speed = TextEditingController(
      text: _mission.speedMetersPerSecond.toStringAsFixed(1),
    );
    final hold = TextEditingController(text: _mission.hoverSeconds.toString());
    final rtn = TextEditingController(
      text: (_mission.returnAltitudeMeters / 0.3048).toStringAsFixed(0),
    );
    final reserve = TextEditingController(
      text: _mission.batteryReservePercent.toString(),
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF202823),
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.of(context).viewInsets.bottom + 22,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MISSION SETTINGS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                _field(name, 'Mission name'),
                _field(takeoff, 'Takeoff altitude (feet)', decimal: true),
                _field(alt, 'Waypoint altitude (1–6 feet)', decimal: true),
                _field(speed, 'Maximum speed (m/s)', decimal: true),
                _field(hold, 'Waypoint wait at each stop (1–10 seconds)'),
                SwitchListTile(
                  value: capturePhotos,
                  onChanged: (value) => update(() => capturePhotos = value),
                  title: const Text(
                    'Capture one photo at each waypoint',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Collect on the route, then analyze together after the last waypoint.',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
                _field(rtn, 'Return altitude (feet)', decimal: true),
                _field(reserve, 'Battery reserve (%)'),
                SwitchListTile(
                  value: returnHome,
                  onChanged: (value) => update(() => returnHome = value),
                  title: const Text(
                    'Return to home',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                SwitchListTile(
                  value: landOnCompletion,
                  onChanged: (value) => update(() => landOnCompletion = value),
                  title: const Text(
                    'Land at mission completion',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final t = double.tryParse(takeoff.text);
                      final a = double.tryParse(alt.text);
                      final s = double.tryParse(speed.text);
                      final h = int.tryParse(hold.text);
                      final settle = h;
                      final r = double.tryParse(rtn.text);
                      final b = int.tryParse(reserve.text);
                      if (t == null ||
                          a == null ||
                          s == null ||
                          h == null ||
                          settle == null ||
                          r == null ||
                          b == null) {
                        return;
                      }
                      if (h < 1 || h > 10 || a < 1 || a > 6 || t < 6 || r < 6) {
                        _toast(
                          'Use waypoint altitude from 1–6 ft, takeoff/return altitude at least 6 ft, and waypoint wait from 1 to 10 seconds.',
                        );
                        return;
                      }
                      _remember();
                      setState(
                        () => _mission = _mission.copyWith(
                          name: name.text,
                          takeoffAltitudeMeters: t * 0.3048,
                          altitudeMeters: a * 0.3048,
                          speedMetersPerSecond: s,
                          hoverSeconds: h,
                          capturePhotoAtEachWaypoint: capturePhotos,
                          cameraSettleSeconds: settle,
                          returnAltitudeMeters: r * 0.3048,
                          batteryReservePercent: b,
                          returnHome: returnHome,
                          landOnCompletion: landOnCompletion,
                        ),
                      );
                      Navigator.pop(context);
                    },
                    child: const Text('SAVE SETTINGS'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _tileSettings() async {
    final c = TextEditingController(text: _tileTemplate);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Satellite map source'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(
            labelText: 'Tile URL template',
            helperText: 'URL must include {z}, {x}, and {y}.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (value == null ||
        !value.contains('{z}') ||
        !value.contains('{x}') ||
        !value.contains('{y}')) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tileKey, value);
    if (mounted) setState(() => _tileTemplate = value);
  }

  void _start() {
    final errors = _mission.validate();
    final all = [...errors];
    if (!_service.connected) {
      all.add('Connect and verify the INAV flight controller.');
    }
    if (_drone == null) {
      all.add('A fresh GPS position with a valid fix is required.');
    }
    if (_mission.capturePhotoAtEachWaypoint && !_cameraReady) {
      all.add(
        'The ESP32-CAM is not connected or has not passed its status check.',
      );
    }
    all.add(
      'Mission upload, navigation readiness, takeoff, abort, and landing commands are not implemented or hardware-verified. Launch remains disabled.',
    );
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mission cannot start'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: all
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('• $e'),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _photoWorkflow() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF202823),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MISSION PHOTO WORKFLOW',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 14),
              _workflowStep(
                '1',
                'Camera preflight',
                _cameraReady
                    ? 'ESP32-CAM connected'
                    : 'Camera not ready — connect and check again',
                _cameraReady ? _green : Colors.amber,
              ),
              _workflowStep(
                '2',
                'Capture on route',
                _mission.capturePhotoAtEachWaypoint
                    ? 'One photo per waypoint • ${_mission.cameraSettleSeconds}s settle • ${_mission.waypoints.length} planned photos'
                    : 'Waypoint photo capture is turned off',
                Colors.white70,
              ),
              _workflowStep(
                '3',
                'Analyze after the last waypoint',
                'Collected photos are sent together after the route is complete. No retake prompt.',
                Colors.white70,
              ),
              _workflowStep(
                '4',
                'Save results',
                'Each diagnosis appears in Health Logs; completion notification follows successful saves.',
                Colors.white70,
              ),
              const SizedBox(height: 12),
              const Text(
                'Photo collection and batch analysis are not active in this build because waypoint flight execution is not implemented. The scan button stays unavailable until photos have actually been collected.',
                style: TextStyle(
                  color: Colors.amber,
                  height: 1.4,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('SCAN ALL COLLECTED PHOTOS'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workflowStep(
    String number,
    String title,
    String detail,
    Color color,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: color.withValues(alpha: 0.18),
          child: Text(
            number,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: TextStyle(color: color, fontSize: 12, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void _toast(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121714),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _MissionMap(
                center: _center,
                zoom: _zoom,
                waypoints: _mission.waypoints,
                drone: _drone,
                headingDegrees: _headingDegrees,
                phone: _phone,
                tileTemplate: _tileTemplate,
                onTap: _addWaypoint,
                onMove: _moveWaypoint,
                onMoveStart: _remember,
                onSelect: _editPoint,
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  _roundButton(Icons.arrow_back, () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _mission.name.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _connection,
                            style: TextStyle(
                              color: _connection.contains('FIX')
                                  ? _green
                                  : Colors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _roundButton(Icons.settings, _settings),
                ],
              ),
            ),
            Positioned(
              right: 12,
              top: 100,
              child: Column(
                children: [
                  _roundButton(
                    Icons.add,
                    () => setState(
                      () => _zoom = (_zoom + 1).clamp(3, 19).toInt(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _roundButton(
                    Icons.remove,
                    () => setState(
                      () => _zoom = (_zoom - 1).clamp(3, 19).toInt(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _roundButton(Icons.my_location, () {
                    final p = _drone ?? _phone;
                    if (p != null) {
                      setState(() => _center = p);
                    } else {
                      _connect();
                    }
                  }),
                  const SizedBox(height: 8),
                  _roundButton(Icons.photo_camera, () {
                    _checkCamera();
                    _photoWorkflow();
                  }),
                ],
              ),
            ),
            Positioned(
              left: 12,
              top: 100,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.navigation_rounded,
                      color: Colors.cyanAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 7),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NOSE / FRONT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'TAIL / BACK • tap route direction',
                          style: TextStyle(color: Colors.white70, fontSize: 9),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      children: [
                        _compactStatus(
                          Icons.navigation,
                          _drone == null ? 'GPS: NO FIX' : 'DRONE: $_heading',
                          Colors.cyanAccent,
                        ),
                        _compactStatus(
                          Icons.photo_camera,
                          _cameraReady ? 'CAMERA: READY' : 'CAMERA: CHECK',
                          _cameraReady ? _green : Colors.amber,
                        ),
                        _compactStatus(
                          Icons.battery_std,
                          _battery,
                          _battery.contains('UNAVAILABLE')
                              ? Colors.amber
                              : _green,
                        ),
                        _compactStatus(
                          Icons.person_pin_circle,
                          _phone == null ? 'PHONE: OFF' : 'PHONE: READY',
                          Colors.white70,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.route, color: _green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_mission.waypoints.length} STOPS • ${(_mission.altitudeMeters / 0.3048).toStringAsFixed(0)} ft • ${_mission.speedMetersPerSecond.toStringAsFixed(1)} m/s • ${_mission.hoverSeconds}s wait',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _mission.waypoints.isEmpty
                              ? null
                              : _editPointForSelected,
                          icon: const Icon(Icons.tune, color: Colors.white),
                        ),
                        IconButton(
                          onPressed: _save,
                          icon: const Icon(
                            Icons.save_outlined,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          onPressed: _photoWorkflow,
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : _service.connected
                                ? () async {
                                    _telemetryTimer?.cancel();
                                    await _service.disconnect();
                                    setState(
                                      () => _connection = 'ESP32 NOT CONNECTED',
                                    );
                                  }
                                : _connect,
                            icon: Icon(
                              _service.connected ? Icons.link_off : Icons.wifi,
                              size: 18,
                            ),
                            label: Text(
                              _busy
                                  ? 'CONNECTING…'
                                  : _service.connected
                                  ? 'DISCONNECT'
                                  : 'CONNECT DRONE',
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white30),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _start,
                            icon: const Icon(Icons.flight_takeoff, size: 18),
                            label: const Text('START MISSION'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF604D31),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'PLANNING ONLY • FLIGHT COMMANDS DISABLED UNTIL VERIFIED',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.w900,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 12,
              top: 170,
              child: Column(
                children: [
                  _roundButton(Icons.undo, _undoMission),
                  const SizedBox(height: 8),
                  _roundButton(Icons.redo, _redoMission),
                  const SizedBox(height: 8),
                  _roundButton(Icons.layers, _tileSettings),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 74,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _panel,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'TAP MAP TO ADD WAYPOINT • DRAG MARKER TO MOVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editPointForSelected() => _editPoint(
    (_selected ?? _mission.waypoints.length - 1).clamp(
      0,
      _mission.waypoints.length - 1,
    ),
  );
  void _undoMission() {
    if (_undo.isEmpty) return;
    _redo.add(_mission);
    setState(() => _mission = _undo.removeLast());
  }

  void _redoMission() {
    if (_redo.isEmpty) return;
    _undo.add(_mission);
    setState(() => _mission = _redo.removeLast());
  }

  Widget _roundButton(IconData icon, VoidCallback onPressed) => Material(
    color: _panel,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(icon, color: Colors.white, size: 21),
      ),
    ),
  );
  Widget _pill(String text, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _compactStatus(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class LatLngD {
  const LatLngD(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class _MissionMap extends StatefulWidget {
  const _MissionMap({
    required this.center,
    required this.zoom,
    required this.waypoints,
    required this.drone,
    required this.headingDegrees,
    required this.phone,
    required this.tileTemplate,
    required this.onTap,
    required this.onMove,
    required this.onMoveStart,
    required this.onSelect,
  });
  final LatLngD center;
  final int zoom;
  final List<MissionPoint> waypoints;
  final LatLngD? drone;
  final double? headingDegrees;
  final LatLngD? phone;
  final String tileTemplate;
  final ValueChanged<LatLngD> onTap;
  final void Function(int, LatLngD) onMove;
  final VoidCallback onMoveStart;
  final ValueChanged<int> onSelect;

  @override
  State<_MissionMap> createState() => _MissionMapState();
}

class _MissionMapState extends State<_MissionMap> {
  Offset? _last;
  LatLngD? _center;
  int? _dragIndex;
  bool _moved = false;
  LatLngD get center => _center ?? widget.center;
  double get tileScale => 256 * (1 << widget.zoom).toDouble();

  Offset _world(LatLngD p) {
    final lat = p.latitude.clamp(-85.0511, 85.0511) * 3.141592653589793 / 180;
    return Offset(
      (p.longitude + 180) / 360 * tileScale,
      (1 - logTan(lat)) / 2 * tileScale,
    );
  }

  LatLngD _geo(Offset local, Size size) {
    final centerPx = _world(center);
    final world =
        centerPx +
        Offset(local.dx - size.width / 2, local.dy - size.height / 2);
    final n = tileScale;
    final lon = world.dx / n * 360 - 180;
    final lat =
        (2 * math.atan(math.exp((1 - 2 * world.dy / n) * 3.141592653589793)) -
            3.141592653589793 / 2) *
        180 /
        3.141592653589793;
    return LatLngD(lat, lon);
  }

  double logTan(double lat) => math.log(math.tan(lat) + 1 / math.cos(lat));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final c = _world(center);
      final baseX = (c.dx / 256).floor();
      final baseY = (c.dy / 256).floor();
      final origin = Offset(
        size.width / 2 - (c.dx - baseX * 256),
        size.height / 2 - (c.dy - baseY * 256),
      );
      final count = 1 << widget.zoom;
      final cols = (size.width / 256).ceil() + 2;
      final rows = (size.height / 256).ceil() + 2;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (e) {
          if (!_moved) widget.onTap(_geo(e.localPosition, size));
          _moved = false;
        },
        onPanStart: (e) {
          _last = e.localPosition;
          _moved = false;
          _dragIndex = _nearestWaypoint(e.localPosition, size);
          if (_dragIndex != null) widget.onMoveStart();
        },
        onPanUpdate: (e) {
          _moved = true;
          if (_dragIndex != null) {
            widget.onMove(_dragIndex!, _geo(e.localPosition, size));
            return;
          }
          final delta = e.localPosition - _last!;
          _last = e.localPosition;
          final world = _world(center) - delta;
          final lon = world.dx / tileScale * 360 - 180;
          final lat =
              (2 *
                      math.atan(
                        math.exp(
                          (1 - 2 * world.dy / tileScale) * 3.141592653589793,
                        ),
                      ) -
                  3.141592653589793 / 2) *
              180 /
              3.141592653589793;
          setState(() => _center = LatLngD(lat, lon));
        },
        onPanEnd: (_) {
          if (_dragIndex != null) {
            widget.onSelect(_dragIndex!);
          }
          _dragIndex = null;
        },
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (var dx = -1; dx <= cols; dx++)
              for (var dy = -1; dy <= rows; dy++)
                (() {
                  final tx = baseX + dx;
                  final ty = baseY + dy;
                  if (ty < 0 || ty >= count) return const SizedBox.shrink();
                  final x = (tx % count + count) % count;
                  final url = widget.tileTemplate
                      .replaceAll('{z}', '${widget.zoom}')
                      .replaceAll('{x}', '$x')
                      .replaceAll('{y}', '$ty');
                  return Positioned(
                    left: origin.dx + dx * 256,
                    top: origin.dy + dy * 256,
                    width: 256,
                    height: 256,
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: const Color(0xFF344238),
                        child: const Center(
                          child: Icon(
                            Icons.satellite_alt,
                            color: Colors.white24,
                          ),
                        ),
                      ),
                    ),
                  );
                })(),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RoutePainter(
                    center: center,
                    zoom: widget.zoom,
                    waypoints: widget.waypoints,
                  ),
                ),
              ),
            ),
            for (var i = 0; i < widget.waypoints.length; i++)
              Positioned.fromRect(
                rect: _markerRect(
                  _world(
                    LatLngD(
                      widget.waypoints[i].latitude,
                      widget.waypoints[i].longitude,
                    ),
                  ),
                  c,
                  size,
                ),
                child: GestureDetector(
                  onTap: () => widget.onSelect(i),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 7),
                      ],
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.drone case final p?)
              Positioned.fromRect(
                rect: _markerRect(_world(p), c, size),
                child: Transform.rotate(
                  angle: widget.headingDegrees == null
                      ? 0
                      : widget.headingDegrees! * math.pi / 180,
                  child: const Icon(
                    Icons.navigation,
                    color: Colors.cyanAccent,
                    size: 42,
                    shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                  ),
                ),
              ),
            if (widget.phone case final p?)
              Positioned.fromRect(
                rect: _markerRect(_world(p), c, size),
                child: const Icon(
                  Icons.person_pin_circle,
                  color: Colors.white,
                  size: 30,
                  shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                ),
              ),
            if (widget.drone == null)
              const Positioned(
                left: 12,
                bottom: 150,
                child: Text(
                  'DRONE HEADING UNAVAILABLE',
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
                  ),
                ),
              ),
            const Positioned(
              right: 4,
              bottom: 142,
              child: Text(
                '© Esri • Imagery',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Rect _markerRect(Offset point, Offset center, Size size) {
    final p = Offset(
      size.width / 2 + point.dx - center.dx,
      size.height / 2 + point.dy - center.dy,
    );
    return Rect.fromCenter(center: p, width: 40, height: 40);
  }

  int? _nearestWaypoint(Offset position, Size size) {
    var nearest = 36.0;
    int? result;
    for (var i = 0; i < widget.waypoints.length; i++) {
      final p = widget.waypoints[i];
      final r = _markerRect(
        _world(LatLngD(p.latitude, p.longitude)),
        _world(center),
        size,
      );
      final distance = (r.center - position).distance;
      if (distance < nearest) {
        nearest = distance;
        result = i;
      }
    }
    return result;
  }
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter({
    required this.center,
    required this.zoom,
    required this.waypoints,
  });
  final LatLngD center;
  final int zoom;
  final List<MissionPoint> waypoints;
  Offset _world(LatLngD p) {
    final n = 256 * (1 << zoom).toDouble();
    final lat = p.latitude.clamp(-85.0511, 85.0511) * 3.141592653589793 / 180;
    return Offset(
      (p.longitude + 180) / 360 * n,
      (1 - math.log(math.tan(lat) + 1 / math.cos(lat))) / 2 * n,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = _world(center);
    Offset screen(LatLngD p) {
      final w = _world(p);
      return Offset(
        size.width / 2 + w.dx - c.dx,
        size.height / 2 + w.dy - c.dy,
      );
    }

    final line = Paint()
      ..color = _green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path();
    final points = waypoints
        .map((e) => screen(LatLngD(e.latitude, e.longitude)))
        .toList();
    for (var i = 0; i < points.length; i++) {
      if (i == 0) {
        path.moveTo(points[i].dx, points[i].dy);
      } else {
        path.lineTo(points[i].dx, points[i].dy);
      }
    }
    if (points.length > 1) canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.center != center || old.zoom != zoom || old.waypoints != waypoints;
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/flight_mission.dart';
import '../services/Esp_Cam.dart';
import '../services/inav_diagnostics_service.dart';

const _green = Color(0xFF47D16C);
const _panel = Color(0xE91A211E);

// Initial field-test settings. Require consecutive fixes to reduce false arrivals
// caused by ordinary GPS position jitter. Tune after testing the actual drone GPS.
const double _waypointArrivalRadiusMeters = 5.0;
const int _requiredArrivalFixes = 3;

/// Map-first mission editor. It intentionally has no flight-command path:
/// this project has no verified MSP mission upload or multicopter launch path.
class MissionPlannerScreen extends StatefulWidget {
  const MissionPlannerScreen({super.key, this.mappingAltitudeFeet});

  final int? mappingAltitudeFeet;

  @override
  State<MissionPlannerScreen> createState() => _MissionPlannerScreenState();
}

class _MissionPlannerScreenState extends State<MissionPlannerScreen> {
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
  LatLngD _center = const LatLngD(0, 0);
  bool get _hasMapLocation => _drone != null || _phone != null;
  int _mapViewRevision = 0;
  int _detailedMappingAltitudeFeet = 2;
  bool _choosingLandingPoint = false;
  bool _mappingPlanConfirmed = false;
  LatLngD? _landingPoint;
  int? _selected;

  // Read-only waypoint monitoring state. It never sends commands to INAV.
  bool _waypointMonitoring = false;
  bool _waypointMonitoringComplete = false;
  int _nextWaypointIndex = 0;
  int _arrivalFixCount = 0;
  double? _distanceToNextWaypointMeters;
  final Set<int> _reachedWaypoints = <int>{};

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
    final landing = prefs.getString('saved_mapping_landing_point');
    if (!mounted) return;
    setState(() {
      if (mission != null) {
        try {
          _mission = FlightMission.decode(mission);
        } catch (_) {}
      }
      if (landing != null) {
        final parts = landing.split(',');
        if (parts.length == 2) {
          final lat = double.tryParse(parts[0]);
          final lon = double.tryParse(parts[1]);
          if (lat != null && lon != null) _landingPoint = LatLngD(lat, lon);
        }
      }
      if (_landingPoint != null && _mission.waypoints.isNotEmpty) {
        _mappingPlanConfirmed = true;
        _detailedMappingAltitudeFeet = (_mission.altitudeMeters / 0.3048)
            .round()
            .clamp(1, 6);
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
    final landing = _landingPoint;
    if (landing != null) {
      await prefs.setString(
        'saved_mapping_landing_point',
        '${landing.latitude},${landing.longitude}',
      );
    } else {
      await prefs.remove('saved_mapping_landing_point');
    }
    if (mounted) _toast('Mapping plan saved on this device.');
  }

  Future<void> _disconnectDrone() async {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _resetWaypointProgress();
    await _service.disconnect();
    if (!mounted) return;
    setState(() {
      _connection = 'ESP32 NOT CONNECTED';
      _drone = null;
      _headingDegrees = null;
      _battery = 'BATTERY UNAVAILABLE';
    });
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
    if (kIsWeb) {
      if (mounted) setState(() => _cameraReady = false);
      return;
    }
    _checkingCamera = true;
    final ready = await _cameraService.checkConnection();
    if (mounted) setState(() => _cameraReady = ready);
    _checkingCamera = false;
  }

  Future<void> _connect() async {
    if (_busy || _service.connected) return;
    if (kIsWeb) {
      _toast(
        'Drone connection requires the Android/iOS app. Chrome cannot use '
        'the UDP discovery and TCP MSP sockets used by the ESP32 bridge.',
      );
      return;
    }
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
          _arrivalFixCount = 0;
          _distanceToNextWaypointMeters = null;
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
        _checkWaypointArrival(point);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _connection = 'TELEMETRY STALE';
        _drone = null;
        _arrivalFixCount = 0;
        _distanceToNextWaypointMeters = null;
      });
      _telemetryTimer?.cancel();
      _telemetryTimer = null;
    }
  }

  void _resetWaypointProgress() {
    _waypointMonitoring = false;
    _waypointMonitoringComplete = false;
    _nextWaypointIndex = 0;
    _arrivalFixCount = 0;
    _distanceToNextWaypointMeters = null;
    _reachedWaypoints.clear();
  }

  void _toggleWaypointMonitoring() {
    if (_waypointMonitoring) {
      setState(() {
        _waypointMonitoring = false;
        _arrivalFixCount = 0;
        _distanceToNextWaypointMeters = null;
      });
      _toast('Waypoint monitoring stopped. No flight command was sent.');
      return;
    }

    if (_mission.waypoints.isEmpty) {
      _toast('Add at least one waypoint first.');
      return;
    }
    if (!_service.connected || _drone == null) {
      _toast('Connect to INAV and wait for a valid live GPS fix first.');
      return;
    }

    setState(() {
      _waypointMonitoring = true;
      _waypointMonitoringComplete = false;
      _nextWaypointIndex = 0;
      _arrivalFixCount = 0;
      _distanceToNextWaypointMeters = null;
      _reachedWaypoints.clear();
    });
    _toast(
      'Read-only waypoint monitoring started. The drone must be flown manually.',
    );
  }

  void _checkWaypointArrival(LatLngD current) {
    if (!_waypointMonitoring ||
        _waypointMonitoringComplete ||
        _nextWaypointIndex >= _mission.waypoints.length) {
      return;
    }

    final target = _mission.waypoints[_nextWaypointIndex];
    final distance = Geolocator.distanceBetween(
      current.latitude,
      current.longitude,
      target.latitude,
      target.longitude,
    );

    var reachedIndex = -1;
    var completed = false;
    setState(() {
      _distanceToNextWaypointMeters = distance;
      if (distance <= _waypointArrivalRadiusMeters) {
        _arrivalFixCount++;
      } else {
        _arrivalFixCount = 0;
      }

      if (_arrivalFixCount >= _requiredArrivalFixes) {
        reachedIndex = _nextWaypointIndex;
        _reachedWaypoints.add(reachedIndex);
        _nextWaypointIndex++;
        _arrivalFixCount = 0;
        if (_nextWaypointIndex >= _mission.waypoints.length) {
          _waypointMonitoring = false;
          _waypointMonitoringComplete = true;
          _distanceToNextWaypointMeters = null;
          completed = true;
        }
      }
    });

    if (reachedIndex >= 0) {
      _toast(
        completed
            ? 'All ${_mission.waypoints.length} waypoints detected as reached.'
            : 'Waypoint ${reachedIndex + 1} reached. Next: waypoint ${reachedIndex + 2}.',
      );
    }
  }

  String get _waypointProgressText {
    final total = _mission.waypoints.length;
    if (total == 0) return 'NO WAYPOINTS PLANNED';
    if (_waypointMonitoringComplete) {
      return 'COMPLETE • ${_reachedWaypoints.length}/$total WAYPOINTS REACHED';
    }
    if (_waypointMonitoring) {
      final distance = _distanceToNextWaypointMeters;
      final distanceLabel = distance == null
          ? 'WAITING FOR GPS'
          : '${distance.toStringAsFixed(1)} m AWAY • $_arrivalFixCount/$_requiredArrivalFixes FIXES';
      return 'MONITORING • WP ${_nextWaypointIndex + 1}/$total • $distanceLabel';
    }
    return '${_reachedWaypoints.length}/$total WAYPOINTS REACHED • MONITORING OFF';
  }

  void _addWaypoint(LatLngD point) {
    if (!_hasMapLocation) {
      _toast(
        'Connect the drone or enable location before choosing field areas.',
      );
      return;
    }
    if (_mission.waypoints.length >= 60) {
      _toast('The plan can contain up to 60 mapping points.');
      return;
    }
    _resetWaypointProgress();
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
    _mappingPlanConfirmed = false;
    _landingPoint = null;
    _choosingLandingPoint = false;
    _toast(
      'Area ${_mission.waypoints.length} added. Tap the map to add another.',
    );
  }

  void _handleMapTap(LatLngD point) {
    if (_choosingLandingPoint) {
      _confirmLandingPoint(point);
    } else {
      _addWaypoint(point);
    }
  }

  Future<void> _reviewMappingAreas() async {
    if (_mission.waypoints.isEmpty) {
      _toast('Tap the map to select at least one area first.');
      return;
    }
    var selectedHeight = _detailedMappingAltitudeFeet;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          backgroundColor: const Color(0xFFFDFEF9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Are these the areas to map?',
            style: TextStyle(
              color: Color(0xFF203A28),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You selected ${_mission.waypoints.length} mapping ${_mission.waypoints.length == 1 ? 'area' : 'areas'}.',
                style: const TextStyle(color: Color(0xFF536356), fontSize: 15),
              ),
              const SizedBox(height: 18),
              const Text(
                'Detailed mapping height',
                style: TextStyle(
                  color: Color(0xFF203A28),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [1, 2, 3, 4, 5, 6]
                    .map(
                      (feet) => ChoiceChip(
                        label: Text(
                          '$feet ft',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        selected: selectedHeight == feet,
                        onSelected: (_) =>
                            updateDialog(() => selectedHeight = feet),
                        selectedColor: const Color(0xFFD9EBDD),
                        backgroundColor: const Color(0xFFF0F3EC),
                        labelStyle: TextStyle(
                          color: selectedHeight == feet
                              ? const Color(0xFF205D35)
                              : const Color(0xFF526253),
                        ),
                        side: BorderSide(
                          color: selectedHeight == feet
                              ? const Color(0xFF4E9561)
                              : const Color(0xFFD6DED3),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                'Next, you will choose the landing location on the map.',
                style: TextStyle(
                  color: Color(0xFF687568),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF286B3D),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    _remember();
    final altitudeMeters = selectedHeight * 0.3048;
    final updatedPoints = _mission.waypoints
        .map(
          (point) => MissionPoint(
            latitude: point.latitude,
            longitude: point.longitude,
            altitudeMeters: altitudeMeters,
            speedMetersPerSecond: point.speedMetersPerSecond,
            hoverSeconds: point.hoverSeconds,
          ),
        )
        .toList();
    setState(() {
      _detailedMappingAltitudeFeet = selectedHeight;
      _mission = _mission.copyWith(
        altitudeMeters: altitudeMeters,
        waypoints: updatedPoints,
      );
      _choosingLandingPoint = true;
      _landingPoint = null;
      _mappingPlanConfirmed = false;
    });
    _toast('Now tap the map to choose where the drone should land.');
  }

  Future<void> _confirmLandingPoint(LatLngD point) async {
    setState(() => _landingPoint = point);
    final usePoint = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFDFEF9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Use this landing location?',
          style: TextStyle(
            color: Color(0xFF203A28),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'Landing point\n${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
          style: const TextStyle(color: Color(0xFF536356), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Choose again'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF286B3D),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm location'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (usePoint == true) {
      setState(() {
        _choosingLandingPoint = false;
        _mappingPlanConfirmed = true;
      });
      _toast(
        'Landing location selected. Save the plan when ready. Flight is not enabled.',
      );
    } else {
      setState(() {
        _landingPoint = null;
        _choosingLandingPoint = true;
        _mappingPlanConfirmed = false;
      });
    }
  }

  void _moveWaypoint(int index, LatLngD point) {
    _resetWaypointProgress();
    final list = [..._mission.waypoints];
    final old = list[index];
    list[index] = MissionPoint(
      latitude: point.latitude,
      longitude: point.longitude,
      altitudeMeters: old.altitudeMeters,
      speedMetersPerSecond: old.speedMetersPerSecond,
      hoverSeconds: old.hoverSeconds,
    );
    setState(() {
      _mission = _mission.copyWith(waypoints: list);
      _mappingPlanConfirmed = false;
      _landingPoint = null;
    });
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
            _field(alt, 'Mapping height (1–6 feet)', decimal: true),
            _field(speed, 'Speed (m/s)', decimal: true),
            _field(hover, 'Position hold (seconds)'),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                IconButton(
                  onPressed: index == 0
                      ? null
                      : () {
                          _remember();
                          _resetWaypointProgress();
                          final points = [..._mission.waypoints];
                          final p = points.removeAt(index);
                          points.insert(index - 1, p);
                          setState(() {
                            _mission = _mission.copyWith(waypoints: points);
                            _selected = index - 1;
                            _mappingPlanConfirmed = false;
                            _landingPoint = null;
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
                          _resetWaypointProgress();
                          final points = [..._mission.waypoints];
                          final p = points.removeAt(index);
                          points.insert(index + 1, p);
                          setState(() {
                            _mission = _mission.copyWith(waypoints: points);
                            _selected = index + 1;
                            _mappingPlanConfirmed = false;
                            _landingPoint = null;
                          });
                          Navigator.pop(context);
                        },
                  icon: const Icon(Icons.arrow_downward, color: Colors.white),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () {
                    _remember();
                    _resetWaypointProgress();
                    final points = [..._mission.waypoints]..removeAt(index);
                    setState(() {
                      _mission = _mission.copyWith(waypoints: points);
                      _selected = null;
                      _mappingPlanConfirmed = false;
                      _landingPoint = null;
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
                        a > 4) {
                      _toast(
                        'Mapping height must be 1–4 ft and wait must be 1–10 seconds.',
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
                    setState(() {
                      _mission = _mission.copyWith(waypoints: points);
                      _mappingPlanConfirmed = false;
                      _landingPoint = null;
                    });
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
    final droneReady = _service.connected && _drone != null;
    final connectionLabel = droneReady
        ? 'Drone location ready'
        : _service.connected
        ? 'Drone connected • waiting for GPS'
        : 'Drone not connected';
    final connectionColor = droneReady
        ? const Color(0xFF187A46)
        : const Color(0xFF9A6B18);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F5EC),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _MissionMap(
                key: ValueKey(_mapViewRevision),
                center: _center,
                zoom: _zoom,
                hasLocation: _hasMapLocation,
                waypoints: _mission.waypoints,
                landingPoint: _landingPoint,
                drone: _drone,
                headingDegrees: _headingDegrees,
                phone: _phone,
                reachedWaypoints: _reachedWaypoints,
                nextWaypointIndex: _nextWaypointIndex,
                waypointMonitoring: _waypointMonitoring,
                onTap: _handleMapTap,
                onMove: _moveWaypoint,
                onMoveStart: _remember,
                onSelect: _editPoint,
              ),
            ),

            // Simple, high-contrast header for the farmer.
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 760,
                    maxHeight: MediaQuery.of(context).size.height * .48,
                  ),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDFEF9),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x220E2818),
                          blurRadius: 18,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _headerIcon(
                          Icons.arrow_back_rounded,
                          () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5F2E5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.eco_rounded,
                            color: Color(0xFF246B3B),
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _mission.name.isEmpty
                                    ? 'Field survey'
                                    : _mission.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF203A28),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                connectionLabel,
                                style: TextStyle(
                                  color: connectionColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _headerIcon(Icons.tune_rounded, _settings),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Map controls are separated from the main farmer actions.
            Positioned(
              top: 112,
              right: 16,
              child: Column(
                children: [
                  _mapControl(
                    Icons.add_rounded,
                    () => setState(
                      () => _zoom = (_zoom + 1).clamp(3, 19).toInt(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _mapControl(
                    Icons.remove_rounded,
                    () => setState(
                      () => _zoom = (_zoom - 1).clamp(3, 19).toInt(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _mapControl(Icons.my_location_rounded, () {
                    final point = _drone ?? _phone;
                    if (point != null) {
                      setState(() {
                        _center = point;
                        _mapViewRevision++;
                      });
                    } else {
                      _connect();
                    }
                  }),
                  const SizedBox(height: 8),
                  _mapControl(
                    Icons.undo_rounded,
                    _undoMission,
                    enabled: _undo.isNotEmpty,
                  ),
                  const SizedBox(height: 8),
                  _mapControl(
                    Icons.redo_rounded,
                    _redoMission,
                    enabled: _redo.isNotEmpty,
                  ),
                ],
              ),
            ),

            if (_choosingLandingPoint)
              Positioned(
                top: 112,
                left: 14,
                right: 76,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF17472B),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Color(0x33000000), blurRadius: 12),
                      ],
                    ),
                    child: const Text(
                      'TAP THE MAP TO CHOOSE A LANDING LOCATION',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),

            // A real location is required before showing map tiles or accepting taps.
            if (!_hasMapLocation)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(28, 110, 72, 270),
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xF7FDFEF9),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x220E2818),
                            blurRadius: 18,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.location_searching_rounded,
                            color: Color(0xFF34754A),
                            size: 42,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Waiting for your field location',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF203A28),
                            ),
                          ),
                          SizedBox(height: 7),
                          Text(
                            'Connect the drone or allow phone location to open the real map. No sample location is shown.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: Color(0xFF5B6B5F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Farmer action panel: fewer actions, larger labels, and clear status.
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDFEF9),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: const Color(0xFFE1E9DD)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x2A102719),
                          blurRadius: 24,
                          offset: Offset(0, 7),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Map your field',
                                  style: TextStyle(
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF203A28),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF3E8),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  '${_mission.waypoints.length} areas',
                                  style: const TextStyle(
                                    color: Color(0xFF28633B),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _choosingLandingPoint
                                ? 'Choose a safe place for the drone to land.'
                                : _mappingPlanConfirmed
                                ? 'Your mapping areas and landing location are selected. Save this plan on your device.'
                                : _hasMapLocation
                                ? 'Tap the map to mark the lettuce areas you want to inspect.'
                                : 'Connect your drone to show the field and start choosing areas.',
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.35,
                              color: Color(0xFF5B6B5F),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _farmerStatus(
                                Icons.flight_rounded,
                                droneReady
                                    ? 'Drone GPS ready'
                                    : _service.connected
                                    ? 'Waiting for GPS'
                                    : 'Drone offline',
                                droneReady
                                    ? const Color(0xFF187A46)
                                    : const Color(0xFF9A6B18),
                              ),
                              _farmerStatus(
                                Icons.photo_camera_rounded,
                                _cameraReady
                                    ? 'Camera ready'
                                    : _checkingCamera
                                    ? 'Checking camera'
                                    : 'Camera offline',
                                _cameraReady
                                    ? const Color(0xFF187A46)
                                    : const Color(0xFF9A6B18),
                                onTap: _checkCamera,
                              ),
                              _farmerStatus(
                                Icons.battery_charging_full_rounded,
                                _battery == 'BATTERY UNAVAILABLE'
                                    ? 'Battery unavailable'
                                    : _battery,
                                _battery.contains('UNAVAILABLE')
                                    ? const Color(0xFF9A6B18)
                                    : const Color(0xFF187A46),
                              ),
                              _farmerStatus(
                                Icons.height,
                                widget.mappingAltitudeFeet == null
                                    ? 'Overview height not set'
                                    : 'Overview ${widget.mappingAltitudeFeet} ft',
                                widget.mappingAltitudeFeet == null
                                    ? const Color(0xFF9A6B18)
                                    : const Color(0xFF187A46),
                              ),
                            ],
                          ),
                          if (_waypointMonitoring ||
                              _waypointMonitoringComplete) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF4DF),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.route_rounded,
                                        color: Color(0xFF946018),
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Text(
                                          _waypointProgressText,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: true,
                                          style: const TextStyle(
                                            color: Color(0xFF775014),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_waypointMonitoring)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _toggleWaypointMonitoring,
                                        child: const Text('Stop monitoring'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : _service.connected
                                  ? _disconnectDrone
                                  : _connect,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 19,
                                      height: 19,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      _service.connected
                                          ? Icons.check_circle_rounded
                                          : Icons.wifi_rounded,
                                      size: 22,
                                    ),
                              label: Text(
                                _busy
                                    ? 'Connecting to drone…'
                                    : _service.connected
                                    ? 'Disconnect drone'
                                    : 'Connect drone',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _service.connected
                                    ? const Color(0xFF526C59)
                                    : const Color(0xFF286B3D),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(
                                  0xFFDCE9DB,
                                ),
                                disabledForegroundColor: const Color(
                                  0xFF28633B,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(17),
                                ),
                              ),
                            ),
                          ),
                          if (_mission.waypoints.isNotEmpty) ...[
                            const SizedBox(height: 9),
                            if (_mappingPlanConfirmed)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 9),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 11,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F4E9),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFF286B3D),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Plan reviewed • $_detailedMappingAltitudeFeet ft • landing point selected',
                                        style: const TextStyle(
                                          color: Color(0xFF28633B),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _save,
                                  icon: const Icon(Icons.save_outlined),
                                  label: const Text('Save plan'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF28633B),
                                    minimumSize: const Size.fromHeight(52),
                                    side: const BorderSide(
                                      color: Color(0xFFB8CDB8),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 9),
                                FilledButton.icon(
                                  onPressed: _choosingLandingPoint
                                      ? null
                                      : _reviewMappingAreas,
                                  icon: Icon(
                                    _mappingPlanConfirmed
                                        ? Icons.edit_location_alt_rounded
                                        : Icons.fact_check_rounded,
                                  ),
                                  label: Text(
                                    _mappingPlanConfirmed
                                        ? 'Change plan'
                                        : 'Review areas',
                                  ),
                                  style: FilledButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: const Color(0xFF286B3D),
                                    disabledBackgroundColor: const Color(
                                      0xFFCBD8CC,
                                    ),
                                    minimumSize: const Size.fromHeight(52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 9),
                          const Center(
                            child: Text(
                              'PLANNING ONLY  •  AUTONOMOUS FLIGHT IS NOT ENABLED',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF8A641E),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .3,
                              ),
                            ),
                          ),
                        ],
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

  void _undoMission() {
    if (_undo.isEmpty) return;
    _redo.add(_mission);
    _resetWaypointProgress();
    setState(() {
      _mission = _undo.removeLast();
      _mappingPlanConfirmed = false;
      _landingPoint = null;
      _choosingLandingPoint = false;
    });
  }

  void _redoMission() {
    if (_redo.isEmpty) return;
    _undo.add(_mission);
    _resetWaypointProgress();
    setState(() {
      _mission = _redo.removeLast();
      _mappingPlanConfirmed = false;
      _landingPoint = null;
      _choosingLandingPoint = false;
    });
  }

  Widget _headerIcon(IconData icon, VoidCallback onTap) => Material(
    color: const Color(0xFFF0F4EC),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 42,
        height: 42,
        child: Icon(icon, color: const Color(0xFF365A40), size: 22),
      ),
    ),
  );

  Widget _mapControl(
    IconData icon,
    VoidCallback onTap, {
    bool enabled = true,
  }) => Material(
    color: const Color(0xFFFDFEF9),
    elevation: 4,
    shadowColor: const Color(0x330E2818),
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(15),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(
          icon,
          color: enabled ? const Color(0xFF315B3C) : const Color(0xFFB5C0B4),
          size: 23,
        ),
      ),
    ),
  );

  Widget _farmerStatus(
    IconData icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 220),
    child: Material(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
    super.key,
    required this.center,
    required this.zoom,
    required this.hasLocation,
    required this.waypoints,
    required this.landingPoint,
    required this.drone,
    required this.headingDegrees,
    required this.phone,
    required this.reachedWaypoints,
    required this.nextWaypointIndex,
    required this.waypointMonitoring,
    required this.onTap,
    required this.onMove,
    required this.onMoveStart,
    required this.onSelect,
  });

  final LatLngD center;
  final int zoom;
  final bool hasLocation;
  final List<MissionPoint> waypoints;
  final LatLngD? landingPoint;
  final LatLngD? drone;
  final double? headingDegrees;
  final LatLngD? phone;
  final Set<int> reachedWaypoints;
  final int nextWaypointIndex;
  final bool waypointMonitoring;
  final ValueChanged<LatLngD> onTap;
  final void Function(int, LatLngD) onMove;
  final VoidCallback onMoveStart;
  final ValueChanged<int> onSelect;

  @override
  State<_MissionMap> createState() => _MissionMapState();
}

class _MissionMapState extends State<_MissionMap> {
  Offset? _last;
  LatLngD? _localCenter;
  int? _dragIndex;
  bool _moved = false;
  bool _userMovedMap = false;

  LatLngD get center => _localCenter ?? widget.center;
  double get tileScale => 256 * (1 << widget.zoom).toDouble();

  @override
  void didUpdateWidget(covariant _MissionMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow live drone position until the user deliberately pans the map.
    if (!_userMovedMap && oldWidget.center != widget.center) {
      _localCenter = null;
    }
    if (!widget.hasLocation) {
      _localCenter = null;
      _userMovedMap = false;
    }
  }

  Offset _world(LatLngD point) {
    final lat = point.latitude.clamp(-85.0511, 85.0511) * math.pi / 180;
    return Offset(
      (point.longitude + 180) / 360 * tileScale,
      (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) /
          2 *
          tileScale,
    );
  }

  LatLngD _fromWorld(Offset world) {
    final lon = world.dx / tileScale * 360 - 180;
    final n = math.pi - 2 * math.pi * world.dy / tileScale;
    final safeN = n.clamp(-20.0, 20.0).toDouble();
    final lat = (2 * math.atan(math.exp(safeN)) - math.pi / 2) * 180 / math.pi;
    return LatLngD(lat, lon);
  }

  LatLngD _geo(Offset local, Size size) {
    final centerPx = _world(center);
    return _fromWorld(
      centerPx + Offset(local.dx - size.width / 2, local.dy - size.height / 2),
    );
  }

  List<Widget> _buildSatelliteTiles(Size size) {
    if (!widget.hasLocation) return const [];

    final centerPx = _world(center);
    final firstX = ((centerPx.dx - size.width / 2) / 256).floor();
    final lastX = ((centerPx.dx + size.width / 2) / 256).floor();
    final firstY = ((centerPx.dy - size.height / 2) / 256).floor();
    final lastY = ((centerPx.dy + size.height / 2) / 256).floor();
    final tileCount = 1 << widget.zoom;
    final tiles = <Widget>[];

    for (var tileX = firstX; tileX <= lastX; tileX++) {
      final wrappedX = ((tileX % tileCount) + tileCount) % tileCount;
      for (var tileY = firstY; tileY <= lastY; tileY++) {
        if (tileY < 0 || tileY >= tileCount) continue;
        final left = size.width / 2 + tileX * 256 - centerPx.dx;
        final top = size.height / 2 + tileY * 256 - centerPx.dy;
        final url =
            'https://services.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/${widget.zoom}/$tileY/$wrappedX';
        tiles.add(
          Positioned(
            left: left,
            top: top,
            width: 256,
            height: 256,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) =>
                  Container(color: const Color(0xFFDDE5D7)),
            ),
          ),
        );
      }
    }
    return tiles;
  }

  Color _waypointMarkerColor(int index) {
    if (widget.reachedWaypoints.contains(index)) return const Color(0xFF32B8A2);
    if (widget.waypointMonitoring && widget.nextWaypointIndex == index) {
      return const Color(0xFFF0A638);
    }
    return const Color(0xFF2E914C);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final centerWorld = widget.hasLocation ? _world(center) : Offset.zero;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          if (!_moved && widget.hasLocation) {
            widget.onTap(_geo(details.localPosition, size));
          }
          _moved = false;
        },
        onPanStart: (details) {
          _last = details.localPosition;
          _moved = false;
          _dragIndex = widget.hasLocation
              ? _nearestWaypoint(details.localPosition, size)
              : null;
          if (_dragIndex != null) widget.onMoveStart();
        },
        onPanUpdate: (details) {
          _moved = true;
          if (!widget.hasLocation) return;
          if (_dragIndex != null) {
            widget.onMove(_dragIndex!, _geo(details.localPosition, size));
            return;
          }
          final delta = details.localPosition - _last!;
          _last = details.localPosition;
          final nextWorld = _world(center) - delta;
          setState(() {
            _localCenter = _fromWorld(nextWorld);
            _userMovedMap = true;
          });
        },
        onPanEnd: (_) {
          if (_dragIndex != null) widget.onSelect(_dragIndex!);
          _dragIndex = null;
        },
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(child: Container(color: const Color(0xFFE8EEE3))),
            if (widget.hasLocation) ..._buildSatelliteTiles(size),
            if (!widget.hasLocation)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFE9F0E5), Color(0xFFDCE7D7)],
                    ),
                  ),
                ),
              ),
            if (widget.hasLocation)
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
            if (widget.hasLocation)
              for (var i = 0; i < widget.waypoints.length; i++)
                Positioned.fromRect(
                  rect: _markerRect(
                    _world(
                      LatLngD(
                        widget.waypoints[i].latitude,
                        widget.waypoints[i].longitude,
                      ),
                    ),
                    centerWorld,
                    size,
                  ),
                  child: GestureDetector(
                    onTap: () => widget.onSelect(i),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _waypointMarkerColor(i),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 9,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
            if (widget.hasLocation && widget.landingPoint != null)
              Positioned.fromRect(
                rect: _markerRect(
                  _world(widget.landingPoint!),
                  centerWorld,
                  size,
                ),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF245DA8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.home_rounded,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
              ),
            if (widget.hasLocation && widget.drone != null)
              Positioned.fromRect(
                rect: _markerRect(_world(widget.drone!), centerWorld, size),
                child: Transform.rotate(
                  angle: (widget.headingDegrees ?? 0) * math.pi / 180,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF123B2A),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                ),
              ),
            if (widget.hasLocation && widget.phone != null)
              Positioned.fromRect(
                rect: _markerRect(_world(widget.phone!), centerWorld, size),
                child: const Icon(
                  Icons.person_pin_circle_rounded,
                  color: Color(0xFF2258A5),
                  size: 32,
                  shadows: [Shadow(color: Colors.white, blurRadius: 5)],
                ),
              ),
            if (widget.hasLocation)
              Positioned(
                right: 10,
                bottom: MediaQuery.of(context).size.height * .50 + 20,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xCC10271B),
                    borderRadius: BorderRadius.all(Radius.circular(7)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Text(
                      'Street map © Esri',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Rect _markerRect(Offset point, Offset centerWorld, Size size) {
    final screen = Offset(
      size.width / 2 + point.dx - centerWorld.dx,
      size.height / 2 + point.dy - centerWorld.dy,
    );
    return Rect.fromCenter(center: screen, width: 42, height: 42);
  }

  int? _nearestWaypoint(Offset position, Size size) {
    var nearest = 38.0;
    int? result;
    final c = _world(center);
    for (var i = 0; i < widget.waypoints.length; i++) {
      final point = widget.waypoints[i];
      final rect = _markerRect(
        _world(LatLngD(point.latitude, point.longitude)),
        c,
        size,
      );
      final distance = (rect.center - position).distance;
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
      (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n,
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

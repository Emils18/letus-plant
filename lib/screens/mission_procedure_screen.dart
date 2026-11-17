import 'package:flutter/material.dart';

import '../services/Esp_Cam.dart';
import 'mission_planner_screen.dart';
import 'scan_mode_screen.dart' show DroneReadinessScreen;

const _green = Color(0xFF2F6B3B);
const _ink = Color(0xFF1E2A1F);

/// Guided setup shown before the automatic mission waypoint dashboard.
class MissionProcedureScreen extends StatefulWidget {
  const MissionProcedureScreen({super.key});

  @override
  State<MissionProcedureScreen> createState() => _MissionProcedureScreenState();
}

class _MissionProcedureScreenState extends State<MissionProcedureScreen> {
  final _camera = EspCamService();
  int _step = 0;
  bool _checking = false;
  bool? _cameraReady;

  Future<void> _checkCamera() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ready = await _camera.checkConnection();
    if (mounted) {
      setState(() {
        _cameraReady = ready;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = ['Camera', 'Flight setup', 'Waypoints'];
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        title: const Text('Automatic flight plan'),
        backgroundColor: const Color(0xFFF6FBF7),
        foregroundColor: _ink,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: List.generate(steps.length, (i) {
                return Expanded(
                  child: InkWell(
                    onTap: () {
                      if (i <= _step) setState(() => _step = i);
                    },
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: i <= _step ? _green : Colors.black12,
                          foregroundColor: i <= _step ? Colors.white : _ink,
                          child: Text('${i + 1}'),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          steps[i],
                          style: TextStyle(
                            color: i == _step ? _green : _ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_step == 0) ...[
                  const Text(
                    'Camera check',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The plan collects one picture at each waypoint. Pictures are reviewed together after the route; each waypoint is visited once.',
                    style: TextStyle(fontSize: 16, height: 1.45, color: _ink),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        _cameraReady == true
                            ? Icons.check_circle
                            : Icons.photo_camera,
                        color: _cameraReady == true ? _green : Colors.orange,
                      ),
                      title: Text(
                        _cameraReady == true
                            ? 'Camera ready'
                            : _cameraReady == false
                            ? 'Camera not connected'
                            : 'Camera not checked',
                      ),
                      subtitle: Text(
                        _cameraReady == true
                            ? 'ESP32 camera responded to its status check.'
                            : 'Connect the camera, then check it before planning photos.',
                      ),
                      trailing: _checking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _checking ? null : _checkCamera,
                    icon: const Icon(Icons.refresh),
                    label: const Text('CHECK CAMERA'),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: const Color(0xFFFFF4E5),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Mission photo capture and flight execution are not active yet. The waypoint dashboard saves a plan; start remains locked until aircraft command and safety paths are verified.',
                        style: TextStyle(height: 1.4, color: _ink),
                      ),
                    ),
                  ),
                ] else if (_step == 1) ...[
                  const Text(
                    'Before mapping',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _info(
                    Icons.height,
                    'Set flight altitude and waypoint wait time in mission settings. The wait can be set from 1 to 10 seconds.',
                  ),
                  _info(
                    Icons.battery_alert,
                    'The app currently reads battery voltage only. Early low-battery alerts, automatic return, landing, and safe resume after battery replacement are not connected to flight controls.',
                  ),
                  _info(
                    Icons.home,
                    'Set and test the aircraft’s return-to-home and failsafe behavior in the flight controller before any real flight.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const DroneReadinessScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.monitor_heart_outlined),
                    label: const Text('OPEN DRONE DIAGNOSTICS'),
                  ),
                ] else ...[
                  const Text(
                    'Waypoint dashboard',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap the map to add each stop in route order. Choose the direction using the drone front and tail marker, then adjust that waypoint.',
                    style: TextStyle(fontSize: 16, height: 1.45, color: _ink),
                  ),
                  const SizedBox(height: 14),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.navigation, color: _green, size: 32),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'NOSE / FRONT → route direction\nTAIL / BACK → behind the drone',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                height: 1.5,
                                color: _ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      child: const Text('BACK'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      if (_step < 2) {
                        setState(() => _step++);
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const MissionPlannerScreen(),
                          ),
                        );
                      }
                    },
                    icon: Icon(_step == 2 ? Icons.map : Icons.arrow_forward),
                    label: Text(_step == 2 ? 'OPEN WAYPOINT MAP' : 'CONTINUE'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(IconData icon, String text) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(height: 1.4, color: _ink)),
          ),
        ],
      ),
    ),
  );
}

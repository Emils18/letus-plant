import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mission_planner_screen.dart';

const _green = Color(0xFF2F6B3B);
const _ink = Color(0xFF1E2A1F);
const _page = Color(0xFFF5F8F3);

/// Guided setup for the existing route planner. Flight execution remains locked
/// until the aircraft command and safety paths are independently verified.
class MissionProcedureScreen extends StatefulWidget {
  const MissionProcedureScreen({super.key});

  @override
  State<MissionProcedureScreen> createState() => _MissionProcedureScreenState();
}

class _MissionProcedureScreenState extends State<MissionProcedureScreen> {
  int _step = 0;
  int _altitudeFeet = 6;
  bool _positionConfirmed = false;

  Future<void> _openPlanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mapping_altitude_feet', _altitudeFeet);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            MissionPlannerScreen(mappingAltitudeFeet: _altitudeFeet),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['Set up drone', 'Choose height', 'Plan route'];
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Automatic Flight Plan'),
        backgroundColor: _page,
        foregroundColor: _ink,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: List.generate(titles.length, (index) {
                final active = index == _step;
                final complete = index < _step;
                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: complete
                        ? () => setState(() => _step = index)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: active || complete
                                ? _green
                                : Colors.black12,
                            foregroundColor: active || complete
                                ? Colors.white
                                : _ink,
                            child: complete
                                ? const Icon(Icons.check, size: 17)
                                : Text('${index + 1}'),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            titles[index],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: active
                                  ? FontWeight.w900
                                  : FontWeight.w600,
                              color: active ? _green : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
              children: [
                if (_step == 0) _placementStep(),
                if (_step == 1) _altitudeStep(),
                if (_step == 2) _planStep(),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      child: const Text('BACK'),
                    ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _step == 0 && !_positionConfirmed
                        ? null
                        : _step < 2
                        ? () => setState(() => _step++)
                        : _openPlanner,
                    icon: Icon(
                      _step == 2
                          ? Icons.map_outlined
                          : Icons.arrow_forward_rounded,
                    ),
                    label: Text(
                      _step == 2 ? 'OPEN WAYPOINT PLANNER' : 'CONTINUE',
                    ),
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

  Widget _placementStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Place your drone at the center of the field',
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: _ink,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Set it on a flat, stable surface with clear space around it. Keep it still during setup.',
        style: TextStyle(fontSize: 16, height: 1.45, color: _ink),
      ),
      const SizedBox(height: 18),
      _fieldIllustration(),
      const SizedBox(height: 14),
      Card(
        color: Colors.white,
        child: CheckboxListTile(
          value: _positionConfirmed,
          activeColor: _green,
          onChanged: (value) =>
              setState(() => _positionConfirmed = value ?? false),
          title: const Text(
            'I have positioned my drone',
            style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
          ),
          subtitle: const Text(
            'This confirms your placement only. It does not start the drone.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      ),
    ],
  );

  Widget _fieldIllustration() => Container(
    height: 220,
    decoration: BoxDecoration(
      color: const Color(0xFFE8F0E2),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFD2E1CB)),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        for (var i = 0; i < 5; i++)
          Positioned(
            left: 18 + i * 13,
            right: 18 + i * 13,
            top: 28,
            bottom: 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                4,
                (_) => const Icon(
                  Icons.eco_rounded,
                  color: Color(0xFF75A65B),
                  size: 21,
                ),
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .12),
                blurRadius: 18,
              ),
            ],
          ),
          child: const Icon(Icons.flight_rounded, color: _green, size: 42),
        ),
        const Positioned(
          bottom: 12,
          child: Text(
            'CENTER OF YOUR FIELD',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w900,
              color: _ink,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _altitudeStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Choose a mapping height',
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: _ink,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'This is a draft preference for field mapping. The app has not verified which heights your aircraft can safely hold.',
        style: TextStyle(fontSize: 16, height: 1.45, color: _ink),
      ),
      const SizedBox(height: 20),
      Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text(
                '$_altitudeFeet ft',
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: _green,
                ),
              ),
              Slider(
                value: _altitudeFeet.toDouble(),
                min: 1,
                max: 6,
                divisions: 5,
                label: '$_altitudeFeet ft',
                activeColor: _green,
                onChanged: (value) =>
                    setState(() => _altitudeFeet = value.round()),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('1 ft'), Text('6 ft')],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      _notice(
        'Flight is not enabled',
        'Altitude hold, obstacle clearance, and camera focus limits are not verified by the app. This choice will be saved for planning only.',
      ),
    ],
  );

  Widget _planStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Waypoint planning',
        style: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w900,
          color: _ink,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Mark each lettuce area on the map, choose a safe landing point, then save your route for review.',
        style: TextStyle(fontSize: 16, height: 1.45, color: _ink),
      ),
      const SizedBox(height: 18),
      _info(Icons.height, 'Draft field-mapping height: $_altitudeFeet ft.'),
      _info(
        Icons.map_outlined,
        'Tap the map to add a stop. You can move or remove stops before saving.',
      ),
      _info(
        Icons.lock_outline,
        'The planner saves this route on your phone. The flight controller command link is not enabled yet.',
      ),
      const SizedBox(height: 12),
      _notice(
        'Route plan only',
        'Use the dashboard to prepare and review the field route. This screen does not start the aircraft.',
      ),
    ],
  );

  Widget _notice(String title, String detail) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3DC),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFFFDDA3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: Color(0xFF8A5A00)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(detail, style: const TextStyle(height: 1.4, color: _ink)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _info(IconData icon, String text) => Card(
    color: Colors.white,
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

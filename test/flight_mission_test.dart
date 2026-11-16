import 'package:flutter_test/flutter_test.dart';
import 'package:letus_plant/models/flight_mission.dart';

void main() {
  test('mission round trips through local JSON persistence', () {
    const mission = FlightMission(
      name: 'North field',
      waypoints: [
        MissionPoint(latitude: 14.5, longitude: 121.0, hoverSeconds: 10),
      ],
    );

    final restored = FlightMission.decode(mission.encode());

    expect(restored.name, 'North field');
    expect(restored.waypoints, hasLength(1));
    expect(restored.waypoints.single.latitude, 14.5);
    expect(restored.waypoints.single.hoverSeconds, 10);
  });

  test('validation reports invalid coordinates and mission speed', () {
    const mission = FlightMission(
      speedMetersPerSecond: 30,
      waypoints: [MissionPoint(latitude: 91, longitude: 181)],
    );

    expect(
      mission.validate(),
      containsAll([
        'Waypoint 1 has invalid coordinates.',
        'Maximum speed must be between 0 and 20 m/s.',
      ]),
    );
  });

  test('position hold uses the requested ten second default', () {
    const point = MissionPoint(latitude: 14, longitude: 120);
    expect(point.hoverSeconds, 10);
  });
}

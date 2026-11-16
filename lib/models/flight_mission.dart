import 'dart:convert';

class MissionPoint {
  const MissionPoint({
    required this.latitude,
    required this.longitude,
    this.altitudeMeters = 1.8288,
    this.speedMetersPerSecond = 3,
    this.hoverSeconds = 10,
  });

  final double latitude;
  final double longitude;
  final double altitudeMeters;
  final double speedMetersPerSecond;
  final int hoverSeconds;

  Map<String, Object> toJson() => {
    'lat': latitude,
    'lon': longitude,
    'alt': altitudeMeters,
    'speed': speedMetersPerSecond,
    'hover': hoverSeconds,
  };

  factory MissionPoint.fromJson(Map<String, dynamic> json) => MissionPoint(
    latitude: (json['lat'] as num).toDouble(),
    longitude: (json['lon'] as num).toDouble(),
    altitudeMeters: ((json['alt'] as num?)?.toDouble() ?? 1.8288)
        .clamp(0.3048, 1.8288)
        .toDouble(),
    speedMetersPerSecond: (json['speed'] as num?)?.toDouble() ?? 3,
    hoverSeconds: (json['hover'] as num?)?.toInt() ?? 10,
  );
}

class FlightMission {
  const FlightMission({
    this.name = 'Field survey',
    this.takeoffAltitudeMeters = 3,
    this.altitudeMeters = 1.8288,
    this.speedMetersPerSecond = 3,
    this.hoverSeconds = 10,
    this.returnAltitudeMeters = 20,
    this.returnHome = true,
    this.landOnCompletion = true,
    this.batteryReservePercent = 30,
    this.capturePhotoAtEachWaypoint = true,
    this.cameraSettleSeconds = 3,
    this.waypoints = const [],
  });

  final String name;
  final double takeoffAltitudeMeters;
  final double altitudeMeters;
  final double speedMetersPerSecond;
  final int hoverSeconds;
  final double returnAltitudeMeters;
  final bool returnHome;
  final bool landOnCompletion;
  final int batteryReservePercent;
  final bool capturePhotoAtEachWaypoint;
  final int cameraSettleSeconds;
  final List<MissionPoint> waypoints;

  FlightMission copyWith({
    String? name,
    double? takeoffAltitudeMeters,
    double? altitudeMeters,
    double? speedMetersPerSecond,
    int? hoverSeconds,
    double? returnAltitudeMeters,
    bool? returnHome,
    bool? landOnCompletion,
    int? batteryReservePercent,
    bool? capturePhotoAtEachWaypoint,
    int? cameraSettleSeconds,
    List<MissionPoint>? waypoints,
  }) => FlightMission(
    name: name ?? this.name,
    takeoffAltitudeMeters: takeoffAltitudeMeters ?? this.takeoffAltitudeMeters,
    altitudeMeters: altitudeMeters ?? this.altitudeMeters,
    speedMetersPerSecond: speedMetersPerSecond ?? this.speedMetersPerSecond,
    hoverSeconds: hoverSeconds ?? this.hoverSeconds,
    returnAltitudeMeters: returnAltitudeMeters ?? this.returnAltitudeMeters,
    returnHome: returnHome ?? this.returnHome,
    landOnCompletion: landOnCompletion ?? this.landOnCompletion,
    batteryReservePercent: batteryReservePercent ?? this.batteryReservePercent,
    capturePhotoAtEachWaypoint:
        capturePhotoAtEachWaypoint ?? this.capturePhotoAtEachWaypoint,
    cameraSettleSeconds: cameraSettleSeconds ?? this.cameraSettleSeconds,
    waypoints: waypoints ?? this.waypoints,
  );

  List<String> validate() {
    final errors = <String>[];
    if (name.trim().isEmpty) errors.add('Enter a mission name.');
    if (takeoffAltitudeMeters < 1.8288 || takeoffAltitudeMeters > 100) {
      errors.add('Takeoff altitude must be at least 6 ft and at most 100 m.');
    }
    if (altitudeMeters < 0.3048 || altitudeMeters > 1.8288) {
      errors.add('Mission waypoint altitude must be between 1 and 6 ft.');
    }
    if (speedMetersPerSecond <= 0 || speedMetersPerSecond > 20) {
      errors.add('Maximum speed must be between 0 and 20 m/s.');
    }
    if (hoverSeconds < 1 || hoverSeconds > 10) {
      errors.add('Waypoint wait must be between 1 and 10 seconds.');
    }
    if (returnAltitudeMeters < 1.8288 || returnAltitudeMeters > 500) {
      errors.add('Return altitude must be at least 6 ft and at most 500 m.');
    }
    if (waypoints.isEmpty) errors.add('Add at least one waypoint.');
    if (waypoints.length > 60) {
      errors.add('INAV supports at most 60 mission points.');
    }
    for (var i = 0; i < waypoints.length; i++) {
      final point = waypoints[i];
      if (!point.latitude.isFinite ||
          point.latitude < -90 ||
          point.latitude > 90 ||
          !point.longitude.isFinite ||
          point.longitude < -180 ||
          point.longitude > 180) {
        errors.add('Waypoint ${i + 1} has invalid coordinates.');
      }
      if (point.altitudeMeters < 0.3048 || point.altitudeMeters > 1.8288) {
        errors.add('Waypoint ${i + 1} altitude must be between 1 and 6 ft.');
      }
      if (point.speedMetersPerSecond <= 0 || point.speedMetersPerSecond > 20) {
        errors.add('Waypoint ${i + 1} speed must be between 0 and 20 m/s.');
      }
      if (point.hoverSeconds < 1 || point.hoverSeconds > 10) {
        errors.add('Waypoint ${i + 1} wait must be between 1 and 10 seconds.');
      }
    }
    if (batteryReservePercent < 10 || batteryReservePercent > 80) {
      errors.add('Battery reserve must be between 10% and 80%.');
    }
    if (cameraSettleSeconds < 0 || cameraSettleSeconds > 60) {
      errors.add('Camera settle time must be between 0 and 60 seconds.');
    }
    if (capturePhotoAtEachWaypoint &&
        waypoints.any((point) => point.hoverSeconds < cameraSettleSeconds)) {
      errors.add(
        'Waypoint hold must be at least as long as camera settle time.',
      );
    }
    return errors;
  }

  Map<String, Object> toJson() => {
    'name': name,
    'takeoffAltitude': takeoffAltitudeMeters,
    'altitude': altitudeMeters,
    'speed': speedMetersPerSecond,
    'hover': hoverSeconds,
    'returnAltitude': returnAltitudeMeters,
    'returnHome': returnHome,
    'landOnCompletion': landOnCompletion,
    'batteryReserve': batteryReservePercent,
    'capturePhotoAtEachWaypoint': capturePhotoAtEachWaypoint,
    'cameraSettleSeconds': cameraSettleSeconds,
    'waypoints': waypoints.map((point) => point.toJson()).toList(),
  };

  factory FlightMission.fromJson(Map<String, dynamic> json) => FlightMission(
    name: json['name'] as String? ?? 'Field survey',
    takeoffAltitudeMeters: (json['takeoffAltitude'] as num?)?.toDouble() ?? 3,
    altitudeMeters: ((json['altitude'] as num?)?.toDouble() ?? 1.8288)
        .clamp(0.3048, 1.8288)
        .toDouble(),
    speedMetersPerSecond: (json['speed'] as num?)?.toDouble() ?? 3,
    hoverSeconds: (json['hover'] as num?)?.toInt() ?? 10,
    returnAltitudeMeters: (json['returnAltitude'] as num?)?.toDouble() ?? 20,
    returnHome: json['returnHome'] as bool? ?? true,
    landOnCompletion: json['landOnCompletion'] as bool? ?? true,
    batteryReservePercent: (json['batteryReserve'] as num?)?.toInt() ?? 30,
    capturePhotoAtEachWaypoint:
        json['capturePhotoAtEachWaypoint'] as bool? ?? true,
    cameraSettleSeconds: (json['cameraSettleSeconds'] as num?)?.toInt() ?? 3,
    waypoints: (json['waypoints'] as List<dynamic>? ?? const [])
        .map(
          (item) =>
              MissionPoint.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );

  String encode() => jsonEncode(toJson());
  static FlightMission decode(String source) =>
      FlightMission.fromJson(jsonDecode(source) as Map<String, dynamic>);
}

/// Network endpoints used by the GreenGuard app.
///
/// Contabo runs the Flask inference service on its configured service port.
/// Override at release time with:
/// --dart-define=GREENGUARD_AI_BASE_URL=http://host:port
class GreenGuardNetworkConfig {
  GreenGuardNetworkConfig._();

  static const String aiServerBaseUrl = String.fromEnvironment(
    'GREENGUARD_AI_BASE_URL',
    defaultValue: 'http://185.133.48.73:5000',
  );

  static const String soilDiscoveryMessage =
      'GREENGUARD_SOIL_DISCOVERY_V1';
  static const int soilDiscoveryPort = 45821;
  static const String soilDeviceName = 'GreenGuard-SOIL-01';

  static const String cameraDeviceName = 'GreenGuard-CAM-01';
  static const int cameraDiscoveryPort = 8765;
}

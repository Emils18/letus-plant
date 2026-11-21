/// Network endpoints used by the GreenGuard app.
///
/// The verified Contabo endpoint is served through Nginx on HTTP port 80.
/// Override at release time (prefer HTTPS for direct clients) with:
/// --dart-define=GREENGUARD_AI_BASE_URL=https://your-ai-host
class GreenGuardNetworkConfig {
  GreenGuardNetworkConfig._();

  static const String aiServerBaseUrl = String.fromEnvironment(
    'GREENGUARD_AI_BASE_URL',
    defaultValue: 'http://185.133.48.73',
  );

  static const String soilDiscoveryMessage =
      'GREENGUARD_SOIL_DISCOVERY_V1';
  static const int soilDiscoveryPort = 45821;
  static const String soilDeviceName = 'GreenGuard-SOIL-01';

  static const String cameraDeviceName = 'GreenGuard-CAM-01';
  static const int cameraDiscoveryPort = 8765;
}

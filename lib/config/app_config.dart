class AppConfig {
  static const bool isDemoMode = false;

  /// WeatherAPI.com Key
  static const String weatherApiKey = 'b0c48f9b43c44a919de41229260407';

  /// Central GreenGuard AI Server configuration.
  /// Defaults to the deployed VPS server. Can be overridden via --dart-define=GREENGUARD_AI_BASE_URL=...
  static const String defaultAiBaseUrl = 'http://185.133.48.73';
  static const String aiBaseUrl = String.fromEnvironment(
    'GREENGUARD_AI_BASE_URL',
    defaultValue: defaultAiBaseUrl,
  );
}
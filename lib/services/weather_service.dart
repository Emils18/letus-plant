import '../config/app_config.dart';

class WeatherService {
  Future<Map<String, dynamic>> fetchWeather() async {
    if (AppConfig.isDemoMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      return {
        'temp': '24°C',
        'humidity': '78%',
        'condition': 'Partly Cloudy',
        'rain_chance': '20%',
        'recommendation': 'Weather is optimal for lettuce growth. No immediate action required.',
        'planted_weather': '22°C Sunny', // Historical mock
      };
    }
    // TODO: Implement real OpenWeather/WeatherAPI fetch here
    return {};
  }
}
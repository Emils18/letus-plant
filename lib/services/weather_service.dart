import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class WeatherService {
  
  Future<Map<String, dynamic>> fetchWeather({required String location}) async {
    final query = location.trim();
    if (query.isEmpty) throw ArgumentError('Choose a weather location.');
    final url = Uri.https('api.weatherapi.com', '/v1/forecast.json', {
      'key': AppConfig.weatherApiKey,
      'q': query,
      'days': '1',
      'aqi': 'no',
      'alerts': 'no',
    });
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Weather is unavailable for this location.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final area = data['location'] as Map<String, dynamic>?;
    final current = data['current'] as Map<String, dynamic>?;
    final forecast = data['forecast']?['forecastday'] as List?;
    final day = forecast?.isNotEmpty == true ? forecast!.first['day'] : null;
    final city = area?['name'] as String?;
    final region = area?['region'] as String?;
    final temperature = current?['temp_c'] as num?;
    final humidity = current?['humidity'] as num?;
    final condition = current?['condition']?['text'] as String?;
    if (city == null || city.isEmpty || temperature == null ||
        humidity == null || condition == null || condition.isEmpty) {
      throw StateError('The weather service returned incomplete data.');
    }
    final rain = day?['daily_chance_of_rain'] as num?;
    final low = day?['mintemp_c'] as num?;
    final high = day?['maxtemp_c'] as num?;
    final forecastCondition = day?['condition']?['text'] as String?;
    return {
      'location': [city, if (region != null && region.isNotEmpty && region != city) region].join(', '),
      'temp': '${temperature.toStringAsFixed(1)}°C',
      'humidity': '${humidity.round()}%',
      'condition': condition,
      if (rain != null) 'rain_chance': '${rain.round()}%',
      if (low != null && high != null) 'forecast':
        ['${low.round()}°C to ${high.round()}°C', if (forecastCondition != null) forecastCondition].join(' · '),
      'updated_at': current?['last_updated'],
      'recommendation': _getRecommendation(temperature.round(), humidity.round(), condition, condition),
    };
  }

  String _getRecommendation(int temp, int humidity, String condition, String description) {
    final cond = condition.toLowerCase();
    final desc = description.toLowerCase();

    if (humidity >= 75) {
      return 'High humidity detected. Monitor lettuce leaves for fungal disease symptoms.';
    }
    if (cond.contains('rain') || desc.contains('rain')) {
      return 'Rain is detected. Avoid unnecessary watering and check farm drainage.';
    }
    if (cond.contains('cloud') || desc.contains('cloud')) {
      return 'Cloudy conditions today. Inspect leaves for prolonged moisture.';
    }
    if (temp >= 30) {
      return 'High temperature detected. Water during cooler hours and monitor heat stress.';
    }
    return 'Current weather conditions are stable. Continue normal crop monitoring.';
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class WeatherService {
  Future<Map<String, dynamic>> fetchWeather({
    required double latitude,
    required double longitude,
  }) async {
    if (!latitude.isFinite || latitude < -90 || latitude > 90 ||
        !longitude.isFinite || longitude < -180 || longitude > 180) {
      return _getErrorData('Location unavailable. Allow location access and try again.');
    }

    final apiKey = AppConfig.weatherApiKey;
    if (apiKey.isEmpty) return _getErrorData('Weather service is not configured.');

    try {
      final uri = Uri.https('api.weatherapi.com', '/v1/forecast.json', {
        'key': apiKey,
        'q': '$latitude,$longitude',
        'days': '1',
        'aqi': 'no',
        'alerts': 'no',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data is! Map || data['error'] != null) {
        return _getErrorData('Unable to load weather for your current location.');
      }

      final current = data['current'] as Map? ?? {};
      final location = data['location'] as Map? ?? {};
      final temperatureValue = current['temp_c'];
      final humidityValue = current['humidity'];
      final conditionValue = current['condition']?['text'];
      if (temperatureValue is! num || humidityValue is! num ||
          conditionValue == null || conditionValue.toString().trim().isEmpty) {
        return _getErrorData('Weather details are unavailable for your current location.');
      }
      final conditionText = conditionValue.toString();
      final temperature = temperatureValue.round();
      final humidity = humidityValue.toString();
      final rainChance = data['forecast']?['forecastday']?[0]?['day']?['daily_chance_of_rain'] ?? 'N/A';
      final providerLocation = [location['name'], location['region'], location['country']]
          .where((part) => part is String && part.trim().isNotEmpty)
          .join(', ');

      return {
        'location': providerLocation.isEmpty ? 'Location name unavailable' : providerLocation,
        'temp': '${temperature}\u00B0C',
        'humidity': '$humidity%',
        'condition': conditionText.split(' ').first,
        'description': conditionText,
        'rain_chance': '$rainChance%',
        'updated_at': current['last_updated']?.toString(),
        'time_zone': location['tz_id']?.toString(),
        'fetched_at': DateTime.now().toIso8601String(),
        'recommendation': _getRecommendation(temperature, humidity, conditionText),
        'planted_weather': '${temperature}\u00B0C ${conditionText.split(' ').first}',
      };
    } catch (error) {
      debugPrint('Weather request failed: $error');
      return _getErrorData('Unable to load weather for your current location.');
    }
  }

  Map<String, dynamic> _getErrorData(String message) => {
        'error': true,
        'temp': 'N/A',
        'humidity': 'N/A',
        'condition': 'Unavailable',
        'rain_chance': 'N/A',
        'recommendation': message,
        'planted_weather': 'N/A',
      };

  String _getRecommendation(int temp, String humidityValue, String description) {
    final humidity = int.tryParse(humidityValue) ?? 0;
    final condition = description.toLowerCase();
    if (humidity >= 75) {
      return 'High humidity detected. Monitor lettuce leaves for fungal disease symptoms.';
    }
    if (condition.contains('rain')) {
      return 'Rain is detected. Avoid unnecessary watering and check farm drainage.';
    }
    if (condition.contains('cloud')) {
      return 'Cloudy conditions today. Inspect leaves for prolonged moisture.';
    }
    if (temp >= 30) {
      return 'High temperature detected. Water during cooler hours and monitor heat stress.';
    }
    return 'Current weather conditions are stable. Continue normal crop monitoring.';
  }
}

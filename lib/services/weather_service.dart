import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class WeatherService {
  
  Future<Map<String, dynamic>> fetchWeather({String? location}) async {
    if (AppConfig.isDemoMode) {
      await Future.delayed(const Duration(milliseconds: 400));
      return _getDemoData();
    }

    if (location == null || location.trim().isEmpty) {
      return _getErrorData('No farm location found. Please update your product location.');
    }

    final apiKey = AppConfig.weatherApiKey;
    if (apiKey.isEmpty) {
      return _getErrorData('Missing API key');
    }

    // Try the original location first
    final locationsToTry = [
      location.trim(),
      '${location.trim()}, Cebu, PH',
      '${location.trim()}, Philippines',
    ];

    for (final loc in locationsToTry) {
      try {
        final url = Uri.parse(
          'https://api.weatherapi.com/v1/current.json?key=$apiKey&q=$loc&aqi=no',
        );

        final response = await http.get(url).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);

          final temp = (data['current']['temp_c'] as num).round();
          final humidity = data['current']['humidity'];
          final conditionText = data['current']['condition']['text'] ?? 'Unknown';
          final windKph = data['current']['wind_kph'] ?? 0;

          final condition = conditionText.split(' ').first;
          final description = conditionText;

          return {
            'temp': '$temp°C',
            'humidity': '$humidity%',
            'condition': condition,
            'rain_chance': '${(windKph / 3.6).round()}%',
            'recommendation': _getRecommendation(temp, humidity, condition, description),
            'planted_weather': '$temp°C $condition',
          };
        }
      } catch (e) {
        debugPrint('WeatherService try failed for "$loc": $e');
      }
    }

    // All attempts failed
    return _getErrorData('Could not find weather for your farm location.');
  }

  Map<String, dynamic> _getDemoData() {
    return {
      'temp': '22°C',
      'humidity': '69%',
      'condition': 'Clouds',
      'rain_chance': '27%',
      'recommendation': 'Cloudy conditions today. Inspect leaves for prolonged moisture.',
      'planted_weather': '22°C Clouds',
    };
  }

  Map<String, dynamic> _getErrorData(String message) {
    return {
      'temp': 'N/A',
      'humidity': 'N/A',
      'condition': 'Error',
      'rain_chance': 'N/A',
      'recommendation': message,
      'planted_weather': 'N/A',
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
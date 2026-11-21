import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/weather_service.dart';
import '../widgets/recommendation_card.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final WeatherService _service = WeatherService();
  Map<String, dynamic>? data;
  String? _weatherError;
  bool _isLoading = true;
  Timer? _weatherRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _weatherRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _loadWeather(),
    );
  }

  @override
  void dispose() {
    _weatherRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadWeather() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      data = null;
      _weatherError = null;
    });
    try {
      final position = await _getCurrentPosition();
      final result = await _service.fetchWeather(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      setState(() {
        if (result['error'] == true) {
          _weatherError = result['recommendation']?.toString();
          data = null;
        } else {
          data = result;
          _weatherError = null;
        }
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        data = null;
        _weatherError = error is _LocationUnavailable
            ? 'Location unavailable. Allow location access and try again.'
            : 'Unable to load current weather. Check your connection and retry.';
        _isLoading = false;
      });
    }
  }

  Future<Position> _getCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationUnavailable();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const _LocationUnavailable();
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on _LocationUnavailable {
      rethrow;
    } catch (_) {
      throw const _LocationUnavailable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Weather Tracking',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E2A1F)),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F)),
        actions: [
          IconButton(
            tooltip: 'Refresh current location and weather',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : () => _loadWeather(),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF2F6B3B),
        onRefresh: () => _loadWeather(),
        child: _isLoading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 260),
                  Center(child: CircularProgressIndicator(color: Color(0xFF2F6B3B))),
                  SizedBox(height: 16),
                  Center(child: Text('Finding your location and loading weather...')),
                ],
              )
            : data == null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(28),
                    children: [
                      const SizedBox(height: 120),
                      const Icon(Icons.location_off_rounded, size: 52, color: Color(0xFF66816B)),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          _weatherError?.startsWith('Location unavailable') == true
                              ? 'Location unavailable'
                              : 'Weather unavailable',
                          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _weatherError ?? 'Allow location access to see weather for your current area.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF526254)),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: FilledButton.icon(
                          onPressed: () => _loadWeather(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry location'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2F6B3B),
                            minimumSize: const Size(190, 52),
                          ),
                        ),
                      ),
                    ],
                  )
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.lightBlue, Colors.blue],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(color: Colors.blue.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.wb_cloudy_rounded, size: 60, color: Colors.white),
                              const SizedBox(height: 16),
                              Text(data!['temp'] ?? 'N/A', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white)),
                              Text(data!['condition'] ?? 'N/A', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)),
                              const SizedBox(height: 8),
                              Text(
                                data!['location']?.toString() ?? 'Location name unavailable',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            Expanded(child: _StatCard(title: 'Humidity', value: data!['humidity'] ?? 'N/A', icon: Icons.water_drop, color: Colors.blue)),
                            const SizedBox(width: 16),
                            Expanded(child: _StatCard(title: 'Rain Chance', value: data!['rain_chance'] ?? 'N/A', icon: Icons.umbrella, color: Colors.indigo)),
                          ],
                        ),
                        const SizedBox(height: 32),
                        const Text('Agricultural Impact', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
                        const SizedBox(height: 16),
                        RecommendationCard(text: data!['recommendation'] ?? 'No recommendation available.'),
                        const SizedBox(height: 24),
                        Center(
                          child: Text(
                            'Weather time (${data!['time_zone'] ?? 'provider local time'}): ${data!['updated_at'] ?? 'Not provided'}\nChecked on this device: ${_formatFetchedAt(data!['fetched_at'])}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _LocationUnavailable implements Exception {
  const _LocationUnavailable();
}

String _formatFetchedAt(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date?.toLocal().toString() ?? 'Not available';
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
        ],
      ),
    );
  }
}

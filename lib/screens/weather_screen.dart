import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final SupabaseClient _supabase = Supabase.instance.client;

  Map<String, dynamic>? data;
  DateTime? _lastUpdated;
  bool _isLoading = true;
  String _locationSource = '';
  Timer? _weatherRefreshTimer;
  StreamSubscription<Position>? _movement;
  bool _requesting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWeatherWithFallback();
    _weatherRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) => _loadWeatherWithFallback(showSpinner: false));
  }

  @override
  void dispose() {
    _weatherRefreshTimer?.cancel();
    _movement?.cancel();
    super.dispose();
  }

  Future<void> _loadWeatherWithFallback({bool showSpinner = true}) async {
    if (_requesting || !mounted) return;
    _requesting = true;
    if (showSpinner && data == null) setState(() => _isLoading = true);
    try {
      String? query;
      try {
        query = await _currentCoordinates(requestPermission: showSpinner);
      } catch (error) {
        debugPrint('Current location unavailable: $error');
      }
      final source = query == null ? 'Saved farm location' : 'Current location';
      if (query != null && mounted) {
        _movement ??= Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 1000,
          ),
        ).listen(
          (_) {
            if (mounted && ModalRoute.of(context)?.isCurrent == true) {
              unawaited(_loadWeatherWithFallback(showSpinner: false));
            }
          },
          onError: (Object error) => debugPrint('Weather location updates stopped: $error'),
        );
      }
      query ??= await _savedLocation();
      if (query == null) {
        if (mounted) setState(() {
          data = null;
          _error = 'Allow location access and switch on GPS, then tap Refresh.';
        });
        return;
      }
      final result = await _service.fetchWeather(location: query);
      if (!mounted) return;
      setState(() {
        data = result;
        _locationSource = source;
        _lastUpdated = DateTime.tryParse(result['updated_at']?.toString() ?? '');
        _error = null;
      });
    } catch (error) {
      debugPrint('Weather request failed: $error');
      if (mounted) setState(() {
        data = null;
        _error = 'Could not load weather. Check your connection and try again.';
      });
    } finally {
      _requesting = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _currentCoordinates({required bool requestPermission}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return '${position.latitude.toStringAsFixed(3)},${position.longitude.toStringAsFixed(3)}';
  }

  Future<String?> _savedLocation() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    for (final source in [('products', 'farmer_id'), ('diagnostic_logs', 'user_id')]) {
      final rows = await _supabase.from(source.$1).select('location')
          .eq(source.$2, user.id).not('location', 'is', null)
          .order('created_at', ascending: false).limit(10);
      for (final row in rows) {
        final location = row['location']?.toString().trim() ?? '';
        if (location.isNotEmpty && !['n/a', 'unknown', 'local farm'].contains(location.toLowerCase())) {
          return location;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text('Weather Tracking', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1E2A1F))),
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadWeatherWithFallback,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF2F6B3B),
        onRefresh: _loadWeatherWithFallback,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF2F6B3B)))
            : data == null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [Text(_error ?? 'Weather is unavailable.'),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _loadWeatherWithFallback, child: const Text('Try again'))],
                  )
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Main Weather Card
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
                              BoxShadow(
                                color: Colors.blue.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.wb_cloudy_rounded, size: 60, color: Colors.white),
                              const SizedBox(height: 16),
                              Text(
                                data!['temp'] ?? 'N/A',
                                style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white),
                              ),
                              Text(
                                data!['condition'] ?? 'N/A',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
                              ),
                              Text(data!['location'] ?? '', textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                              if (_locationSource.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _locationSource,
                                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Humidity & Rain Chance
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: 'Humidity',
                                value: data!['humidity'] ?? 'N/A',
                                icon: Icons.water_drop,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _StatCard(
                                title: 'Rain Chance',
                                value: data!['rain_chance'] ?? 'N/A',
                                icon: Icons.umbrella,
                                color: Colors.indigo,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        if (data!['forecast'] case final String forecast)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Text('Today: $forecast', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          ),

                        // Agricultural Impact
                        const Text(
                          'Agricultural Impact',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F)),
                        ),
                        const SizedBox(height: 16),
                        RecommendationCard(text: data!['recommendation'] ?? 'No recommendation available.'),

                        const SizedBox(height: 24),

                        if (_lastUpdated != null)
                          Center(
                            child: Text(
                              'Last updated: ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F)),
          ),
        ],
      ),
    );
  }
}

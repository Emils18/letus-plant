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

  @override
  void initState() {
    super.initState();
    _loadWeatherWithFallback();
  }

  /// Main method: Try farmer location → GPS fallback
  Future<void> _loadWeatherWithFallback() async {
    setState(() => _isLoading = true);

    String? locationToUse;

    // 1. Try to get location from farmer's products or health logs
    final user = _supabase.auth.currentUser;
    if (user != null) {
      // Try Products first
      final product = await _supabase
          .from('products')
          .select('location')
          .eq('farmer_id', user.id)
          .not('location', 'is', null)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (product != null && product['location'] != null) {
        locationToUse = product['location'].toString().trim();
        _locationSource = 'From your products';
      }

      // If still no location, try Health Logs
      if (locationToUse == null || locationToUse.isEmpty) {
        final log = await _supabase
            .from('diagnostic_logs')
            .select('location')
            .eq('user_id', user.id)
            .not('location', 'is', null)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (log != null && log['location'] != null) {
          locationToUse = log['location'].toString().trim();
          _locationSource = 'From your health logs';
        }
      }
    }

    // 2. GPS Fallback if no farmer location found
    if (locationToUse == null || locationToUse.isEmpty) {
      try {
        final position = await _getCurrentPosition();
        if (position != null) {
          locationToUse = '${position.latitude},${position.longitude}';
          _locationSource = 'Using your current location (GPS)';
        }
      } catch (e) {
        debugPrint('GPS Error: $e');
      }
    }

    // 3. Load weather
    final result = await _service.fetchWeather(location: locationToUse);
    setState(() {
      data = result;
      _lastUpdated = DateTime.now();
      _isLoading = false;
    });
  }

  /// Get current device GPS location
  Future<Position?> _getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
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
                ? const Center(child: Text('Unable to load weather'))
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
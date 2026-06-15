import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    final result = await _service.fetchWeather();
    setState(() => data = result);
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
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2F6B3B)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.lightBlue, Colors.blue], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.wb_cloudy_rounded, size: 60, color: Colors.white),
                        const SizedBox(height: 16),
                        Text(data!['temp'], style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white)),
                        Text(data!['condition'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(title: 'Humidity', value: data!['humidity'], icon: Icons.water_drop, color: Colors.blue),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(title: 'Rain Chance', value: data!['rain_chance'], icon: Icons.umbrella, color: Colors.indigo),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text('Agricultural Impact', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
                  const SizedBox(height: 16),
                  RecommendationCard(text: data!['recommendation']),
                ],
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

  const _StatCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 15)]),
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
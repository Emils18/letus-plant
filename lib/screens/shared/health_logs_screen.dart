import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HealthLogsScreen extends StatefulWidget {
  const HealthLogsScreen({
    super.key,
    this.farmerId,
    this.productName,
    this.readOnlyBuyer = false,
    this.title,
  });

  final String? farmerId;
  final String? productName;
  final bool readOnlyBuyer;
  final String? title;

  @override
  State<HealthLogsScreen> createState() => _HealthLogsScreenState();
}

class _HealthLogsScreenState extends State<HealthLogsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadHealthLogs();
  }

  Future<void> _loadHealthLogs() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No logged-in user.');

      dynamic query = _supabase.from('diagnostic_logs').select('*');

      if (widget.readOnlyBuyer && widget.farmerId != null) {
        query = query.eq('user_id', widget.farmerId!);
      } else {
        query = query.eq('user_id', user.id);
      }

      final data = await query.order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _logs = List<Map<String, dynamic>>.from(data);
      });
    } catch (error) {
      if (mounted) _showSnack('Failed to load health logs', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _getText(Map<String, dynamic> log, List<String> keys, String fallback) {
    for (final key in keys) {
      final value = log[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return fallback;
  }

  String _getDiseaseName(Map<String, dynamic> log) {
    return _getText(log, ['disease_name', 'result', 'disease', 'label'], 'Unknown Result');
  }

  String _getConfidence(Map<String, dynamic> log) {
    final raw = log['confidence_score'] ?? log['confidence'] ?? log['score'];
    if (raw == null) return 'N/A';
    final value = double.tryParse(raw.toString());
    if (value == null) return raw.toString();
    return value <= 1 ? '${(value * 100).toStringAsFixed(1)}%' : '${value.toStringAsFixed(1)}%';
  }

  String _getTemperature(Map<String, dynamic> log) {
    final raw = log['temperature'] ?? log['temp'];
    if (raw == null) return 'N/A';
    final value = double.tryParse(raw.toString());
    return value == null ? raw.toString() : '${value.toStringAsFixed(1)}°C';
  }

  String _getDate(Map<String, dynamic> log) {
    final raw = log['captured_at'] ?? log['created_at'];
    if (raw == null) return 'No date';
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    return '${parsed.month}/${parsed.day}/${parsed.year} • ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  bool _isHealthy(String diseaseName) {
    final value = diseaseName.toLowerCase();
    return value.contains('healthy') || value.contains('none') || value.contains('no disease');
  }

  Color _statusColor(String diseaseName) {
    return _isHealthy(diseaseName) ? const Color(0xFF5DBB63) : Colors.orangeAccent;
  }

  int get _healthyCount => _logs.where((log) => _isHealthy(_getDiseaseName(log))).length;
  int get _riskCount => _logs.length - _healthyCount;

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Colors.red : const Color(0xFF2F6B3B),
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title ?? (widget.readOnlyBuyer ? 'Product Health Logs' : 'Scan History Logs');

    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6FBF7),
        elevation: 0,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: Color(0xFF1E2A1F))),
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F), size: 32),
        actions: [
          IconButton(
            onPressed: _loadHealthLogs,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF2F6B3B), size: 32),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF2F6B3B),
        onRefresh: _loadHealthLogs,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF2F6B3B)))
            : ListView(
                padding: const EdgeInsets.all(28),
                children: [
                  Row(
                    children: [
                      Expanded(child: _summaryCard('Total Logs', _logs.length.toString(), Icons.history_rounded)),
                      const SizedBox(width: 16),
                      Expanded(child: _summaryCard('Healthy', _healthyCount.toString(), Icons.verified_rounded)),
                      const SizedBox(width: 16),
                      Expanded(child: _summaryCard('Risk', _riskCount.toString(), Icons.warning_rounded)),
                    ],
                  ),
                  const SizedBox(height: 32),
                  if (_logs.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.eco_rounded, size: 90, color: Colors.grey),
                          SizedBox(height: 20),
                          Text('No health logs yet.', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                          SizedBox(height: 12),
                          Text('Scan records will appear here after using the camera.', style: TextStyle(fontSize: 18)),
                        ],
                      ),
                    )
                  else
                    ..._logs.map(_buildLogCard),
                ],
              ),
      ),
    );
  }

  Widget _summaryCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF2F6B3B), size: 36),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 18, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final diseaseName = _getText(log, ['disease_name', 'result', 'disease', 'label'], 'Unknown Result');
    final confidence = _getConfidence(log);
    final temperature = _getTemperature(log);
    final weather = _getText(log, ['weather_condition', 'weather'], 'N/A');
    final date = _getDate(log);
    final color = _statusColor(diseaseName);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  _isHealthy(diseaseName) ? Icons.verified_rounded : Icons.warning_amber_rounded,
                  color: color,
                  size: 40,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(diseaseName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E2A1F))),
                    const SizedBox(height: 6),
                    Text(date, style: const TextStyle(fontSize: 18, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Confidence: $confidence', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Temperature: $temperature', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Weather: $weather', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
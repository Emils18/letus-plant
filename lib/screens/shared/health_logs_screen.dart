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

  // For buyer view, pass the farmer_id of the product.
  // For farmer view, leave this null so it loads current farmer logs.
  final String? farmerId;

  // Optional product name shown in buyer view.
  final String? productName;

  // true = buyer can only view logs.
  // false = farmer views own logs.
  final bool readOnlyBuyer;

  final String? title;

  @override
  State<HealthLogsScreen> createState() => _HealthLogsScreenState();
}

class _HealthLogsScreenState extends State<HealthLogsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const Color darkBg = Color(0xFF07100B);
  static const Color cardBg = Color(0xFF0D1711);
  static const Color green = Color(0xFF5DBB63);
  static const Color lightGreen = Color(0xFF8DEB93);

  bool _loading = true;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _loadHealthLogs();
  }

  Future<void> _loadHealthLogs() async {
    setState(() {
      _loading = true;
    });

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw Exception('No logged-in user found.');
      }

      dynamic query = _supabase.from('diagnostic_logs').select('*');

      if (widget.readOnlyBuyer && widget.farmerId != null) {
        // Buyer views health logs of the farmer selling the product.
        query = query.eq('user_id', widget.farmerId!);
      } else {
        // Farmer views own health logs.
        query = query.eq('user_id', user.id);
      }

      final data = await query.order('created_at', ascending: false);

      setState(() {
        _logs = List<Map<String, dynamic>>.from(data);
      });
    } catch (error) {
      _showSnack('Failed to load health logs: $error', isError: true);
    } finally {
      setState(() {
        _loading = false;
      });
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
    return _getText(
      log,
      ['disease_name', 'result', 'disease', 'label'],
      'Unknown Result',
    );
  }

  String _getConfidence(Map<String, dynamic> log) {
    final raw = log['confidence_score'] ?? log['confidence'] ?? log['score'];

    if (raw == null) return 'N/A';

    final value = double.tryParse(raw.toString());

    if (value == null) return raw.toString();

    if (value <= 1) {
      return '${(value * 100).toStringAsFixed(1)}%';
    }

    return '${value.toStringAsFixed(1)}%';
  }

  String _getTemperature(Map<String, dynamic> log) {
    final raw = log['temperature'] ?? log['temp'];

    if (raw == null) return 'N/A';

    final value = double.tryParse(raw.toString());

    if (value == null) return raw.toString();

    return '${value.toStringAsFixed(1)}°C';
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

    return value.contains('healthy') ||
        value.contains('none') ||
        value.contains('no disease');
  }

  Color _statusColor(String diseaseName) {
    if (_isHealthy(diseaseName)) return green;

    return Colors.orangeAccent;
  }

  int get _healthyCount {
    return _logs.where((log) => _isHealthy(_getDiseaseName(log))).length;
  }

  int get _riskCount {
    return _logs.length - _healthyCount;
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? Colors.red.shade700 : green,
        content: Text(
          message,
          style: TextStyle(
            color: isError ? Colors.white : darkBg,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 14),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final diseaseName = _getDiseaseName(log);
    final confidence = _getConfidence(log);
    final temperature = _getTemperature(log);
    final weather = _getText(log, ['weather_condition', 'weather'], 'N/A');
    final location = _getText(log, ['location'], 'No location');
    final date = _getDate(log);
    final imageUrl = _getText(log, ['image_url'], '');
    final color = _statusColor(diseaseName);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                imageUrl,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Container(
                    height: 170,
                    alignment: Alignment.center,
                    color: darkBg,
                    child: const Text(
                      'Image unavailable',
                      style: TextStyle(color: Colors.white38),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _isHealthy(diseaseName)
                      ? Icons.verified_rounded
                      : Icons.warning_amber_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      diseaseName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      date,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withOpacity(0.35)),
                ),
                child: Text(
                  _isHealthy(diseaseName) ? 'HEALTHY' : 'RISK',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: darkBg.withOpacity(0.75),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _infoItem(
                        label: 'Confidence',
                        value: confidence,
                        valueColor: lightGreen,
                      ),
                    ),
                    Expanded(
                      child: _infoItem(
                        label: 'Temperature',
                        value: temperature,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _infoItem(
                        label: 'Weather',
                        value: weather,
                      ),
                    ),
                    Expanded(
                      child: _infoItem(
                        label: 'Location',
                        value: location,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.readOnlyBuyer) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: green.withOpacity(0.22)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.visibility_rounded, color: green, size: 19),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Read-only crop health record from farmer scan history.',
                      style: TextStyle(
                        color: green,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoItem({
    required String label,
    required String value,
    Color valueColor = Colors.white,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title ??
        (widget.readOnlyBuyer ? 'Product Health Logs' : 'Scan History Logs');

    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: darkBg,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadHealthLogs,
            icon: const Icon(Icons.refresh_rounded, color: green),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: green,
        backgroundColor: cardBg,
        onRefresh: _loadHealthLogs,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: green),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF132019),
                          Color(0xFF0D1711),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: green.withOpacity(0.18)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.readOnlyBuyer
                              ? 'Crop Health Summary'
                              : 'Plant Health Logs',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.readOnlyBuyer
                              ? 'View recent AI scan records before buying${widget.productName != null ? ' ${widget.productName}' : ''}.'
                              : 'Review your ESP32-CAM disease scan history and AI detection results.',
                          style: const TextStyle(
                            color: Colors.white54,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      _buildSummaryCard(
                        label: 'Total Logs',
                        value: _logs.length.toString(),
                        icon: Icons.history_rounded,
                        color: lightGreen,
                      ),
                      const SizedBox(width: 12),
                      _buildSummaryCard(
                        label: 'Healthy',
                        value: _healthyCount.toString(),
                        icon: Icons.verified_rounded,
                        color: green,
                      ),
                      const SizedBox(width: 12),
                      _buildSummaryCard(
                        label: 'Risk',
                        value: _riskCount.toString(),
                        icon: Icons.warning_rounded,
                        color: Colors.orangeAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_logs.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.eco_rounded,
                            size: 70,
                            color: Colors.white24,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No health logs yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Farmer scan records will appear here after ESP32-CAM disease detection.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38),
                          ),
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
}
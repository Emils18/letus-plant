import 'dart:async';
import 'package:flutter/material.dart';

import '../services/monitoring_service.dart';
import 'scan_mode_screen.dart';
import 'sell_crop_screen.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen>
    with WidgetsBindingObserver {
  final MonitoringService _service = MonitoringService();

  Map<String, dynamic>? data;
  Timer? _refreshTimer;
  bool _loading = true;
  bool _requestInFlight = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  bool get _connected => data?['connected'] == true;
  String get _connectionState =>
      (data?['connection_state'] as String?) ??
      (_loading ? 'CONNECTING' : 'DISCONNECTED');
  String get _sensorIp => (data?['device_ip'] as String?)?.isNotEmpty == true
      ? data!['device_ip'] as String
      : MonitoringService.soilEsp32Ip.isNotEmpty
      ? MonitoringService.soilEsp32Ip
      : 'Not found yet';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadData());
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_lifecycleState == AppLifecycleState.resumed) unawaited(_loadData());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) unawaited(_loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadData({bool forceDiscovery = false}) async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    try {
      if (mounted && (_loading || forceDiscovery)) {
        setState(() {
          if (data == null) {
            data = {
              'connected': false,
              'connection_state': 'CONNECTING',
              'soil_value': '--%',
              'soil_status': 'UNKNOWN',
            };
          } else if (forceDiscovery && _connected) {
            data = {...data!, 'connection_state': 'RECONNECTING'};
          }
        });
      }
      final result = await _service.fetchSensorData(
        forceDiscovery: forceDiscovery,
      );
      if (!mounted) return;
      setState(() {
        data = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        data = {
          ...?data,
          'connected': false,
          'connection_state': 'ERROR',
          'error': 'Unable to update soil readings: $error',
          'stale': data != null && data?['last_successful_update'] != null,
        };
        _loading = false;
      });
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> _editSensorAddress() async {
    final controller = TextEditingController(
      text: MonitoringService.soilEsp32Ip,
    );
    final address = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Soil sensor address'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'ESP32 IP address',
            hintText: 'For example: 192.168.43.120',
            helperText:
                'Use the current “Soil ESP32 IP” shown in Serial Monitor.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (address == null || address.trim().isEmpty) return;
    try {
      await MonitoringService.setSoilAddress(address);
      if (mounted) {
        setState(() {
          data = null;
          _loading = true;
        });
      }
      await _loadData();
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Color _connectionColor(String state) {
    switch (state) {
      case 'CONNECTED':
        return const Color(0xFF2F6B3B);
      case 'CONNECTING':
      case 'RECONNECTING':
        return Colors.orange.shade800;
      case 'ERROR':
        return Colors.red.shade700;
      default:
        return Colors.blueGrey;
    }
  }

  String _formattedUpdate(dynamic value) {
    final time = value == null
        ? null
        : DateTime.tryParse(value.toString())?.toLocal();
    if (time == null) return 'No successful update yet';
    final date =
        '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    final clock =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    return '$date $clock';
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
          'Farm Monitoring',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: Color(0xFF1E2A1F),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E2A1F)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ============================================================
            // SENSOR STATUS
            // ============================================================

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 15,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _connected ? 'Soil Sensor Connected' : 'Soil Sensor',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _connectionColor(
                        _connectionState,
                      ).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _connectionState,
                      style: TextStyle(
                        color: _connectionColor(_connectionState),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ESP32 IP: $_sensorIp',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
                TextButton.icon(
                  onPressed: _editSensorAddress,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Set IP'),
                ),
                IconButton(
                  onPressed: _requestInFlight
                      ? null
                      : () => _loadData(forceDiscovery: true),
                  tooltip: 'Search and reconnect',
                  icon: _requestInFlight
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find_rounded),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Last successful update: ${_formattedUpdate(data?['last_successful_update'])}${data?['stale'] == true ? ' · readings are stale' : ''}',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
            if (data?['error'] != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Text(
                  data!['error'].toString(),
                  style: TextStyle(color: Colors.brown.shade800, height: 1.35),
                ),
              ),
            ],
            const SizedBox(height: 20),

            // ============================================================
            // CURRENT READINGS
            // ============================================================
            const Text(
              'Current Readings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _bigCard(
                    'Soil Moisture',
                    data?['soil_value'] ?? '—',
                    Icons.water_drop_rounded,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _bigCard(
                    'Raw Sensor Value',
                    data?['soil_raw']?.toString() ?? '—',
                    Icons.sensors_rounded,
                    Colors.orange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _bigCard(
                    'Soil Status',
                    data?['soil_status']?.toString() ?? '—',
                    Icons.eco_rounded,
                    const Color(0xFF2F6B3B),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _bigCard(
                    'Last Update',
                    data?['last_successful_update']
                            ?.toString()
                            .split('T')
                            .last
                            .split('.')
                            .first ??
                        '—',
                    Icons.grass_rounded,
                    Colors.teal,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // ============================================================
            // QUICK ACTIONS
            // ============================================================
            // Reports are NOT placed here.
            // The final report will appear after the farmer
            // finishes a lettuce scanning session.
            // ============================================================
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ScanModeScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.document_scanner),
                    label: const Text('Scan Disease'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.indigo,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SellCropScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.storefront),
                    label: const Text('Sell Crop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5DBB63),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

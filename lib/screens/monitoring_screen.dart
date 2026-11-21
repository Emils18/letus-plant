import 'dart:async';
import 'package:flutter/material.dart';

import '../services/monitoring_service.dart';
import 'scan_mode_screen.dart';
import 'sell_crop_screen.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() =>
      _MonitoringScreenState();
}

class _MonitoringScreenState
    extends State<MonitoringScreen> {
  final MonitoringService _service =
      MonitoringService();

  Map<String, dynamic>? data;
  Timer? _refreshTimer;
  bool _loading = true;
  bool _requestInProgress = false;

  bool get _connected =>
      data?['connected'] == true && data?['reading_is_live'] == true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadData());
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_loadData()));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_requestInProgress) return;
    _requestInProgress = true;
    final result =
        await _service.fetchSensorData();
    _requestInProgress = false;

    if (!mounted) return;

    setState(() {
      data = result;
      _loading = false;
    });
  }

  Future<void> _editSensorAddress() async {
    final controller = TextEditingController(text: MonitoringService.soilEsp32Ip);
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
            helperText: 'Use the “Soil ESP32 IP” shown in Serial Monitor.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (address == null || address.trim().isEmpty) return;
    await MonitoringService.setSoilAddress(address);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF6FBF7),
      appBar: AppBar(
        backgroundColor:
            Colors.transparent,
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
        iconTheme:
            const IconThemeData(
          color: Color(0xFF1E2A1F),
        ),
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(
                color:
                    Color(0xFF2F6B3B),
              ),
            )
          : SingleChildScrollView(
              padding:
                  const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  // ============================================================
                  // SENSOR STATUS
                  // ============================================================

                  Container(
                    padding:
                        const EdgeInsets.all(
                      20,
                    ),
                    decoration:
                        BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.circular(
                        24,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black
                                  .withValues(
                            alpha: 0.03,
                          ),
                          blurRadius: 15,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment
                              .spaceBetween,
                      children: [
                        Text(
                          _connected ? 'Soil Sensor Connected' : 'Soil Sensor Offline',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration:
                              BoxDecoration(
                            color: _connected ? Colors.green.shade50 : Colors.orange.shade50,
                            borderRadius:
                                BorderRadius
                                    .circular(
                              20,
                            ),
                          ),
                          child: Text(
                            _connected ? 'LIVE' : 'OFFLINE',
                            style: TextStyle(
                              color: _connected ? Colors.green : Colors.deepOrange,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Text(MonitoringService.soilEsp32Ip.isEmpty ? 'ESP32: Searching automatically' : 'ESP32: ${MonitoringService.soilEsp32Ip}', style: const TextStyle(color: Colors.black54))),
                    TextButton.icon(onPressed: _editSensorAddress, icon: const Icon(Icons.edit, size: 16), label: const Text('Set IP')),
                    IconButton(onPressed: _loadData, tooltip: 'Refresh now', icon: const Icon(Icons.refresh)),
                  ]),
                  const SizedBox(height: 20),

                  // ============================================================
                  // CURRENT READINGS
                  // ============================================================

                  const Text(
                    'Current Readings',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: _bigCard(
                          'Soil Moisture',
                          data?[
                                  'soil_value'] ??
                              'N/A',
                          Icons
                              .water_drop_rounded,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(
                        width: 16,
                      ),
                      Expanded(
                        child: _bigCard(
                          'Raw Sensor Value',
                          data?['soil_raw']?.toString() ?? 'N/A',
                          Icons.sensors_rounded,
                          Colors.orange,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: _bigCard(
                          'Soil Status',
                          data?['soil_status']?.toString() ?? 'N/A',
                          Icons.eco_rounded,
                          const Color(
                            0xFF2F6B3B,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 16,
                      ),
                      Expanded(
                        child: _bigCard(
                          'Last Update',
                          data?['last_sync']?.toString().split('T').last.split('.').first ?? 'N/A',
                          Icons.grass_rounded,
                          Colors.teal,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 40,
                  ),

                  // ============================================================
                  // QUICK ACTIONS
                  // ============================================================
                  // Reports are NOT placed here.
                  // The final report will appear after the farmer
                  // finishes a lettuce scanning session.
                  // ============================================================

                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),

                  const SizedBox(
                    height: 16,
                  ),

                  Row(
                    children: [
                      Expanded(
                        child:
                            ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const ScanModeScreen(),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons
                                .document_scanner,
                          ),
                          label:
                              const Text(
                            'Scan Disease',
                          ),
                          style:
                              ElevatedButton
                                  .styleFrom(
                            backgroundColor:
                                Colors.white,
                            foregroundColor:
                                Colors.indigo,
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              vertical: 18,
                            ),
                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                20,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(
                        width: 16,
                      ),

                      Expanded(
                        child:
                            ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const SellCropScreen(),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons
                                .storefront,
                          ),
                          label:
                              const Text(
                            'Sell Crop',
                          ),
                          style:
                              ElevatedButton
                                  .styleFrom(
                            backgroundColor:
                                const Color(
                              0xFF5DBB63,
                            ),
                            foregroundColor:
                                Colors.white,
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              vertical: 18,
                            ),
                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius
                                      .circular(
                                20,
                              ),
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

  Widget _bigCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding:
          const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withValues(
              alpha: 0.03,
            ),
            blurRadius: 15,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 36,
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            title,
            style:
                const TextStyle(
              fontSize: 14,
              fontWeight:
                  FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            value,
            style:
                const TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

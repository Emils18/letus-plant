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
  State<HealthLogsScreen> createState() =>
      _HealthLogsScreenState();
}

class _HealthLogsScreenState
    extends State<HealthLogsScreen> {
  final SupabaseClient _supabase =
      Supabase.instance.client;

  bool _loading = true;

  List<Map<String, dynamic>>
      _logs = [];

  @override
  void initState() {
    super.initState();

    _loadHealthLogs();
  }

  Future<void>
      _loadHealthLogs() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
    });

    try {
      final user =
          _supabase.auth.currentUser;

      if (user == null) {
        throw Exception(
          'No logged-in user.',
        );
      }

      dynamic query =
          _supabase
              .from(
                'diagnostic_logs',
              )
              .select('*');

      if (widget.readOnlyBuyer &&
          widget.farmerId != null) {
        query = query.eq(
          'user_id',
          widget.farmerId!,
        );
      }
      else {
        query = query.eq(
          'user_id',
          user.id,
        );
      }

      final dynamic data =
          await query.order(
        'created_at',
        ascending: false,
      );

      if (!mounted) return;

      setState(() {
        _logs =
            List<Map<String, dynamic>>
                .from(
          data as List,
        );
      });
    } catch (error) {
      if (mounted) {
        _showSnack(
          'Failed to load health logs: $error',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _getText(
    Map<String, dynamic> log,
    List<String> keys,
    String fallback,
  ) {
    for (final String key
        in keys) {
      final dynamic value =
          log[key];

      if (value != null &&
          value
              .toString()
              .trim()
              .isNotEmpty) {
        return value.toString();
      }
    }

    return fallback;
  }

  String _getDiseaseName(
    Map<String, dynamic> log,
  ) {
    return _getText(
      log,
      [
        'disease_name',
        'result',
        'disease',
        'label',
      ],
      'Unknown Result',
    ).replaceAll(
      '_',
      ' ',
    );
  }

  String _getConfidence(
    Map<String, dynamic> log,
  ) {
    final dynamic raw =
        log['confidence_score'] ??
            log['confidence'] ??
            log['score'];

    if (raw == null) {
      return 'N/A';
    }

    final double? value =
        double.tryParse(
      raw.toString(),
    );

    if (value == null) {
      return raw.toString();
    }

    if (value <= 1) {
      return '${(value * 100).toStringAsFixed(1)}%';
    }

    return '${value.toStringAsFixed(1)}%';
  }

  String _getTemperature(
    Map<String, dynamic> log,
  ) {
    final dynamic raw =
        log['temperature'] ??
            log['temp'];

    if (raw == null) {
      return 'N/A';
    }

    final double? value =
        double.tryParse(
      raw.toString(),
    );

    if (value == null) {
      return raw.toString();
    }

    return '${value.toStringAsFixed(1)}°C';
  }

  String _getDate(
    Map<String, dynamic> log,
  ) {
    final dynamic raw =
        log['captured_at'] ??
            log['created_at'];

    if (raw == null) {
      return 'No date';
    }

    final DateTime? parsed =
        DateTime.tryParse(
      raw.toString(),
    );

    if (parsed == null) {
      return raw.toString();
    }

    final DateTime local =
        parsed.toLocal();

    return '${local.month}/${local.day}/${local.year} • '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _getPathogen(
    String diseaseName,
  ) {
    final String value =
        diseaseName
            .toLowerCase()
            .replaceAll(
              '_',
              ' ',
            )
            .trim();

    if (value ==
        'downy mildew') {
      return 'Bremia lactucae';
    }

    if (value ==
        'powdery mildew') {
      return 'Erysiphe cichoracearum';
    }

    if (value ==
            'septoria blight' ||
        value ==
            'septoria leaf spot') {
      return 'Septoria lactucae';
    }

    if (value.contains(
      'healthy',
    )) {
      return 'No pathogen detected';
    }

    return 'N/A';
  }

  bool _isHealthy(
    String diseaseName,
  ) {
    final String value =
        diseaseName.toLowerCase();

    return value.contains(
          'healthy',
        ) ||
        value.contains(
          'none',
        ) ||
        value.contains(
          'no disease',
        );
  }

  bool _isUnknown(
    String diseaseName,
  ) {
    final String value =
        diseaseName.toLowerCase();

    return value.contains(
          'unknown',
        ) ||
        value.contains(
          'out of scope',
        );
  }

  bool _isDemo(
    Map<String, dynamic> log,
  ) {
    return log['device_id']
            ?.toString()
            .toUpperCase() ==
        'DEMO_MODE';
  }

  Color _statusColor(
    String diseaseName,
  ) {
    final String value =
        diseaseName
            .toLowerCase()
            .replaceAll(
              '_',
              ' ',
            );

    if (_isHealthy(
      diseaseName,
    )) {
      return const Color(
        0xFF5DBB63,
      );
    }

    if (value.contains(
      'downy mildew',
    )) {
      return Colors.redAccent;
    }

    if (value.contains(
      'powdery mildew',
    )) {
      return Colors.orangeAccent;
    }

    if (value.contains(
      'septoria',
    )) {
      return Colors.deepOrange;
    }

    return Colors.grey;
  }

  int get _healthyCount =>
      _logs
          .where(
            (
              Map<String, dynamic>
                  log,
            ) =>
                _isHealthy(
              _getDiseaseName(
                log,
              ),
            ),
          )
          .length;

  int get _riskCount =>
      _logs.length -
      _healthyCount;

  void _showSnack(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        backgroundColor:
            isError
                ? Colors.red
                : const Color(
                    0xFF2F6B3B,
                  ),
        content: Text(
          message,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final String title =
        widget.title ??
            (
              widget.readOnlyBuyer
                  ? 'Product Health Logs'
                  : 'Scan History Logs'
            );

    return Scaffold(
      backgroundColor:
          const Color(
        0xFFF6FBF7,
      ),
      appBar: AppBar(
        backgroundColor:
            const Color(
          0xFFF6FBF7,
        ),
        elevation: 0,
        title: Text(
          title,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.w900,
            fontSize: 25,
            color: Color(
              0xFF1E2A1F,
            ),
          ),
        ),
        iconTheme:
            const IconThemeData(
          color: Color(
            0xFF1E2A1F,
          ),
          size: 30,
        ),
        actions: [
          IconButton(
            onPressed:
                _loading
                    ? null
                    : _loadHealthLogs,
            icon: const Icon(
              Icons.refresh_rounded,
              color: Color(
                0xFF2F6B3B,
              ),
              size: 30,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(
          0xFF2F6B3B,
        ),
        onRefresh:
            _loadHealthLogs,
        child: _loading
            ? const Center(
                child:
                    CircularProgressIndicator(
                  color: Color(
                    0xFF2F6B3B,
                  ),
                ),
              )
            : ListView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.all(
                  18,
                ),
                children: [
                  if (widget.productName !=
                      null) ...[
                    Container(
                      width:
                          double.infinity,
                      padding:
                          const EdgeInsets.all(
                        16,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            Colors.white,
                        borderRadius:
                            BorderRadius
                                .circular(
                          18,
                        ),
                      ),
                      child: Text(
                        'Crop: ${widget.productName}',
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight
                                  .w800,
                          color:
                              Color(
                            0xFF2F6B3B,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child:
                            _summaryCard(
                          'Total',
                          _logs.length
                              .toString(),
                          Icons
                              .history_rounded,
                        ),
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      Expanded(
                        child:
                            _summaryCard(
                          'Healthy',
                          _healthyCount
                              .toString(),
                          Icons
                              .verified_rounded,
                        ),
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      Expanded(
                        child:
                            _summaryCard(
                          'Risk',
                          _riskCount
                              .toString(),
                          Icons
                              .warning_rounded,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 24,
                  ),

                  if (_logs.isEmpty)
                    Container(
                      padding:
                          const EdgeInsets.all(
                        38,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            Colors.white,
                        borderRadius:
                            BorderRadius
                                .circular(
                          28,
                        ),
                      ),
                      child:
                          const Column(
                        children: [
                          Icon(
                            Icons
                                .eco_rounded,
                            size: 80,
                            color:
                                Colors.grey,
                          ),
                          SizedBox(
                            height: 18,
                          ),
                          Text(
                            'No health logs yet.',
                            textAlign:
                                TextAlign
                                    .center,
                            style:
                                TextStyle(
                              fontSize:
                                  22,
                              fontWeight:
                                  FontWeight
                                      .w900,
                            ),
                          ),
                          SizedBox(
                            height: 10,
                          ),
                          Text(
                            'Real lettuce AI scan records will appear here after Use Photo completes successfully.',
                            textAlign:
                                TextAlign
                                    .center,
                            style:
                                TextStyle(
                              fontSize:
                                  15,
                              height:
                                  1.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._logs.map(
                      _buildLogCard,
                    ),
                ],
              ),
      ),
    );
  }

  Widget _summaryCard(
    String label,
    String value,
    IconData icon,
  ) {
    return Container(
      constraints:
          const BoxConstraints(
        minHeight: 136,
      ),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 18,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          22,
        ),
      ),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment
                .center,
        children: [
          Icon(
            icon,
            color:
                const Color(
              0xFF2F6B3B,
            ),
            size: 30,
          ),
          const SizedBox(
            height: 10,
          ),
          Text(
            value,
            style:
                const TextStyle(
              fontSize: 28,
              fontWeight:
                  FontWeight.w900,
              color: Color(
                0xFF1E2A1F,
              ),
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style:
                  const TextStyle(
                fontSize: 14,
                fontWeight:
                    FontWeight.w700,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(
    Map<String, dynamic> log,
  ) {
    final String diseaseName =
        _getDiseaseName(
      log,
    );

    final String confidence =
        _getConfidence(
      log,
    );

    final String temperature =
        _getTemperature(
      log,
    );

    final String weather =
        _getText(
      log,
      [
        'weather_condition',
        'weather',
      ],
      'N/A',
    );

    final String location =
        _getText(
      log,
      [
        'location',
      ],
      'N/A',
    );

    final String device =
        _getText(
      log,
      [
        'device_id',
      ],
      'Unknown device',
    );

    final String date =
        _getDate(
      log,
    );

    final String pathogen =
        _getPathogen(
      diseaseName,
    );

    final Color color =
        _statusColor(
      diseaseName,
    );

    final bool demo =
        _isDemo(
      log,
    );

    final bool unknown =
        _isUnknown(
      diseaseName,
    );

    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 18,
      ),
      padding:
          const EdgeInsets.all(
        22,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          26,
        ),
        border: Border.all(
          color: color.withValues(
            alpha: 0.18,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment
                    .start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration:
                    BoxDecoration(
                  color:
                      color.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius:
                      BorderRadius
                          .circular(
                    16,
                  ),
                ),
                child: Icon(
                  _isHealthy(
                    diseaseName,
                  )
                      ? Icons
                          .verified_rounded
                      : unknown
                          ? Icons
                              .help_outline_rounded
                          : Icons
                              .warning_amber_rounded,
                  color: color,
                  size: 30,
                ),
              ),

              const SizedBox(
                width: 14,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      diseaseName,
                      style:
                          const TextStyle(
                        fontSize: 21,
                        fontWeight:
                            FontWeight
                                .w900,
                        color: Color(
                          0xFF1E2A1F,
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      date,
                      style:
                          const TextStyle(
                        fontSize: 14,
                        color:
                            Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                demo
                    ? 'Demo / Legacy'
                    : 'AI Scan',
                demo
                    ? Colors.grey
                    : const Color(
                        0xFF2F6B3B,
                      ),
              ),
              _chip(
                device,
                const Color(
                  0xFF2F6B3B,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 18,
          ),

          _infoRow(
            'Confidence',
            confidence,
          ),

          if (pathogen !=
              'N/A')
            _infoRow(
              'Pathogen',
              pathogen,
            ),

          _infoRow(
            'Temperature',
            temperature,
          ),

          _infoRow(
            'Weather',
            weather,
          ),

          _infoRow(
            'Location',
            location,
          ),
        ],
      ),
    );
  }

  Widget _chip(
    String label,
    Color color,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: 0.10,
        ),
        borderRadius:
            BorderRadius.circular(
          18,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight:
              FontWeight.w800,
        ),
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment
                .start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              '$label:',
              style:
                  const TextStyle(
                fontSize: 15,
                fontWeight:
                    FontWeight.w800,
                color:
                    Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(
                fontSize: 15,
                fontWeight:
                    FontWeight.w800,
                color: Color(
                  0xFF1E2A1F,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

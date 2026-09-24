import 'package:flutter/material.dart';

import '../services/monitoring_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() =>
      _ReportsScreenState();
}

class _ReportsScreenState
    extends State<ReportsScreen> {
  final MonitoringService _monitoringService =
      MonitoringService();

  static const double minimumConfidence = 0.80;

  bool _loading = true;

  String? _error;

  String _selectedRange = 'All';

  List<Map<String, dynamic>> _logs = [];

  final List<String> _ranges = [
    'All',
    'Today',
    'Week',
    'Month',
  ];

  @override
  void initState() {
    super.initState();

    _loadReports();
  }

  Future<void> _loadReports() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final logs =
          await _monitoringService
              .fetchHealthLogs();

      if (!mounted) return;

      setState(() {
        _logs = logs;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // REPORT FILTERING
  // ============================================================

  List<Map<String, dynamic>>
      get _realLogs {
    return _logs.where(
      (
        Map<String, dynamic> log,
      ) {
        final String device =
            log['device_id']
                    ?.toString()
                    .trim()
                    .toUpperCase() ??
                '';

        // Do not include old demo records
        // in the official farmer report.
        return device != 'DEMO_MODE';
      },
    ).toList();
  }

  List<Map<String, dynamic>>
      get _filteredLogs {
    final DateTime now =
        DateTime.now();

    return _realLogs.where(
      (
        Map<String, dynamic> log,
      ) {
        if (_selectedRange == 'All') {
          return true;
        }

        final DateTime? date =
            _getLogDate(
          log,
        );

        if (date == null) {
          return false;
        }

        if (_selectedRange ==
            'Today') {
          return date.year ==
                  now.year &&
              date.month ==
                  now.month &&
              date.day ==
                  now.day;
        }

        if (_selectedRange ==
            'Week') {
          final DateTime start =
              now.subtract(
            const Duration(
              days: 7,
            ),
          );

          return date.isAfter(
            start,
          );
        }

        if (_selectedRange ==
            'Month') {
          return date.year ==
                  now.year &&
              date.month ==
                  now.month;
        }

        return true;
      },
    ).toList();
  }

  DateTime? _getLogDate(
    Map<String, dynamic> log,
  ) {
    final dynamic value =
        log['captured_at'] ??
            log['created_at'];

    if (value == null) {
      return null;
    }

    return DateTime.tryParse(
      value.toString(),
    )?.toLocal();
  }

  // ============================================================
  // DISEASE / CONFIDENCE HELPERS
  // ============================================================

  String _diseaseName(
    Map<String, dynamic> log,
  ) {
    return (
      log['disease_name'] ??
          log['result'] ??
          log['disease'] ??
          log['label'] ??
          'Unknown'
    )
        .toString()
        .replaceAll(
          '_',
          ' ',
        )
        .trim();
  }

  String _normalizedDisease(
    Map<String, dynamic> log,
  ) {
    return _diseaseName(
      log,
    ).toLowerCase();
  }

  double _confidence(
    Map<String, dynamic> log,
  ) {
    final dynamic raw =
        log['confidence_score'] ??
            log['confidence'] ??
            log['score'];

    final double value =
        double.tryParse(
              raw?.toString() ??
                  '',
            ) ??
            0.0;

    if (value > 1) {
      return value / 100;
    }

    return value;
  }

  bool _knownDisease(
    Map<String, dynamic> log,
  ) {
    final String disease =
        _normalizedDisease(
      log,
    );

    return disease ==
            'healthy' ||
        disease ==
            'downy mildew' ||
        disease ==
            'powdery mildew' ||
        disease ==
            'septoria blight' ||
        disease ==
            'septoria leaf spot';
  }

  bool _accepted(
    Map<String, dynamic> log,
  ) {
    return _knownDisease(
          log,
        ) &&
        _confidence(
              log,
            ) >=
            minimumConfidence;
  }

  bool _matchesDisease(
    Map<String, dynamic> log,
    String disease,
  ) {
    final String current =
        _normalizedDisease(
      log,
    );

    final String target =
        disease.toLowerCase();

    if (target ==
        'septoria blight') {
      return current ==
              'septoria blight' ||
          current ==
              'septoria leaf spot';
    }

    return current == target;
  }

  List<Map<String, dynamic>>
      get _acceptedLogs {
    return _filteredLogs
        .where(
          _accepted,
        )
        .toList();
  }

  int _countDisease(
    String disease,
  ) {
    return _acceptedLogs
        .where(
          (
            Map<String, dynamic> log,
          ) =>
              _matchesDisease(
            log,
            disease,
          ),
        )
        .length;
  }

  double _averageConfidence(
    String disease,
  ) {
    final List<
        Map<String, dynamic>> records =
        _acceptedLogs
            .where(
              (
                Map<String, dynamic>
                    log,
              ) =>
                  _matchesDisease(
                log,
                disease,
              ),
            )
            .toList();

    if (records.isEmpty) {
      return 0;
    }

    double total = 0;

    for (final log
        in records) {
      total +=
          _confidence(
        log,
      );
    }

    return total /
        records.length;
  }

  double _percentage(
    int count,
  ) {
    if (_acceptedLogs.isEmpty) {
      return 0;
    }

    return count /
        _acceptedLogs.length *
        100;
  }

  // ============================================================
  // COUNTS
  // ============================================================

  int get _healthyCount =>
      _countDisease(
        'Healthy',
      );

  int get _downyCount =>
      _countDisease(
        'Downy Mildew',
      );

  int get _powderyCount =>
      _countDisease(
        'Powdery Mildew',
      );

  int get _septoriaCount =>
      _countDisease(
        'Septoria Blight',
      );

  int get _diseasedCount =>
      _downyCount +
      _powderyCount +
      _septoriaCount;

  int get _needsRetakeCount =>
      _filteredLogs.length -
      _acceptedLogs.length;

  // ============================================================
  // FARMER-FRIENDLY DESCRIPTIONS
  // ============================================================

  String _description(
    String disease,
  ) {
    switch (disease) {
      case 'Healthy':
        return 'No visible signs of the supported lettuce diseases were detected. '
            'The lettuce appears healthy based on the GreenGuard scan.';

      case 'Downy Mildew':
        return 'Downy mildew may cause yellow or pale patches on lettuce leaves '
            'and mold-like growth underneath. Wet conditions can help it spread.';

      case 'Powdery Mildew':
        return 'Powdery mildew usually appears as white powder-like patches on '
            'the leaf surface. Good airflow can help reduce its spread.';

      case 'Septoria Blight':
        return 'Septoria blight can cause small brown or dark leaf spots that '
            'may enlarge and damage the lettuce leaves.';

      default:
        return '';
    }
  }

  String _pathogen(
    String disease,
  ) {
    switch (disease) {
      case 'Healthy':
        return 'No pathogen detected';

      case 'Downy Mildew':
        return 'Bremia lactucae';

      case 'Powdery Mildew':
        return 'Erysiphe cichoracearum';

      case 'Septoria Blight':
        return 'Septoria lactucae';

      default:
        return 'N/A';
    }
  }

  // ============================================================
  // SCREEN
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
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
        centerTitle: true,
        iconTheme:
            const IconThemeData(
          color: Color(
            0xFF1E2A1F,
          ),
        ),
        title: const Text(
          'Farm Reports',
          style: TextStyle(
            fontSize: 22,
            fontWeight:
                FontWeight.w900,
            color: Color(
              0xFF1E2A1F,
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed:
                _loading
                    ? null
                    : _loadReports,
            icon:
                const Icon(
              Icons.refresh_rounded,
              color:
                  Color(
                0xFF2F6B3B,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(
                color:
                    Color(
                  0xFF2F6B3B,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh:
                  _loadReports,
              color:
                  const Color(
                0xFF2F6B3B,
              ),
              child: ListView(
                padding:
                    const EdgeInsets.all(
                  20,
                ),
                children: [
                  _buildHeader(),

                  const SizedBox(
                    height: 18,
                  ),

                  _buildFilters(),

                  const SizedBox(
                    height: 20,
                  ),

                  if (_error != null)
                    _errorCard()
                  else ...[
                    _buildConfidenceRule(),

                    const SizedBox(
                      height: 20,
                    ),

                    _buildOverview(),

                    const SizedBox(
                      height: 26,
                    ),

                    const Text(
                      'Health Breakdown',
                      style:
                          TextStyle(
                        fontSize:
                            22,
                        fontWeight:
                            FontWeight
                                .w900,
                        color:
                            Color(
                          0xFF1E2A1F,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    _diseaseCard(
                      name:
                          'Healthy',
                      count:
                          _healthyCount,
                      color:
                          const Color(
                        0xFF5DBB63,
                      ),
                      icon:
                          Icons
                              .verified_rounded,
                    ),

                    _diseaseCard(
                      name:
                          'Downy Mildew',
                      count:
                          _downyCount,
                      color:
                          Colors.redAccent,
                      icon:
                          Icons
                              .warning_amber_rounded,
                    ),

                    _diseaseCard(
                      name:
                          'Powdery Mildew',
                      count:
                          _powderyCount,
                      color:
                          Colors.orange,
                      icon:
                          Icons
                              .warning_amber_rounded,
                    ),

                    _diseaseCard(
                      name:
                          'Septoria Blight',
                      count:
                          _septoriaCount,
                      color:
                          Colors.deepOrange,
                      icon:
                          Icons
                              .warning_amber_rounded,
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    _buildReportNote(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(
        24,
      ),
      decoration:
          BoxDecoration(
        gradient:
            const LinearGradient(
          begin:
              Alignment.topLeft,
          end:
              Alignment.bottomRight,
          colors: [
            Color(
              0xFF1E2A1F,
            ),
            Color(
              0xFF2F6B3B,
            ),
          ],
        ),
        borderRadius:
            BorderRadius.circular(
          28,
        ),
      ),
      child: const Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            Icons
                .analytics_rounded,
            color: Colors.white,
            size: 42,
          ),

          SizedBox(
            height: 14,
          ),

          Text(
            'Lettuce Health Report',
            style: TextStyle(
              fontSize: 26,
              fontWeight:
                  FontWeight.w900,
              color:
                  Colors.white,
            ),
          ),

          SizedBox(
            height: 7,
          ),

          Text(
            'Overall results collected from GreenGuard AI lettuce scans.',
            style: TextStyle(
              fontSize: 15,
              fontWeight:
                  FontWeight.w600,
              height: 1.4,
              color:
                  Color(
                0xFFE7F1E8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          _ranges.map(
        (
          String range,
        ) {
          return ChoiceChip(
            label:
                Text(
              range,
            ),
            selected:
                _selectedRange ==
                    range,
            selectedColor:
                const Color(
              0xFFDDEEDF,
            ),
            onSelected: (_) {
              setState(() {
                _selectedRange =
                    range;
              });
            },
          );
        },
      ).toList(),
    );
  }

  Widget _buildConfidenceRule() {
    return Container(
      padding:
          const EdgeInsets.all(
        18,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xFFFFF8E7,
        ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
        border:
            Border.all(
          color: Colors.orange
              .withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: const Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            Icons
                .verified_user_rounded,
            color: Colors.orange,
          ),

          SizedBox(
            width: 12,
          ),

          Expanded(
            child: Text(
              'Only diagnoses with 80% confidence or higher are counted as accepted results. Lower-confidence scans are placed under Needs Retake.',
              style:
                  TextStyle(
                fontSize: 14,
                fontWeight:
                    FontWeight.w700,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverview() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Text(
          'Overall Summary',
          style:
              TextStyle(
            fontSize: 22,
            fontWeight:
                FontWeight.w900,
            color:
                Color(
              0xFF1E2A1F,
            ),
          ),
        ),

        const SizedBox(
          height: 14,
        ),

        Row(
          children: [
            Expanded(
              child:
                  _summaryCard(
                title:
                    'Total Scans',
                value:
                    _filteredLogs.length
                        .toString(),
                icon:
                    Icons
                        .document_scanner_rounded,
                color:
                    const Color(
                  0xFF2F6B3B,
                ),
              ),
            ),

            const SizedBox(
              width: 12,
            ),

            Expanded(
              child:
                  _summaryCard(
                title:
                    'Accepted',
                value:
                    _acceptedLogs.length
                        .toString(),
                icon:
                    Icons
                        .check_circle_rounded,
                color:
                    Colors.green,
              ),
            ),
          ],
        ),

        const SizedBox(
          height: 12,
        ),

        Row(
          children: [
            Expanded(
              child:
                  _summaryCard(
                title:
                    'Sellable / Healthy',
                value:
                    '$_healthyCount\n${_percentage(_healthyCount).toStringAsFixed(1)}%',
                icon:
                    Icons
                        .storefront_rounded,
                color:
                    const Color(
                  0xFF5DBB63,
                ),
              ),
            ),

            const SizedBox(
              width: 12,
            ),

            Expanded(
              child:
                  _summaryCard(
                title:
                    'Not Healthy',
                value:
                    '$_diseasedCount\n${_percentage(_diseasedCount).toStringAsFixed(1)}%',
                icon:
                    Icons
                        .warning_rounded,
                color:
                    Colors.redAccent,
              ),
            ),
          ],
        ),

        const SizedBox(
          height: 12,
        ),

        _summaryCard(
          title:
              'Needs Retake / Below 80%',
          value:
              _needsRetakeCount
                  .toString(),
          icon:
              Icons
                  .refresh_rounded,
          color:
              Colors.orange,
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      constraints:
          const BoxConstraints(
        minHeight: 145,
      ),
      padding:
          const EdgeInsets.all(
        18,
      ),
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          22,
        ),
        border:
            Border.all(
          color:
              color.withValues(
            alpha: 0.15,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: color,
            size: 30,
          ),

          const SizedBox(
            height: 9,
          ),

          Text(
            value,
            textAlign:
                TextAlign.center,
            style:
                const TextStyle(
              fontSize: 24,
              fontWeight:
                  FontWeight.w900,
              color:
                  Color(
                0xFF1E2A1F,
              ),
            ),
          ),

          const SizedBox(
            height: 5,
          ),

          Text(
            title,
            textAlign:
                TextAlign.center,
            style:
                const TextStyle(
              fontSize: 13,
              fontWeight:
                  FontWeight.w700,
              color:
                  Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _diseaseCard({
    required String name,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    final double average =
        _averageConfidence(
      name,
    );

    final double percentage =
        _percentage(
      count,
    );

    return Container(
      width: double.infinity,
      margin:
          const EdgeInsets.only(
        bottom: 14,
      ),
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
        border:
            Border.all(
          color:
              color.withValues(
            alpha: 0.18,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration:
                    BoxDecoration(
                  color:
                      color.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius:
                      BorderRadius
                          .circular(
                    15,
                  ),
                ),
                child:
                    Icon(
                  icon,
                  color:
                      color,
                ),
              ),

              const SizedBox(
                width: 13,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      name,
                      style:
                          const TextStyle(
                        fontSize:
                            19,
                        fontWeight:
                            FontWeight
                                .w900,
                        color:
                            Color(
                          0xFF1E2A1F,
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 3,
                    ),

                    Text(
                      _pathogen(
                        name,
                      ),
                      style:
                          const TextStyle(
                        fontSize:
                            13,
                        fontStyle:
                            FontStyle
                                .italic,
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

          Row(
            children: [
              Expanded(
                child:
                    _metric(
                  'Count',
                  '$count',
                ),
              ),

              Expanded(
                child:
                    _metric(
                  'Share',
                  '${percentage.toStringAsFixed(1)}%',
                ),
              ),

              Expanded(
                child:
                    _metric(
                  'Avg. Confidence',
                  count == 0
                      ? 'N/A'
                      : '${(average * 100).toStringAsFixed(1)}%',
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 16,
          ),

          Text(
            _description(
              name,
            ),
            style:
                const TextStyle(
              fontSize: 14,
              height: 1.5,
              fontWeight:
                  FontWeight.w600,
              color:
                  Color(
                0xFF68736A,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(
    String title,
    String value,
  ) {
    return Column(
      children: [
        Text(
          value,
          textAlign:
              TextAlign.center,
          style:
              const TextStyle(
            fontSize: 17,
            fontWeight:
                FontWeight.w900,
            color:
                Color(
              0xFF1E2A1F,
            ),
          ),
        ),

        const SizedBox(
          height: 3,
        ),

        Text(
          title,
          textAlign:
              TextAlign.center,
          style:
              const TextStyle(
            fontSize: 11,
            fontWeight:
                FontWeight.w700,
            color:
                Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildReportNote() {
    return Container(
      padding:
          const EdgeInsets.all(
        18,
      ),
      decoration:
          BoxDecoration(
        color:
            const Color(
          0xFFEAF4EB,
        ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
      ),
      child: const Text(
        'Report counting rule: one accepted AI scan is counted as one lettuce. '
        'Avoid scanning the same lettuce more than once when using this report '
        'as an estimate of the number of healthy or diseased lettuce.',
        style:
            TextStyle(
          fontSize: 13,
          height: 1.5,
          fontWeight:
              FontWeight.w700,
          color:
              Color(
            0xFF2F6B3B,
          ),
        ),
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding:
          const EdgeInsets.all(
        24,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.red.shade50,
        borderRadius:
            BorderRadius.circular(
          22,
        ),
      ),
      child: Text(
        'Unable to load report.\n$_error',
        style:
            const TextStyle(
          fontWeight:
              FontWeight.w700,
          color:
              Colors.red,
        ),
      ),
    );
  }
}
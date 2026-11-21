import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/lettuce_scan_report.dart';
import '../../widgets/lettuce_scan_report_card.dart';

class ScanSessionReportScreen extends StatefulWidget {
  const ScanSessionReportScreen({
    super.key,
    required this.scans,
    required this.startedAt,
    required this.completedAt,
    this.historyMode = false,
    this.overallMode = false,
  });

  final List<Map<String, dynamic>> scans;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool historyMode;
  final bool overallMode;

  @override
  State<ScanSessionReportScreen> createState() =>
      _ScanSessionReportScreenState();
}

class _ScanSessionReportScreenState extends State<ScanSessionReportScreen> {
  static const _background = Color(0xfff6fbf7);
  static const _green = Color(0xff2f6b3b);
  static const _ink = Color(0xff1e2a1f);
  static const _body = TextStyle(color: _ink, fontSize: 16, height: 1.4);

  late final Map<String, List<Map<String, dynamic>>> _groups = {
    for (final key in LettuceScanReport.diseaseNames.keys) key: [],
  };

  final List<Map<String, dynamic>> _unclassified = [];
  late final Future<List<({Map<String, dynamic> values, bool usedReference})>>
  _guidance = Future.wait(widget.scans.map(LettuceScanReport.resolve));

  @override
  void initState() {
    super.initState();
    for (final scan in widget.scans) {
      final key = LettuceScanReport.diseaseKey(
        LettuceScanReport.diseaseName(scan),
      );
      (_groups[key] ?? _unclassified).add(scan);
    }
  }

  int get _healthyCount => _groups['healthy']!.length;
  int get _diseasedCount =>
      widget.scans.length - _healthyCount - _unclassified.length;

  @override
  Widget build(BuildContext context) {
    final isComplete = widget.completedAt != null;
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _ink,
        title: Text(
          widget.overallMode
              ? 'Overall Health Report'
              : isComplete
              ? 'Final Scan Report'
              : 'Scan Session Report',
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
            sliver: SliverList.list(
              children: [
                _overview(),
                const SizedBox(height: 20),
                const Text(
                  'Individual reports',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                if (widget.scans.isEmpty)
                  const Text('No saved scans yet.', style: _body)
                else
                  const Text(
                    'Open a photo’s report to see its diagnosis and advice.',
                    style: _body,
                  ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            sliver: SliverList.builder(
              itemCount: widget.scans.length,
              itemBuilder: (_, index) => LettuceScanReportCard(
                scan: widget.scans[index],
                photoNumber: index + 1,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
            sliver: SliverList.list(
              children: [
                if (widget.scans.isNotEmpty) _sessionAdvice(),
                if (!widget.historyMode && !widget.overallMode) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Start a new session'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Close report'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overview() {
    final format = DateFormat.yMMMd().add_jm();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffc8ddca)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lettuce scan summary',
            style: TextStyle(
              color: _ink,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (widget.startedAt case final date?)
            Text('Started ${format.format(date.toLocal())}', style: _body),
          if (widget.completedAt case final date?)
            Text('Completed ${format.format(date.toLocal())}', style: _body),
          const Divider(height: 24, color: Color(0xffd8e7d9)),
          _summaryLine('Total lettuce scanned', widget.scans.length),
          _summaryLine('Healthy', _healthyCount),
          _summaryLine('Disease detected', _diseasedCount),
          if (_unclassified.isNotEmpty)
            _summaryLine('Needs review', _unclassified.length),
          const Divider(height: 24, color: Color(0xffd8e7d9)),
          const Text(
            'Disease breakdown',
            style: TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in LettuceScanReport.diseaseNames.entries)
            if (entry.key != 'healthy')
              _summaryLine(entry.value, _groups[entry.key]!.length),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, int count) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: _body)),
        const SizedBox(width: 10),
        Text('$count', style: _body.copyWith(fontWeight: FontWeight.w800)),
      ],
    ),
  );

  Widget _sessionAdvice() {
    final selling = <String>[
      if (_healthyCount > 0)
        'Inspect the $_healthyCount healthy-looking lettuce before selling. Check the whole head and follow your normal produce safety checks.',
      if (_diseasedCount > 0)
        'Set aside the $_diseasedCount affected lettuce for inspection. Keep visibly damaged or mildewed leaves out of the sale batch.',
      if (_unclassified.isNotEmpty)
        'Inspect the ${_unclassified.length} unclassified lettuce before deciding whether to sell it.',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xffecf4ed),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.overallMode
                ? 'Care across all scans'
                : 'What to do after this session',
            style: const TextStyle(
              color: _ink,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Treatment and prevention',
            style: TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          FutureBuilder(
            future: _guidance,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Text('Loading management guidance…', style: _body);
              }
              final items = <String>{};
              for (final report in snapshot.data ?? const []) {
                items.addAll(LettuceScanReport.treatment(report.values));
              }
              if (items.isEmpty) {
                return const Text(
                  'Check each photo report for any saved guidance.',
                  style: _body,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $item', style: _body),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          const Text(
            'Selling guidance',
            style: TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in selling)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line, style: _body),
            ),
          const Text(
            LettuceScanReport.advisory,
            style: TextStyle(
              color: Color(0xff4d6050),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/lettuce_scan_report.dart';

class LettuceScanReportCard extends StatefulWidget {
  const LettuceScanReportCard({
    super.key,
    required this.scan,
    this.photoNumber,
    this.initiallyExpanded = false,
  });

  final Map<String, dynamic> scan;
  final int? photoNumber;
  final bool initiallyExpanded;

  @override
  State<LettuceScanReportCard> createState() => _LettuceScanReportCardState();
}

class _LettuceScanReportCardState extends State<LettuceScanReportCard> {
  static const ink = Color(0xff1e2a1f);
  static const green = Color(0xff2f6b3b);
  static const muted = Color(0xff4d6050);

  late Future<({Map<String, dynamic> values, bool usedReference})> _report;

  @override
  void initState() {
    super.initState();
    _report = LettuceScanReport.resolve(widget.scan);
  }

  @override
  void didUpdateWidget(LettuceScanReportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scan != widget.scan) {
      _report = LettuceScanReport.resolve(widget.scan);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = LettuceScanReport.diseaseName(widget.scan);
    final disease = LettuceScanReport.diseaseKey(name);
    final confidence = LettuceScanReport.confidence(widget.scan);
    final date = LettuceScanReport.capturedAt(widget.scan);
    final isHealthy = disease == 'healthy';
    final hasDisease = LettuceScanReport.diseaseNames.containsKey(disease);
    final status = isHealthy
        ? 'Healthy'
        : hasDisease
        ? 'At risk'
        : 'Needs review';
    final statusColor = isHealthy ? green : const Color(0xff854318);

    return FutureBuilder(
      future: _report,
      builder: (context, snapshot) {
        final data = snapshot.data?.values ?? widget.scan;
        final pathogen = LettuceScanReport.text(data, ['pathogen_name']);
        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: statusColor.withValues(alpha: .23)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _photo(data),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.photoNumber case final number?)
                            Text(
                              'Photo $number',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 14,
                              ),
                            ),
                          Text(
                            name,
                            style: const TextStyle(
                              color: ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (pathogen.isNotEmpty)
                            Text(
                              pathogen,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 16,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 5,
                            children: [
                              Text(
                                status,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (confidence != null)
                                Text(
                                  '${(confidence * 100).toStringAsFixed(1)}% confidence',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 15,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ExpansionTile(
                initiallyExpanded: widget.initiallyExpanded,
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                iconColor: green,
                collapsedIconColor: green,
                title: const Text(
                  'Report details',
                  style: TextStyle(
                    color: green,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                children: [
                  _details(data, date, snapshot.data?.usedReference ?? false),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _photo(Map<String, dynamic> data) {
    final url = LettuceScanReport.text(data, ['image_url', 'photo_url']);
    final bytes = data['image_bytes'];
    final hasBytes = bytes is Uint8List && bytes.isNotEmpty;
    if (!hasBytes && url.isEmpty) {
      return SizedBox(width: 78, height: 78, child: _missingPhoto());
    }
    Widget image(BoxFit fit) => hasBytes
        ? Image.memory(
            bytes,
            fit: fit,
            semanticLabel: 'Scanned lettuce',
            errorBuilder: (_, _, _) => _missingPhoto(),
          )
        : Image.network(
            url,
            fit: fit,
            semanticLabel: 'Scanned lettuce',
            errorBuilder: (_, _, _) => _missingPhoto(),
          );
    return SizedBox(
      width: 78,
      height: 78,
      child: Semantics(
        label: 'Enlarge scan photo',
        button: true,
        child: InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Scan photo'),
              content: SizedBox(
                width: 440,
                height: 280,
                child: InteractiveViewer(child: image(BoxFit.contain)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
          child: image(BoxFit.cover),
        ),
      ),
    );
  }

  Widget _missingPhoto() => const ColoredBox(
    color: Color(0xffecf4ed),
    child: Center(
      child: Icon(
        Icons.hide_image_outlined,
        color: muted,
        semanticLabel: 'Photo unavailable',
      ),
    ),
  );

  Widget _details(Map<String, dynamic> data, DateTime? date, bool reference) {
    const body = TextStyle(color: ink, fontSize: 16, height: 1.4);
    final treatments = LettuceScanReport.treatment(data);
    final location = LettuceScanReport.text(data, ['location']);
    final weather = LettuceScanReport.text(data, [
      'weather_condition',
      'weather',
    ]);
    final temperature = LettuceScanReport.text(data, ['temperature', 'temp']);
    final tempValue = double.tryParse(temperature);
    final selling = LettuceScanReport.text(data, ['selling_recommendation']);
    final reason = LettuceScanReport.text(data, ['selling_explanation']);
    final device = LettuceScanReport.text(data, ['device_id']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reference)
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'Includes reference guidance for details missing from this saved scan.',
              style: TextStyle(color: muted, fontSize: 14, height: 1.4),
            ),
          ),
        _section('What does the result mean?', [
          Text(
            LettuceScanReport.text(data, [
              'disease_description',
            ], fallback: 'No explanation available.'),
            style: body,
          ),
        ]),
        _section('About the pathogen', [
          Text(
            LettuceScanReport.text(data, [
              'pathogen_description',
            ], fallback: 'No pathogen details available.'),
            style: body,
          ),
        ]),
        _section('What should I do?', [
          if (treatments.isEmpty)
            const Text('No treatment guidance available.', style: body),
          for (final treatment in treatments)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $treatment', style: body),
            ),
        ]),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xffecf4ed),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _section('Can I sell this lettuce?', [
              Text(
                selling.isEmpty ? 'No selling guidance available.' : selling,
                style: body.copyWith(fontWeight: FontWeight.w800),
              ),
              if (reason.isNotEmpty) Text(reason, style: body),
              const SizedBox(height: 6),
              const Text(
                LettuceScanReport.advisory,
                style: TextStyle(color: muted, fontSize: 14, height: 1.4),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          date == null
              ? 'Scan date unavailable'
              : DateFormat.yMMMd().add_jm().format(date.toLocal()),
          style: const TextStyle(color: muted, fontSize: 15),
        ),
        if (location.isNotEmpty)
          Text(
            'Location: $location',
            style: const TextStyle(color: muted, fontSize: 15),
          ),
        if (weather.isNotEmpty || tempValue != null)
          Text(
            'Weather: ${[if (weather.isNotEmpty) weather, if (tempValue != null) '${tempValue.toStringAsFixed(1)} °C'].join(' · ')}',
            style: const TextStyle(color: muted, fontSize: 15),
          ),
        if (device == 'DEMO_MODE')
          const Text('Demo scan', style: TextStyle(color: muted, fontSize: 15)),
      ],
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        ...children,
      ],
    ),
  );
}

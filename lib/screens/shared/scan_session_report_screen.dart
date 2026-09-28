import 'dart:typed_data';

import 'package:flutter/material.dart';

class ScanSessionReportScreen extends StatelessWidget {
  const ScanSessionReportScreen({
    super.key,
    required this.scans,
    required this.startedAt,
    required this.completedAt,
    this.historyMode = false,
  });

  final List<Map<String, dynamic>> scans;
  final DateTime startedAt;
  final DateTime completedAt;

  // false = report immediately after scanning
  // true  = old report opened from Scan History
  final bool historyMode;

  // ============================================================
  // NORMALIZE
  // ============================================================

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('_', ' ')
        .trim();
  }

  String _diseaseName(
    Map<String, dynamic> scan,
  ) {
    return (
      scan['disease_name'] ??
          scan['result'] ??
          scan['disease'] ??
          scan['label'] ??
          'Unknown'
    )
        .toString()
        .replaceAll('_', ' ')
        .trim();
  }

  // ============================================================
  // CONFIDENCE
  // ============================================================

  double _confidence(
    Map<String, dynamic> scan,
  ) {
    final dynamic raw =
        scan['confidence'] ??
        scan['confidence_score'] ??
        scan['score'];

    if (raw == null) {
      return 0.0;
    }

    final double value =
        raw is num
            ? raw.toDouble()
            : double.tryParse(
                  raw.toString(),
                ) ??
                0.0;

    // Normalize to 0.0 - 1.0
    return value > 1.0
        ? value / 100.0
        : value;
  }

  // ============================================================
  // DISEASE MATCH
  // ============================================================

  bool _matches(
    Map<String, dynamic> scan,
    String disease,
  ) {
    final String current =
        _normalize(
      _diseaseName(scan),
    );

    final String target =
        _normalize(disease);

    if (target == 'septoria blight') {
      return current == 'septoria blight' ||
          current == 'septoria leaf spot';
    }

    return current == target;
  }

  int _count(String disease) {
    return scans.where(
      (scan) {
        return _matches(
          scan,
          disease,
        );
      },
    ).length;
  }

  // ============================================================
  // AVERAGE CONFIDENCE
  // ============================================================

  double _averageConfidence(
    String disease,
  ) {
    final List<Map<String, dynamic>>
        matching =
        scans.where(
      (scan) {
        return _matches(
          scan,
          disease,
        );
      },
    ).toList();

    if (matching.isEmpty) {
      return 0.0;
    }

    double total = 0.0;

    for (final scan in matching) {
      total += _confidence(scan);
    }

    return total / matching.length;
  }

  double _percent(int count) {
    if (scans.isEmpty) {
      return 0.0;
    }

    return count /
        scans.length *
        100.0;
  }

  // ============================================================
  // HEALTHY
  // ============================================================

  bool _isHealthy(
    String disease,
  ) {
    final String value =
        _normalize(disease);

    return value == 'healthy' ||
        value == 'none' ||
        value == 'no disease';
  }

  // ============================================================
  // PATHOGEN
  // ============================================================

  String _pathogen(
    String disease,
  ) {
    final String value =
        _normalize(disease);

    if (value == 'downy mildew') {
      return 'Bremia lactucae';
    }

    if (value == 'powdery mildew') {
      return 'Erysiphe cichoracearum';
    }

    if (value == 'septoria blight' ||
        value == 'septoria leaf spot') {
      return 'Septoria lactucae';
    }

    if (_isHealthy(disease)) {
      return 'None detected';
    }

    return 'Not available';
  }

  // ============================================================
  // SIMPLE DESCRIPTION
  // ============================================================

  String _description(
    String disease,
  ) {
    final String value =
        _normalize(disease);

    if (_isHealthy(disease)) {
      return 'No visible signs of Downy Mildew, Powdery Mildew, '
          'or Septoria Blight were detected. GreenGuard classifies '
          'this lettuce as healthy based on this scan.';
    }

    if (value == 'downy mildew') {
      return 'Downy Mildew can cause yellow or pale spots on the '
          'lettuce leaves and mold-like growth underneath the leaf.';
    }

    if (value == 'powdery mildew') {
      return 'Powdery Mildew usually looks like white powder on '
          'the leaves and may spread across the lettuce plant.';
    }

    if (value == 'septoria blight' ||
        value == 'septoria leaf spot') {
      return 'Septoria Blight causes small brown or dark spots '
          'that may grow and damage lettuce leaves.';
    }

    return 'GreenGuard completed the lettuce health scan.';
  }

  // ============================================================
  // PATHOGEN DESCRIPTION
  // ============================================================

  String _pathogenDescription(
    String disease,
  ) {
    final String value =
        _normalize(disease);

    if (_isHealthy(disease)) {
      return 'No supported disease-causing pathogen was detected '
          'in this lettuce image.';
    }

    if (value == 'downy mildew') {
      return 'Bremia lactucae is a disease-causing microorganism '
          'that infects lettuce leaves. It grows well in cool, '
          'wet, and humid conditions.';
    }

    if (value == 'powdery mildew') {
      return 'Erysiphe cichoracearum is a fungus that grows on '
          'plant surfaces and can appear like white powder on '
          'lettuce leaves.';
    }

    if (value == 'septoria blight' ||
        value == 'septoria leaf spot') {
      return 'Septoria lactucae is a fungus that infects lettuce '
          'leaves and causes brown or dark leaf spots.';
    }

    return 'No pathogen information is available.';
  }

  // ============================================================
  // COLOR
  // ============================================================

  Color _diseaseColor(
    String disease,
  ) {
    final String value =
        _normalize(disease);

    if (_isHealthy(disease)) {
      return const Color(
        0xFF5DBB63,
      );
    }

    if (value == 'downy mildew') {
      return Colors.redAccent;
    }

    if (value == 'powdery mildew') {
      return Colors.orange;
    }

    if (value.contains('septoria')) {
      return Colors.deepOrange;
    }

    return Colors.grey;
  }

  // ============================================================
  // DATE
  // ============================================================

  DateTime? _capturedAt(
    Map<String, dynamic> scan,
  ) {
    final dynamic raw =
        scan['captured_at'] ??
        scan['created_at'];

    if (raw == null) {
      return null;
    }

    return DateTime.tryParse(
      raw.toString(),
    );
  }

  String _formatDateTime(
    DateTime value,
  ) {
    final DateTime local =
        value.toLocal();

    final int rawHour =
        local.hour;

    final int displayHour =
        rawHour == 0
            ? 12
            : rawHour > 12
                ? rawHour - 12
                : rawHour;

    final String minute =
        local.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    final String amPm =
        rawHour >= 12
            ? 'PM'
            : 'AM';

    return '${local.month}/${local.day}/${local.year} • '
        '$displayHour:$minute $amPm';
  }

  // ============================================================
  // IMAGE
  // ============================================================

  Widget _scanImage(
    Map<String, dynamic> scan,
  ) {
    final dynamic rawImage =
        scan['image_bytes'];

    final Uint8List? imageBytes =
        rawImage is Uint8List
            ? rawImage
            : null;

    final String imageUrl =
        scan['image_url']
                ?.toString()
                .trim() ??
            '';

    if (imageBytes != null &&
        imageBytes.isNotEmpty) {
      return Image.memory(
        imageBytes,
        width: 105,
        height: 105,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }

    if (imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        width: 105,
        height: 105,
        fit: BoxFit.cover,
        errorBuilder: (
          context,
          error,
          stackTrace,
        ) {
          return _imageUnavailable();
        },
        loadingBuilder: (
          context,
          child,
          progress,
        ) {
          if (progress == null) {
            return child;
          }

          return Container(
            width: 105,
            height: 105,
            color:
                const Color(
              0xFFEAF4EB,
            ),
            child:
                const Center(
              child:
                  CircularProgressIndicator(
                color:
                    Color(
                  0xFF2F6B3B,
                ),
                strokeWidth: 2,
              ),
            ),
          );
        },
      );
    }

    return _imageUnavailable();
  }

  Widget _imageUnavailable() {
    return Container(
      width: 105,
      height: 105,
      color:
          const Color(
        0xFFEAF4EB,
      ),
      child:
          const Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_rounded,
            color:
                Color(
              0xFF2F6B3B,
            ),
            size: 34,
          ),
          SizedBox(
            height: 6,
          ),
          Text(
            'Image\nunavailable',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              fontSize: 10,
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

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final int total =
        scans.length;

    final int healthy =
        _count(
      'Healthy',
    );

    final int downy =
        _count(
      'Downy Mildew',
    );

    final int powdery =
        _count(
      'Powdery Mildew',
    );

    final int septoria =
        _count(
      'Septoria Blight',
    );

    final int notHealthy =
        downy +
        powdery +
        septoria;

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
        foregroundColor:
            const Color(
          0xFF1E2A1F,
        ),
        title: Text(
          historyMode
              ? 'Scan Report'
              : 'Final Scan Report',
          style:
              const TextStyle(
            fontSize: 21,
            fontWeight:
                FontWeight.w900,
            color:
                Color(
              0xFF1E2A1F,
            ),
          ),
        ),
      ),

      body: ListView(
        padding:
            const EdgeInsets.all(
          18,
        ),
        children: [
          // ====================================================
          // HEADER
          // ====================================================

          Container(
            width:
                double.infinity,
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
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.assessment_rounded,
                  size: 44,
                  color:
                      Colors.white,
                ),

                const SizedBox(
                  height: 14,
                ),

                const Text(
                  'Lettuce Scan Summary',
                  style:
                      TextStyle(
                    fontSize: 25,
                    fontWeight:
                        FontWeight.w900,
                    color:
                        Colors.white,
                  ),
                ),

                const SizedBox(
                  height: 8,
                ),

                Text(
                  'Started: ${_formatDateTime(startedAt)}',
                  style:
                      TextStyle(
                    color:
                        Colors.white
                            .withValues(
                      alpha: 0.85,
                    ),
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),

                const SizedBox(
                  height: 4,
                ),

                Text(
                  'Completed: ${_formatDateTime(completedAt)}',
                  style:
                      TextStyle(
                    color:
                        Colors.white
                            .withValues(
                      alpha: 0.85,
                    ),
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),

                const SizedBox(
                  height: 22,
                ),

                Row(
                  children: [
                    Expanded(
                      child:
                          _headerMetric(
                        'TOTAL',
                        total.toString(),
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child:
                          _headerMetric(
                        'HEALTHY',
                        healthy.toString(),
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child:
                          _headerMetric(
                        'AT RISK',
                        notHealthy
                            .toString(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(
            height: 18,
          ),

          // ====================================================
          // SELLABLE SUMMARY
          // ====================================================

          Row(
            children: [
              Expanded(
                child:
                    _statusSummaryCard(
                  title:
                      'Healthy / Sellable Estimate',
                  count:
                      healthy,
                  percent:
                      _percent(
                    healthy,
                  ),
                  color:
                      const Color(
                    0xFF5DBB63,
                  ),
                  icon:
                      Icons.verified_rounded,
                ),
              ),

              const SizedBox(
                width: 12,
              ),

              Expanded(
                child:
                    _statusSummaryCard(
                  title:
                      'Not Healthy / Not Sellable',
                  count:
                      notHealthy,
                  percent:
                      _percent(
                    notHealthy,
                  ),
                  color:
                      Colors.redAccent,
                  icon:
                      Icons.warning_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 18,
          ),

          // ====================================================
          // DISEASE BREAKDOWN
          // ====================================================

          Container(
            width:
                double.infinity,
            padding:
                const EdgeInsets.all(
              20,
            ),
            decoration:
                BoxDecoration(
              color:
                  Colors.white,
              borderRadius:
                  BorderRadius.circular(
                24,
              ),
            ),
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Disease Breakdown',
                  style:
                      TextStyle(
                    fontSize: 21,
                    fontWeight:
                        FontWeight.w900,
                    color:
                        Color(
                      0xFF1E2A1F,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 16,
                ),

                _diseaseRow(
                  disease:
                      'Healthy',
                  count:
                      healthy,
                ),

                _diseaseRow(
                  disease:
                      'Downy Mildew',
                  count:
                      downy,
                ),

                _diseaseRow(
                  disease:
                      'Powdery Mildew',
                  count:
                      powdery,
                ),

                _diseaseRow(
                  disease:
                      'Septoria Blight',
                  count:
                      septoria,
                ),
              ],
            ),
          ),

          const SizedBox(
            height: 18,
          ),

          // ====================================================
          // INDIVIDUAL LETTUCE
          // ====================================================

          const Text(
            'Individual Lettuce Results',
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
            height: 6,
          ),

          const Text(
            'Each approved lettuce image and its GreenGuard diagnosis.',
            style:
                TextStyle(
              fontSize: 14,
              fontWeight:
                  FontWeight.w600,
              color:
                  Colors.grey,
            ),
          ),

          const SizedBox(
            height: 14,
          ),

          if (scans.isEmpty)
            Container(
              padding:
                  const EdgeInsets.all(
                30,
              ),
              decoration:
                  BoxDecoration(
                color:
                    Colors.white,
                borderRadius:
                    BorderRadius.circular(
                  24,
                ),
              ),
              child:
                  const Center(
                child:
                    Text(
                  'No lettuce results are available in this report.',
                  textAlign:
                      TextAlign.center,
                ),
              ),
            )
          else
            ...List.generate(
              scans.length,
              (
                int index,
              ) {
                return _lettuceCard(
                  scan:
                      scans[index],
                  number:
                      index + 1,
                );
              },
            ),

          const SizedBox(
            height: 10,
          ),

          // ====================================================
          // IMPORTANT NOTE
          // ====================================================

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
                  const Color(
                0xFFFFF8E8,
              ),
              borderRadius:
                  BorderRadius.circular(
                18,
              ),
              border:
                  Border.all(
                color:
                    Colors.orange
                        .withValues(
                  alpha: 0.25,
                ),
              ),
            ),
            child:
                const Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color:
                      Colors.orange,
                ),

                SizedBox(
                  width: 10,
                ),

                Expanded(
                  child:
                      Text(
                    'Sellable Estimate is based only on the supported '
                    'GreenGuard disease classes: Healthy, Downy Mildew, '
                    'Powdery Mildew, and Septoria Blight.',
                    style:
                        TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: 20,
          ),

          // ====================================================
          // START NEW SCAN
          // ====================================================

          if (!historyMode) ...[
            SizedBox(
              width:
                  double.infinity,
              height: 58,
              child:
                  ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(
                    context,
                    true,
                  );
                },
                icon:
                    const Icon(
                  Icons
                      .document_scanner_rounded,
                ),
                label:
                    const Text(
                  'Start New Scan',
                  style:
                      TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
                style:
                    ElevatedButton
                        .styleFrom(
                  backgroundColor:
                      const Color(
                    0xFF2F6B3B,
                  ),
                  foregroundColor:
                      Colors.white,
                  elevation: 0,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      18,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 12,
            ),
          ],

          SizedBox(
            width:
                double.infinity,
            height: 56,
            child:
                OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              icon:
                  const Icon(
                Icons.close_rounded,
              ),
              label:
                  Text(
                historyMode
                    ? 'Close Report'
                    : 'Cancel / Close Report',
                style:
                    const TextStyle(
                  fontSize: 15,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
              style:
                  OutlinedButton
                      .styleFrom(
                foregroundColor:
                    const Color(
                  0xFF2F6B3B,
                ),
                side:
                    const BorderSide(
                  color:
                      Color(
                    0xFF2F6B3B,
                  ),
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    18,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(
            height: 20,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HEADER METRIC
  // ============================================================

  Widget _headerMetric(
    String label,
    String value,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        vertical: 13,
        horizontal: 8,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.white
                .withValues(
          alpha: 0.10,
        ),
        borderRadius:
            BorderRadius.circular(
          16,
        ),
      ),
      child:
          Column(
        children: [
          Text(
            value,
            style:
                const TextStyle(
              color:
                  Colors.white,
              fontSize: 22,
              fontWeight:
                  FontWeight.w900,
            ),
          ),

          const SizedBox(
            height: 3,
          ),

          Text(
            label,
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              color:
                  Colors.white
                      .withValues(
                alpha: 0.75,
              ),
              fontSize: 10,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STATUS SUMMARY CARD
  // ============================================================

  Widget _statusSummaryCard({
    required String title,
    required int count,
    required double percent,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding:
          const EdgeInsets.all(
        16,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.white,
        borderRadius:
            BorderRadius.circular(
          22,
        ),
        border:
            Border.all(
          color:
              color.withValues(
            alpha: 0.20,
          ),
        ),
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 28,
          ),

          const SizedBox(
            height: 10,
          ),

          Text(
            count.toString(),
            style:
                TextStyle(
              fontSize: 27,
              fontWeight:
                  FontWeight.w900,
              color: color,
            ),
          ),

          const SizedBox(
            height: 3,
          ),

          Text(
            '${percent.toStringAsFixed(1)}%',
            style:
                const TextStyle(
              fontSize: 15,
              fontWeight:
                  FontWeight.w800,
              color:
                  Color(
                0xFF1E2A1F,
              ),
            ),
          ),

          const SizedBox(
            height: 7,
          ),

          Text(
            title,
            style:
                const TextStyle(
              fontSize: 12,
              height: 1.3,
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

  // ============================================================
  // DISEASE ROW
  // ============================================================

  Widget _diseaseRow({
    required String disease,
    required int count,
  }) {
    final Color color =
        _diseaseColor(
      disease,
    );

    final double average =
        _averageConfidence(
      disease,
    );

    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 10,
      ),
      padding:
          const EdgeInsets.all(
        14,
      ),
      decoration:
          BoxDecoration(
        color:
            color.withValues(
          alpha: 0.06,
        ),
        borderRadius:
            BorderRadius.circular(
          16,
        ),
      ),
      child:
          Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration:
                BoxDecoration(
              color: color,
              shape:
                  BoxShape.circle,
            ),
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            child:
                Text(
              disease,
              style:
                  const TextStyle(
                fontSize: 15,
                fontWeight:
                    FontWeight.w800,
                color:
                    Color(
                  0xFF1E2A1F,
                ),
              ),
            ),
          ),

          Column(
            crossAxisAlignment:
                CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style:
                    TextStyle(
                  fontSize: 17,
                  fontWeight:
                      FontWeight.w900,
                  color: color,
                ),
              ),

              if (count > 0)
                Text(
                  'Avg ${(average * 100).toStringAsFixed(1)}%',
                  style:
                      const TextStyle(
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w600,
                    color:
                        Colors.grey,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LETTUCE CARD
  // ============================================================

  Widget _lettuceCard({
    required Map<String, dynamic> scan,
    required int number,
  }) {
    final String disease =
        _diseaseName(
      scan,
    );

    final double confidence =
        _confidence(
      scan,
    );

    final DateTime? capturedAt =
        _capturedAt(
      scan,
    );

    final bool healthy =
        _isHealthy(
      disease,
    );

    final Color color =
        _diseaseColor(
      disease,
    );

    return Container(
      width:
          double.infinity,
      margin:
          const EdgeInsets.only(
        bottom: 16,
      ),
      padding:
          const EdgeInsets.all(
        16,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.white,
        borderRadius:
            BorderRadius.circular(
          24,
        ),
        border:
            Border.all(
          color:
              color.withValues(
            alpha: 0.22,
          ),
        ),
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          // IMAGE + MAIN RESULT

          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(
                  16,
                ),
                child:
                    _scanImage(
                  scan,
                ),
              ),

              const SizedBox(
                width: 14,
              ),

              Expanded(
                child:
                    Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lettuce #$number',
                      style:
                          const TextStyle(
                        fontSize: 13,
                        fontWeight:
                            FontWeight.w800,
                        color:
                            Colors.grey,
                      ),
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      disease,
                      style:
                          TextStyle(
                        fontSize: 20,
                        fontWeight:
                            FontWeight.w900,
                        color: color,
                      ),
                    ),

                    const SizedBox(
                      height: 6,
                    ),

                    Text(
                      'Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
                      style:
                          const TextStyle(
                        fontSize: 14,
                        fontWeight:
                            FontWeight.w800,
                        color:
                            Color(
                          0xFF1E2A1F,
                        ),
                      ),
                    ),

                    if (capturedAt !=
                        null) ...[
                      const SizedBox(
                        height: 5,
                      ),

                      Text(
                        'Captured: ${_formatDateTime(capturedAt)}',
                        style:
                            const TextStyle(
                          fontSize: 11,
                          fontWeight:
                              FontWeight.w600,
                          color:
                              Colors.grey,
                        ),
                      ),
                    ],

                    const SizedBox(
                      height: 8,
                    ),

                    Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            color.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          20,
                        ),
                      ),
                      child:
                          Text(
                        healthy
                            ? 'HEALTHY / SELLABLE ESTIMATE'
                            : 'NOT HEALTHY / NOT SELLABLE',
                        style:
                            TextStyle(
                          fontSize: 10,
                          fontWeight:
                              FontWeight.w900,
                          color: color,
                        ),
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

          const Divider(),

          const SizedBox(
            height: 12,
          ),

          Text(
            healthy
                ? 'Pathogen: None detected'
                : 'Pathogen: ${_pathogen(disease)}',
            style:
                const TextStyle(
              fontSize: 15,
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

          Container(
            width:
                double.infinity,
            padding:
                const EdgeInsets.all(
              15,
            ),
            decoration:
                BoxDecoration(
              color:
                  color.withValues(
                alpha: 0.06,
              ),
              borderRadius:
                  BorderRadius.circular(
                16,
              ),
            ),
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'What does this mean?',
                  style:
                      TextStyle(
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w900,
                    color:
                        Color(
                      0xFF1E2A1F,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                Text(
                  _description(
                    disease,
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

                const SizedBox(
                  height: 14,
                ),

                const Divider(),

                const SizedBox(
                  height: 10,
                ),

                const Text(
                  'What is this pathogen?',
                  style:
                      TextStyle(
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w900,
                    color:
                        Color(
                      0xFF1E2A1F,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                Text(
                  _pathogenDescription(
                    disease,
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
          ),
        ],
      ),
    );
  }
}
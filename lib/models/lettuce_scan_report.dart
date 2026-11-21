import 'dart:convert';

import 'package:flutter/services.dart';

class LettuceScanReport {
  static const diseaseNames = {
    'healthy': 'Healthy',
    'downy mildew': 'Downy Mildew',
    'powdery mildew': 'Powdery Mildew',
    'septoria blight': 'Septoria Blight',
  };

  static const snapshotFields = [
    'pathogen_name',
    'disease_description',
    'pathogen_description',
    'treatment_recommendations',
    'selling_recommendation',
    'selling_explanation',
  ];

  static const advisory =
      'A photo cannot confirm food safety. Check the whole lettuce before selling.';

  static final Future<Map<String, dynamic>> _guide = _loadGuide();

  static Future<Map<String, dynamic>> _loadGuide() async {
    final source = await rootBundle.loadString(
      'assets/data/lettuce_scan_guidance.json',
    );
    return Map<String, dynamic>.from(jsonDecode(source) as Map);
  }

  static String diseaseKey(String name) {
    final key = name.trim().toLowerCase().replaceAll(RegExp(r'[_\s]+'), ' ');
    return switch (key) {
      'none' || 'no disease' => 'healthy',
      'septoria leaf spot' => 'septoria blight',
      _ => key,
    };
  }

  static String diseaseName(Map<String, dynamic> scan) {
    final value = text(scan, [
      'disease_name',
      'result',
      'disease',
      'label',
    ], fallback: 'Unknown result');
    return diseaseNames[diseaseKey(value)] ?? value.replaceAll('_', ' ');
  }

  static double? confidence(Map<String, dynamic> scan) {
    final raw = text(scan, ['confidence_score', 'confidence', 'score']);
    final value = double.tryParse(raw.replaceAll('%', '').trim());
    if (value == null || !value.isFinite || value < 0 || value > 100) {
      return null;
    }
    return value > 1 || raw.endsWith('%') ? value / 100 : value;
  }

  static String text(
    Map<String, dynamic> values,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = values[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  static DateTime? capturedAt(Map<String, dynamic> scan) =>
      DateTime.tryParse(text(scan, ['captured_at', 'created_at']));

  static List<String> treatment(Map<String, dynamic> values) {
    final value = values['treatment_recommendations'];
    if (value is List) {
      return value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return treatment({'treatment_recommendations': decoded});
        }
      } on FormatException {
        // Older snapshots can contain plain text.
      }
      return [value.trim()];
    }
    return [];
  }

  static Future<Map<String, dynamic>> guidance(String disease) async {
    final entry = (await _guide)[diseaseKey(disease)];
    return entry is Map ? Map<String, dynamic>.from(entry) : {};
  }

  static Future<({Map<String, dynamic> values, bool usedReference})> resolve(
    Map<String, dynamic> scan,
  ) async {
    final values = Map<String, dynamic>.of(scan);
    final missing = snapshotFields.where((field) {
      if (field == 'treatment_recommendations') return treatment(scan).isEmpty;
      return text(scan, [field]).isEmpty;
    }).toList();
    if (missing.isEmpty) return (values: values, usedReference: false);

    final reference = await guidance(diseaseName(scan));
    var usedReference = false;
    for (final field in missing) {
      if (reference[field] != null) {
        values[field] = reference[field];
        usedReference = true;
      }
    }
    return (values: values, usedReference: usedReference);
  }
}

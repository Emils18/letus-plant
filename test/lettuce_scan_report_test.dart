import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letus_plant/models/lettuce_scan_report.dart';
import 'package:letus_plant/screens/shared/scan_session_report_screen.dart';
import 'package:letus_plant/widgets/lettuce_scan_report_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> healthy;
  late Map<String, dynamic> septoria;

  setUpAll(() async {
    healthy = await LettuceScanReport.guidance('healthy');
    septoria = await LettuceScanReport.guidance('septoria blight');
  });

  test(
    'known legacy labels resolve guidance without changing saved values',
    () async {
      final saved = <String, dynamic>{
        'disease_name': 'Downy_Mildew',
        'confidence_score': 0.948,
        'selling_explanation': 'This is the original saved explanation.',
      };

      final report = await LettuceScanReport.resolve(saved);

      expect(LettuceScanReport.diseaseName(saved), 'Downy Mildew');
      expect(LettuceScanReport.confidence(saved), 0.948);
      expect(report.values['pathogen_name'], 'Bremia lactucae');
      expect(
        report.values['selling_explanation'],
        saved['selling_explanation'],
      );
      expect(report.usedReference, isTrue);
      expect(saved.containsKey('pathogen_name'), isFalse);
    },
  );

  test('unknown scans and missing confidence remain unknown', () async {
    final scan = <String, dynamic>{'disease_name': 'Unclassified'};

    final report = await LettuceScanReport.resolve(scan);

    expect(LettuceScanReport.confidence(scan), isNull);
    expect(
      LettuceScanReport.confidence({'confidence': '94.8%'}),
      closeTo(.948, .0001),
    );
    expect(LettuceScanReport.confidence({'confidence': '1%'}), .01);
    expect(report.values['pathogen_name'], isNull);
    expect(report.usedReference, isFalse);
  });

  testWidgets('individual report expands to show its own advice and status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LettuceScanReportCard(
              scan: {
                ...healthy,
                'disease_name': 'Healthy',
                'confidence_score': .755,
                'location': 'Busay',
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('75.5% confidence'), findsOneWidget);
    await tester.tap(find.text('Report details'));
    await tester.pumpAndSettle();

    expect(find.text('No pathogen detected'), findsOneWidget);
    expect(find.text('Consider selling after inspection'), findsOneWidget);
    expect(find.text('Location: Busay'), findsOneWidget);
    expect(find.text(LettuceScanReport.advisory), findsOneWidget);
  });

  testWidgets('final report keeps healthy and diseased photos separate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScanSessionReportScreen(
          scans: [
            {...healthy, 'disease_name': 'Healthy', 'confidence_score': .82},
            {
              ...septoria,
              'disease_name': 'Septoria Blight',
              'confidence_score': .62,
            },
          ],
          startedAt: DateTime.utc(2026, 11, 21),
          completedAt: DateTime.utc(2026, 11, 21),
        ),
      ),
    );
    expect(find.text('Final Scan Report'), findsOneWidget);
    expect(find.text('Total lettuce scanned'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Photo 2'), 240);
    expect(find.text('62.0% confidence'), findsOneWidget);
    expect(find.text('Septoria lactucae'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Selling guidance'), 240);
    expect(
      find.textContaining('Set aside the 1 affected lettuce'),
      findsOneWidget,
    );
  });

  testWidgets('overall report opens with all scans and no session actions', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: ScanSessionReportScreen(
        scans: [
          {'disease_name': 'Healthy', 'confidence_score': .82},
          {'disease_name': 'Downy Mildew', 'confidence_score': .76},
        ],
        startedAt: null,
        completedAt: null,
        overallMode: true,
        historyMode: true,
      ),
    ));
    expect(find.text('Overall Health Report'), findsOneWidget);
    expect(find.text('Total lettuce scanned'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Photo 2'), 240);
    expect(find.text('76.0% confidence'), findsOneWidget);
    expect(find.text('Start a new session'), findsNothing);
  });
}

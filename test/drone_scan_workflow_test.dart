import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letus_plant/screens/scan_mode_screen.dart';
import 'package:letus_plant/services/inav_diagnostics_service.dart';

void main() {
  group('MSP v1 codec', () {
    test('encodes a read request with the MSP checksum', () {
      expect(
        InavDiagnosticsService.encodeRequest(1),
        orderedEquals(<int>[0x24, 0x4d, 0x3c, 0, 1, 1]),
      );
    });

    test('accepts a valid response and rejects a bad checksum', () {
      final frame = <int>[0x24, 0x4d, 0x3e, 3, 2, 1, 2, 3];
      var checksum = 0;
      for (final byte in frame.skip(3)) {
        checksum ^= byte;
      }
      frame.add(checksum);

      final reply = InavDiagnosticsService.takeReply(frame, 2);
      expect(reply?.command, 2);
      expect(reply?.payload, orderedEquals(Uint8List.fromList([1, 2, 3])));

      frame[frame.length - 1] ^= 1;
      expect(InavDiagnosticsService.takeReply(frame, 2), isNull);
    });
  });

  testWidgets(
    'Scan Disease keeps scan modes and adds automatic flight planning',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ScanModeScreen()));

      expect(find.text('Drone Manual Scan'), findsOneWidget);
      expect(find.text('Drone readiness check'), findsOneWidget);
      expect(find.text('Automatic Flight Plan'), findsOneWidget);
      expect(find.text('Manual Farmer Scan'), findsNothing);
    },
  );

  testWidgets('automatic diagnostics starts without claiming readiness', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DroneReadinessScreen()));

    expect(find.text('START DIAGNOSTIC'), findsOneWidget);
    expect(find.text('Connection: DISCONNECTED'), findsOneWidget);
    expect(find.text('READY'), findsNothing);
  });
}

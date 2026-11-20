import 'package:flutter_test/flutter_test.dart';
import 'package:letus_plant/services/monitoring_service.dart';

void main() {
  group('soil ESP32 response parsing', () {
    test('parses all fields from a real firmware response', () {
      final receivedAt = DateTime.utc(2026, 11, 17, 1, 30);
      final result = MonitoringService.parseSoilResponse(
        '{"soil_moisture":45,"soil_raw":1800,"soil_status":"IDEAL","device_ip":"10.181.71.214"}',
        requestedIp: '10.181.71.214',
        receivedAt: receivedAt,
      );

      expect(result['connected'], isTrue);
      expect(result['connection_state'], 'CONNECTED');
      expect(result['soil_moisture'], 45);
      expect(result['soil_raw'], 1800);
      expect(result['soil_status'], 'IDEAL');
      expect(result['device_ip'], '10.181.71.214');
      expect(result['last_successful_update'], receivedAt.toIso8601String());
    });

    test('rejects a response missing any required firmware field', () {
      expect(
        () => MonitoringService.parseSoilResponse(
          '{"soil_moisture":45,"soil_raw":1800,"soil_status":"IDEAL"}',
          requestedIp: '10.181.71.214',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects out-of-range moisture and unknown soil conditions', () {
      expect(
        () => MonitoringService.parseSoilResponse(
          '{"soil_moisture":101,"soil_raw":1800,"soil_status":"IDEAL","device_ip":"10.181.71.214"}',
          requestedIp: '10.181.71.214',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => MonitoringService.parseSoilResponse(
          '{"soil_moisture":45,"soil_raw":1800,"soil_status":"UNKNOWN","device_ip":"10.181.71.214"}',
          requestedIp: '10.181.71.214',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

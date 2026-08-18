import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/services/wifi_attendance_service.dart';

void main() {
  group('WifiAttendanceService.normalizeSsid', () {
    test('strips surrounding quotes and trims whitespace', () {
      expect(WifiAttendanceService.normalizeSsid('"Cashback"'), 'Cashback');
      expect(WifiAttendanceService.normalizeSsid('  Cashback  '), 'Cashback');
      expect(WifiAttendanceService.normalizeSsid('"Cashback_5G" '), 'Cashback_5G');
    });
  });

  group('WifiAttendanceService.matchesCompany', () {
    const configured = ['Cashback_Office', 'Cashback_Office_5G', 'Cashback_Office_2'];

    test('matches the first configured network', () {
      expect(WifiAttendanceService.matchesCompany('Cashback_Office', configured), isTrue);
    });

    test('matches a later configured network (no first/second bias)', () {
      expect(WifiAttendanceService.matchesCompany('Cashback_Office_5G', configured), isTrue);
      expect(WifiAttendanceService.matchesCompany('Cashback_Office_2', configured), isTrue);
    });

    test('normalizes both sides consistently (quotes + whitespace)', () {
      expect(WifiAttendanceService.matchesCompany('"Cashback_Office_5G"', configured), isTrue);
      expect(WifiAttendanceService.matchesCompany('  Cashback_Office_2 ', configured), isTrue);
    });

    test('does not match a network outside the list', () {
      expect(WifiAttendanceService.matchesCompany('Home_WiFi', configured), isFalse);
      expect(WifiAttendanceService.matchesCompany('Neighbor_5G', configured), isFalse);
    });

    test('null / empty current SSID is not on the company network', () {
      expect(WifiAttendanceService.matchesCompany(null, configured), isFalse);
      expect(WifiAttendanceService.matchesCompany('', configured), isFalse);
      expect(WifiAttendanceService.matchesCompany('   ', configured), isFalse);
    });

    test('empty config means not SSID-gated (any WiFi counts)', () {
      expect(WifiAttendanceService.matchesCompany('anything', const []), isTrue);
      expect(WifiAttendanceService.matchesCompany(null, const []), isTrue);
    });
  });
}

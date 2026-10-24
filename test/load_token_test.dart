// Stale-guard logic for department-switch races.

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/utils/load_token.dart';

void main() {
  group('LoadToken (latest-wins)', () {
    test('a fresh token is current', () {
      final t = LoadToken();
      final a = t.begin();
      expect(t.isStale(a), isFalse);
    });

    test('an earlier load is stale once a newer one starts (dept switch)', () {
      final t = LoadToken();
      final deptA = t.begin(); // load for Department A
      final deptB = t.begin(); // user switched → load for Department B
      expect(t.isStale(deptA), isTrue);  // A's late response is discarded
      expect(t.isStale(deptB), isFalse); // B's response is applied
    });

    test('rapid switching: only the last token wins', () {
      final t = LoadToken();
      final a = t.begin();
      final b = t.begin();
      final c = t.begin();
      expect(t.isStale(a), isTrue);
      expect(t.isStale(b), isTrue);
      expect(t.isStale(c), isFalse);
    });

    test('out-of-order completion: older finishing after newer is still stale', () {
      final t = LoadToken();
      final first = t.begin();
      final second = t.begin();
      // second completes, then first completes late:
      expect(t.isStale(second), isFalse);
      expect(t.isStale(first), isTrue);
    });
  });
}

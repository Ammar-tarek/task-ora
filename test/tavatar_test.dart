// test/tavatar_test.dart
// Regression: TAvatar must not crash on an empty/whitespace name (a profile
// with no full name) — it previously threw RangeError from codeUnitAt(0).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, String name) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: TAvatar(name: name)))),
  );
}

void main() {
  group('TAvatar', () {
    testWidgets('empty name renders a safe fallback, no crash', (tester) async {
      await _pump(tester, '');
      expect(tester.takeException(), isNull);
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('whitespace-only name renders fallback, no crash', (tester) async {
      await _pump(tester, '   ');
      expect(tester.takeException(), isNull);
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('normal full name shows two initials', (tester) async {
      await _pump(tester, 'Ammar Nasser');
      expect(tester.takeException(), isNull);
      expect(find.text('AN'), findsOneWidget);
    });

    testWidgets('single short name shows its letters', (tester) async {
      await _pump(tester, 'Jo');
      expect(tester.takeException(), isNull);
      expect(find.text('JO'), findsOneWidget);
    });
  });
}

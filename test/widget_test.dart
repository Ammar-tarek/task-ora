import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/main.dart';
import 'package:task_ora/core/router/app_router.dart';
import 'package:task_ora/core/auth/auth_notifier.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final auth = AuthNotifier();
    final router = makeRouter(auth);
    await tester.pumpWidget(CbToDoApp(router: router));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

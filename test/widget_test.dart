import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:task_ora/main.dart';
import 'package:task_ora/core/router/app_router.dart';
import 'package:task_ora/core/auth/auth_notifier.dart';
import 'package:task_ora/core/providers/locale_controller.dart';
import 'package:task_ora/core/providers/team_filter_notifier.dart';
import 'package:task_ora/core/providers/team_privileges_notifier.dart';
import 'package:task_ora/core/providers/theme_controller.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final auth = AuthNotifier();
    final teamPrivs = TeamPrivilegesNotifier(auth);
    final router = makeRouter(auth);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider(create: (_) => TeamFilterNotifier()),
          ChangeNotifierProvider.value(value: teamPrivs),
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => LocaleController()),
        ],
        child: CbToDoApp(router: router),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

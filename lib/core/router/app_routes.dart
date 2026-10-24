// lib/core/router/app_routes.dart
// Canonical route-path constants. Introduced in M2 for the new workspace
// routing/guard logic and its tests. Existing routes keep their string literals
// to avoid churn; new code references these constants.

class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String tasks = '/tasks';
  static const String dashboard = '/dashboard';
  static const String workspaces = '/workspaces';
  static const String expenses = '/expenses';
}

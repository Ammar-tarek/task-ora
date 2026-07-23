// lib/core/router/app_router.dart
// GoRouter with auth redirect guard — navigation is 100% automatic.
// No screen ever needs to call context.go('/login') on logout.

import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/providers/team_privileges_notifier.dart';
import '../../core/theme/app_theme.dart';

import '../../features/splash/splash_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/auth/pending_approval_screen.dart';
import '../../features/dashboard/admin_dashboard_screen.dart';
import '../../features/tasks/task_board_screen.dart';
import '../../features/tasks/task_table_screen.dart';
import '../../features/tasks/task_detail_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/finance/finance_dashboard_screen.dart';
import '../../features/finance/finance_analytics_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/analytics/advanced_analytics_screen.dart';
import '../../features/attendance/attendance_screen.dart';
import '../../features/penalties/penalty_management_screen.dart';
import '../../features/users/user_management_screen.dart';
import '../../features/users/user_privileges_screen.dart';
import '../../features/roles/roles_editor_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/expenses/daily_expenses_screen.dart';
import '../../features/teams/team_management_screen.dart';
import '../../features/teams/team_members_screen.dart';
import '../../features/teams/team_privileges_screen.dart';
import '../../features/clients/clients_screen.dart';
import '../../features/clients/client_finance_screen.dart';
import '../../features/users/create_user_screen.dart';
import '../widgets/bottom_nav_shell.dart';

/// Called from main.dart — receives the AuthNotifier so the router
/// can listen for changes via [refreshListenable].
GoRouter makeRouter(AuthNotifier auth) {
  return GoRouter(
    initialLocation: '/splash',

    // Re-evaluate [redirect] every time AuthNotifier notifies.
    // This is what makes logout / login automatically push the right route.
    refreshListenable: auth,

    redirect: (BuildContext context, GoRouterState state) {
      final loc = state.matchedLocation;
      final status = auth.status;

      // ① Session still loading — stay on splash
      if (status == AuthStatus.loading) {
        return loc == '/splash' ? null : '/splash';
      }

      // ② Not logged in — must see login screen
      if (status == AuthStatus.unauthenticated) {
        if (loc == '/login' || loc == '/forgot-password' || loc == '/signup')
          return null;
        return '/login';
      }

      // ③ Pending account — employee not yet assigned to a team.
      // They can only see the pending screen until an admin/manager adds
      // them to a team. Everything else redirects here.
      final pendingProfile = auth.profile;
      final isPending =
          pendingProfile?.isEmployee == true && pendingProfile?.teamId == null;
      if (isPending) {
        return loc == '/pending' ? null : '/pending';
      }
      // Non-pending users must never sit on the pending screen.
      if (loc == '/pending') {
        final role = auth.profile?.role ?? 'employee';
        return (role == 'admin' || role == 'manager') ? '/dashboard' : '/tasks';
      }

      // ④ Logged in — redirect away from auth-only screens
      if (loc == '/splash' || loc == '/login' || loc == '/signup') {
        final role = auth.profile?.role ?? 'employee';
        if (role == 'admin') return '/dashboard';
        if (role == 'manager') return '/dashboard';
        if (role == 'employee') return '/tasks';
        if (role == 'client') return '/tasks';
        return '/dashboard';
      }

      // ⑤ Role-based access control
      final profile = auth.profile;

      // Clients: tasks + calendar + their own finance only
      if (profile?.isClient == true) {
        if (loc == '/users' ||
            loc.startsWith('/users/') ||
            loc == '/roles' ||
            loc == '/penalties' ||
            loc == '/teams' ||
            loc.startsWith('/teams/') ||
            loc == '/clients' ||
            loc.startsWith('/clients/') ||
            loc == '/dashboard' ||
            loc == '/analytics' ||
            loc == '/attendance' ||
            loc == '/expenses' ||
            loc == '/finance/analytics') {
          return '/tasks';
        }
      }

      // Managers: no team creation/editing, no analytics.
      // They CAN access /users, /clients, /attendance, /expenses, /penalties,
      // /roles (scoped to their own team — privileges only), and their own
      // team's members screen (/teams/:id/members).
      if (profile?.isManager == true) {
        final isMembersRoute = RegExp(r'^/teams/[^/]+/members$').hasMatch(loc);
        if (!isMembersRoute && (loc == '/teams' || loc.startsWith('/teams/'))) {
          return '/dashboard';
        }
      }

      // Employees: no finance, no user/role/team management.
      // /penalties IS allowed — screen shows only their own record.
      if (profile?.isEmployee == true) {
        if (loc.startsWith('/finance')) return '/tasks';
        if (loc == '/users' ||
            loc.startsWith('/users/') ||
            loc == '/roles' ||
            loc == '/teams' ||
            loc.startsWith('/teams/') ||
            loc == '/create-user') {
          return '/tasks';
        }
      }

      // Clients cannot create users.
      if (profile?.isClient == true && loc == '/create-user') {
        return '/tasks';
      }

      return null; // no redirect needed
    },

    routes: [
      // ── Auth ──────────────────────────────────────────────────────────────
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignUpScreen()),
      GoRoute(
        path: '/pending',
        builder: (_, __) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordScreen(),
      ),

      // ── Shell (bottom nav) ───────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => BottomNavShell(shell: shell),
        branches: [
          // 0 — Dashboard
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (_, __) => const AdminDashboardScreen(),
              ),
            ],
          ),
          // 1 — Tasks
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tasks',
                builder: (_, state) {
                  final filter =
                      state.uri.queryParameters['filter'] ??
                      (state.extra is String ? state.extra as String : null);
                  return TaskBoardScreen(initialFilter: filter);
                },
                routes: [
                  GoRoute(
                    path: 'table',
                    builder: (_, __) => const TaskTableScreen(),
                  ),
                  GoRoute(
                    path: 'detail/:id',
                    builder: (_, state) => TaskDetailScreen(
                      taskId: state.pathParameters['id'] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
          // 2 — Calendar
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/calendar',
                builder: (_, __) => const CalendarScreen(),
                routes: [
                  GoRoute(
                    path: 'enhanced',
                    builder: (_, __) => const CalendarScreen(),
                  ),
                ],
              ),
            ],
          ),
          // 3 — Finance (role-aware: clients see their own finance)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/finance',
                builder: (_, __) => const _FinanceRouter(),
                routes: [
                  GoRoute(
                    path: 'analytics',
                    builder: (_, __) => const FinanceAnalyticsScreen(),
                  ),
                ],
              ),
            ],
          ),
          // 4 — Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Full-page routes (no bottom nav) ──────────────────────────────────
      GoRoute(
        path: '/analytics',
        builder: (_, __) => const AdvancedAnalyticsScreen(),
      ),
      GoRoute(
        path: '/attendance',
        builder: (_, __) => const AttendanceScreen(),
      ),
      GoRoute(
        path: '/penalties',
        builder: (_, __) => const PenaltyManagementScreen(),
      ),
      GoRoute(path: '/users', builder: (_, __) => const UserManagementScreen()),
      GoRoute(
        path: '/users/:id/privileges',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return UserPrivilegesScreen(
            userId: state.pathParameters['id'] ?? '',
            userName: extra?['userName'] as String? ?? 'User',
            role: extra?['role'] as String?,
          );
        },
      ),
      GoRoute(path: '/roles', builder: (_, __) => const RolesEditorScreen()),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/expenses',
        builder: (_, __) => const DailyExpensesScreen(),
      ),
      GoRoute(path: '/teams', builder: (_, __) => const TeamManagementScreen()),
      GoRoute(
        path: '/teams/:id/members',
        builder: (_, state) => TeamMembersScreen(
          teamId: state.pathParameters['id'] ?? '',
          teamName: state.extra as String? ?? 'Team',
        ),
      ),
      GoRoute(
        path: '/teams/:id/privileges',
        builder: (_, state) => TeamPrivilegesScreen(
          teamId: state.pathParameters['id'] ?? '',
          teamName: state.extra as String? ?? 'Team',
        ),
      ),
      GoRoute(
        path: '/create-user',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return CreateUserScreen(
            teamId: extra?['teamId'] as String?,
            teamName: extra?['teamName'] as String?,
          );
        },
      ),
      GoRoute(path: '/clients', builder: (_, __) => const ClientsScreen()),
      GoRoute(
        path: '/clients/:id/finance',
        builder: (_, state) =>
            ClientFinanceScreen(clientId: state.pathParameters['id'] ?? ''),
      ),
    ],
  );
}

/// Shows the right finance screen based on role + team privileges.
class _FinanceRouter extends StatelessWidget {
  const _FinanceRouter();

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthNotifier>().profile;
    final privs = context.watch<TeamPrivilegesNotifier>();

    if (profile?.isClient == true) {
      return ClientFinanceScreen(clientId: profile!.id);
    }
    // Manager blocked by team privileges
    if (profile?.isManager == true && !privs.canViewFinance) {
      return const _PrivilegeDeniedScreen(
        icon: Icons.account_balance_outlined,
        message:
            'Your team does not have access to the Finance dashboard.\n'
            'Contact your admin to enable it.',
      );
    }
    return const FinanceDashboardScreen();
  }
}

/// Shown inside any screen when a manager's team privilege blocks access.
class _PrivilegeDeniedScreen extends StatelessWidget {
  const _PrivilegeDeniedScreen({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppColors.outlineVariant),
              const SizedBox(height: 16),
              Text(
                'Access Restricted',
                style: AppTextStyles.headlineSm,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

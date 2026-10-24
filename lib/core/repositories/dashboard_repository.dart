// lib/core/repositories/dashboard_repository.dart
// Fetches all data needed for the admin dashboard in one shot.

import '../models/profile_model.dart';
import '../models/task_model.dart';
import '../services/supabase_service.dart';
import 'task_repository.dart';

class DashboardStats {
  final int totalTasks;
  final int doneTasks;
  final int inProgressTasks;
  final int totalEmployees;
  final int presentToday;
  final double totalRevenue;
  final int unreadNotifications;

  const DashboardStats({
    required this.totalTasks,
    required this.doneTasks,
    required this.inProgressTasks,
    required this.totalEmployees,
    required this.presentToday,
    required this.totalRevenue,
    required this.unreadNotifications,
  });
}

class DashboardRepository {
  /// Safely run a Supabase query, returning empty list on failure.
  static Future<List<dynamic>> _safeQuery(Future<dynamic> query) async {
    try {
      return (await query) as List<dynamic>;
    } catch (_) {
      return [];
    }
  }

  /// Admin view scoped to a single department's team. Mirrors the company-wide
  /// admin stats but filters every metric by [teamId] (read-only; RLS-safe).
  static Future<DashboardStats> _fetchAdminScopedStats(
    ProfileModel profile,
    String teamId,
    String today,
  ) async {
    final db = SupabaseService.client;

    final members = await _safeQuery(
      db.from('profiles').select('id').eq('team_id', teamId),
    );
    final memberIds = members.map((m) => m['id'] as String).toList();

    // Revenue for a department = paid invoices of the clients this team serves.
    final clientRows = await _safeQuery(
      db
          .from('tasks')
          .select('client_id')
          .eq('team_id', teamId)
          .not('client_id', 'is', null),
    );
    final clientIds = clientRows
        .map((r) => r['client_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    final results = await Future.wait([
      TaskRepository.fetchTasksForProfile(profile, overrideTeamId: teamId),
      memberIds.isNotEmpty
          ? _safeQuery(
              db
                  .from('attendance')
                  .select('id')
                  .eq('attendance_date', today)
                  .eq('status', 'present')
                  .inFilter('employee_id', memberIds),
            )
          : Future<List<dynamic>>.value(<dynamic>[]),
      clientIds.isNotEmpty
          ? _safeQuery(
              db
                  .from('crm_entries')
                  .select('paid_amount')
                  .eq('status', 'paid')
                  .inFilter('client_id', clientIds),
            )
          : Future<List<dynamic>>.value(<dynamic>[]),
      _safeQuery(
        db
            .from('notifications')
            .select('id')
            .eq('recipient_id', profile.id)
            .eq('is_read', false),
      ),
    ]);

    final tasks = results[0] as List<TaskModel>;
    final present = results[1];
    final crmEntries = results[2];
    final notifs = results[3];

    final done = tasks.where((t) => t.status == 'completed').length;
    final inProgress = tasks.where((t) => t.status == 'in_progress').length;
    final revenue = crmEntries.fold<double>(
      0,
      (sum, e) => sum + ((e['paid_amount'] as num?)?.toDouble() ?? 0),
    );

    return DashboardStats(
      totalTasks: tasks.length,
      doneTasks: done,
      inProgressTasks: inProgress,
      totalEmployees: memberIds.length,
      presentToday: present.length,
      totalRevenue: revenue,
      unreadNotifications: notifs.length,
    );
  }

  /// Fetch dashboard stats, tailored for Admin, Manager, or Employee profiles.
  ///
  /// [scopeTeamId] (admin-only) narrows the company-wide admin view to a single
  /// department's team — tasks, members, attendance and revenue are all scoped
  /// to that team at the QUERY level. Null means "All Departments" (company-wide).
  static Future<DashboardStats> fetchStats(
    ProfileModel profile, {
    String? scopeTeamId,
  }) async {
    final db = SupabaseService.client;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    if (profile.isAdmin) {
      // Department-scoped admin view (a workspace is selected).
      if (scopeTeamId != null) {
        return _fetchAdminScopedStats(profile, scopeTeamId, today);
      }
      // Admin / Super Admin — company-wide statistics
      final results = await Future.wait([
        TaskRepository.fetchTasksForProfile(profile),
        _safeQuery(
          db
              .from('profiles')
              .select('id')
              .neq('role', 'client')
              .eq('status', 'active'),
        ),
        _safeQuery(
          db
              .from('attendance')
              .select('id')
              .eq('attendance_date', today)
              .eq('status', 'present'),
        ),
        _safeQuery(
          db.from('crm_entries').select('paid_amount').eq('status', 'paid'),
        ),
        _safeQuery(
          db
              .from('notifications')
              .select('id')
              .eq('recipient_id', profile.id)
              .eq('is_read', false),
        ),
      ]);

      final adminTasks = results[0] as List<TaskModel>;
      final employees = results[1];
      final present = results[2];
      final crmEntries = results[3];
      final notifs = results[4];

      final done = adminTasks.where((t) => t.status == 'completed').length;
      final inProgress = adminTasks
          .where((t) => t.status == 'in_progress')
          .length;
      final revenue = crmEntries.fold<double>(
        0,
        (sum, e) => sum + ((e['paid_amount'] as num?)?.toDouble() ?? 0),
      );

      return DashboardStats(
        totalTasks: adminTasks.length,
        doneTasks: done,
        inProgressTasks: inProgress,
        totalEmployees: employees.length,
        presentToday: present.length,
        totalRevenue: revenue,
        unreadNotifications: notifs.length,
      );
    } else if (profile.isManager) {
      final teamId = profile.teamId;
      List<dynamic> teamMembers = [];
      if (teamId != null) {
        teamMembers = await _safeQuery(
          db.from('profiles').select('id').eq('team_id', teamId),
        );
      } else {
        // Fallback to teams led by this manager
        final leadTeams = await _safeQuery(
          db.from('teams').select('id').eq('team_lead_id', profile.id),
        );
        if (leadTeams.isNotEmpty) {
          final leadTeamId = leadTeams.first['id'] as String;
          teamMembers = await _safeQuery(
            db.from('profiles').select('id').eq('team_id', leadTeamId),
          );
        }
      }

      final memberIds = teamMembers.map((m) => m['id'] as String).toList();

      Future<List<dynamic>> attendanceQuery;
      if (memberIds.isNotEmpty) {
        attendanceQuery = _safeQuery(
          db
              .from('attendance')
              .select('id')
              .eq('attendance_date', today)
              .eq('status', 'present')
              .inFilter('employee_id', memberIds),
        );
      } else {
        attendanceQuery = Future.value([]);
      }

      final results = await Future.wait([
        TaskRepository.fetchTasksForProfile(profile),
        attendanceQuery,
        _safeQuery(
          db
              .from('notifications')
              .select('id')
              .eq('recipient_id', profile.id)
              .eq('is_read', false),
        ),
      ]);

      final managerTasks = results[0] as List<TaskModel>;
      final present = results[1];
      final notifs = results[2];

      final done = managerTasks.where((t) => t.status == 'completed').length;
      final inProgress = managerTasks
          .where((t) => t.status == 'in_progress')
          .length;

      return DashboardStats(
        totalTasks: managerTasks.length,
        doneTasks: done,
        inProgressTasks: inProgress,
        totalEmployees: teamMembers.length,
        presentToday: present.length,
        totalRevenue: 0,
        unreadNotifications: notifs.length,
      );
    } else {
      // Regular Employee / Client — strictly assigned tasks & personal stats
      List<dynamic> teamMembers = [];
      if (profile.teamId != null) {
        teamMembers = await _safeQuery(
          db.from('profiles').select('id').eq('team_id', profile.teamId!),
        );
      }

      final results = await Future.wait([
        TaskRepository.fetchTasksForProfile(profile),
        _safeQuery(
          db
              .from('attendance')
              .select('id')
              .eq('employee_id', profile.id)
              .eq('attendance_date', today)
              .eq('status', 'present'),
        ),
        _safeQuery(
          db
              .from('notifications')
              .select('id')
              .eq('recipient_id', profile.id)
              .eq('is_read', false),
        ),
      ]);

      final empTasks = results[0] as List<TaskModel>;
      final isPresent = results[1].isNotEmpty;
      final notifsCount = results[2].length;

      final done = empTasks.where((t) => t.status == 'completed').length;
      final inProgress = empTasks
          .where((t) => t.status == 'in_progress')
          .length;

      return DashboardStats(
        totalTasks: empTasks.length,
        doneTasks: done,
        inProgressTasks: inProgress,
        totalEmployees: teamMembers.isNotEmpty ? teamMembers.length : 1,
        presentToday: isPresent ? 1 : 0,
        totalRevenue: 0,
        unreadNotifications: notifsCount,
      );
    }
  }
}

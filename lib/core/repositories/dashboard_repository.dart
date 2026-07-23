// lib/core/repositories/dashboard_repository.dart
// Fetches all data needed for the admin dashboard in one shot.

import '../models/profile_model.dart';
import '../services/supabase_service.dart';

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

  /// Fetch dashboard stats, tailored for Admin or Manager profiles.
  static Future<DashboardStats> fetchStats(ProfileModel profile) async {
    final client = SupabaseService.client;
    final admin = SupabaseService.adminClient;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    if (profile.isManager) {
      final teamId = profile.teamId;
      List<dynamic> teamMembers = [];
      if (teamId != null) {
        teamMembers = await _safeQuery(
          admin.from('profiles').select('id').eq('team_id', teamId),
        );
      } else {
        // Fallback to teams led by this manager
        final leadTeams = await _safeQuery(
          admin.from('teams').select('id').eq('team_lead_id', profile.id),
        );
        if (leadTeams.isNotEmpty) {
          final leadTeamId = leadTeams.first['id'] as String;
          teamMembers = await _safeQuery(
            admin.from('profiles').select('id').eq('team_id', leadTeamId),
          );
        }
      }

      final memberIds = teamMembers.map((m) => m['id'] as String).toList();

      Future<List<dynamic>> tasksQuery;
      if (teamId != null) {
        tasksQuery = _safeQuery(
          client
              .from('tasks')
              .select('id, status')
              .or('team_id.eq.$teamId,handoff_to_team_id.eq.$teamId'),
        );
      } else {
        tasksQuery = _safeQuery(client.from('tasks').select('id, status'));
      }

      Future<List<dynamic>> attendanceQuery;
      if (memberIds.isNotEmpty) {
        attendanceQuery = _safeQuery(
          admin
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
        tasksQuery,
        attendanceQuery,
        _safeQuery(
          admin
              .from('notifications')
              .select('id')
              .eq('recipient_id', profile.id)
              .eq('is_read', false),
        ),
      ]);

      final tasks = results[0];
      final present = results[1];
      final notifs = results[2];

      final done = tasks.where((t) => t['status'] == 'completed').length;
      final inProgress = tasks
          .where((t) => t['status'] == 'in_progress')
          .length;

      return DashboardStats(
        totalTasks: tasks.length,
        doneTasks: done,
        inProgressTasks: inProgress,
        totalEmployees: teamMembers.length,
        presentToday: present.length,
        totalRevenue: 0,
        unreadNotifications: notifs.length,
      );
    } else {
      // Admin / Default
      final results = await Future.wait([
        _safeQuery(admin.from('tasks').select('id, status')),
        _safeQuery(
          admin
              .from('profiles')
              .select('id')
              .neq('role', 'client')
              .eq('status', 'active'),
        ),
        _safeQuery(
          admin
              .from('attendance')
              .select('id')
              .eq('attendance_date', today)
              .eq('status', 'present'),
        ),
        _safeQuery(
          admin.from('crm_entries').select('paid_amount').eq('status', 'paid'),
        ),
        _safeQuery(
          admin
              .from('notifications')
              .select('id')
              .eq('recipient_id', profile.id)
              .eq('is_read', false),
        ),
      ]);

      final tasks = results[0];
      final employees = results[1];
      final present = results[2];
      final crmEntries = results[3];
      final notifs = results[4];

      final done = tasks.where((t) => t['status'] == 'completed').length;
      final inProgress = tasks
          .where((t) => t['status'] == 'in_progress')
          .length;
      final revenue = crmEntries.fold<double>(
        0,
        (sum, e) => sum + ((e['paid_amount'] as num?)?.toDouble() ?? 0),
      );

      return DashboardStats(
        totalTasks: tasks.length,
        doneTasks: done,
        inProgressTasks: inProgress,
        totalEmployees: employees.length,
        presentToday: present.length,
        totalRevenue: revenue,
        unreadNotifications: notifs.length,
      );
    }
  }
}

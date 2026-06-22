// lib/core/repositories/dashboard_repository.dart
// Fetches all data needed for the admin dashboard in one shot.

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

  /// Fetch all dashboard stats for the current admin.
  static Future<DashboardStats> fetchStats(String currentUserId) async {
    final client = SupabaseService.client;
    final today  = DateTime.now().toIso8601String().substring(0, 10);

    // Run queries in parallel — each is individually safe.
    final results = await Future.wait([
      _safeQuery(client.from('tasks').select('id, status')),
      _safeQuery(client.from('profiles').select('id').eq('role', 'employee').eq('status', 'active')),
      _safeQuery(client.from('attendance').select('id').eq('attendance_date', today).eq('status', 'present')),
      _safeQuery(client.from('crm_entries').select('paid_amount').eq('status', 'paid')),
      _safeQuery(client.from('notifications').select('id').eq('recipient_id', currentUserId).eq('is_read', false)),
    ]);

    final tasks       = results[0];
    final employees   = results[1];
    final present     = results[2];
    final crmEntries  = results[3];
    final notifs      = results[4];

    final done       = tasks.where((t) => t['status'] == 'completed').length;
    final inProgress = tasks.where((t) => t['status'] == 'in_progress').length;
    final revenue    = crmEntries.fold<double>(
        0, (sum, e) => sum + ((e['paid_amount'] as num?)?.toDouble() ?? 0));

    return DashboardStats(
      totalTasks:          tasks.length,
      doneTasks:           done,
      inProgressTasks:     inProgress,
      totalEmployees:      employees.length,
      presentToday:        present.length,
      totalRevenue:        revenue,
      unreadNotifications: notifs.length,
    );
  }
}

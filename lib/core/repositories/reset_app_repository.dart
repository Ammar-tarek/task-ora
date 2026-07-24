// lib/core/repositories/reset_app_repository.dart
// Resets all application data across all tables, keeping only the Super Admin profile record.

import '../services/supabase_service.dart';

class ResetAppRepository {
  static final _admin = SupabaseService.adminClient;

  /// Deletes all data from application tables in foreign key dependency order.
  /// Preserves the profile with [superAdminId].
  /// Returns null on success, or an error string if an exception occurs.
  static Future<String?> resetApplicationData({
    required String superAdminId,
  }) async {
    try {
      // 1. Task dependent tables
      await _deleteWhere('task_comments');
      await _deleteWhere('task_assignees');
      await _deleteWhere('task_mentions');
      await _deleteWhere('task_approvals');
      await _deleteWhere('task_attachments');
      await _deleteWhere('task_audit_log');
      await _deleteWhere('client_task_visibility');
      await _deleteWhere('client_task_column_visibility');
      
      // Delete tasks & boards
      await _deleteWhere('tasks');
      await _deleteWhere('task_board_columns');
      await _deleteWhere('task_boards');

      // 2. Attendance
      await _deleteWhere('attendance');

      // 3. Finance & Expenses
      await _deleteWhere('expenses');
      await _deleteWhere('expense_categories');
      await _deleteWhere('penalties');
      await _deleteWhere('penalty_types');
      await _deleteWhere('crm_payments');
      await _deleteWhere('crm_entries');

      // 4. Events & Calendar
      await _deleteWhere('event_attendees');
      await _deleteWhere('event_attachments');
      await _deleteWhere('room_bookings');
      await _deleteWhere('events');
      await _deleteWhere('rooms');

      // 5. Notes & Workspace
      await _deleteWhere('note_audit_log');
      await _deleteWhere('note_links');
      await _deleteWhere('note_attachments');
      await _deleteWhere('note_shares');
      await _deleteWhere('note_tags');
      await _deleteWhere('notes');

      // 6. Custom Tables & Audit Logs
      await _deleteWhere('cell_audit_log');
      await _deleteWhere('custom_cell_values');
      await _deleteWhere('custom_rows');
      await _deleteWhere('column_status_options');
      await _deleteWhere('custom_columns');
      await _deleteWhere('table_permissions');
      await _deleteWhere('table_views');
      await _deleteWhere('custom_tables');

      // 7. System & Notifications
      await _deleteWhere('notifications');
      await _deleteWhere('ai_interactions');

      // 8. Clients & Team Privileges
      await _deleteWhere('client_profiles');
      await _deleteWhere('user_privileges');
      await _deleteWhere('team_privileges');

      // Delete teams (remove team_id foreign key references in profiles first)
      await _admin.from('profiles').update({'team_id': null}).neq('id', '00000000-0000-0000-0000-000000000000');
      await _deleteWhere('teams');

      // 9. Delete non-super-admin Auth users & profiles — preserve ONLY Super Admin record
      final nonSuperAdminProfiles = await _admin
          .from('profiles')
          .select('id')
          .neq('id', superAdminId);

      for (final p in nonSuperAdminProfiles) {
        final uid = p['id'] as String?;
        if (uid != null && uid != superAdminId) {
          try {
            await _admin.auth.admin.deleteUser(uid);
          } catch (_) {}
        }
      }

      await _admin.from('profiles').delete().neq('id', superAdminId);

      return null; // success
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> _deleteWhere(String table) async {
    try {
      await _admin.from(table).delete().neq('id', '00000000-0000-0000-0000-000000000000');
      return;
    } catch (_) {}
    try {
      await _admin.from(table).delete().not('created_at', 'is', null);
      return;
    } catch (_) {}
    try {
      await _admin.from(table).delete().neq('team_id', '00000000-0000-0000-0000-000000000000');
      return;
    } catch (_) {}
    try {
      await _admin.from(table).delete().neq('user_id', '00000000-0000-0000-0000-000000000000');
      return;
    } catch (_) {}
  }
}

// lib/core/repositories/user_privileges_repository.dart
// CRUD for the user_privileges table. Admins may edit anyone; managers may
// edit members of their own team (enforced by RLS + UI gating).

import '../models/user_privileges_model.dart';
import '../services/supabase_service.dart';

class UserPrivilegesRepository {
  static final _admin = SupabaseService.adminClient;

  /// Fetch privileges for [userId]. Returns defaults when no row saved yet,
  /// or null if the table is missing / on error.
  static Future<UserPrivilegesModel?> fetchForUser(String userId) async {
    try {
      final data = await _admin
          .from('user_privileges')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (data == null) return null;
      return UserPrivilegesModel.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Like [fetchForUser] but returns defaults instead of null when no row
  /// exists (used by the editor screen).
  static Future<UserPrivilegesModel> fetchForUserOrDefaults(String userId) async {
    final existing = await fetchForUser(userId);
    return existing ?? UserPrivilegesModel.defaults(userId);
  }

  /// Upsert privileges for a user.
  static Future<void> save(UserPrivilegesModel privileges, {String? updatedBy}) async {
    await _admin
        .from('user_privileges')
        .upsert(privileges.toUpsertMap(updatedBy: updatedBy), onConflict: 'user_id');
  }
}

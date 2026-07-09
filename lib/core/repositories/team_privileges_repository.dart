// lib/core/repositories/team_privileges_repository.dart
// CRUD for the team_privileges table — admin only.

import '../models/team_privileges_model.dart';
import '../services/supabase_service.dart';

class TeamPrivilegesRepository {
  static final _admin = SupabaseService.adminClient;

  /// Fetch privileges for [teamId].
  /// Returns defaults if the table exists but no row has been saved yet.
  /// Throws if the table doesn't exist (caller should show SQL migration prompt).
  static Future<TeamPrivilegesModel> fetchForTeam(String teamId) async {
    final data = await _admin
        .from('team_privileges')
        .select()
        .eq('team_id', teamId)
        .maybeSingle(); // throws PGRST205 if table absent — don't catch here
    if (data == null) return TeamPrivilegesModel.defaults(teamId);
    return TeamPrivilegesModel.fromMap(data);
  }

  /// Upsert [privileges] — inserts on first save, updates on subsequent saves.
  static Future<void> save(TeamPrivilegesModel privileges) async {
    await _admin
        .from('team_privileges')
        .upsert(privileges.toUpsertMap(), onConflict: 'team_id');
  }
}

// lib/core/repositories/team_repository.dart
// Full CRUD for the teams table + member assignment via profiles.team_id.
// Matches exact Supabase schema: name, description, department, team_lead_id,
// is_active, created_at, updated_at.

import '../models/team_model.dart';
import '../models/profile_model.dart';
import '../services/supabase_service.dart';

class TeamRepository {
  static final _client = SupabaseService.client;
  static final _admin  = SupabaseService.adminClient;

  // ── Teams ──────────────────────────────────────────────────────────────────

  /// All teams bypassing RLS — needed where a manager must see OTHER teams
  /// (e.g. the department-handoff picker). Managers' RLS limits them to their
  /// own team, so the normal [fetchAll] would return only one team.
  static Future<List<TeamModel>> fetchAllAdmin({bool activeOnly = false}) async {
    try {
      var query = _admin.from('teams').select();
      if (activeOnly) query = query.eq('is_active', true);
      final data = await query.order('name');
      return (data as List).map((m) => TeamModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch a single team by id.
  static Future<TeamModel?> fetchById(String id) async {
    try {
      final data = await _client.from('teams').select().eq('id', id).single();
      return TeamModel.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Fetch all teams ordered by name. Includes inactive teams for admin view.
  static Future<List<TeamModel>> fetchAll({bool activeOnly = false}) async {
    try {
      var query = _client.from('teams').select();
      if (activeOnly) query = query.eq('is_active', true);
      final data = await query.order('name');
      return (data as List).map((m) => TeamModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Create a new team. Returns the created model or null on failure.
  static Future<TeamModel?> create({
    required String name,
    String? description,
    String? department,
    String? teamLeadId,
  }) async {
    try {
      final data = await _client.from('teams').insert({
        'name': name.trim(),
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        if (department != null && department.trim().isNotEmpty)
          'department': department.trim(),
        if (teamLeadId != null) 'team_lead_id': teamLeadId,
        'is_active': true,
      }).select().single();
      return TeamModel.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Update a team's details.
  static Future<bool> update({
    required String id,
    required String name,
    String? description,
    String? department,
    String? teamLeadId,
    bool? isActive,
  }) async {
    try {
      await _client.from('teams').update({
        'name': name.trim(),
        'description': (description != null && description.trim().isNotEmpty)
            ? description.trim()
            : null,
        'department': (department != null && department.trim().isNotEmpty)
            ? department.trim()
            : null,
        'team_lead_id': teamLeadId,
        if (isActive != null) 'is_active': isActive,
      }).eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deactivate a team (soft delete — sets is_active = false).
  static Future<bool> deactivate(String id) async {
    try {
      await _client
          .from('teams')
          .update({'is_active': false})
          .eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Hard-delete a team and unassign all its members first.
  static Future<bool> delete(String id) async {
    try {
      await _client
          .from('profiles')
          .update({'team_id': null})
          .eq('team_id', id);
      await _client.from('teams').delete().eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Member management ──────────────────────────────────────────────────────

  /// Fetch all profiles assigned to this team.
  /// Team members bypassing RLS — used where an ADMIN (no team of their own)
  /// must list another team's members, e.g. the task assignee picker.
  static Future<List<ProfileModel>> fetchMembersAdmin(String teamId) async {
    try {
      final data = await _admin
          .from('profiles')
          .select()
          .eq('team_id', teamId)
          .order('full_name');
      return (data as List).map((m) => ProfileModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// All active staff (non-client) bypassing RLS — admin fallback when a task
  /// has no team yet.
  static Future<List<ProfileModel>> fetchAllStaffAdmin() async {
    try {
      final data = await _admin
          .from('profiles')
          .select()
          .neq('role', 'client')
          .eq('status', 'active')
          .order('full_name');
      return (data as List).map((m) => ProfileModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<ProfileModel>> fetchMembers(String teamId) async {
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('team_id', teamId)
          .order('full_name');
      return (data as List).map((m) => ProfileModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Assign or remove a user from a team. Pass null [teamId] to unassign.
  static Future<bool> setTeamForUser(String userId, String? teamId) async {
    try {
      await _client
          .from('profiles')
          .update({'team_id': teamId})
          .eq('id', userId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fetch teams where [userId] is the team lead.
  /// Returns an empty list if the user hasn't created any team.
  static Future<List<TeamModel>> fetchByLeadId(String userId) async {
    try {
      final data = await _client
          .from('teams')
          .select()
          .eq('team_lead_id', userId)
          .order('name');
      return (data as List).map((m) => TeamModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch member counts for every team at once. Returns {teamId -> count}.
  static Future<Map<String, int>> fetchMemberCounts() async {
    try {
      final data = await _admin
          .from('profiles')
          .select('team_id')
          .not('team_id', 'is', null);
      final counts = <String, int>{};
      for (final row in (data as List)) {
        final tid = row['team_id'] as String?;
        if (tid != null) counts[tid] = (counts[tid] ?? 0) + 1;
      }
      return counts;
    } catch (_) {
      return {};
    }
  }
}

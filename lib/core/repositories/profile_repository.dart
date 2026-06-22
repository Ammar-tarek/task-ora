// lib/core/repositories/profile_repository.dart
// Queries for the profiles table (user management).

import '../models/profile_model.dart';
import '../services/supabase_service.dart';

class ProfileRepository {
  static final _client = SupabaseService.client;

  /// Fetch all employees (role = employee or admin).
  static Future<List<ProfileModel>> fetchEmployees() async {
    try {
      final data = await _client
          .from('profiles')
          .select()
          .inFilter('role', ['admin', 'employee'])
          .order('full_name');
      return (data as List).map((m) => ProfileModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch all profiles (any role).
  static Future<List<ProfileModel>> fetchAll() async {
    try {
      final data = await _client
          .from('profiles')
          .select()
          .order('full_name');
      return (data as List).map((m) => ProfileModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch a single profile by id.
  static Future<ProfileModel?> fetchById(String id) async {
    try {
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', id)
          .single();
      return ProfileModel.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  /// Update a user's status (active / inactive).
  static Future<void> setStatus(String id, String status) async {
    try {
      await _client.from('profiles').update({
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } catch (_) { /* silently fail if table doesn't exist */ }
  }

  /// Fetch profiles that have no team assigned yet (for the member picker).
  static Future<List<ProfileModel>> fetchUnassigned() async {
    try {
      final data = await _client
          .from('profiles')
          .select()
          .isFilter('team_id', null)
          .inFilter('role', ['admin', 'employee'])
          .order('full_name');
      return (data as List).map((m) => ProfileModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch all profiles that belong to [teamId].
  static Future<List<ProfileModel>> fetchByTeam(String teamId) async {
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

  /// Look up the team name for a given team_id.
  static Future<String?> fetchTeamName(String? teamId) async {
    if (teamId == null) return null;
    try {
      final data = await SupabaseService.client
          .from('teams')
          .select('name')
          .eq('id', teamId)
          .single();
      return data['name'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Look up a profile by the user's email address.
  ///
  /// Requires this one-time SQL function in Supabase:
  /// ```sql
  /// create or replace function get_profile_by_email(user_email text)
  /// returns setof profiles
  /// language sql security definer as $$
  ///   select p.*
  ///   from profiles p
  ///   join auth.users u on u.id = p.id
  ///   where lower(u.email) = lower(user_email)
  ///   limit 1;
  /// $$;
  /// ```
  static Future<ProfileModel?> fetchByEmail(String email) async {
    try {
      final data = await SupabaseService.client
          .rpc('get_profile_by_email', params: {'user_email': email.trim().toLowerCase()});
      final list = data as List?;
      if (list == null || list.isEmpty) return null;
      return ProfileModel.fromMap(list.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

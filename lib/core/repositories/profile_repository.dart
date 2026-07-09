// lib/core/repositories/profile_repository.dart
// Queries for the profiles table (user management).

import 'package:supabase_flutter/supabase_flutter.dart';
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
          .inFilter('role', ['admin', 'manager', 'employee'])
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

  /// Create a new auth user + profile via the service-role client.
  /// Returns null on success, or an error message string.
  /// The Supabase `handle_new_user` DB trigger creates the profile row
  /// automatically; we also attempt a manual insert as a fallback.
  static Future<String?> createUser({
    required String email,
    required String password,
    required String fullName,
    required String role, // 'manager' or 'employee'
    String? teamId,       // auto-assign to this team after creation
  }) async {
    try {
      // Step 1: Create auth user with only full_name in metadata.
      // We intentionally omit 'role' here so the handle_new_user DB trigger
      // creates the profile row with its default role ('employee'), avoiding
      // any CHECK constraint that doesn't include 'manager'.
      final response = await SupabaseService.adminClient.auth.admin.createUser(
        AdminUserAttributes(
          email: email.trim(),
          password: password,
          emailConfirm: true,
          userMetadata: {'full_name': fullName.trim()},
        ),
      );

      final userId = response.user?.id;
      if (userId == null) return 'Failed to create account.';

      // Step 2: Wait for the trigger to insert the profile row, then update
      // the role and name explicitly — bypassing any trigger constraints.
      await Future.delayed(const Duration(milliseconds: 800));
      await SupabaseService.adminClient.from('profiles').upsert({
        'id':        userId,
        'full_name': fullName.trim(),
        'role':      role,
        'status':    'active',
        if (teamId != null) 'team_id': teamId,
      });

      return null;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already registered') ||
          msg.contains('already exists') ||
          msg.contains('email address is already')) {
        return 'An account with this email already exists.';
      }
      return e.message;
    } on PostgrestException catch (e) {
      if (e.code == '22P02') {
        return 'Role assignment failed: run '
            "ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'manager'; "
            'in Supabase SQL Editor, then try again.';
      }
      return 'Account created but profile setup failed: ${e.message}';
    } catch (_) {
      return 'Account created but profile setup failed — please refresh and try again.';
    }
  }

  /// Fetch active employees that can be promoted (role == 'employee').
  static Future<List<ProfileModel>> fetchPromotable() async {
    try {
      final data = await SupabaseService.adminClient
          .from('profiles')
          .select()
          .eq('role', 'employee')
          .eq('status', 'active')
          .order('full_name');
      return (data as List).map((m) => ProfileModel.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Change the role of an existing profile row.
  /// Returns null on success, or a user-readable error message on failure.
  static Future<String?> updateRole(String userId, String role) async {
    try {
      await SupabaseService.adminClient
          .from('profiles')
          .update({'role': role})
          .eq('id', userId);
      return null;
    } on PostgrestException catch (e) {
      if (e.code == '22P02') {
        return "Role '$role' is not in the database enum. "
            "Run in Supabase SQL Editor: "
            "ALTER TYPE user_role ADD VALUE IF NOT EXISTS '$role';";
      }
      return 'Failed to update role: ${e.message}';
    } catch (_) {
      return 'Failed to update role. Please try again.';
    }
  }

  /// Fetch the auth email for a user (requires admin client).
  static Future<String?> fetchEmail(String userId) async {
    try {
      final res = await SupabaseService.adminClient.auth.admin.getUserById(userId);
      return res.user?.email;
    } catch (_) {
      return null;
    }
  }

  /// Update an employee's profile + optionally change email / password.
  /// Returns null on success, or a user-readable error string on failure.
  static Future<String?> updateEmployee({
    required String userId,
    required String fullName,
    String? email,
    String? phone,
    String? newPassword,
    String? role,
    String? status,
  }) async {
    try {
      // 1. Update auth user if email or password changed
      final attrs = AdminUserAttributes(
        email:    (email != null && email.isNotEmpty) ? email : null,
        password: (newPassword != null && newPassword.isNotEmpty) ? newPassword : null,
      );
      if (attrs.email != null || attrs.password != null) {
        await SupabaseService.adminClient.auth.admin
            .updateUserById(userId, attributes: attrs);
      }

      // 2. Update profile row
      final updates = <String, dynamic>{
        'full_name':   fullName,
        'phone':       phone?.isEmpty == true ? null : phone,
        'updated_at':  DateTime.now().toIso8601String(),
        if (role   != null) 'role':   role,
        if (status != null) 'status': status,
      };
      await SupabaseService.adminClient
          .from('profiles')
          .update(updates)
          .eq('id', userId);

      return null;
    } on AuthException catch (e) {
      return e.message;
    } on PostgrestException catch (e) {
      if (e.code == '22P02') {
        return "Role '$role' is not in the database enum. "
            "Run: ALTER TYPE user_role ADD VALUE IF NOT EXISTS '$role';";
      }
      return e.message;
    } catch (_) {
      return 'An unexpected error occurred. Please try again.';
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

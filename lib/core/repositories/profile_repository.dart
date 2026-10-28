// lib/core/repositories/profile_repository.dart
// Queries for the profiles table (user management).

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile_model.dart';
import '../services/privileged_ops.dart';
import '../services/supabase_service.dart';
import 'notification_repository.dart';

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
      final data = await _client.from('profiles').select().order('full_name');
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
      await _client
          .from('profiles')
          .update({
            'status': status,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
    } catch (_) {
      /* silently fail if table doesn't exist */
    }
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
    required String role, // 'admin', 'manager', 'employee', 'client'
    String? teamId, // auto-assign to this team after creation
    String? companyName,
    String? contactPerson,
    String? phone,
  }) async {
    try {
      // Auth user + profile row are created server-side (admin-user-ops Edge
      // Function). The service-role key lives only in the function runtime.
      final userId = await PrivilegedOps.createUser(
        email: email.trim(),
        password: password,
        fullName: fullName.trim(),
        role: role,
        teamId: (teamId != null && teamId.isNotEmpty) ? teamId : null,
      );
      if (userId == null) return 'Failed to create account.';

      // If role is client, ensure client_profiles row exists (RLS: admin write).
      if (role == 'client') {
        final compName = (companyName != null && companyName.trim().isNotEmpty)
            ? companyName.trim()
            : fullName.trim();
        final contactP = (contactPerson != null && contactPerson.trim().isNotEmpty)
            ? contactPerson.trim()
            : fullName.trim();

        await _client.from('client_profiles').upsert({
          'id': userId,
          'company_name': compName,
          'contact_person': contactP,
          'email': email.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        });
      }

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

  /// Deactivate an employee: the server bans the Auth user and sets
  /// profiles.status = 'inactive'. No data is deleted. Returns null on success,
  /// or a user-readable error message.
  static Future<String?> deactivateEmployee(String userId) =>
      _setActive(userId, active: false);

  /// Reactivate an employee: lifts the Auth ban and restores
  /// profiles.status = 'active'. Returns null on success, or an error message.
  static Future<String?> reactivateEmployee(String userId) =>
      _setActive(userId, active: true);

  static Future<String?> _setActive(String userId, {required bool active}) async {
    try {
      final err = await PrivilegedOps.setActive(userId: userId, active: active);
      if (err != null) return err;

      // Best-effort: notify the affected user. They may be banned/offline, so
      // a failure here never fails the status change.
      try {
        await NotificationRepository.notifyAction(
          title: active ? 'Account Reactivated' : 'Account Deactivated',
          body: active
              ? 'Your account has been reactivated. You can sign in again.'
              : 'Your account has been deactivated. Contact your administrator.',
          type: 'role_changed',
          referenceType: 'profile',
          referenceId: userId,
          targetUserIds: [userId],
        );
      } catch (_) {}

      return null;
    } catch (_) {
      return 'Could not update employee status. Please try again.';
    }
  }

  /// Fetch active employees that can be promoted (role == 'employee').
  static Future<List<ProfileModel>> fetchPromotable() async {
    try {
      final data = await _client
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
      // Role change is privileged (super_admin grants gated server-side).
      await PrivilegedOps.updateUser(userId: userId, role: role);

      try {
        await NotificationRepository.notifyAction(
          title: 'Role Updated',
          body: 'Your account role has been updated to $role.',
          type: 'role_changed',
          referenceType: 'profile',
          referenceId: userId,
          targetUserIds: [userId],
        );
      } catch (_) {}

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

  /// Fetch the auth email for a user (server-side, behind the admin gate).
  static Future<String?> fetchEmail(String userId) async {
    try {
      return await PrivilegedOps.fetchEmail(userId);
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
      // Auth change (email/password) + privileged profile fields (role/status)
      // + name/phone all happen server-side in one admin-gated call.
      await PrivilegedOps.updateUser(
        userId: userId,
        email: (email != null && email.isNotEmpty) ? email : null,
        password: (newPassword != null && newPassword.isNotEmpty)
            ? newPassword
            : null,
        fullName: fullName,
        role: role,
        status: status,
        phone: phone?.isEmpty == true ? null : phone,
      );

      if (role != null || status != null) {
        try {
          await NotificationRepository.notifyAction(
            title: 'Account Settings Updated',
            body: 'Your account profile settings have been updated.',
            type: 'role_changed',
            referenceType: 'profile',
            referenceId: userId,
            targetUserIds: [userId],
          );
        } catch (_) {}
      }

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
      final data = await SupabaseService.client.rpc(
        'get_profile_by_email',
        params: {'user_email': email.trim().toLowerCase()},
      );
      final list = data as List?;
      if (list == null || list.isEmpty) return null;
      return ProfileModel.fromMap(list.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateFcmToken(String userId, String? token) async {
    try {
      await _client.from('profiles').update({
        'fcm_token': token,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (_) {
      /* silently catch if column or table not available yet */
    }
  }
}

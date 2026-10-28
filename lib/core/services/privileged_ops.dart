// lib/core/services/privileged_ops.dart
// Client-side entry to the trusted server boundary that REPLACED the old
// service-role adminClient. It carries only the user's auth JWT — no
// service-role key. Backed by the deployed Edge Functions (admin-user-ops,
// admin-reset-app) and SECURITY DEFINER RPCs (notify_action, list_active_teams).

import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class PrivilegedOps {
  PrivilegedOps._();

  static SupabaseClient get _c => SupabaseService.client;

  // ── Edge Functions (service-role lives only in the function runtime) ────────

  /// admin-user-ops: create an auth user + profile. Global admin only (server).
  static Future<String?> createUser({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? teamId,
  }) async {
    final res = await _c.functions.invoke(
      'admin-user-ops',
      body: {
        'action': 'create_user',
        'email': email,
        'password': password,
        'fullName': fullName,
        'role': role,
        'teamId': ?teamId,
      },
    );
    final data = res.data as Map?;
    return data?['id'] as String?; // null → caller handles error via status
  }

  static Future<void> deleteUser(String userId) => _c.functions.invoke(
    'admin-user-ops',
    body: {'action': 'delete_user', 'userId': userId},
  );

  static Future<void> updateUser({
    required String userId,
    String? email,
    String? password,
    String? fullName,
    String? role,
    String? status,
    Object? phone = _unset,
  }) => _c.functions.invoke(
    'admin-user-ops',
    body: {
      'action': 'update_user',
      'userId': userId,
      'email': ?email,
      'password': ?password,
      'fullName': ?fullName,
      'role': ?role,
      'status': ?status,
      // Pass phone only when the caller set it; null clears it server-side.
      if (!identical(phone, _unset)) 'phone': phone,
    },
  );

  /// Sentinel so callers can distinguish "leave phone unchanged" from "clear it".
  static const Object _unset = Object();

  /// admin-user-ops: activate/deactivate an employee. Global admin only
  /// (server-enforced). [active] == false bans the Auth user and sets
  /// profiles.status = 'inactive'; true lifts the ban and restores 'active'.
  /// No data is deleted. Returns null on success, or a server error message.
  static Future<String?> setActive({
    required String userId,
    required bool active,
  }) async {
    try {
      await _c.functions.invoke(
        'admin-user-ops',
        body: {'action': 'set_active', 'userId': userId, 'active': active},
      );
      return null;
    } on FunctionException catch (e) {
      // Non-2xx: the Edge Function returns { error } in the body.
      final d = e.details;
      if (d is Map && d['error'] != null) return d['error'].toString();
      return 'Operation failed (status ${e.status}).';
    }
  }

  /// Auth email for a user (service-role read, behind the function's admin gate).
  static Future<String?> fetchEmail(String userId) async {
    final res = await _c.functions.invoke(
      'admin-user-ops',
      body: {'action': 'get_email', 'userId': userId},
    );
    return (res.data as Map?)?['email'] as String?;
  }

  /// admin-reset-app: destructive reset. Super admin only (server).
  static Future<void> resetApp() =>
      _c.functions.invoke('admin-reset-app', body: const {});

  // ── RPCs (SECURITY DEFINER, authenticated) ──────────────────────────────────

  static Future<void> notifyAction({
    required String title,
    required String body,
    required String type,
    String? referenceType,
    String? referenceId,
    String? teamId,
    List<String>? targetUserIds,
  }) => _c.rpc(
    'notify_action',
    params: {
      'p_title': title,
      'p_body': body,
      'p_type': type,
      'p_reference_type': referenceType,
      'p_reference_id': referenceId,
      'p_team_id': teamId,
      'p_target_user_ids': targetUserIds,
    },
  );

  /// Active teams for the handoff destination picker.
  static Future<List<Map<String, dynamic>>> listActiveTeams() async {
    final data = await _c.rpc('list_active_teams');
    return (data as List).cast<Map<String, dynamic>>();
  }
}

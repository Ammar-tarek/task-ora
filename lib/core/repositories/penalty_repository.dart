// lib/core/repositories/penalty_repository.dart

import '../services/supabase_service.dart';

class PenaltyItem {
  final String id;
  final String employeeId;
  final String employeeName;
  final String penaltyType;
  final String penaltyTypeId;
  final String reason;
  final String date;
  final double amount;
  final bool isApplied;
  final String approvedByName;

  const PenaltyItem({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.penaltyType,
    required this.penaltyTypeId,
    required this.reason,
    required this.date,
    required this.amount,
    required this.isApplied,
    required this.approvedByName,
  });

  factory PenaltyItem.fromMap(Map<String, dynamic> m) {
    final employee   = m['employee'] as Map<String, dynamic>?;
    final pType      = m['penalty_type'] as Map<String, dynamic>?;
    final approvedBy = m['approver'] as Map<String, dynamic>?;
    return PenaltyItem(
      id:              m['id'] as String,
      employeeId:      m['employee_id'] as String? ?? '',
      employeeName:    employee?['full_name'] as String? ?? 'Unknown',
      penaltyType:     pType?['name'] as String? ?? '',
      penaltyTypeId:   m['penalty_type_id'] as String? ?? '',
      reason:          m['reason'] as String? ?? '',
      date:            m['penalty_date'] as String? ?? '',
      amount:          (m['amount'] as num?)?.toDouble() ?? 0,
      isApplied:       m['is_applied'] as bool? ?? false,
      approvedByName:  approvedBy?['full_name'] as String? ?? '',
    );
  }
}

class PenaltyRepository {
  static final _client = SupabaseService.client;
  static final _admin  = SupabaseService.adminClient;

  static const _select = '''
    *,
    employee:profiles!penalties_employee_id_fkey(full_name),
    penalty_type:penalty_types(name),
    approver:profiles!penalties_approved_by_fkey(full_name)
  ''';

  /// All penalties — for admin / manager views.
  /// Pass [teamId] to scope to a specific team's employees.
  static Future<List<PenaltyItem>> fetchAll({String? teamId}) async {
    try {
      if (teamId != null) {
        final members = await _admin
            .from('profiles')
            .select('id')
            .eq('team_id', teamId);
        final ids = (members as List).map((m) => m['id'] as String).toList();
        if (ids.isEmpty) return [];
        final data = await _admin
            .from('penalties')
            .select(_select)
            .inFilter('employee_id', ids)
            .order('penalty_date', ascending: false);
        return (data as List).map((m) => PenaltyItem.fromMap(m)).toList();
      }
      final data = await _admin
          .from('penalties')
          .select(_select)
          .order('penalty_date', ascending: false);
      return (data as List).map((m) => PenaltyItem.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Penalties for a specific employee — for self-service employee view.
  static Future<List<PenaltyItem>> fetchForEmployee(String employeeId) async {
    try {
      final data = await _client
          .from('penalties')
          .select(_select)
          .eq('employee_id', employeeId)
          .order('penalty_date', ascending: false);
      return (data as List).map((m) => PenaltyItem.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchTypes() async {
    try {
      // adminClient: penalty_types is shared reference data; manager RLS on the
      // regular client returns zero rows.
      final data = await _admin
          .from('penalty_types')
          .select()
          .eq('is_active', true)
          .order('name');
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  /// Fetch active employees for the "assign penalty" dropdown.
  /// Pass [teamId] to restrict to one team (manager view).
  static Future<List<Map<String, dynamic>>> fetchEmployees({
    String? teamId,
  }) async {
    try {
      var query = _admin
          .from('profiles')
          .select('id, full_name, role')
          .neq('role', 'client')
          .eq('status', 'active');
      if (teamId != null) {
        query = query.eq('team_id', teamId);
      }
      final data = await query.order('full_name');
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  static Future<void> applyPenalty(String penaltyId) async {
    try {
      await _admin.from('penalties').update({
        'is_applied': true,
        'applied_at': DateTime.now().toIso8601String(),
      }).eq('id', penaltyId);
    } catch (_) {}
  }

  static Future<void> createPenalty({
    required String employeeId,
    required String penaltyTypeId,
    required String reason,
    required double amount,
    required String approvedBy,
    required String date,
  }) async {
    try {
      await _admin.from('penalties').insert({
        'employee_id':     employeeId,
        'penalty_type_id': penaltyTypeId,
        'reason':          reason,
        'amount':          amount,
        'approved_by':     approvedBy,
        'penalty_date':    date,
        'is_applied':      false,
      });
    } catch (_) {}
  }

  static Future<void> deletePenalty(String penaltyId) async {
    try {
      await _admin.from('penalties').delete().eq('id', penaltyId);
    } catch (_) {}
  }
}

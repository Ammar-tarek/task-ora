// lib/core/repositories/penalty_repository.dart

import '../services/supabase_service.dart';
import 'notification_repository.dart';

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
  final String status; // 'pending' | 'approved' | 'rejected'
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
    required this.status,
    required this.approvedByName,
  });

  factory PenaltyItem.fromMap(Map<String, dynamic> m) {
    final employee = m['employee'] as Map<String, dynamic>?;
    final pType = m['penalty_type'] as Map<String, dynamic>?;
    final approvedBy = m['approver'] as Map<String, dynamic>?;
    final isApp = m['is_applied'] as bool? ?? false;
    final rawStatus = m['status'] as String?;
    final calcStatus = rawStatus ?? (isApp ? 'approved' : 'pending');

    return PenaltyItem(
      id: m['id'] as String,
      employeeId: m['employee_id'] as String? ?? '',
      employeeName: employee?['full_name'] as String? ?? 'Unknown',
      penaltyType: pType?['name'] as String? ?? 'Penalty',
      penaltyTypeId: m['penalty_type_id'] as String? ?? '',
      reason: m['reason'] as String? ?? '',
      date: m['penalty_date'] as String? ?? '',
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      isApplied: isApp || calcStatus == 'approved',
      status: calcStatus,
      approvedByName: approvedBy?['full_name'] as String? ?? '',
    );
  }
}

class PenaltyRepository {
  static final _client = SupabaseService.client;
  static final _admin = SupabaseService.adminClient;

  static const _select = '''
    *,
    employee:profiles!penalties_employee_id_fkey(full_name),
    penalty_type:penalty_types(name),
    approver:profiles!penalties_approved_by_fkey(full_name)
  ''';

  static Future<Map<String, String>> _fetchProfilesMap() async {
    try {
      final res = await _admin.from('profiles').select('id, full_name');
      final map = <String, String>{};
      for (final r in res as List) {
        map[r['id'] as String] = r['full_name'] as String? ?? 'Unknown';
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, String>> _fetchTypesMap() async {
    try {
      final res = await _admin.from('penalty_types').select('id, name');
      final map = <String, String>{};
      for (final r in res as List) {
        map[r['id'] as String] = r['name'] as String? ?? 'Penalty';
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// All penalties — for admin / manager views.
  /// Pass [teamId] to scope to a specific team's employees.
  static Future<List<PenaltyItem>> fetchAll({String? teamId}) async {
    try {
      List<dynamic> data = [];
      try {
        if (teamId != null) {
          final members = await _admin
              .from('profiles')
              .select('id')
              .eq('team_id', teamId);
          final ids = (members as List).map((m) => m['id'] as String).toList();
          if (ids.isEmpty) return [];
          data = await _admin
              .from('penalties')
              .select(_select)
              .inFilter('employee_id', ids)
              .order('penalty_date', ascending: false);
        } else {
          data = await _admin
              .from('penalties')
              .select(_select)
              .order('penalty_date', ascending: false);
        }
      } catch (_) {
        // Fallback query if relational join fails
        if (teamId != null) {
          final members = await _admin
              .from('profiles')
              .select('id')
              .eq('team_id', teamId);
          final ids = (members as List).map((m) => m['id'] as String).toList();
          if (ids.isEmpty) return [];
          data = await _admin
              .from('penalties')
              .select()
              .inFilter('employee_id', ids)
              .order('penalty_date', ascending: false);
        } else {
          data = await _admin
              .from('penalties')
              .select()
              .order('penalty_date', ascending: false);
        }
      }

      final profiles = await _fetchProfilesMap();
      final types = await _fetchTypesMap();

      return data.map((m) {
        final itemMap = Map<String, dynamic>.from(m as Map);
        final empId = itemMap['employee_id'] as String?;
        final typeId = itemMap['penalty_type_id'] as String?;
        final apprId = itemMap['approved_by'] as String?;

        if (itemMap['employee'] == null && empId != null && profiles.containsKey(empId)) {
          itemMap['employee'] = {'full_name': profiles[empId]};
        }
        if (itemMap['penalty_type'] == null && typeId != null && types.containsKey(typeId)) {
          itemMap['penalty_type'] = {'name': types[typeId]};
        }
        if (itemMap['approver'] == null && apprId != null && profiles.containsKey(apprId)) {
          itemMap['approver'] = {'full_name': profiles[apprId]};
        }

        return PenaltyItem.fromMap(itemMap);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Penalties for a specific employee — for self-service employee view.
  static Future<List<PenaltyItem>> fetchForEmployee(String employeeId) async {
    try {
      List<dynamic> data = [];
      try {
        data = await _client
            .from('penalties')
            .select(_select)
            .eq('employee_id', employeeId)
            .order('penalty_date', ascending: false);
      } catch (_) {
        data = await _client
            .from('penalties')
            .select()
            .eq('employee_id', employeeId)
            .order('penalty_date', ascending: false);
      }

      final profiles = await _fetchProfilesMap();
      final types = await _fetchTypesMap();

      return data.map((m) {
        final itemMap = Map<String, dynamic>.from(m as Map);
        final empId = itemMap['employee_id'] as String?;
        final typeId = itemMap['penalty_type_id'] as String?;
        final apprId = itemMap['approved_by'] as String?;

        if (itemMap['employee'] == null && empId != null && profiles.containsKey(empId)) {
          itemMap['employee'] = {'full_name': profiles[empId]};
        }
        if (itemMap['penalty_type'] == null && typeId != null && types.containsKey(typeId)) {
          itemMap['penalty_type'] = {'name': types[typeId]};
        }
        if (itemMap['approver'] == null && apprId != null && profiles.containsKey(apprId)) {
          itemMap['approver'] = {'full_name': profiles[apprId]};
        }

        return PenaltyItem.fromMap(itemMap);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchTypes() async {
    try {
      final data = await _admin
          .from('penalty_types')
          .select()
          .order('name');
      final list = List<Map<String, dynamic>>.from(data as List);
      if (list.isNotEmpty) return list;

      // Seed default penalty types if table is empty in DB
      try {
        final defaults = [
          {'name': 'Late Arrival', 'description': 'Late arrival penalty'},
          {'name': 'Unexcused Absence', 'description': 'Absence penalty'},
          {'name': 'Policy Violation', 'description': 'Policy violation penalty'},
          {'name': 'Other / General', 'description': 'General penalty'},
        ];
        final inserted = await _admin.from('penalty_types').insert(defaults).select();
        final insertedList = List<Map<String, dynamic>>.from(inserted as List);
        if (insertedList.isNotEmpty) return insertedList;
      } catch (_) {}

      return [
        {'id': 'late_arrival', 'name': 'Late Arrival'},
        {'id': 'absence', 'name': 'Unexcused Absence'},
        {'id': 'policy_violation', 'name': 'Policy Violation'},
        {'id': 'other', 'name': 'Other / General'},
      ];
    } catch (_) {
      return [
        {'id': 'late_arrival', 'name': 'Late Arrival'},
        {'id': 'absence', 'name': 'Unexcused Absence'},
        {'id': 'policy_violation', 'name': 'Policy Violation'},
        {'id': 'other', 'name': 'Other / General'},
      ];
    }
  }

  /// Fetch active employees for the "assign penalty" dropdown.
  /// Pass [teamId] to restrict to one team (manager view).
  static Future<List<Map<String, dynamic>>> fetchEmployees({
    String? teamId,
  }) async {
    try {
      if (teamId != null) {
        try {
          final data = await _admin
              .from('profiles')
              .select('id, full_name, role')
              .neq('role', 'client')
              .eq('team_id', teamId)
              .order('full_name');
          final list = List<Map<String, dynamic>>.from(data as List);
          if (list.isNotEmpty) return list;
        } catch (_) {}
      }

      // Fetch all non-client profiles
      final data = await _admin
          .from('profiles')
          .select('id, full_name, role')
          .neq('role', 'client')
          .order('full_name');
      final list = List<Map<String, dynamic>>.from(data as List);
      if (list.isNotEmpty) return list;

      // Basic fallback select id, full_name
      final basicData = await _admin
          .from('profiles')
          .select('id, full_name')
          .order('full_name');
      return List<Map<String, dynamic>>.from(basicData as List);
    } catch (_) {
      try {
        final basicData = await _admin
            .from('profiles')
            .select('id, full_name');
        return List<Map<String, dynamic>>.from(basicData as List);
      } catch (_) {
        return [];
      }
    }
  }

  /// Approve & Apply penalty deduction
  static Future<void> approvePenalty(String penaltyId, {String? actorId}) async {
    try {
      try {
        await _admin
            .from('penalties')
            .update({
              'is_applied': true,
              'applied_at': DateTime.now().toIso8601String(),
              if (actorId != null) ...{'approved_by': actorId},
            })
            .eq('id', penaltyId);
      } catch (_) {
        await _admin
            .from('penalties')
            .update({
              'is_applied': true,
              'status': 'approved',
              'applied_at': DateTime.now().toIso8601String(),
              if (actorId != null) ...{'approved_by': actorId},
            })
            .eq('id', penaltyId);
      }

      try {
        final p = await _admin
            .from('penalties')
            .select('employee_id, amount, reason')
            .eq('id', penaltyId)
            .maybeSingle();
        if (p != null) {
          final empId = p['employee_id'] as String?;
          final amt = p['amount'];
          final reason = p['reason'] as String? ?? 'Penalty';
          if (empId != null) {
            await NotificationRepository.notifyAction(
              title: '✅ Penalty Approved',
              body: 'Your penalty of \$$amt ($reason) has been approved and applied.',
              type: 'penalty_applied',
              referenceType: 'penalty',
              referenceId: penaltyId,
              targetUserIds: [empId],
              actorId: actorId,
            );
          }
        }
      } catch (_) {}
    } catch (_) {}
  }

  /// Reject / Cancel penalty
  static Future<void> rejectPenalty(String penaltyId, {String? actorId}) async {
    try {
      try {
        await _admin
            .from('penalties')
            .update({
              'is_applied': false,
            })
            .eq('id', penaltyId);
      } catch (_) {
        await _admin
            .from('penalties')
            .update({
              'is_applied': false,
              'status': 'rejected',
            })
            .eq('id', penaltyId);
      }

      try {
        final p = await _admin
            .from('penalties')
            .select('employee_id, amount, reason')
            .eq('id', penaltyId)
            .maybeSingle();
        if (p != null) {
          final empId = p['employee_id'] as String?;
          final amt = p['amount'];
          final reason = p['reason'] as String? ?? 'Penalty';
          if (empId != null) {
            await NotificationRepository.notifyAction(
              title: '❌ Penalty Rejected',
              body: 'The penalty of \$$amt ($reason) was rejected.',
              type: 'penalty_updated',
              referenceType: 'penalty',
              referenceId: penaltyId,
              targetUserIds: [empId],
              actorId: actorId,
            );
          }
        }
      } catch (_) {}
    } catch (_) {}
  }

  static Future<void> applyPenalty(String penaltyId) async {
    await approvePenalty(penaltyId);
  }

  static Future<void> _sendPenaltyNotif(String? pId, String employeeId, double amount, String reason, String actorId) async {
    try {
      await NotificationRepository.notifyAction(
        title: '⚠️ Penalty Logged',
        body: 'A penalty of \$$amount was logged for: $reason.',
        type: 'penalty_created',
        referenceType: 'penalty',
        referenceId: pId,
        targetUserIds: [employeeId],
        actorId: actorId,
      );
    } catch (_) {}
  }

  static Future<bool> createPenalty({
    required String employeeId,
    required String penaltyTypeId,
    required String reason,
    required double amount,
    required String approvedBy,
    required String date,
  }) async {
    final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

    String resolvedTypeId = penaltyTypeId;
    if (!uuidRegex.hasMatch(resolvedTypeId)) {
      try {
        final existing = await _admin.from('penalty_types').select('id').limit(1);
        if ((existing as List).isNotEmpty) {
          resolvedTypeId = existing.first['id'] as String;
        } else {
          final newType = await _admin.from('penalty_types').insert({
            'name': 'General Penalty',
            'description': 'General system penalty type',
          }).select('id').single();
          resolvedTypeId = newType['id'] as String;
        }
      } catch (_) {}
    }

    String resolvedApprovedBy = approvedBy;
    if (!uuidRegex.hasMatch(resolvedApprovedBy)) {
      final currentUser = _admin.auth.currentUser;
      if (currentUser != null && uuidRegex.hasMatch(currentUser.id)) {
        resolvedApprovedBy = currentUser.id;
      } else if (uuidRegex.hasMatch(employeeId)) {
        resolvedApprovedBy = employeeId;
      }
    }

    final payload = <String, dynamic>{
      'employee_id': employeeId,
      'penalty_date': date,
      'amount': amount,
      'reason': reason,
      'is_applied': false,
    };
    if (uuidRegex.hasMatch(resolvedTypeId)) {
      payload['penalty_type_id'] = resolvedTypeId;
    }
    if (uuidRegex.hasMatch(resolvedApprovedBy)) {
      payload['approved_by'] = resolvedApprovedBy;
    }

    try {
      // 1. Try standard database payload matching public.penalties schema
      final res = await _admin.from('penalties').insert(payload).select('id').maybeSingle();
      final pId = res?['id'] as String?;
      await _sendPenaltyNotif(pId, employeeId, amount, reason, resolvedApprovedBy);
      return true;
    } catch (_) {
      try {
        // 2. Try payload with status column if table was altered with status column
        final fullPayload = Map<String, dynamic>.from(payload)..['status'] = 'pending';
        final res = await _admin.from('penalties').insert(fullPayload).select('id').maybeSingle();
        final pId = res?['id'] as String?;
        await _sendPenaltyNotif(pId, employeeId, amount, reason, resolvedApprovedBy);
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  static Future<void> deletePenalty(String penaltyId) async {
    try {
      await _admin.from('penalties').delete().eq('id', penaltyId);
    } catch (_) {}
  }
}


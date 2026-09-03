// lib/core/repositories/expense_repository.dart

import '../services/supabase_service.dart';
import 'notification_repository.dart';

class ExpenseItem {
  final String id;
  final String date;
  final String categoryName;
  final double amount;
  final String description;
  final String? receiptUrl;
  final String recordedByName;
  final String status; // 'pending' | 'approved' | 'rejected'
  final String? approvedBy;

  const ExpenseItem({
    required this.id,
    required this.date,
    required this.categoryName,
    required this.amount,
    required this.description,
    this.receiptUrl,
    required this.recordedByName,
    this.status = 'pending',
    this.approvedBy,
  });

  factory ExpenseItem.fromMap(Map<String, dynamic> m) {
    final cat = m['category'] as Map<String, dynamic>?;
    final profile = m['recorder'] as Map<String, dynamic>?;
    return ExpenseItem(
      id: m['id'] as String,
      date: m['expense_date'] as String? ?? '',
      categoryName: cat?['name'] as String? ?? 'Other',
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      description: m['description'] as String? ?? '',
      receiptUrl: m['receipt_url'] as String?,
      recordedByName: profile?['full_name'] as String? ?? '',
      status: m['status'] as String? ?? 'pending',
      approvedBy: m['approved_by'] as String?,
    );
  }
}

class ExpenseRepository {
  static final _admin = SupabaseService.adminClient;

  /// Team id of a profile — used so expense decisions reach the recorder's
  /// department manager (via NotificationRepository.notifyAction).
  static Future<String?> _teamIdForProfile(String profileId) async {
    try {
      final p = await _admin
          .from('profiles')
          .select('team_id')
          .eq('id', profileId)
          .maybeSingle();
      return p?['team_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Expenses ─────────────────────────────────────────────────────────────────

  /// Fetch expense records. Pass [teamId] to scope to a specific team
  /// (filters by the recorder's team_id).
  static Future<List<ExpenseItem>> fetchAll({
    int limit = 50,
    String? teamId,
  }) async {
    try {
      const sel =
          '*, category:expense_categories(name), recorder:profiles!expenses_recorded_by_fkey(full_name)';
      if (teamId != null) {
        final members = await _admin
            .from('profiles')
            .select('id')
            .eq('team_id', teamId);
        final ids = (members as List).map((m) => m['id'] as String).toList();
        if (ids.isEmpty) return [];
        final data = await _admin
            .from('expenses')
            .select(sel)
            .inFilter('recorded_by', ids)
            .order('expense_date', ascending: false)
            .limit(limit);
        return (data as List).map((m) => ExpenseItem.fromMap(m)).toList();
      }
      final data = await _admin
          .from('expenses')
          .select(sel)
          .order('expense_date', ascending: false)
          .limit(limit);
      return (data as List).map((m) => ExpenseItem.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> createExpense({
    required String categoryId,
    required double amount,
    required String description,
    required String recordedBy,
    required String date,
    String? paidTo,
  }) async {
    // adminClient: expenses RLS is admin-only, so managers/employees would be
    // blocked on the regular client. UI gates who can reach this.
    try {
      final res = await _admin.from('expenses').insert({
        'category_id': categoryId,
        'amount': amount,
        'description': description,
        'recorded_by': recordedBy,
        'expense_date': date,
        'paid_to': paidTo,
        'status': 'pending',
      }).select('id').maybeSingle();

      final expId = res?['id'] as String?;

      await NotificationRepository.notifyAction(
        title: 'New Expense Logged',
        body: 'Expense of \$$amount ($description) was logged.',
        type: 'expense_created',
        referenceType: 'expense',
        referenceId: expId,
        actorId: recordedBy,
      );
    } catch (_) {}
  }

  /// Admin / manager approves an expense.
  static Future<void> approveExpense(
    String expenseId,
    String approvedById,
  ) async {
    try {
      await _admin
          .from('expenses')
          .update({'status': 'approved', 'approved_by': approvedById})
          .eq('id', expenseId);

      try {
        final exp = await _admin
            .from('expenses')
            .select('recorded_by, amount, description')
            .eq('id', expenseId)
            .maybeSingle();
        if (exp != null) {
          final recorderId = exp['recorded_by'] as String?;
          final amt = exp['amount'];
          final desc = exp['description'] as String? ?? 'Expense';
          if (recorderId != null) {
            final teamId = await _teamIdForProfile(recorderId);
            await NotificationRepository.notifyAction(
              title: 'Expense Approved',
              body: 'Your expense of \$$amt ($desc) was approved.',
              type: 'expense_approved',
              referenceType: 'expense',
              referenceId: expenseId,
              teamId: teamId,
              targetUserIds: [recorderId],
              actorId: approvedById,
            );
          }
        }
      } catch (_) {}
    } catch (_) {}
  }

  /// Admin / manager rejects an expense.
  static Future<void> rejectExpense(
    String expenseId,
    String rejectedById,
  ) async {
    try {
      await _admin
          .from('expenses')
          .update({'status': 'rejected', 'approved_by': rejectedById})
          .eq('id', expenseId);

      try {
        final exp = await _admin
            .from('expenses')
            .select('recorded_by, amount, description')
            .eq('id', expenseId)
            .maybeSingle();
        if (exp != null) {
          final recorderId = exp['recorded_by'] as String?;
          final amt = exp['amount'];
          final desc = exp['description'] as String? ?? 'Expense';
          if (recorderId != null) {
            final teamId = await _teamIdForProfile(recorderId);
            await NotificationRepository.notifyAction(
              title: 'Expense Rejected',
              body: 'Your expense of \$$amt ($desc) was rejected.',
              type: 'expense_rejected',
              referenceType: 'expense',
              referenceId: expenseId,
              teamId: teamId,
              targetUserIds: [recorderId],
              actorId: rejectedById,
            );
          }
        }
      } catch (_) {}
    } catch (_) {}
  }

  /// Admin / manager deletes an expense.
  static Future<void> deleteExpense(String expenseId) async {
    try {
      await _admin.from('expenses').delete().eq('id', expenseId);
    } catch (_) {}
  }

  // ── Categories ────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchCategories() async {
    try {
      final data = await _admin
          .from('expense_categories')
          .select()
          .eq('is_active', true)
          .order('name');
      final list = List<Map<String, dynamic>>.from(data as List);
      if (list.isNotEmpty) return list;

      // Auto-seed default categories if empty
      const defaults = [
        'Food',
        'Office',
        'Transport',
        'Software',
        'Infrastructure',
        'Training',
        'Other',
      ];
      for (final name in defaults) {
        try {
          await _admin.from('expense_categories').insert({
            'name': name,
            'is_active': true,
          });
        } catch (_) {}
      }

      final seeded = await _admin
          .from('expense_categories')
          .select()
          .eq('is_active', true)
          .order('name');
      return List<Map<String, dynamic>>.from(seeded as List);
    } catch (_) {
      return [];
    }
  }

  /// Admin / manager creates a new expense category.
  static Future<bool> createCategory({required String name}) async {
    try {
      await _admin.from('expense_categories').insert({
        'name': name,
        'is_active': true,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Admin / manager renames an expense category.
  static Future<bool> updateCategory({
    required String id,
    required String name,
  }) async {
    try {
      await _admin
          .from('expense_categories')
          .update({'name': name})
          .eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Admin / manager soft-deletes a category (sets is_active = false).
  static Future<bool> deleteCategory(String id) async {
    try {
      await _admin
          .from('expense_categories')
          .update({'is_active': false})
          .eq('id', id);
      return true;
    } catch (_) {
      return false;
    }
  }
}

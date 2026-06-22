// lib/core/repositories/expense_repository.dart

import '../services/supabase_service.dart';

class ExpenseItem {
  final String id;
  final String date;
  final String categoryName;
  final double amount;
  final String description;
  final String? receiptUrl;
  final String recordedByName;

  const ExpenseItem({
    required this.id,
    required this.date,
    required this.categoryName,
    required this.amount,
    required this.description,
    this.receiptUrl,
    required this.recordedByName,
  });

  factory ExpenseItem.fromMap(Map<String, dynamic> m) {
    final cat     = m['category'] as Map<String, dynamic>?;
    final profile = m['recorder'] as Map<String, dynamic>?;
    return ExpenseItem(
      id:              m['id'] as String,
      date:            m['expense_date'] as String? ?? '',
      categoryName:    cat?['name'] as String? ?? 'Other',
      amount:          (m['amount'] as num?)?.toDouble() ?? 0,
      description:     m['description'] as String? ?? '',
      receiptUrl:      m['receipt_url'] as String?,
      recordedByName:  profile?['full_name'] as String? ?? '',
    );
  }
}

class ExpenseRepository {
  static final _client = SupabaseService.client;
  static final _admin  = SupabaseService.adminClient;

  static Future<List<ExpenseItem>> fetchAll({int limit = 50}) async {
    try {
      final data = await _admin
          .from('expenses')
          .select('*, category:expense_categories(name), recorder:profiles!expenses_recorded_by_fkey(full_name)')
          .order('expense_date', ascending: false)
          .limit(limit);
      return (data as List).map((m) => ExpenseItem.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchCategories() async {
    try {
      final data = await _admin
          .from('expense_categories')
          .select()
          .eq('is_active', true)
          .order('name');
      return List<Map<String, dynamic>>.from(data as List);
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
    try {
      await _client.from('expenses').insert({
        'category_id':  categoryId,
        'amount':       amount,
        'description':  description,
        'recorded_by':  recordedBy,
        'expense_date': date,
        'paid_to':      paidTo,
      });
    } catch (_) { /* table may not exist yet */ }
  }
}

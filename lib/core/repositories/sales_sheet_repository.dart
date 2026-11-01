// lib/core/repositories/sales_sheet_repository.dart
// CRUD for the Sales Sheet (public.sales_sheet_entries). Uses the authenticated
// Supabase client only — RLS is the real boundary: Sales-team staff (and global
// admins) can read; Sales managers and global admins can write. No service-role.
//
// DEPLOYMENT DEPENDENCY: apply PROPOSED_sales_sheet_entries.sql (and, to load the
// imported rows, PROPOSED_sales_sheet_seed.sql). Until then reads return [] and
// writes return an error string the UI surfaces.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sales_sheet_entry.dart';
import '../services/supabase_service.dart';

class SalesSheetRepository {
  static final _client = SupabaseService.client;
  static const _table = 'sales_sheet_entries';

  /// Columns the client is allowed to write (whitelist guards against typos and
  /// stray keys; RLS still gates whether the write is permitted at all).
  static const _editable = {
    'client',
    'link',
    'owner_name',
    'owner_number',
    'status',
    'probability',
    'est_value',
    'last_contact',
    'expected_close',
  };

  /// All rows, in manual order (sort_order, then insertion time).
  static Future<List<SalesSheetEntry>> fetchAll() async {
    try {
      final data = await _client
          .from(_table)
          .select()
          .order('sort_order', ascending: true)
          .order('created_at', ascending: true);
      return (data as List)
          .map((m) => SalesSheetEntry.fromMap(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Append a blank row at the bottom. Returns the new row id, or null on error.
  static Future<String?> addRow() async {
    try {
      final res = await _client
          .from(_table)
          .insert({'sort_order': DateTime.now().millisecondsSinceEpoch.toDouble()})
          .select('id')
          .single();
      return res['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Update a single column on one row. Returns null on success, else a message.
  static Future<String?> updateField(String id, String column, String value) async {
    if (!_editable.contains(column)) return 'Invalid column';
    try {
      await _client.from(_table).update({column: value}).eq('id', id);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Delete one row. Returns null on success, else a message.
  static Future<String?> deleteRow(String id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }
}

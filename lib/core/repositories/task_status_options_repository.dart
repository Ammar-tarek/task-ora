// lib/core/repositories/task_status_options_repository.dart
// Manages task status options stored in column_status_options.
// Self-bootstrapping: creates the backing custom_table + custom_column on
// first admin access so non-admins never hit a missing-table error.

import 'package:flutter/material.dart';
import '../models/task_status_option.dart';
import '../services/supabase_service.dart';

class TaskStatusOptionsRepository {
  static final _client = SupabaseService.client;

  static const _systemTableName = '_task_status_system';
  static const _columnName      = 'task_status';

  static String? _cachedColumnId;
  static List<TaskStatusOption>? _cache;

  // Default built-in options seeded on first setup.
  static const List<List<String>> _defaults = [
    ['not_started',     '#6D4C41'],
    ['in_progress',     '#1565C0'],
    ['employee_done',   '#755B00'],
    ['client_approve',  '#2E7D32'],
    ['client_rejected', '#BA1A1A'],
    ['completed',       '#2E7D32'],
    ['on_hold',         '#747878'],
  ];

  // ── Bootstrap ───────────────────────────────────────────────────────────────

  /// Find or create the system custom_table + custom_column and seed defaults.
  /// Call this once from admin context on first use.
  static Future<void> init(String adminUserId) async {
    await _getOrCreateColumnId(adminUserId);
  }

  static Future<String?> _getOrCreateColumnId(String userId) async {
    if (_cachedColumnId != null) return _cachedColumnId;

    // Step 1 — find / create system table
    String? tableId;
    try {
      final rows = await _client
          .from('custom_tables')
          .select('id')
          .eq('name', _systemTableName)
          .limit(1);
      if ((rows as List).isNotEmpty) {
        tableId = rows.first['id'] as String;
      } else {
        final res = await _client.from('custom_tables').insert({
          'name':       _systemTableName,
          'icon':       '🏷',
          'color':      '#888888',
          'created_by': userId,
          'is_archived': false,
        }).select('id').single();
        tableId = res['id'] as String;
      }
    } catch (_) {
      return null;
    }

    // Step 2 — find / create column
    try {
      final cols = await _client
          .from('custom_columns')
          .select('id')
          .eq('table_id', tableId!)
          .eq('name', _columnName)
          .limit(1);

      String columnId;
      if ((cols as List).isNotEmpty) {
        columnId = cols.first['id'] as String;
      } else {
        final res = await _client.from('custom_columns').insert({
          'table_id':              tableId,
          'name':                  _columnName,
          'field_type':            'status',
          'position':              0,
          'created_by':            userId,
          'is_required':           false,
          'is_admin_only':         false,
          'is_hidden_from_client': false,
        }).select('id').single();
        columnId = res['id'] as String;

        // Seed the 7 built-in options
        final seeds = <Map<String, dynamic>>[];
        for (var i = 0; i < _defaults.length; i++) {
          seeds.add({
            'column_id':  columnId,
            'label':      _defaults[i][0],
            'color':      _defaults[i][1],
            'position':   i,
            'is_default': true,
          });
        }
        await _client.from('column_status_options').insert(seeds);
      }

      _cachedColumnId = columnId;
      return columnId;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _findColumnId() async {
    if (_cachedColumnId != null) return _cachedColumnId;
    try {
      final tables = await _client
          .from('custom_tables')
          .select('id')
          .eq('name', _systemTableName)
          .limit(1);
      if ((tables as List).isEmpty) return null;
      final tableId = tables.first['id'] as String;

      final cols = await _client
          .from('custom_columns')
          .select('id')
          .eq('table_id', tableId)
          .eq('name', _columnName)
          .limit(1);
      if ((cols as List).isEmpty) return null;

      _cachedColumnId = cols.first['id'] as String;
      return _cachedColumnId;
    } catch (_) {
      return null;
    }
  }

  // ── Read ────────────────────────────────────────────────────────────────────

  static Future<List<TaskStatusOption>> fetchOptions() async {
    final columnId = await _findColumnId();
    if (columnId == null) {
      return _fallback();
    }
    try {
      final data = await _client
          .from('column_status_options')
          .select()
          .eq('column_id', columnId)
          .order('position');
      final list = (data as List)
          .map((m) => TaskStatusOption.fromMap(m as Map<String, dynamic>))
          .toList();
      _cache = list.isEmpty ? _fallback() : list;
      return _cache!;
    } catch (_) {
      return _fallback();
    }
  }

  // ── Write (admin only) ───────────────────────────────────────────────────────

  static Future<TaskStatusOption?> addOption({
    required String label,
    required String color,
    required String userId,
  }) async {
    final columnId = await _getOrCreateColumnId(userId);
    if (columnId == null) return null;
    try {
      final existing = _cache ?? await fetchOptions();
      final maxPos = existing.isEmpty
          ? 0
          : existing.map((o) => o.position).reduce((a, b) => a > b ? a : b) + 1;

      final res = await _client.from('column_status_options').insert({
        'column_id':  columnId,
        'label':      label,
        'color':      color,
        'position':   maxPos,
        'is_default': false,
      }).select().single();
      final opt = TaskStatusOption.fromMap(res);
      _cache = [...(existing), opt];
      return opt;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> updateOption(
    String id, {
    required String label,
    required String color,
  }) async {
    try {
      await _client.from('column_status_options').update({
        'label': label,
        'color': color,
      }).eq('id', id);
      _cache = null; // invalidate
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteOption(String id) async {
    try {
      await _client.from('column_status_options').delete().eq('id', id);
      _cache?.removeWhere((o) => o.id == id);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Returns the display color for a task status value using live cache,
  /// falling back to static mapping. Used by board / table screens.
  static Color colorForStatus(String value) {
    if (_cache != null) {
      for (final opt in _cache!) {
        if (opt.label == value) return opt.dartColor;
      }
    }
    return _staticColor(value);
  }

  static Color _staticColor(String value) {
    switch (value) {
      case 'in_progress':     return const Color(0xFF1565C0);
      case 'employee_done':   return const Color(0xFF755B00);
      case 'client_approve':  return const Color(0xFF2E7D32);
      case 'client_rejected': return const Color(0xFFBA1A1A);
      case 'completed':       return const Color(0xFF2E7D32);
      case 'on_hold':         return const Color(0xFF747878);
      default:                return const Color(0xFF6D4C41);
    }
  }

  static List<TaskStatusOption> _fallback() {
    return List.generate(_defaults.length, (i) => TaskStatusOption(
      id:        i.toString(),
      columnId:  '',
      label:     _defaults[i][0],
      color:     _defaults[i][1],
      position:  i,
      isDefault: true,
    ));
  }
}

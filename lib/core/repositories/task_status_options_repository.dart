// lib/core/repositories/task_status_options_repository.dart
// Task status options ("manage columns"), stored in the flat, GLOBAL table
// public.task_status_options. Everyone signed in can READ (shared across all
// tasks); admins + managers can WRITE (RLS-enforced). This replaced the old
// custom_tables/custom_columns backing, whose team-scoped RLS made the feature
// unstable (only a global admin could use it; others silently fell back).
//
// DEPLOYMENT DEPENDENCY: apply PROPOSED_task_status_options.sql. Until then,
// reads fall back to the built-in list and writes return an error.

import 'package:flutter/material.dart';
import '../models/task_status_option.dart';
import '../services/supabase_service.dart';

class TaskStatusOptionsRepository {
  static final _client = SupabaseService.client;
  static const _table = 'task_status_options';

  static List<TaskStatusOption>? _cache;

  // Built-in options, used only as a read fallback when the table is missing.
  static const List<List<String>> _defaults = [
    ['not_started', '#6D4C41'],
    ['in_progress', '#1565C0'],
    ['employee_done', '#755B00'],
    ['client_approved', '#2E7D32'],
    ['client_rejected', '#BA1A1A'],
    ['completed', '#2E7D32'],
    ['on_hold', '#747878'],
  ];

  /// Kept for call-site compatibility. The flat table + seed migration replace
  /// the old self-bootstrap, so there is nothing to create here.
  static Future<void> init(String adminUserId) async {}

  // ── Read ────────────────────────────────────────────────────────────────────

  static Future<List<TaskStatusOption>> fetchOptions() async {
    try {
      final data =
          await _client.from(_table).select().order('position', ascending: true);
      final list = (data as List)
          .map((m) => TaskStatusOption.fromMap(m as Map<String, dynamic>))
          .toList();
      _cache = list.isEmpty ? _fallback() : list;
      return _cache!;
    } catch (_) {
      return _fallback();
    }
  }

  // ── Write (admin / manager; RLS-enforced) ────────────────────────────────────

  static Future<TaskStatusOption?> addOption({
    required String label,
    required String color,
    required String userId, // kept for call-site compatibility
  }) async {
    try {
      final existing = _cache ?? await fetchOptions();
      final maxPos = existing.isEmpty
          ? 0
          : existing.map((o) => o.position).reduce((a, b) => a > b ? a : b) + 1;
      final res = await _client
          .from(_table)
          .insert({
            'label': label,
            'color': color,
            'position': maxPos,
            'is_default': false,
          })
          .select()
          .single();
      final opt = TaskStatusOption.fromMap(res);
      _cache = [...existing, opt];
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
      await _client
          .from(_table)
          .update({'label': label, 'color': color})
          .eq('id', id);
      _cache = null; // invalidate; next fetch reloads
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteOption(String id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
      _cache?.removeWhere((o) => o.id == id);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Display color for a task status value — live cache first, then a static
  /// mapping. Used by the board / table screens.
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
      case 'in_progress':
        return const Color(0xFF1565C0);
      case 'employee_done':
        return const Color(0xFF755B00);
      case 'client_approved':
        return const Color(0xFF2E7D32);
      case 'client_rejected':
        return const Color(0xFFBA1A1A);
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'on_hold':
        return const Color(0xFF747878);
      default:
        return const Color(0xFF6D4C41);
    }
  }

  static List<TaskStatusOption> _fallback() {
    return List.generate(
      _defaults.length,
      (i) => TaskStatusOption(
        id: i.toString(),
        columnId: '',
        label: _defaults[i][0],
        color: _defaults[i][1],
        position: i,
        isDefault: true,
      ),
    );
  }
}

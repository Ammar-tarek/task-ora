// lib/core/services/realtime_service.dart
// Live auto-refresh: subscribes to Supabase realtime (postgres_changes) on the
// app's core tables. Screens register a callback per table and reload when a
// row changes — no manual refresh needed.

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class RealtimeService {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();

  static const _tables = [
    'tasks', 'task_assignees', 'attendance', 'expenses', 'penalties',
    'crm_entries', 'profiles', 'events', 'client_profiles',
    'app_settings', 'team_privileges', 'user_privileges',
  ];

  RealtimeChannel? _channel;
  final Map<String, List<void Function()>> _listeners = {};
  final Map<String, Timer> _debounce = {};

  /// Call once after Supabase.initialize (main.dart).
  void init() {
    if (_channel != null) return;
    // adminClient socket → service-role bypasses RLS, one stream for all roles.
    var ch = SupabaseService.adminClient.channel('app-live');
    for (final t in _tables) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t,
        callback: (_) => _fire(t),
      );
    }
    _channel = ch..subscribe();
  }

  void _fire(String table) {
    // Debounce bursts (e.g. multi-row updates) into one refresh.
    _debounce[table]?.cancel();
    _debounce[table] = Timer(const Duration(milliseconds: 400), () {
      final cbs = List.of(_listeners[table] ?? const <void Function()>[]);
      for (final cb in cbs) {
        try { cb(); } catch (_) {}
      }
    });
  }

  /// Subscribe [onChange] to changes on any of [tables].
  void listen(List<String> tables, void Function() onChange) {
    for (final t in tables) {
      _listeners.putIfAbsent(t, () => []).add(onChange);
    }
  }

  /// Remove a previously registered [onChange] callback.
  void unlisten(void Function() onChange) {
    for (final l in _listeners.values) {
      l.remove(onChange);
    }
  }
}

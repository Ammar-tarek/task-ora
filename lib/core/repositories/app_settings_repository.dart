// lib/core/repositories/app_settings_repository.dart
// Central key/value settings shared across all devices (stored in Supabase).
// Used for the company WiFi networks + auto-attendance toggle, which the ADMIN
// sets once and every employee/manager device reads.

import 'dart:convert';

import '../services/supabase_service.dart';

class AppSettingsRepository {
  static final _admin = SupabaseService.adminClient;

  /// Legacy single-SSID key. Kept for backward compatibility (see [getWifiSsids]
  /// / [setWifiSsids]) — never deleted so old app versions keep working.
  static const kWifiSsid = 'company_wifi_ssid';

  /// New multi-network key. Value is a JSON array of SSID strings, e.g.
  /// `["Cashback_Office","Cashback_Office_5G"]`, stored in the text `value`
  /// column (the table is a plain key/value store).
  static const kWifiSsids = 'company_wifi_ssids';

  static const kWifiEnabled = 'wifi_attendance_enabled';
  static const kWorkDataCutoffDate = 'work_data_cutoff_date';

  /// Read a single setting value. Returns null if missing.
  static Future<String?> get(String key) async {
    try {
      final row = await _admin
          .from('app_settings')
          .select('value')
          .eq('key', key)
          .maybeSingle();
      return row?['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Write a single setting value (admin only — UI gates this).
  static Future<void> set(String key, String value, {String? updatedBy}) async {
    await _admin.from('app_settings').upsert({
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toIso8601String(),
      'updated_by': ?updatedBy,
    }, onConflict: 'key');
  }

  // ── Convenience getters ────────────────────────────────────────────────────

  /// Legacy single-SSID accessor. Prefer [getWifiSsids] — kept only so any
  /// remaining old caller and old app versions still resolve a value.
  static Future<String> getWifiSsid() async => (await get(kWifiSsid)) ?? '';

  /// Company WiFi networks. Reads the new JSON-array key and falls back to the
  /// legacy single-SSID key when the array is missing/empty (backward compat).
  /// Returns a normalized, de-duplicated, non-empty list.
  static Future<List<String>> getWifiSsids() async {
    final raw = await get(kWifiSsids);
    final parsed = _decodeSsidList(raw);
    if (parsed.isNotEmpty) return parsed;

    // Backward compatibility: migrate reads from the legacy single key.
    final legacy = ((await get(kWifiSsid)) ?? '').trim();
    return legacy.isEmpty ? <String>[] : <String>[legacy];
  }

  static Future<bool> isWifiEnabled() async =>
      (await get(kWifiEnabled)) == 'true';

  /// Legacy single-SSID setter. Prefer [setWifiSsids].
  static Future<void> setWifiSsid(String ssid, {String? updatedBy}) =>
      setWifiSsids([ssid], updatedBy: updatedBy);

  /// Persist the company WiFi networks centrally for all devices. Also mirrors
  /// the primary (first) SSID into the legacy key so older app builds that only
  /// read [kWifiSsid] keep working during the transition.
  static Future<void> setWifiSsids(List<String> ssids, {String? updatedBy}) async {
    final cleaned = _cleanSsidList(ssids);
    await set(kWifiSsids, jsonEncode(cleaned), updatedBy: updatedBy);
    await set(kWifiSsid, cleaned.isEmpty ? '' : cleaned.first, updatedBy: updatedBy);
  }

  /// Parse the stored value into a clean SSID list. Accepts a JSON array, or a
  /// bare string (legacy) which becomes a single-element list.
  static List<String> _decodeSsidList(String? raw) {
    if (raw == null) return <String>[];
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        return _cleanSsidList(decoded.map((e) => e.toString()));
      }
    } catch (_) {
      // Not JSON — treat the whole value as a single legacy SSID.
    }
    return _cleanSsidList([trimmed]);
  }

  /// Trim each SSID, drop empties, and de-duplicate while preserving order.
  static List<String> _cleanSsidList(Iterable<String> ssids) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in ssids) {
      final t = s.trim();
      if (t.isEmpty || !seen.add(t)) continue;
      out.add(t);
    }
    return out;
  }

  static Future<void> setWifiEnabled(bool enabled, {String? updatedBy}) =>
      set(kWifiEnabled, enabled ? 'true' : 'false', updatedBy: updatedBy);

  static Future<String?> getWorkDataCutoffDate() async =>
      await get(kWorkDataCutoffDate);

  static Future<void> setWorkDataCutoffDate(String dateStr, {String? updatedBy}) =>
      set(kWorkDataCutoffDate, dateStr.trim(), updatedBy: updatedBy);

  static Future<void> clearWorkDataCutoffDate({String? updatedBy}) =>
      set(kWorkDataCutoffDate, '', updatedBy: updatedBy);
}

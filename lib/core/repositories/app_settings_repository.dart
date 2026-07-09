// lib/core/repositories/app_settings_repository.dart
// Central key/value settings shared across all devices (stored in Supabase).
// Used for the company WiFi SSID + auto-attendance toggle, which the ADMIN
// sets once and every employee/manager device reads.

import '../services/supabase_service.dart';

class AppSettingsRepository {
  static final _admin = SupabaseService.adminClient;

  static const kWifiSsid    = 'company_wifi_ssid';
  static const kWifiEnabled = 'wifi_attendance_enabled';

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
      'key':        key,
      'value':      value,
      'updated_at': DateTime.now().toIso8601String(),
      if (updatedBy != null) 'updated_by': updatedBy,
    }, onConflict: 'key');
  }

  // ── Convenience getters ────────────────────────────────────────────────────

  static Future<String> getWifiSsid() async => (await get(kWifiSsid)) ?? '';

  static Future<bool> isWifiEnabled() async =>
      (await get(kWifiEnabled)) == 'true';

  static Future<void> setWifiSsid(String ssid, {String? updatedBy}) =>
      set(kWifiSsid, ssid.trim(), updatedBy: updatedBy);

  static Future<void> setWifiEnabled(bool enabled, {String? updatedBy}) =>
      set(kWifiEnabled, enabled ? 'true' : 'false', updatedBy: updatedBy);
}

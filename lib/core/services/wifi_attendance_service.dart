// lib/core/services/wifi_attendance_service.dart
// Monitors WiFi connectivity and auto-checks employees in/out when they
// connect to / disconnect from the configured company WiFi network.

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/attendance_repository.dart';
import 'local_notification_service.dart';

// Local cache keys — mirror the central DB values so detection still works
// briefly offline. The DB (app_settings) is always the source of truth.
const _kCompanySsid        = 'wifi_company_ssid';
const _kWifiAttendance     = 'wifi_attendance_enabled';
const _kSessionStart       = 'wifi_session_start_ms';

class WifiAttendanceService {
  WifiAttendanceService._();
  static final WifiAttendanceService instance = WifiAttendanceService._();

  final _network = NetworkInfo();
  String? _employeeId;
  bool _initialized = false;

  // ── Settings helpers ───────────────────────────────────────────────────────
  // Source of truth is the central app_settings table (admin-controlled).
  // We mirror values into SharedPreferences so detection keeps working if the
  // network read momentarily fails.

  static Future<String?> getCompanySsid() async {
    try {
      final ssid = await AppSettingsRepository.getWifiSsid();
      final p = await SharedPreferences.getInstance();
      await p.setString(_kCompanySsid, ssid); // refresh cache
      return ssid;
    } catch (_) {
      final p = await SharedPreferences.getInstance();
      return p.getString(_kCompanySsid);
    }
  }

  /// Admin only — persists the SSID centrally for all devices.
  static Future<void> setCompanySsid(String ssid, {String? updatedBy}) async {
    await AppSettingsRepository.setWifiSsid(ssid, updatedBy: updatedBy);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCompanySsid, ssid.trim());
  }

  static Future<bool> isEnabled() async {
    try {
      final enabled = await AppSettingsRepository.isWifiEnabled();
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kWifiAttendance, enabled); // refresh cache
      return enabled;
    } catch (_) {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_kWifiAttendance) ?? false;
    }
  }

  /// Admin only — toggles auto-attendance centrally for all devices.
  static Future<void> setEnabled(bool enabled, {String? updatedBy}) async {
    await AppSettingsRepository.setWifiEnabled(enabled, updatedBy: updatedBy);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWifiAttendance, enabled);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Call once when the authenticated employee's profile is available.
  Future<void> init(String employeeId) async {
    if (_initialized && _employeeId == employeeId) return;
    _employeeId   = employeeId;
    _initialized  = true;

    // Listen for connectivity changes while the app is in the foreground.
    Connectivity().onConnectivityChanged.listen(_onConnectivity);

    // Also do an immediate check on startup.
    await checkNow();
  }

  void dispose() {
    _initialized = false;
    _employeeId  = null;
  }

  // ── Core logic ─────────────────────────────────────────────────────────────

  /// Called from app-resume (WidgetsBindingObserver) and from init.
  Future<void> checkNow() async {
    if (_employeeId == null) return;
    if (!await isEnabled())  return;

    final results = await Connectivity().checkConnectivity();
    final onWifi  = results.contains(ConnectivityResult.wifi);

    if (onWifi && await _isOnCompanyNetwork()) {
      await _handleConnected();
    } else {
      await _handleDisconnected();
    }
  }

  Future<void> _onConnectivity(List<ConnectivityResult> results) async {
    if (_employeeId == null) return;
    if (!await isEnabled())  return;

    final onWifi = results.contains(ConnectivityResult.wifi);

    if (onWifi && await _isOnCompanyNetwork()) {
      await _handleConnected();
    } else {
      await _handleDisconnected();
    }
  }

  /// Returns true when the device is on the company network.
  /// On web, SSID is not readable — we trust WiFi connectivity alone
  /// (set SSID to empty in settings to use this web/fallback mode).
  Future<bool> _isOnCompanyNetwork() async {
    // Web: browser has no API to read SSID — treat any WiFi as company WiFi
    // when no SSID is configured, or always if running on web.
    final companySsid = await getCompanySsid();
    if (kIsWeb || companySsid == null || companySsid.isEmpty) return true;

    final currentSsid = await _getSsid();
    if (currentSsid == null) return false;
    return _normalizeSsid(currentSsid) == _normalizeSsid(companySsid);
  }

  Future<void> _handleConnected() async {
    final prefs = await SharedPreferences.getInstance();

    // If no session is running, start one and check-in.
    if (!prefs.containsKey(_kSessionStart)) {
      prefs.setInt(_kSessionStart, DateTime.now().millisecondsSinceEpoch);
      await AttendanceRepository.autoCheckIn(_employeeId!);
      // Notify the employee that their attendance was recorded.
      LocalNotificationService.show(
        title: '✅ Checked In',
        body:  'Your attendance has been automatically recorded.',
        type:  LocalNotificationService.typeHr,
        id:    2001,
      );
    }
  }

  Future<void> _handleDisconnected() async {
    final prefs = await SharedPreferences.getInstance();

    final sessionStart = prefs.getInt(_kSessionStart);
    if (sessionStart == null) return; // No session was running.

    final minutes = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(sessionStart))
        .inMinutes;

    await prefs.remove(_kSessionStart);
    await AttendanceRepository.autoCheckOut(_employeeId!, accumulatedMinutes: minutes);
    // Notify the employee that their check-out was recorded.
    LocalNotificationService.show(
      title: '🔔 Checked Out',
      body:  'You have been automatically checked out after ${minutes}m session.',
      type:  LocalNotificationService.typeHr,
      id:    2002,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<String?> _getSsid() async {
    try {
      return await _network.getWifiName();
    } catch (_) {
      return null;
    }
  }

  /// Strip surrounding quotes that some platforms add to the SSID.
  String _normalizeSsid(String s) => s.replaceAll('"', '').trim();
}

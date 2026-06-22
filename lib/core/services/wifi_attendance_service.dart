// lib/core/services/wifi_attendance_service.dart
// Monitors WiFi connectivity and auto-checks employees in/out when they
// connect to / disconnect from the configured company WiFi network.

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/attendance_repository.dart';

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

  static Future<String?> getCompanySsid() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kCompanySsid);
  }

  static Future<void> setCompanySsid(String ssid) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCompanySsid, ssid.trim());
  }

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kWifiAttendance) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
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

    final companySsid = await getCompanySsid();
    if (companySsid == null || companySsid.isEmpty) return;

    final results = await Connectivity().checkConnectivity();
    final onWifi  = results.contains(ConnectivityResult.wifi);

    if (onWifi) {
      final currentSsid = await _getSsid();
      if (currentSsid != null &&
          _normalizeSsid(currentSsid) == _normalizeSsid(companySsid)) {
        await _handleConnected();
        return;
      }
    }
    await _handleDisconnected();
  }

  Future<void> _onConnectivity(List<ConnectivityResult> results) async {
    if (_employeeId == null) return;
    if (!await isEnabled())  return;

    final companySsid = await getCompanySsid();
    if (companySsid == null || companySsid.isEmpty) return;

    final onWifi = results.contains(ConnectivityResult.wifi);
    if (onWifi) {
      final currentSsid = await _getSsid();
      if (currentSsid != null &&
          _normalizeSsid(currentSsid) == _normalizeSsid(companySsid)) {
        await _handleConnected();
        return;
      }
    }
    await _handleDisconnected();
  }

  Future<void> _handleConnected() async {
    final prefs = await SharedPreferences.getInstance();

    // If no session is running, start one and check-in.
    if (!prefs.containsKey(_kSessionStart)) {
      prefs.setInt(_kSessionStart, DateTime.now().millisecondsSinceEpoch);
      await AttendanceRepository.autoCheckIn(_employeeId!);
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

// lib/core/services/wifi_attendance_service.dart
// Monitors WiFi connectivity and auto-checks employees in/out when they
// connect to / disconnect from any of the configured company WiFi networks.
//
// The company can configure MANY WiFi networks (SSIDs). An employee is treated
// as "on the company network" whenever the device is connected to ANY of them,
// so switching between two company networks does NOT check the employee out.

import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/app_settings_repository.dart';
import '../repositories/attendance_repository.dart';

// Local cache keys — mirror the central DB values so detection still works
// briefly offline. The DB (app_settings) is always the source of truth.
const _kCompanySsids = 'wifi_company_ssids'; // JSON-encoded List<String>
const _kLegacyCompanySsid = 'wifi_company_ssid'; // pre-multi-network cache key
const _kWifiAttendance = 'wifi_attendance_enabled';
const _kSessionStart = 'wifi_session_start_ms';

/// Grace period before an auto check-out actually fires after leaving WiFi.
/// This absorbs the brief "no company network" blip that happens while the OS
/// hands the device off from one company WiFi to another (and coalesces rapid
/// connectivity callbacks) so a legitimate switch never checks the user out.
const _kDisconnectGrace = Duration(seconds: 25);

class WifiAttendanceService {
  WifiAttendanceService._();
  static final WifiAttendanceService instance = WifiAttendanceService._();

  final _network = NetworkInfo();
  String? _employeeId;
  bool _initialized = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  // Pending grace-period checkout (see [_kDisconnectGrace]).
  Timer? _pendingCheckout;

  // Serializes connectivity handlers so rapid callbacks can't race into
  // duplicate check-ins / check-outs.
  Future<void> _lock = Future.value();

  Future<void> _synchronized(Future<void> Function() action) {
    final completer = Completer<void>();
    _lock = _lock.then((_) async {
      try {
        await action();
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    // Never surface handler errors to the connectivity stream.
    return completer.future.catchError((_) {});
  }

  // ── Settings helpers ───────────────────────────────────────────────────────
  // Source of truth is the central app_settings table (admin-controlled).
  // We mirror values into SharedPreferences so detection keeps working if the
  // network read momentarily fails.

  /// The configured company WiFi networks. Reads the central DB (and refreshes
  /// the local cache), falling back to the cache if the DB read fails.
  static Future<List<String>> getCompanySsids() async {
    try {
      final ssids = await AppSettingsRepository.getWifiSsids();
      final p = await SharedPreferences.getInstance();
      await p.setString(_kCompanySsids, jsonEncode(ssids)); // refresh cache
      return ssids;
    } catch (_) {
      final p = await SharedPreferences.getInstance();
      final cached = p.getString(_kCompanySsids);
      if (cached != null) {
        try {
          final decoded = jsonDecode(cached);
          if (decoded is List) {
            return decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      }
      // Fall back to the pre-multi-network cache key if present.
      final legacy = p.getString(_kLegacyCompanySsid)?.trim();
      return (legacy == null || legacy.isEmpty) ? <String>[] : <String>[legacy];
    }
  }

  /// Admin only — persists the SSID list centrally for all devices.
  static Future<void> setCompanySsids(
    List<String> ssids, {
    String? updatedBy,
  }) async {
    await AppSettingsRepository.setWifiSsids(ssids, updatedBy: updatedBy);
    final cleaned = ssids.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCompanySsids, jsonEncode(cleaned));
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

    if (!enabled) {
      await p.remove(_kSessionStart);
      instance.dispose();
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Call once when the authenticated employee's profile is available.
  Future<void> init(String employeeId) async {
    if (!await isEnabled()) return;
    if (_initialized && _employeeId == employeeId) return;
    _employeeId = employeeId;
    _initialized = true;

    // Listen for connectivity changes while the app is in the foreground.
    await _subscription?.cancel();
    _subscription = Connectivity().onConnectivityChanged.listen(_onConnectivity);

    // Also do an immediate check on startup.
    await checkNow();
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _pendingCheckout?.cancel();
    _pendingCheckout = null;
    _initialized = false;
    _employeeId = null;
  }

  // ── Core logic ─────────────────────────────────────────────────────────────

  /// Called from app-resume (WidgetsBindingObserver) and from init.
  Future<void> checkNow() => _synchronized(_evaluate);

  Future<void> _onConnectivity(List<ConnectivityResult> results) =>
      _synchronized(_evaluate);

  /// Single source of truth for the connect/disconnect decision. Re-reads the
  /// live connectivity + SSID each time (connectivity events don't always carry
  /// an up-to-date SSID, and this is also called from the grace timer).
  Future<void> _evaluate() async {
    if (_employeeId == null) return;
    if (!await isEnabled()) {
      _pendingCheckout?.cancel();
      _pendingCheckout = null;
      final p = await SharedPreferences.getInstance();
      await p.remove(_kSessionStart);
      return;
    }

    final results = await Connectivity().checkConnectivity();
    final onWifi = results.contains(ConnectivityResult.wifi);

    if (onWifi && await _isOnCompanyNetwork()) {
      await _handleConnected();
    } else {
      await _handleDisconnected();
    }
  }

  /// Returns true when the device is connected to ANY configured company SSID.
  ///
  /// On web (and when no SSID is configured) the browser has no API to read the
  /// SSID, so we trust WiFi connectivity alone — see the class-level notes and
  /// the Admin settings screen for the documented platform behavior.
  Future<bool> _isOnCompanyNetwork() async {
    final companySsids = await getCompanySsids();
    // Web: browser can't read SSID — treat any WiFi as company WiFi. Same
    // fallback when the admin hasn't configured any SSID yet.
    if (kIsWeb || companySsids.isEmpty) return true;

    final currentSsid = await _getSsid();
    return matchesCompany(currentSsid, companySsids);
  }

  /// Pure, testable core of the network check: is the detected [current] SSID
  /// one of the [configured] company SSIDs, comparing normalized values?
  /// An empty [configured] list means "not SSID-gated" (see [_isOnCompanyNetwork]).
  static bool matchesCompany(String? current, List<String> configured) {
    if (configured.isEmpty) return true;
    if (current == null) return false;
    final norm = normalizeSsid(current);
    if (norm.isEmpty) return false;
    for (final ssid in configured) {
      if (normalizeSsid(ssid) == norm) return true;
    }
    return false;
  }

  Future<void> _handleConnected() async {
    // Back on (or still on) a company network — cancel any pending checkout so
    // switching between company networks never checks the employee out.
    _pendingCheckout?.cancel();
    _pendingCheckout = null;

    final prefs = await SharedPreferences.getInstance();

    // If no session is running, start one and check-in.
    if (!prefs.containsKey(_kSessionStart)) {
      await prefs.setInt(_kSessionStart, DateTime.now().millisecondsSinceEpoch);
      await AttendanceRepository.autoCheckIn(_employeeId!);
    }
  }

  Future<void> _handleDisconnected() async {
    final prefs = await SharedPreferences.getInstance();

    // No session running → nothing to check out.
    if (!prefs.containsKey(_kSessionStart)) return;

    // Already waiting out the grace period → don't reset it (avoids indefinite
    // delay under connectivity flapping, and coalesces rapid callbacks).
    if (_pendingCheckout != null) return;

    _pendingCheckout = Timer(_kDisconnectGrace, () {
      _synchronized(_finalizeCheckout);
    });
  }

  /// Runs after the grace period: only checks out if the device is STILL not on
  /// a company network (i.e. it was a real departure, not a network switch).
  Future<void> _finalizeCheckout() async {
    _pendingCheckout = null;
    if (_employeeId == null) return;

    final results = await Connectivity().checkConnectivity();
    final onWifi = results.contains(ConnectivityResult.wifi);
    if (onWifi && await _isOnCompanyNetwork()) {
      // Reconnected to a company network during the grace window — stay in.
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final sessionStart = prefs.getInt(_kSessionStart);
    if (sessionStart == null) return; // Session already closed elsewhere.

    final minutes = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(sessionStart))
        .inMinutes;

    await prefs.remove(_kSessionStart);
    await AttendanceRepository.autoCheckOut(
      _employeeId!,
      accumulatedMinutes: minutes < 0 ? 0 : minutes,
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

  /// Strip surrounding quotes that some platforms add to the SSID, and trim.
  /// Applied identically to every configured SSID and the detected SSID.
  static String normalizeSsid(String s) => s.replaceAll('"', '').trim();
}

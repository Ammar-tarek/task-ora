// lib/core/repositories/reset_app_repository.dart
// Resets all application data, keeping only the calling Super Admin.
// The destructive work runs server-side in the `admin-reset-app` Edge Function,
// which re-verifies the caller is a super admin from their JWT (never a
// client-supplied flag) and holds the service-role key only in its runtime.

import '../services/privileged_ops.dart';

class ResetAppRepository {
  /// Triggers the server-side reset. [superAdminId] is accepted for call-site
  /// compatibility but ignored — the function preserves the authenticated
  /// caller, so the client cannot redirect whose account survives.
  /// Returns null on success, or an error string.
  static Future<String?> resetApplicationData({
    required String superAdminId,
  }) async {
    try {
      await PrivilegedOps.resetApp();
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}

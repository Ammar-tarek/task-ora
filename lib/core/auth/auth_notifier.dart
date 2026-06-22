// lib/core/auth/auth_notifier.dart
// Central auth state — listens to Supabase auth stream, fetches profile

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile_model.dart';
import '../services/supabase_service.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

/// Returned by signUp() when Supabase requires email verification
/// before the session is active.
const String kEmailConfirmationRequired = 'EMAIL_CONFIRMATION_REQUIRED';

class AuthNotifier extends ChangeNotifier {
  AuthStatus _status = AuthStatus.loading;
  ProfileModel? _profile;
  String? _error;

  AuthStatus get status    => _status;
  ProfileModel? get profile => _profile;
  String? get error        => _error;
  bool get isLoggedIn      => _status == AuthStatus.authenticated;

  AuthNotifier() {
    SupabaseService.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      // signedIn  → normal login
      // tokenRefreshed / userUpdated → keep session alive
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.tokenRefreshed ||
          event == AuthChangeEvent.userUpdated) {
        _fetchProfile();
      } else if (event == AuthChangeEvent.signedOut) {
        _profile = null;
        _status  = AuthStatus.unauthenticated;
        _error   = null;
        notifyListeners();
      }
    });

    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = SupabaseService.auth.currentSession;
    if (session != null) {
      await _fetchProfile();
    } else {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  /// Fetch the profile row. Retries up to 4 times with a 1s delay to handle
  /// the race condition between Supabase Auth emitting signedIn/signedUp and
  /// the `handle_new_user` DB trigger inserting the profiles row.
  Future<void> _fetchProfile() async {
    const maxAttempts = 4;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final userId = SupabaseService.auth.currentUser!.id;
        final data = await SupabaseService.client
            .from('profiles')
            .select()
            .eq('id', userId)
            .single();

        _profile = ProfileModel.fromMap(data);
        _status  = AuthStatus.authenticated;
        _error   = null;

        // Update last_login_at (fire-and-forget)
        SupabaseService.client.from('profiles').update({
          'last_login_at': DateTime.now().toIso8601String(),
        }).eq('id', userId).then((_) {}, onError: (_) {});

        notifyListeners();
        return; // ← success, stop retrying
      } catch (_) {
        if (attempt < maxAttempts - 1) {
          // Profile row not created yet (trigger race condition) — wait and retry
          await Future.delayed(const Duration(milliseconds: 900));
          continue;
        }
        // All retries exhausted
        _error  = 'Could not load your profile. Please contact your administrator.';
        _status = AuthStatus.unauthenticated;
      }
    }
    notifyListeners();
  }

  // ── Public methods ─────────────────────────────────────────────────────────

  /// Sign in with email + password.
  /// Returns null on success, or an error string.
  Future<String?> signIn(String email, String password) async {
    try {
      _error = null;
      await SupabaseService.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      // onAuthStateChange fires → _fetchProfile → notifyListeners → router redirects
      return null;
    } on AuthException catch (e) {
      return _friendlyAuthError(e.message);
    } catch (_) {
      return 'Unexpected error. Please try again.';
    }
  }

  /// Register a new user.
  ///
  /// Role logic (checked against DB, not client-side only):
  ///   - profiles table empty → first user → role = 'admin'
  ///   - profiles table has rows → role = 'employee'
  ///
  /// Email uniqueness is enforced by Supabase Auth (auth.users UNIQUE constraint).
  ///
  /// Returns:
  ///   - null                         → success + session active → router will redirect
  ///   - kEmailConfirmationRequired   → signup OK but email must be verified first
  ///   - any other string             → error message to show in the UI
  Future<String?> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      // Determine role — first ever user becomes admin
      final existing = await SupabaseService.client
          .from('profiles')
          .select('id')
          .limit(1);
      final isFirstUser = (existing as List).isEmpty;
      final role = isFirstUser ? 'admin' : 'employee';

      final response = await SupabaseService.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          'role':      role,
        },
      );

      // If Supabase immediately returns a session (email confirmation OFF),
      // manually kick off profile fetch so the redirect fires faster.
      if (response.session != null) {
        await _fetchProfile();
      } else {
        // Email confirmation is ON — user must verify before they can log in.
        return kEmailConfirmationRequired;
      }

      return null; // success
    } on AuthException catch (e) {
      return _friendlySignUpError(e.message);
    } catch (_) {
      return 'Unexpected error. Please try again.';
    }
  }

  /// Sign out and clear state.
  Future<void> signOut() async {
    try {
      await SupabaseService.auth.signOut();
    } catch (_) {
      _profile = null;
      _status  = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  /// Send a password-reset email.
  /// Returns null on success, or an error string.
  Future<String?> sendPasswordReset(String email) async {
    try {
      await SupabaseService.auth.resetPasswordForEmail(email.trim());
      return null;
    } on AuthException catch (e) {
      return _friendlyAuthError(e.message);
    } catch (_) {
      return 'Could not send reset email. Check your connection.';
    }
  }

  // ── Error helpers ──────────────────────────────────────────────────────────

  String _friendlySignUpError(String raw) {
    final r = raw.toLowerCase();
    // Duplicate email — most common sign-up error
    if (r.contains('already registered') ||
        r.contains('already exists') ||
        r.contains('user already registered') ||
        r.contains('email address is already')) {
      return 'An account with this email already exists. Please sign in instead.';
    }
    if (r.contains('password')) {
      return 'Password must be at least 6 characters.';
    }
    if (r.contains('invalid email') || r.contains('unable to validate email')) {
      return 'Please enter a valid email address.';
    }
    if (r.contains('signup disabled') || r.contains('signups not allowed')) {
      return 'New registrations are currently disabled. Contact your administrator.';
    }
    return raw;
  }

  String _friendlyAuthError(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('invalid login') || r.contains('invalid credentials')) {
      return 'Incorrect email or password.';
    }
    if (r.contains('email not confirmed')) {
      return 'Please verify your email before signing in.';
    }
    if (r.contains('too many requests')) {
      return 'Too many attempts. Please wait a moment.';
    }
    return raw;
  }
}

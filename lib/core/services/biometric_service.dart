// lib/core/services/biometric_service.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keyPrefix = 'biometric_enabled_';

  // Biometric-gated login credentials. Stored ONLY when the user enables
  // biometric login (with the password they just typed), inside the platform
  // secure store (Android Keystore / iOS Keychain). Used to re-authenticate
  // after a logout when the user taps "Sign in with fingerprint".
  static const String _kCredEmail = 'bio_cred_email';
  static const String _kCredPassword = 'bio_cred_password';

  /// Persist login credentials for biometric re-login (encrypted at rest).
  Future<void> saveCredentials(String email, String password) async {
    try {
      await _storage.write(key: _kCredEmail, value: email);
      await _storage.write(key: _kCredPassword, value: password);
    } catch (e) {
      debugPrint('Error saving biometric credentials: $e');
    }
  }

  /// Read stored biometric-login credentials, or null if none.
  Future<({String email, String password})?> readCredentials() async {
    try {
      final email = await _storage.read(key: _kCredEmail);
      final password = await _storage.read(key: _kCredPassword);
      if (email != null && email.isNotEmpty &&
          password != null && password.isNotEmpty) {
        return (email: email, password: password);
      }
    } catch (_) {}
    return null;
  }

  /// True when biometric-login credentials are stored on this device.
  Future<bool> hasCredentials() async => (await readCredentials()) != null;

  /// Wipe stored biometric-login credentials (called when biometric is disabled).
  Future<void> clearCredentials() async {
    try {
      await _storage.delete(key: _kCredEmail);
      await _storage.delete(key: _kCredPassword);
    } catch (_) {}
  }

  /// Checks if hardware supports biometrics and device allows biometric checks.
  Future<bool> isHardwareSupported() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Checks if biometric authentication can be checked.
  Future<bool> canCheckBiometrics() async {
    if (kIsWeb) return false;
    try {
      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if biometrics hardware is available AND at least one biometric is enrolled.
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      final isSupported = await isHardwareSupported();
      final canCheck = await canCheckBiometrics();
      if (!isSupported || !canCheck) return false;
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Returns available biometric types (e.g. fingerprint, face, iris).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (kIsWeb) return [];
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Prompts user for biometric authentication with device dialog.
  /// Never throws an exception.
  Future<bool> authenticate({required String localizedReason}) async {
    if (kIsWeb) return false;
    try {
      final available = await isAvailable();
      if (!available) return false;

      return await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          useErrorDialogs: true,
          biometricOnly: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('Biometric authentication error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Biometric unexpected authentication error: $e');
      return false;
    }
  }

  /// Checks if biometric login is enabled for [userId] in secure storage.
  Future<bool> isBiometricEnabled(String userId) async {
    if (userId.isEmpty) return false;
    try {
      final value = await _storage.read(key: '$_keyPrefix$userId');
      return value == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Sets biometric login preference for [userId] in secure storage.
  Future<void> setBiometricEnabled(String userId, bool enabled) async {
    if (userId.isEmpty) return;
    try {
      if (enabled) {
        await _storage.write(key: '$_keyPrefix$userId', value: 'true');
      } else {
        await _storage.delete(key: '$_keyPrefix$userId');
      }
    } catch (e) {
      debugPrint('Error writing biometric preference: $e');
    }
  }

  /// Clears biometric login preference for [userId].
  Future<void> clearBiometricPreference(String userId) async {
    if (userId.isEmpty) return;
    try {
      await _storage.delete(key: '$_keyPrefix$userId');
    } catch (_) {}
  }
}

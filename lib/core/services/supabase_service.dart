
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static const _url =
      'https://csncaoqvercxvbfbzbfa.supabase.co';

  static const _anonKey =
      'sb_publishable_TIegHIG4ayFLStiAautDSA_Q8wJTVQ0';

  // No service-role key lives in the client.
  // Privileged operations go through Edge Functions / RPCs.

  /// Call once in main() before runApp
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _url,
      publishableKey: _anonKey,
    );
  }

  /// The one client: respects RLS.
  static SupabaseClient get client =>
      Supabase.instance.client;

  static GoTrueClient get auth => client.auth;
  static User? get currentUser => auth.currentUser;
  static Session? get currentSession => auth.currentSession;
}

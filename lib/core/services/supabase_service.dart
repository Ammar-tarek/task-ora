// lib/core/services/supabase_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static const _url = 'https://csncaoqvercxvbfbzbfa.supabase.co';
  static const _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNzbmNhb3F2ZXJjeHZiZmJ6YmZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgzNTQ0MjgsImV4cCI6MjA5MzkzMDQyOH0.CsyuCGI5ytf8VPBt0ThAu3Ja3m244Aos56nzPA4rh9M';

  // Paste your service_role key from Supabase → Settings → API
  static const _serviceRoleKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNzbmNhb3F2ZXJjeHZiZmJ6YmZhIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODM1NDQyOCwiZXhwIjoyMDkzOTMwNDI4fQ.l_GhKyc_WyT-fpnXA1218OHYsh9kusgcTb5zStfVouE';

  /// Call once in main() before runApp
  static Future<void> initialize() async {
    await Supabase.initialize(url: _url, publishableKey: _anonKey);
  }

  /// Regular client (anon key, respects RLS)
  static SupabaseClient get client => Supabase.instance.client;

  /// Admin client (service role key, bypasses RLS, can create auth users)
  static final SupabaseClient adminClient = SupabaseClient(
    _url,
    _serviceRoleKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  static GoTrueClient get auth => client.auth;
  static User? get currentUser => auth.currentUser;
  static Session? get currentSession => auth.currentSession;
}

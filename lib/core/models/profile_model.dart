// lib/core/models/profile_model.dart
// Matches public.profiles table exactly

class ProfileModel {
  final String id;
  final String role; // 'admin' | 'manager' | 'employee' | 'client'
  final String fullName;
  final String? phone;
  final String? avatarUrl;
  final String status; // 'active' | 'inactive' | 'suspended'
  final String? teamId;
  final String? lastLoginAt;
  final String timezone;
  final String preferredLanguage;
  final String createdAt;

  /// Verified global-admin flag, sourced from the DB column
  /// `profiles.is_super_admin` (added by the department migration). Super Admin
  /// is modeled as an admin with this flag set — never as a free-text role
  /// string — so the tier cannot be spoofed via the `role` enum. Defaults to
  /// false, including before the column exists, so behavior is unchanged until
  /// the migration lands.
  final bool isSuperAdminFlag;

  const ProfileModel({
    required this.id,
    required this.role,
    required this.fullName,
    this.phone,
    this.avatarUrl,
    required this.status,
    this.teamId,
    this.lastLoginAt,
    required this.timezone,
    required this.preferredLanguage,
    required this.createdAt,
    this.isSuperAdminFlag = false,
  });

  factory ProfileModel.fromMap(Map<String, dynamic> m) => ProfileModel(
    id: m['id'] as String,
    role: m['role'] as String? ?? 'employee',
    fullName: m['full_name'] as String? ?? '',
    phone: m['phone'] as String?,
    avatarUrl: m['avatar_url'] as String?,
    status: m['status'] as String? ?? 'active',
    teamId: m['team_id'] as String?,
    lastLoginAt: m['last_login_at'] as String?,
    timezone: m['timezone'] as String? ?? 'UTC',
    preferredLanguage: m['preferred_language'] as String? ?? 'en',
    createdAt: m['created_at'] as String? ?? '',
    isSuperAdminFlag: m['is_super_admin'] as bool? ?? false,
  );

  /// True when the user holds the verified global Super Admin flag. The legacy
  /// `role == 'super_admin'` string is still honored for forward/backward
  /// compatibility, but the DB enum has no such value, so the flag is the real
  /// source of truth.
  bool get isSuperAdmin => isSuperAdminFlag || role == 'super_admin';
  bool get isAdmin => role == 'admin' || isSuperAdmin;
  bool get isManager => role == 'manager';
  bool get isEmployee => role == 'employee';
  bool get isClient => role == 'client';
  bool get isAdminOrManager => isAdmin || isManager;
  bool get isActive => status == 'active';

  /// First name for greeting
  String get firstName => fullName.split(' ').first;

  /// Initials for avatar
  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return fullName.substring(0, fullName.length >= 2 ? 2 : 1).toUpperCase();
  }
}

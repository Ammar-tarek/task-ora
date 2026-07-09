// lib/core/models/profile_model.dart
// Matches public.profiles table exactly

class ProfileModel {
  final String id;
  final String role;        // 'admin' | 'manager' | 'employee' | 'client'
  final String fullName;
  final String? phone;
  final String? avatarUrl;
  final String status;      // 'active' | 'inactive' | 'suspended'
  final String? teamId;
  final String? lastLoginAt;
  final String timezone;
  final String preferredLanguage;
  final String createdAt;

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
      );

  bool get isAdmin          => role == 'admin';
  bool get isManager        => role == 'manager';
  bool get isEmployee       => role == 'employee';
  bool get isClient         => role == 'client';
  bool get isAdminOrManager => role == 'admin' || role == 'manager';
  bool get isActive         => status == 'active';

  /// First name for greeting
  String get firstName => fullName.split(' ').first;

  /// Initials for avatar
  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return fullName.substring(0, fullName.length >= 2 ? 2 : 1).toUpperCase();
  }
}

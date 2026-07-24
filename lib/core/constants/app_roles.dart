// lib/core/constants/app_roles.dart
// Single source of truth for valid role strings.
// Values MUST match the `user_role` PostgreSQL enum in Supabase exactly.
// Required SQL to keep DB in sync:
//   ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'manager';
//   ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'super_admin';

class AppRoles {
  static const String superAdmin = 'super_admin';
  static const String admin = 'admin';
  static const String manager = 'manager';
  static const String employee = 'employee';
  static const String client = 'client';

  /// All roles in the DB enum.
  static const List<String> all = [superAdmin, admin, manager, employee, client];

  /// Roles that can log into the staff portal.
  static const List<String> staff = [superAdmin, admin, manager, employee];

  /// Roles that can hold team membership.
  static const List<String> teamMembers = [manager, employee];
}

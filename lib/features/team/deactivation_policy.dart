// lib/features/team/deactivation_policy.dart
// Pure, testable client-side rules for the Team deactivate/reactivate action.
// These MIRROR the server guards in admin-user-ops `set_active`, but the server
// remains the authoritative security boundary — this only decides what the UI
// offers so unauthorized users never see an action they can't perform.

import '../../core/models/profile_model.dart';

class DeactivationPolicy {
  DeactivationPolicy._();

  /// Whether [viewer] may manage active status at all. Only a global admin
  /// (admin or super admin) can deactivate/reactivate from the Team screen.
  static bool canManage(ProfileModel? viewer) => viewer?.isAdmin == true;

  /// Whether [viewer] may change the active status of the given target.
  /// Rules (all enforced again server-side):
  ///   • viewer must be able to manage,
  ///   • a user can never change their OWN status (no self-deactivation),
  ///   • only a super admin may change another admin's / super admin's status.
  static bool canChangeStatus({
    required ProfileModel? viewer,
    required String targetId,
    required String targetRole,
    required bool targetIsSuperAdmin,
  }) {
    if (!canManage(viewer)) return false;
    if (viewer!.id == targetId) return false; // self-deactivation blocked
    final targetIsAdmin = targetRole == 'admin' || targetIsSuperAdmin;
    if (targetIsAdmin && !viewer.isSuperAdmin) return false;
    return true;
  }
}

// lib/core/constants/departments.dart
// Canonical catalogue of the operational department workspaces.
//
// Product decision (2026-10): departments are represented by `teams` rows
// (see DEPARTMENT_MIGRATION_ASSESSMENT.md §7.1). This enum is the fixed set of
// five department *workspaces* the product exposes. The company-wide Expenses
// workspace is intentionally NOT a department — it is admin-only and handled
// separately by DepartmentService.canAccessExpenses.

import '../models/team_model.dart';

/// The five operational department workspaces.
enum Department { marketing, montage, production, sales, studio }

extension DepartmentX on Department {
  /// Stable, non-localized key used for storage, routing and comparison.
  String get key {
    switch (this) {
      case Department.marketing:
        return 'marketing';
      case Department.montage:
        return 'montage';
      case Department.production:
        return 'production';
      case Department.sales:
        return 'sales';
      case Department.studio:
        return 'studio';
    }
  }

  /// English canonical label. UI layers localize via S.t(label).
  String get label {
    switch (this) {
      case Department.marketing:
        return 'Marketing';
      case Department.montage:
        return 'Montage';
      case Department.production:
        return 'Production';
      case Department.sales:
        return 'Sales';
      case Department.studio:
        return 'Studio';
    }
  }
}

/// Lookup / resolution helpers for the department catalogue.
class Departments {
  Departments._();

  /// Every department workspace, in display order.
  static const List<Department> all = Department.values;

  /// Maps a normalized free-text label (a team's `department` or `name`) onto a
  /// canonical [Department]. Includes legacy aliases so existing data resolves
  /// correctly before the team-rename migration runs (e.g. "Video Production").
  static const Map<String, Department> _aliases = {
    'marketing': Department.marketing,
    'montage': Department.montage,
    'production': Department.production,
    'video production': Department.production,
    'sales': Department.sales,
    'studio': Department.studio,
  };

  /// Resolve a department from free text. Returns null for unknown values
  /// (e.g. the internal "Admins" team, which is not a department workspace).
  static Department? fromLabel(String? text) {
    if (text == null) return null;
    final norm = text.trim().toLowerCase();
    if (norm.isEmpty) return null;
    return _aliases[norm];
  }

  /// Resolve a department from a team: prefer the explicit `department` field,
  /// then fall back to the team `name`.
  static Department? fromTeam(TeamModel team) =>
      fromLabel(team.department) ?? fromLabel(team.name);
}

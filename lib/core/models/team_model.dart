// lib/core/models/team_model.dart
// Matches public.teams table exactly.

class TeamModel {
  final String id;
  final String name;
  final String? description;
  final String? department;
  final String? teamLeadId;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  const TeamModel({
    required this.id,
    required this.name,
    this.description,
    this.department,
    this.teamLeadId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TeamModel.fromMap(Map<String, dynamic> m) => TeamModel(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        description: m['description'] as String?,
        department: m['department'] as String?,
        teamLeadId: m['team_lead_id'] as String?,
        isActive: m['is_active'] as bool? ?? true,
        createdAt: m['created_at'] as String? ?? '',
        updatedAt: m['updated_at'] as String? ?? '',
      );

  TeamModel copyWith({
    String? name,
    String? description,
    String? department,
    String? teamLeadId,
    bool? isActive,
  }) =>
      TeamModel(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        department: department ?? this.department,
        teamLeadId: teamLeadId ?? this.teamLeadId,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

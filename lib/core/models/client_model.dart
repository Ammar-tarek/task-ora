// lib/core/models/client_model.dart
// Matches public.client_profiles table exactly.

class ClientModel {
  final String id;
  final String companyName;
  final String contactPerson;
  final String email;
  final String? phone;
  final String? whatsappNumber;
  final String? address;
  final String? notes;
  final String? contractStartDate;
  final String? contractEndDate;
  final bool isArchived;
  final String createdAt;

  const ClientModel({
    required this.id,
    required this.companyName,
    required this.contactPerson,
    required this.email,
    this.phone,
    this.whatsappNumber,
    this.address,
    this.notes,
    this.contractStartDate,
    this.contractEndDate,
    this.isArchived = false,
    required this.createdAt,
  });

  factory ClientModel.fromMap(Map<String, dynamic> m) => ClientModel(
        id:                m['id'] as String,
        companyName:       m['company_name'] as String? ?? 'Unknown',
        contactPerson:     m['contact_person'] as String? ?? '',
        email:             m['email'] as String? ?? '',
        phone:             m['phone'] as String?,
        whatsappNumber:    m['whatsapp_number'] as String?,
        address:           m['address'] as String?,
        notes:             m['notes'] as String?,
        contractStartDate: m['contract_start_date'] as String?,
        contractEndDate:   m['contract_end_date'] as String?,
        isArchived:        m['is_archived'] as bool? ?? false,
        createdAt:         m['created_at'] as String? ?? '',
      );

  String get initials {
    final parts = companyName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return companyName.substring(0, companyName.length >= 2 ? 2 : 1).toUpperCase();
  }
}

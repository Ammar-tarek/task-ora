// lib/core/models/sales_sheet_entry.dart
// One row of the Sales Sheet (a Sales-department pipeline table). All columns
// are free text, mirroring the source spreadsheet. `link` holds an optional
// URL (facebook / instagram / etc.) that the UI renders as a tappable link.

class SalesSheetEntry {
  final String id;
  final double sortOrder;
  final String client;
  final String link;
  final String ownerName;
  final String ownerNumber;
  final String status;
  final String probability;
  final String estValue;
  final String lastContact;
  final String expectedClose;

  const SalesSheetEntry({
    required this.id,
    this.sortOrder = 0,
    this.client = '',
    this.link = '',
    this.ownerName = '',
    this.ownerNumber = '',
    this.status = '',
    this.probability = '',
    this.estValue = '',
    this.lastContact = '',
    this.expectedClose = '',
  });

  factory SalesSheetEntry.fromMap(Map<String, dynamic> m) => SalesSheetEntry(
        id: m['id'] as String? ?? '',
        sortOrder: (m['sort_order'] as num?)?.toDouble() ?? 0,
        client: m['client'] as String? ?? '',
        link: m['link'] as String? ?? '',
        ownerName: m['owner_name'] as String? ?? '',
        ownerNumber: m['owner_number'] as String? ?? '',
        status: m['status'] as String? ?? '',
        probability: m['probability'] as String? ?? '',
        estValue: m['est_value'] as String? ?? '',
        lastContact: m['last_contact'] as String? ?? '',
        expectedClose: m['expected_close'] as String? ?? '',
      );

  /// The ordered, user-facing columns: (db column key, display header).
  static const List<({String key, String header})> columns = [
    (key: 'client', header: 'Client'),
    (key: 'link', header: 'Link'),
    (key: 'owner_name', header: 'Owner Name'),
    (key: 'owner_number', header: 'Owner Number'),
    (key: 'status', header: 'Status'),
    (key: 'probability', header: 'Probability'),
    (key: 'est_value', header: 'Est. Value'),
    (key: 'last_contact', header: 'Last Contact'),
    (key: 'expected_close', header: 'Expected Close'),
  ];

  String valueOf(String key) {
    switch (key) {
      case 'client':
        return client;
      case 'link':
        return link;
      case 'owner_name':
        return ownerName;
      case 'owner_number':
        return ownerNumber;
      case 'status':
        return status;
      case 'probability':
        return probability;
      case 'est_value':
        return estValue;
      case 'last_contact':
        return lastContact;
      case 'expected_close':
        return expectedClose;
      default:
        return '';
    }
  }
}

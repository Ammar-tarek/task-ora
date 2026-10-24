// test/crm_entry_revenue_mapping_test.dart
// The revenue row maps correctly from the DB: Date uses the editable entry_date
// (not created_at), Client/Payer uses the free-text payer_name with a legacy
// client fallback, and Notes loads from description. This verifies the LOAD/
// DISPLAY side of date/payer/notes persistence (the write side goes through
// Supabase RPCs/inserts and is exercised by the DB tests).

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/repositories/finance_repository.dart';

Map<String, dynamic> _row({
  String? entryDate,
  String? createdAt = '2026-01-05T09:30:00Z',
  String? payerName,
  String? clientCompany,
  String? clientId,
  String? description,
  String? notes,
}) => {
  'id': 'e1',
  'client_id': clientId,
  if (clientCompany != null) 'client': {'company_name': clientCompany},
  'team_id': 't1',
  'title': 'Sponsorship',
  'description': description,
  'notes': notes,
  'amount': 1000,
  'paid_amount': 400,
  'status': 'partial',
  'source_type': 'manual',
  'entry_date': entryDate,
  'payer_name': payerName,
  'created_at': createdAt,
  'currency': 'EGP',
};

void main() {
  group('CrmEntry revenue mapping', () {
    test('Date uses the editable entry_date, not created_at', () {
      final e = CrmEntry.fromMap(_row(entryDate: '2026-03-15'));
      expect(e.entryDate, '2026-03-15');
      expect(e.displayDate, '2026-03-15');
    });

    test('Date falls back to created_at for a legacy row without entry_date', () {
      final e = CrmEntry.fromMap(_row(entryDate: null));
      expect(e.displayDate, '2026-01-05');
    });

    test('Payer uses free-text payer_name when set', () {
      final e = CrmEntry.fromMap(
        _row(payerName: 'Ahmed Fathy', clientId: 'c1', clientCompany: 'Acme'),
      );
      expect(e.payerDisplay, 'Ahmed Fathy');
    });

    test('Payer falls back to the linked client name (legacy rows)', () {
      final e = CrmEntry.fromMap(
        _row(payerName: null, clientId: 'c1', clientCompany: 'Acme'),
      );
      expect(e.payerDisplay, 'Acme');
    });

    test('Payer is a dash for an internal row with no payer and no client', () {
      final e = CrmEntry.fromMap(_row(payerName: null, clientId: null));
      expect(e.payerDisplay, '—');
    });

    test('Notes load from the dedicated notes column', () {
      final e = CrmEntry.fromMap(_row(notes: 'Q1 retainer'));
      expect(e.notes, 'Q1 retainer');
      expect(e.notesDisplay, 'Q1 retainer');
    });

    test('notesDisplay is empty (not null) when notes absent', () {
      final e = CrmEntry.fromMap(_row(notes: null));
      expect(e.notes, isNull);
      expect(e.notesDisplay, '');
    });

    test('Notes and Description are independent, never overwrite each other', () {
      final e = CrmEntry.fromMap(
        _row(description: 'internal desc', notes: 'client-facing note'),
      );
      expect(e.description, 'internal desc');
      expect(e.notes, 'client-facing note');
      // notesDisplay reflects notes only, never description.
      expect(e.notesDisplay, 'client-facing note');

      // A row with description but no notes must NOT surface description as notes.
      final e2 = CrmEntry.fromMap(_row(description: 'only desc', notes: null));
      expect(e2.description, 'only desc');
      expect(e2.notesDisplay, '');
    });
  });
}

// test/client_search_test.dart
// Phase A — client name search (case-insensitive, partial, order-preserving).

import 'package:flutter_test/flutter_test.dart';
import 'package:task_ora/core/models/client_model.dart';
import 'package:task_ora/features/clients/client_search.dart';

ClientModel _c(String id, String name) =>
    ClientModel(id: id, companyName: name, contactPerson: '', email: '', createdAt: '');

void main() {
  final clients = [
    _c('1', 'Acme Corp'),
    _c('2', 'Globex'),
    _c('3', 'Acme Studios'),
    _c('4', 'Initech'),
  ];

  group('ClientSearch.filter', () {
    test('full name match returns that client', () {
      final r = ClientSearch.filter(clients, 'Globex');
      expect(r.map((c) => c.id), ['2']);
    });

    test('partial name match returns all matching clients, order preserved', () {
      final r = ClientSearch.filter(clients, 'Acme');
      expect(r.map((c) => c.id), ['1', '3']);
    });

    test('match is case-insensitive', () {
      expect(ClientSearch.filter(clients, 'acme').map((c) => c.id), ['1', '3']);
      expect(ClientSearch.filter(clients, 'GLOBEX').map((c) => c.id), ['2']);
    });

    test('mid-word substring matches', () {
      expect(ClientSearch.filter(clients, 'tech').map((c) => c.id), ['4']);
    });

    test('empty / whitespace query returns the list unchanged', () {
      expect(ClientSearch.filter(clients, ''), same(clients));
      expect(ClientSearch.filter(clients, '   ').map((c) => c.id),
          ['1', '2', '3', '4']);
    });

    test('no match returns empty list (drives the empty state)', () {
      expect(ClientSearch.filter(clients, 'zzz'), isEmpty);
    });

    test('query is trimmed before matching', () {
      expect(ClientSearch.filter(clients, '  Globex  ').map((c) => c.id), ['2']);
    });
  });

  group('ClientSearch.matches', () {
    test('empty query matches everything', () {
      expect(ClientSearch.matches(_c('x', 'Anything'), ''), isTrue);
    });
    test('non-matching name is false', () {
      expect(ClientSearch.matches(_c('x', 'Acme'), 'globex'), isFalse);
    });
  });
}

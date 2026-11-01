// lib/features/clients/client_search.dart
// Pure, UI-free client name search so the matching logic is unit-testable
// without Flutter. The list passed in is already department/RLS-scoped by the
// repository; this only narrows what the viewer already sees — it never widens
// visibility.

import '../../core/models/client_model.dart';

class ClientSearch {
  ClientSearch._();

  /// Case-insensitive partial match on the client's name (company_name).
  /// A single client matches when [query] (trimmed) is empty, or is a substring
  /// of its name. Empty query => matches everything.
  static bool matches(ClientModel client, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return client.companyName.toLowerCase().contains(q);
  }

  /// Keep only the clients whose name matches [query], preserving input order.
  /// An empty/whitespace query returns the list unchanged.
  static List<ClientModel> filter(List<ClientModel> clients, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return clients;
    return clients
        .where((c) => c.companyName.toLowerCase().contains(q))
        .toList();
  }
}

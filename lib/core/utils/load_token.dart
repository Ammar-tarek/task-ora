// lib/core/utils/load_token.dart
// Tiny latest-wins guard for async loads. A screen that reloads on department
// (workspace) switch calls [begin] at the start of each load, captures the
// returned token, and after its awaits discards the result when [isStale] —
// so a response started under department A can never overwrite department B.

class LoadToken {
  int _latest = 0;

  /// Start a new load; returns its token. Any earlier token is now stale.
  int begin() => ++_latest;

  /// True when [token] is not the most recent load (its result must be dropped).
  bool isStale(int token) => token != _latest;
}

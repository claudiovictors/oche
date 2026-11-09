import 'dart:convert';

import 'session_store.dart';

/// A [SessionStore] that keeps sessions in the memory of the process.
///
/// It is meant for development and tests: everything is lost when the server
/// restarts, and sessions are not shared between processes. Use another store
/// in production.
///
/// Data is serialized to JSON when saved, so it behaves like a real store:
/// values that are not JSON-encodable fail early.
class MemoryStore implements SessionStore {
  final Map<String, _Entry> _entries = <String, _Entry>{};
  int _writes = 0;

  /// How many sessions are currently held, including expired ones that were
  /// not collected yet.
  int get length => _entries.length;

  @override
  Future<Map<String, Object?>?> get(String id) async {
    final entry = _entries[id];
    if (entry == null) return null;

    if (entry.isExpired) {
      _entries.remove(id);
      return null;
    }
    return Map<String, Object?>.from(jsonDecode(entry.json) as Map);
  }

  @override
  Future<void> set(String id, Map<String, Object?> data, Duration ttl) async {
    _entries[id] = _Entry(jsonEncode(data), DateTime.now().add(ttl));

    // Collect expired sessions now and then, without timers that would keep
    // the process alive.
    if (++_writes % 100 == 0) {
      _entries.removeWhere((_, entry) => entry.isExpired);
    }
  }

  @override
  Future<void> destroy(String id) async {
    _entries.remove(id);
  }
}

class _Entry {
  _Entry(this.json, this.expiresAt);

  final String json;
  final DateTime expiresAt;

  bool get isExpired => expiresAt.isBefore(DateTime.now());
}
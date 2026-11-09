/// Where session data is kept between requests.
///
/// Implement this interface to keep sessions in a database, in Redis, in
/// files, and so on. [MemoryStore] is the built-in implementation.
///
/// ```dart
/// class RedisStore implements SessionStore {
///   @override
///   Future<Map<String, Object?>?> get(String id) async { ... }
///   // ...
/// }
///
/// app.use(Oche.session(secret: '...', store: RedisStore()));
/// ```
abstract interface class SessionStore {
  /// Returns the data of the session [id], or `null` when it does not exist
  /// or has expired.
  Future<Map<String, Object?>?> get(String id);

  /// Saves [data] as the session [id], to be kept for [ttl].
  ///
  /// Saving an existing id replaces its data and renews its expiry.
  Future<void> set(String id, Map<String, Object?> data, Duration ttl);

  /// Deletes the session [id]. Deleting an unknown id is not an error.
  Future<void> destroy(String id);
}
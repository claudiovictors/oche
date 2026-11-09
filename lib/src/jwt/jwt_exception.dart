/// The reason why a token was rejected by [Jwt.verify].
enum JwtFailure {
  /// The token is not a well-formed JWT: wrong number of parts, invalid
  /// base64url or invalid JSON.
  malformed,

  /// The `alg` header is missing or is not in the list of accepted
  /// algorithms.
  unsupportedAlgorithm,

  /// The signature does not match: the token was altered or it was signed
  /// with another secret.
  invalidSignature,

  /// The `exp` claim is in the past.
  expired,

  /// The `nbf` claim is in the future.
  notYetValid,

  /// A claim has an unexpected value (`iss`, `aud`) or an invalid type.
  invalidClaim,
}

/// Thrown when a token cannot be accepted.
///
/// Check [failure] to know why:
///
/// ```dart
/// try {
///   Jwt.verify(token, secret: secret);
/// } on JwtException catch (e) {
///   if (e.failure == JwtFailure.expired) { ... }
/// }
/// ```
class JwtException implements Exception {
  /// Creates an exception for the given [failure].
  const JwtException(this.failure, this.message);

  /// Why the token was rejected.
  final JwtFailure failure;

  /// A human-readable description.
  final String message;

  @override
  String toString() => 'JwtException(${failure.name}): $message';
}
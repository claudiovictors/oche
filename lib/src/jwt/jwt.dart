import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'jwt_exception.dart';

/// Creates and verifies JSON Web Tokens (JWT) signed with HMAC.
///
/// Supported algorithms: `HS256` (default), `HS384` and `HS512`.
///
/// ```dart
/// final token = Jwt.sign(
///   {'id': 1, 'role': 'admin'},
///   secret: secret,
///   expiresIn: Duration(hours: 1),
/// );
///
/// final payload = Jwt.verify(token, secret: secret);
/// print(payload['id']); // 1
/// ```
///
/// A JWT is signed, **not encrypted**: anyone can read its payload. Never put
/// passwords or other secrets in it.
class Jwt {
  Jwt._();

  static final Map<String, Hash> _hashes = <String, Hash>{
    'HS256': sha256,
    'HS384': sha384,
    'HS512': sha512,
  };

  /// Creates a signed token with [payload] as its claims.
  ///
  /// Extra claims are added from the named options. When an option and
  /// [payload] define the same claim, the option wins:
  ///
  /// * [expiresIn] adds `exp` (expiration time).
  /// * [issuer], [subject] and [audience] add `iss`, `sub` and `aud`.
  /// * [issuedAt] adds `iat` (issue time) and is on by default.
  ///
  /// [now] replaces the current time, which is useful in tests.
  ///
  /// Throws an [ArgumentError] when [secret] is empty or [algorithm] is not
  /// supported. Use a secret with at least 32 random characters.
  static String sign(
    Map<String, Object?> payload, {
    required String secret,
    String algorithm = 'HS256',
    Duration? expiresIn,
    String? issuer,
    String? subject,
    String? audience,
    bool issuedAt = true,
    DateTime? now,
  }) {
    final hash = _hashes[algorithm];
    if (hash == null) {
      throw ArgumentError.value(
        algorithm,
        'algorithm',
        'Unsupported algorithm. Use one of: ${_hashes.keys.join(', ')}.',
      );
    }
    _checkSecret(secret);

    final issued = _seconds(now ?? DateTime.now());
    final claims = <String, Object?>{
      ...payload,
      if (issuedAt) 'iat': issued,
      if (expiresIn != null) 'exp': issued + expiresIn.inSeconds,
      if (issuer != null) 'iss': issuer,
      if (subject != null) 'sub': subject,
      if (audience != null) 'aud': audience,
    };
    final header = <String, Object?>{'alg': algorithm, 'typ': 'JWT'};

    final signingInput = '${_encodeSegment(header)}.${_encodeSegment(claims)}';
    return '$signingInput.${_signature(signingInput, secret, hash)}';
  }

  /// Checks [token] and returns its payload.
  ///
  /// The token is accepted only when:
  ///
  /// * it is well formed;
  /// * its algorithm is one of [algorithms] (default: only `HS256`). The
  ///   algorithm is never taken from the token itself, which blocks the
  ///   `alg: none` and algorithm-swap attacks;
  /// * its signature matches [secret];
  /// * it is not expired (`exp`) and is already valid (`nbf`). The
  ///   [clockTolerance] allows for small clock differences between servers;
  /// * the `iss` claim equals [issuer] and the `aud` claim contains
  ///   [audience], when those are given.
  ///
  /// [now] replaces the current time, which is useful in tests.
  ///
  /// Throws a [JwtException] when the token is rejected, and an
  /// [ArgumentError] when [secret] is empty.
  static Map<String, Object?> verify(
    String token, {
    required String secret,
    List<String> algorithms = const <String>['HS256'],
    String? issuer,
    String? audience,
    Duration clockTolerance = Duration.zero,
    DateTime? now,
  }) {
    _checkSecret(secret);

    final parts = token.split('.');
    if (parts.length != 3) {
      throw const JwtException(
        JwtFailure.malformed,
        'The token must have three parts.',
      );
    }

    final header = _decodeSegment(parts[0]);
    final algorithm = header['alg'];
    if (algorithm is! String ||
        !algorithms.contains(algorithm) ||
        !_hashes.containsKey(algorithm)) {
      throw JwtException(
        JwtFailure.unsupportedAlgorithm,
        'The algorithm "$algorithm" is not accepted.',
      );
    }

    final expected =
        _signature('${parts[0]}.${parts[1]}', secret, _hashes[algorithm]!);
    if (!_secureEquals(expected, parts[2])) {
      throw const JwtException(
        JwtFailure.invalidSignature,
        'The signature does not match.',
      );
    }

    final claims = _decodeSegment(parts[1]);
    final nowSeconds = _seconds(now ?? DateTime.now());
    final tolerance = clockTolerance.inSeconds;

    if (claims.containsKey('exp')) {
      final exp = claims['exp'];
      if (exp is! num) {
        throw const JwtException(
          JwtFailure.invalidClaim,
          'The "exp" claim must be a number.',
        );
      }
      if (nowSeconds >= exp + tolerance) {
        throw const JwtException(JwtFailure.expired, 'The token has expired.');
      }
    }

    if (claims.containsKey('nbf')) {
      final nbf = claims['nbf'];
      if (nbf is! num) {
        throw const JwtException(
          JwtFailure.invalidClaim,
          'The "nbf" claim must be a number.',
        );
      }
      if (nowSeconds < nbf - tolerance) {
        throw const JwtException(
          JwtFailure.notYetValid,
          'The token is not valid yet.',
        );
      }
    }

    if (issuer != null && claims['iss'] != issuer) {
      throw const JwtException(JwtFailure.invalidClaim, 'Unexpected issuer.');
    }

    if (audience != null) {
      final aud = claims['aud'];
      final matches = aud == audience || (aud is List && aud.contains(audience));
      if (!matches) {
        throw const JwtException(
          JwtFailure.invalidClaim,
          'Unexpected audience.',
        );
      }
    }

    return claims;
  }

  /// Reads the payload of [token] **without verifying anything**.
  ///
  /// Never trust the result for security decisions: anyone can craft a token
  /// with any content. Use [verify] for that. This is only useful to peek at
  /// a token, for example to read its expiry on the client side.
  ///
  /// Throws a [JwtException] when the token is malformed.
  static Map<String, Object?> decode(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw const JwtException(
        JwtFailure.malformed,
        'The token must have three parts.',
      );
    }
    return _decodeSegment(parts[1]);
  }

  static void _checkSecret(String secret) {
    if (secret.isEmpty) {
      throw ArgumentError.value(secret, 'secret', 'must not be empty');
    }
  }

  static int _seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

  static String _base64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static String _encodeSegment(Map<String, Object?> data) =>
      _base64(utf8.encode(jsonEncode(data)));

  static Map<String, Object?> _decodeSegment(String segment) {
    try {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segment))),
      );
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on FormatException {
      // Falls through to the error below.
    }
    throw const JwtException(
      JwtFailure.malformed,
      'The token is not valid base64url-encoded JSON.',
    );
  }

  static String _signature(String input, String secret, Hash hash) {
    final mac = Hmac(hash, utf8.encode(secret)).convert(utf8.encode(input));
    return _base64(mac.bytes);
  }

  /// Compares two strings in time that does not depend on where they differ.
  static bool _secureEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
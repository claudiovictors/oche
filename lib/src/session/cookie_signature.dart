import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Signs [value] with HMAC-SHA256 using [secret].
///
/// The result has the form `value.signature`, where the signature is
/// base64url without padding. Signed values can be stored in cookies: the
/// client can read them, but cannot change them without [unsignCookie]
/// noticing.
String signCookie(String value, String secret) {
  final mac = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(value));
  final signature = base64Url.encode(mac.bytes).replaceAll('=', '');
  return '$value.$signature';
}

/// Checks a value produced by [signCookie] and returns the original value.
///
/// Returns `null` when the signature is missing or does not match, which
/// means the cookie was forged or signed with a different secret.
String? unsignCookie(String signed, String secret) {
  final dot = signed.lastIndexOf('.');
  if (dot <= 0) return null;

  final value = signed.substring(0, dot);
  final expected = signCookie(value, secret);
  return _constantTimeEquals(expected, signed) ? value : null;
}

/// Generates a random, URL-safe identifier with 192 bits of entropy.
///
/// Used for session ids. It relies on [Random.secure].
String generateSessionId() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Compares two strings in time that does not depend on where they differ,
/// to avoid leaking the signature through timing.
bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
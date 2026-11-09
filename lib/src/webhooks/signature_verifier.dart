import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../util/secure_equals.dart';

/// Decides whether a webhook really comes from the expected sender.
///
/// Webhook senders sign the request body with a secret you share with them.
/// Implement this interface for providers with their own scheme, or use
/// [HmacVerifier] and [StripeVerifier].
abstract interface class WebhookVerifier {
  /// Returns `true` when the request is authentic.
  ///
  /// [header] looks up a request header by name (case-insensitive) and returns
  /// `null` when it is absent. [body] is the raw, unmodified request body:
  /// signatures are computed over these exact bytes, so the body must not be
  /// parsed and re-encoded before checking.
  bool verify(String? Function(String name) header, List<int> body);
}

/// Verifies a plain HMAC signature of the body, sent in a header.
///
/// ```dart
/// // Signature in "X-Signature", as lowercase hex of HMAC-SHA256:
/// HmacVerifier('my-secret')
///
/// // GitHub: "X-Hub-Signature-256: sha256=<hex>"
/// HmacVerifier.github('my-secret')
///
/// // Custom header and base64 encoding:
/// HmacVerifier('my-secret', header: 'x-hook-signature', useBase64: true)
/// ```
///
/// This scheme does not include a timestamp, so it cannot detect a request
/// that is captured and sent again later. When the provider offers a
/// timestamped scheme (like Stripe), prefer it.
class HmacVerifier implements WebhookVerifier {
  /// Creates a verifier for the given [secret].
  ///
  /// * [header] is the name of the header that carries the signature.
  /// * [prefix] is text that comes before the signature in the header value,
  ///   such as `sha256=`.
  /// * [hash] is the HMAC hash. Defaults to SHA-256.
  /// * [useBase64] expects base64 instead of lowercase hex.
  HmacVerifier(
    this.secret, {
    this.header = 'x-signature',
    this.prefix = '',
    Hash? hash,
    this.useBase64 = false,
  }) : hash = hash ?? sha256;

  /// Creates a verifier for GitHub webhooks.
  ///
  /// GitHub sends `X-Hub-Signature-256: sha256=<hex>`.
  HmacVerifier.github(String secret)
      : this(secret, header: 'x-hub-signature-256', prefix: 'sha256=');

  /// The shared secret.
  final String secret;

  /// The header that carries the signature.
  final String header;

  /// Text that precedes the signature in the header value.
  final String prefix;

  /// The hash used by the HMAC.
  final Hash hash;

  /// Whether the signature is base64 (`true`) or lowercase hex (`false`).
  final bool useBase64;

  @override
  bool verify(String? Function(String name) header, List<int> body) {
    final received = header(this.header);
    if (received == null || !received.startsWith(prefix)) return false;

    final provided = received.substring(prefix.length).trim();
    final mac = Hmac(hash, utf8.encode(secret)).convert(body);

    return useBase64
        ? secureEquals(base64Encode(mac.bytes), provided)
        : secureEquals(mac.toString(), provided.toLowerCase());
  }
}

/// Verifies Stripe-style signatures, which include a timestamp.
///
/// The header looks like `Stripe-Signature: t=1700000000,v1=<hex>`. The
/// signed text is `<t>.<body>`, and the request is rejected when `t` is
/// farther than [tolerance] from the current time, which blocks replays.
///
/// ```dart
/// app.webhook('/hooks/stripe', handler, verifier: StripeVerifier('whsec_...'));
/// ```
class StripeVerifier implements WebhookVerifier {
  /// Creates a verifier for the given [secret].
  ///
  /// [clock] replaces the current time, which is useful in tests.
  StripeVerifier(
    this.secret, {
    this.tolerance = const Duration(minutes: 5),
    this.header = 'stripe-signature',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The shared secret (for Stripe, the endpoint signing secret).
  final String secret;

  /// The largest accepted difference between the signed timestamp and now.
  final Duration tolerance;

  /// The header that carries the signature.
  final String header;

  final DateTime Function() _clock;

  @override
  bool verify(String? Function(String name) header, List<int> body) {
    final value = header(this.header);
    if (value == null) return false;

    int? timestamp;
    final signatures = <String>[];

    for (final part in value.split(',')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;

      final key = part.substring(0, separator).trim();
      final content = part.substring(separator + 1).trim();
      if (key == 't') {
        timestamp = int.tryParse(content);
      } else if (key == 'v1') {
        signatures.add(content.toLowerCase());
      }
    }
    if (timestamp == null || signatures.isEmpty) return false;

    final nowSeconds = _clock().millisecondsSinceEpoch ~/ 1000;
    if ((nowSeconds - timestamp).abs() > tolerance.inSeconds) return false;

    final signedPayload = <int>[...utf8.encode('$timestamp.'), ...body];
    final expected =
        Hmac(sha256, utf8.encode(secret)).convert(signedPayload).toString();

    return signatures.any((signature) => secureEquals(expected, signature));
  }
}
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:oche/src/webhooks/signature_verifier.dart';
import 'package:test/test.dart';

String? Function(String) headers(Map<String, String> values) =>
    (name) => values[name.toLowerCase()];

void main() {
  group('HmacVerifier', () {
    // Test vector from the GitHub documentation.
    const secret = "It's a Secret to Everybody";
    final body = utf8.encode('Hello, World!');
    const signature = 'sha256=757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17';

    test('accepts the GitHub documentation example', () {
      final verifier = HmacVerifier.github(secret);

      expect(
        verifier.verify(headers({'x-hub-signature-256': signature}), body),
        isTrue,
      );
    });

    test('rejects a different body', () {
      final verifier = HmacVerifier.github(secret);

      expect(
        verifier.verify(
          headers({'x-hub-signature-256': signature}),
          utf8.encode('Hello, World?'),
        ),
        isFalse,
      );
    });

    test('rejects a different secret', () {
      final verifier = HmacVerifier.github('another secret');

      expect(
        verifier.verify(headers({'x-hub-signature-256': signature}), body),
        isFalse,
      );
    });

    test('rejects a missing header or a wrong prefix', () {
      final verifier = HmacVerifier.github(secret);

      expect(verifier.verify(headers({}), body), isFalse);
      expect(
        verifier.verify(
          headers({'x-hub-signature-256': signature.replaceFirst('sha256=', 'sha1=')}),
          body,
        ),
        isFalse,
      );
    });

    test('supports a custom header with base64', () {
      final mac = Hmac(sha256, utf8.encode('k')).convert(body);
      final verifier = HmacVerifier('k', header: 'x-sig', useBase64: true);

      expect(
        verifier.verify(headers({'x-sig': base64Encode(mac.bytes)}), body),
        isTrue,
      );
    });
  });

  group('StripeVerifier', () {
    const secret = 'whsec_test';
    const timestamp = 1700000000;
    final body = utf8.encode('{"type":"charge.succeeded"}');

    String sign(int t) => Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode('$t.${utf8.decode(body)}'))
        .toString();

    StripeVerifier verifierAt(int seconds) => StripeVerifier(
          secret,
          clock: () => DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
        );

    test('accepts a valid signature within the tolerance', () {
      final header = 't=$timestamp,v1=${sign(timestamp)}';

      expect(
        verifierAt(timestamp + 60).verify(headers({'stripe-signature': header}), body),
        isTrue,
      );
    });

    test('accepts when one of several v1 signatures matches', () {
      final header = 't=$timestamp,v1=deadbeef,v1=${sign(timestamp)}';

      expect(
        verifierAt(timestamp).verify(headers({'stripe-signature': header}), body),
        isTrue,
      );
    });

    test('rejects a timestamp outside the tolerance (replay)', () {
      final header = 't=$timestamp,v1=${sign(timestamp)}';

      expect(
        verifierAt(timestamp + 3600).verify(headers({'stripe-signature': header}), body),
        isFalse,
      );
    });

    test('rejects a signature made for another body', () {
      final header = 't=$timestamp,v1=${sign(timestamp)}';

      expect(
        verifierAt(timestamp).verify(
          headers({'stripe-signature': header}),
          utf8.encode('{"type":"other"}'),
        ),
        isFalse,
      );
    });

    test('rejects a malformed or missing header', () {
      final verifier = verifierAt(timestamp);

      expect(verifier.verify(headers({}), body), isFalse);
      expect(verifier.verify(headers({'stripe-signature': 'garbage'}), body), isFalse);
    });
  });
}
import 'dart:convert';

import 'package:oche_web/src/jwt/jwt.dart';
import 'package:oche_web/src/jwt/jwt_exception.dart';
import 'package:test/test.dart';

Matcher throwsJwt(JwtFailure failure) => throwsA(
      isA<JwtException>().having((e) => e.failure, 'failure', failure),
    );

String _b64(String text) =>
    base64Url.encode(utf8.encode(text)).replaceAll('=', '');

void main() {
  const secret = 'a-secret-with-at-least-32-characters!';

  group('Jwt', () {
    test('verifies the well-known jwt.io example token', () {
      const token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
          'eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.'
          'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

      final payload = Jwt.verify(token, secret: 'your-256-bit-secret');

      expect(payload['name'], 'John Doe');
      expect(payload['sub'], '1234567890');
    });

    test('signs and verifies a token', () {
      final token = Jwt.sign({'id': 1}, secret: secret);
      final payload = Jwt.verify(token, secret: secret);

      expect(payload['id'], 1);
      expect(payload, contains('iat'));
    });

    test('rejects a wrong secret', () {
      final token = Jwt.sign({'id': 1}, secret: secret);

      expect(
        () => Jwt.verify(token, secret: 'another-secret'),
        throwsJwt(JwtFailure.invalidSignature),
      );
    });

    test('rejects a tampered payload', () {
      final token = Jwt.sign({'id': 1}, secret: secret);
      final parts = token.split('.');
      final forged = '${parts[0]}.${_b64('{"id":99}')}.${parts[2]}';

      expect(
        () => Jwt.verify(forged, secret: secret),
        throwsJwt(JwtFailure.invalidSignature),
      );
    });

    test('rejects expired tokens', () {
      final token = Jwt.sign(
        {'id': 1},
        secret: secret,
        expiresIn: const Duration(minutes: 1),
      );
      final later = DateTime.now().add(const Duration(minutes: 2));

      expect(
        () => Jwt.verify(token, secret: secret, now: later),
        throwsJwt(JwtFailure.expired),
      );
    });

    test('accepts a token that has not expired yet', () {
      final token = Jwt.sign(
        {'id': 1},
        secret: secret,
        expiresIn: const Duration(hours: 1),
      );

      expect(Jwt.verify(token, secret: secret)['id'], 1);
    });

    test('rejects the "none" algorithm', () {
      final token =
          '${_b64('{"alg":"none","typ":"JWT"}')}.${_b64('{"id":1}')}.';

      expect(
        () => Jwt.verify(token, secret: secret),
        throwsJwt(JwtFailure.unsupportedAlgorithm),
      );
    });

    test('rejects an algorithm that is not in the accepted list', () {
      final token = Jwt.sign({'id': 1}, secret: secret, algorithm: 'HS512');

      expect(
        () => Jwt.verify(token, secret: secret),
        throwsJwt(JwtFailure.unsupportedAlgorithm),
      );
      expect(
        Jwt.verify(token, secret: secret, algorithms: ['HS512'])['id'],
        1,
      );
    });

    test('rejects malformed tokens', () {
      expect(
        () => Jwt.verify('abc', secret: secret),
        throwsJwt(JwtFailure.malformed),
      );
      expect(
        () => Jwt.verify('..', secret: secret),
        throwsJwt(JwtFailure.malformed),
      );
    });

    test('checks issuer and audience', () {
      final token =
          Jwt.sign({}, secret: secret, issuer: 'oche', audience: 'app');

      expect(
        Jwt.verify(token, secret: secret, issuer: 'oche', audience: 'app'),
        isNotEmpty,
      );
      expect(
        () => Jwt.verify(token, secret: secret, issuer: 'other'),
        throwsJwt(JwtFailure.invalidClaim),
      );
      expect(
        () => Jwt.verify(token, secret: secret, audience: 'other'),
        throwsJwt(JwtFailure.invalidClaim),
      );
    });

    test('decode reads the payload without verifying', () {
      final token = Jwt.sign({'id': 7}, secret: secret);

      expect(Jwt.decode(token)['id'], 7);
    });
  });
}
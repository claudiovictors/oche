import '../errors/http_error.dart';
import '../http/request.dart';
import '../http/response.dart';
import '../middleware/middleware.dart';
import 'jwt.dart';
import 'jwt_exception.dart';

/// Creates a middleware that protects routes with a JWT.
///
/// It reads the token from the `Authorization: Bearer <token>` header,
/// verifies it, and stores the payload in `req.user`:
///
/// ```dart
/// app.use('/private', Oche.jwt(secret: secret));
///
/// app.get('/private/profile', (req, res) {
///   res.json({'user': req.user});
/// });
/// ```
///
/// Failures are reported as `401 Unauthorized` with a short message
/// (`Token expired`, `Invalid token` or `Missing authentication token`).
///
/// Options:
///
/// * [secret], [algorithms], [issuer], [audience] and [clockTolerance] are
///   passed to [Jwt.verify].
/// * [credentialsRequired] — when `false`, requests without a token continue
///   with `req.user == null`. A token that is present but invalid is always
///   rejected.
/// * [getToken] — a custom way to find the token, for example in a cookie or
///   in the query string. Return `null` when there is none.
Middleware jwtMiddleware({
  required String secret,
  List<String> algorithms = const <String>['HS256'],
  String? issuer,
  String? audience,
  Duration clockTolerance = Duration.zero,
  bool credentialsRequired = true,
  String? Function(Request req)? getToken,
}) {
  if (secret.isEmpty) {
    throw ArgumentError.value(secret, 'secret', 'must not be empty');
  }
  final readToken = getToken ?? _bearerToken;

  return (Request req, Response res, Next next) {
    final token = readToken(req);

    if (token == null) {
      if (credentialsRequired) {
        throw HttpError.unauthorized('Missing authentication token');
      }
      next();
      return;
    }

    try {
      req.user = Jwt.verify(
        token,
        secret: secret,
        algorithms: algorithms,
        issuer: issuer,
        audience: audience,
        clockTolerance: clockTolerance,
      );
    } on JwtException catch (error) {
      throw HttpError.unauthorized(
        error.failure == JwtFailure.expired ? 'Token expired' : 'Invalid token',
      );
    }
    next();
  };
}

/// Extracts the token from an `Authorization: Bearer <token>` header.
String? _bearerToken(Request req) {
  final header = req.header('authorization');
  if (header == null) return null;

  final parts = header.trim().split(RegExp(r'\s+'));
  if (parts.length != 2 || parts[0].toLowerCase() != 'bearer') return null;
  return parts[1];
}
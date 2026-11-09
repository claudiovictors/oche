import '../http/request.dart';
import '../http/response.dart';
import '../middleware/middleware.dart';
import 'cookie_signature.dart';
import 'memory_store.dart';
import 'session.dart';
import 'session_store.dart';

/// Creates a middleware that gives every request a [Session] in
/// `req.session`.
///
/// ```dart
/// app.use(Oche.session(secret: 'a-long-random-secret'));
/// ```
///
/// How it works:
///
/// 1. The session id travels in a cookie signed with [secret], so it cannot
///    be forged. A missing, invalid or expired cookie starts a new session.
/// 2. Just before the response is sent, the session is saved in [store] and
///    the cookie is set. Sessions that were not modified are not saved, and
///    do not set a cookie.
///
/// Options:
///
/// * [store] keeps the data. Defaults to a [MemoryStore].
/// * [cookieName] is the name of the cookie.
/// * [maxAge] is how long a session lives.
/// * [rolling] renews the expiry (and the cookie) on every response, instead
///   of only when the session changes.
/// * [secure] sends the cookie only over HTTPS. Turn it on in production.
/// * [httpOnly] hides the cookie from JavaScript. On by default.
/// * [path] and [domain] scope the cookie.
///
/// Throws an [ArgumentError] when [secret] is empty.
Middleware sessionMiddleware({
  required String secret,
  SessionStore? store,
  String cookieName = 'oche.sid',
  Duration maxAge = const Duration(days: 1),
  String path = '/',
  String? domain,
  bool secure = false,
  bool httpOnly = true,
  bool rolling = false,
}) {
  if (secret.isEmpty) {
    throw ArgumentError.value(secret, 'secret', 'must not be empty');
  }
  final sessions = store ?? MemoryStore();

  return (Request req, Response res, Next next) async {
    final existingId = _readSessionId(req, cookieName, secret);
    final data = existingId == null ? null : await sessions.get(existingId);

    final session = (existingId != null && data != null)
        ? Session(existingId, data: data, isNew: false)
        : Session(generateSessionId());
    req.session = session;

    // Runs right before the response is written, so the cookie can still be
    // added to the headers.
    res.onBeforeSend(() async {
      final previous = session.previousId;
      if (previous != null) await sessions.destroy(previous);

      if (session.isDestroyed) {
        await sessions.destroy(session.id);
        res.clearCookie(cookieName, path: path, domain: domain);
        return;
      }

      final shouldSave = session.isModified || (rolling && !session.isNew);
      if (!shouldSave) return;

      await sessions.set(session.id, session.toMap(), maxAge);
      res.cookie(
        cookieName,
        signCookie(session.id, secret),
        maxAge: maxAge,
        path: path,
        domain: domain,
        secure: secure,
        httpOnly: httpOnly,
      );
    });

    next();
  };
}

/// Returns the verified session id sent by the client, or `null`.
String? _readSessionId(Request req, String cookieName, String secret) {
  for (final cookie in req.cookies) {
    if (cookie.name != cookieName) continue;
    try {
      return unsignCookie(Uri.decodeComponent(cookie.value), secret);
    } on FormatException {
      return null;
    }
  }
  return null;
}
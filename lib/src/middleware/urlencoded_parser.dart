import 'dart:convert';

import '../errors/http_error.dart';
import '../http/request.dart';
import '../http/response.dart';
import 'body_reader.dart';
import 'middleware.dart';

/// Creates a middleware that parses HTML form bodies
/// (`application/x-www-form-urlencoded`) into [Request.body].
///
/// The result is a `Map<String, String>`. When a key is repeated, the last
/// value wins.
///
/// ```dart
/// app.use(Oche.urlencoded());
///
/// app.post('/login', (req, res) {
///   final form = req.body as Map<String, String>;
///   res.send('Hello ${form['user']}');
/// });
/// ```
///
/// Malformed bodies fail with `400 Bad Request`, and bodies larger than
/// [limit] bytes fail with `413 Payload Too Large`.
Middleware urlencodedBodyParser({int limit = defaultBodyLimit}) {
  return (Request req, Response res, Next next) async {
    if (req.body != null ||
        !req.isContentType('application/x-www-form-urlencoded')) {
      next();
      return;
    }

    final bytes = await readBody(req, limit);
    if (bytes.isNotEmpty) {
      try {
        req.body = Uri.splitQueryString(utf8.decode(bytes));
      } on FormatException {
        throw HttpError.badRequest('Invalid form body');
      }
    }
    next();
  };
}
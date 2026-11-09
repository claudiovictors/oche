import 'dart:convert';

import '../errors/http_error.dart';
import '../http/request.dart';
import '../http/response.dart';
import 'body_reader.dart';
import 'middleware.dart';

/// Creates a middleware that parses JSON request bodies into [Request.body].
///
/// It only acts on requests whose `Content-Type` is `application/json` (or a
/// `+json` type) and whose body is not empty. Other requests pass through
/// untouched.
///
/// ```dart
/// app.use(Oche.json());
///
/// app.post('/users', (req, res) {
///   final body = req.body as Map<String, dynamic>;
///   res.status(201).json({'name': body['name']});
/// });
/// ```
///
/// Invalid JSON fails with `400 Bad Request`, and bodies larger than [limit]
/// bytes fail with `413 Payload Too Large`.
Middleware jsonBodyParser({int limit = defaultBodyLimit}) {
  return (Request req, Response res, Next next) async {
    final type = req.contentType;
    final isJson =
        type != null && (type == 'application/json' || type.endsWith('+json'));

    if (req.body != null || !isJson) {
      next();
      return;
    }

    final bytes = await readBody(req, limit);
    if (bytes.isNotEmpty) {
      try {
        req.body = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        throw HttpError.badRequest('Invalid JSON body');
      }
    }
    next();
  };
}
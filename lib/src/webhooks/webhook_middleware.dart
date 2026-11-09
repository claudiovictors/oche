import 'dart:convert';

import '../errors/http_error.dart';
import '../http/request.dart';
import '../http/response.dart';
import '../middleware/body_reader.dart';
import '../middleware/middleware.dart';
import 'signature_verifier.dart';

/// Creates a middleware that only lets authentic webhooks through.
///
/// It reads the raw body, asks the [verifier] to check the signature, and
/// answers `401 Unauthorized` when it does not match. When the signature is
/// valid and the body is JSON, the parsed value is stored in `req.body`.
///
/// ```dart
/// app.post(
///   '/hooks/custom',
///   (req, res) => res.sendStatus(200),
///   middlewares: [webhookMiddleware(HmacVerifier('secret'))],
/// );
/// ```
///
/// Most of the time `app.webhook(...)` is simpler, since it does this for you.
/// Bodies larger than [limit] bytes fail with `413 Payload Too Large`.
Middleware webhookMiddleware(
  WebhookVerifier verifier, {
  int limit = defaultBodyLimit,
}) {
  return (Request req, Response res, Next next) async {
    final body = await readBody(req, limit);

    if (!verifier.verify(req.header, body)) {
      throw HttpError.unauthorized('Invalid webhook signature');
    }

    final type = req.contentType;
    final isJson =
        type != null && (type == 'application/json' || type.endsWith('+json'));

    if (req.body == null && body.isNotEmpty && isJson) {
      try {
        req.body = jsonDecode(utf8.decode(body));
      } on FormatException {
        throw HttpError.badRequest('Invalid JSON body');
      }
    }
    next();
  };
}
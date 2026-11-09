import 'dart:io';

import '../http/request.dart';
import '../http/response.dart';
import 'http_error.dart';

/// The error handler used when none is registered with `Oche.onError`.
///
/// * An [HttpError] is sent with its own status code and JSON body.
/// * Any other error is logged to `stderr` and answered with a generic
///   `500 Internal Server Error`, so internal details are never leaked to
///   the client.
void defaultErrorHandler(Object error, Request req, Response res) {
  if (error is HttpError) {
    res.status(error.statusCode).json(error.toJson());
    return;
  }

  stderr.writeln('Unhandled error on ${req.method} ${req.originalUrl}: $error');
  res.status(500).json(HttpError.internal().toJson());
}
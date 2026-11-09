import '../http/status.dart';

/// An error that maps directly to an HTTP response.
///
/// Throw it from any handler or middleware (or pass it to `next`) and the
/// error handler will reply with [statusCode] and [message].
///
/// ```dart
/// app.get('/users/:id', (req, res) async {
///   final user = await db.find(req.params['id']);
///   if (user == null) throw HttpError.notFound('User not found');
///   res.json(user);
/// });
/// ```
///
/// The class is named `HttpError` instead of `HttpException` on purpose, to
/// avoid clashing with `HttpException` from `dart:io`.
class HttpError implements Exception {
  /// Creates an error with the given HTTP [statusCode].
  ///
  /// When [message] is omitted, the standard reason phrase of [statusCode]
  /// is used (for example `'Not Found'` for `404`). Optional [details] can
  /// carry any extra JSON-encodable data, such as validation errors.
  HttpError(this.statusCode, [String? message, this.details])
      : message = message ?? reasonPhraseFor(statusCode);

  /// Creates a `400 Bad Request` error.
  HttpError.badRequest([String? message, Object? details])
      : this(400, message, details);

  /// Creates a `401 Unauthorized` error.
  HttpError.unauthorized([String? message, Object? details])
      : this(401, message, details);

  /// Creates a `403 Forbidden` error.
  HttpError.forbidden([String? message, Object? details])
      : this(403, message, details);

  /// Creates a `404 Not Found` error.
  HttpError.notFound([String? message, Object? details])
      : this(404, message, details);

  /// Creates a `409 Conflict` error.
  HttpError.conflict([String? message, Object? details])
      : this(409, message, details);

  /// Creates a `422 Unprocessable Entity` error.
  HttpError.unprocessable([String? message, Object? details])
      : this(422, message, details);

  /// Creates a `500 Internal Server Error` error.
  HttpError.internal([String? message, Object? details])
      : this(500, message, details);

  /// The HTTP status code sent to the client.
  final int statusCode;

  /// A human-readable description of what went wrong.
  final String message;

  /// Optional extra data describing the error (e.g. validation failures).
  final Object? details;

  /// Converts this error to a JSON-encodable map.
  ///
  /// This is the shape used by the default error handler.
  Map<String, Object?> toJson() => <String, Object?>{
        'status': statusCode,
        'message': message,
        if (details != null) 'details': details,
      };

  @override
  String toString() => 'HttpError($statusCode): $message';
}

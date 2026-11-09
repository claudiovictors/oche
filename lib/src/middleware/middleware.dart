import 'dart:async';

import '../http/request.dart';
import '../http/response.dart';

/// Passes control to the next middleware or handler in the chain.
///
/// Calling `next()` with no argument continues normally. Calling it with an
/// [error] skips the remaining handlers and jumps to the [ErrorHandler]:
///
/// ```dart
/// app.use((req, res, next) {
///   if (req.header('x-token') == null) {
///     return next(HttpError.unauthorized('Missing token'));
///   }
///   next();
/// });
/// ```
typedef Next = void Function([Object? error]);

/// A route handler, the final step of a request.
///
/// Used by `get`, `post`, `put`, `delete` and `patch`. It may be synchronous
/// or `async`:
///
/// ```dart
/// Handler hello = (req, res) => res.send('Hello World!');
/// ```
typedef Handler = FutureOr<void> Function(Request req, Response res);

/// A function that runs before the final handler.
///
/// Used by `use` and `all`. It must either send a response or call [Next]:
///
/// ```dart
/// void myLogger(Request req, Response res, Next next) {
///   print('LOGGED');
///   next();
/// }
/// ```
typedef Middleware = FutureOr<void> Function(
  Request req,
  Response res,
  Next next,
);

/// Handles errors thrown by handlers or passed to [Next].
///
/// ```dart
/// app.onError((error, req, res) {
///   res.status(500).json({'error': error.toString()});
/// });
/// ```
typedef ErrorHandler = FutureOr<void> Function(
  Object error,
  Request req,
  Response res,
);

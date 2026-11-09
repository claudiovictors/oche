import 'dart:async';

import '../http/request.dart';
import '../http/response.dart';
import 'middleware.dart';

/// Creates a middleware that logs one line per request, after the response
/// is finished:
///
/// ```text
/// GET /users/42 200 3ms
/// ```
///
/// Lines are printed with [print], or sent to [output] when it is given:
///
/// ```dart
/// app.use(Oche.logger());
/// app.use(Oche.logger(output: myLogger.info));
/// ```
Middleware requestLogger({void Function(String line)? output}) {
  final write = output ?? print;

  return (Request req, Response res, Next next) {
    final stopwatch = Stopwatch()..start();
    final method = req.method;
    final url = req.originalUrl;

    unawaited(
      res.raw.done.then<void>(
        (_) => write(
          '$method $url ${res.statusCode} ${stopwatch.elapsedMilliseconds}ms',
        ),
        onError: (Object _) {},
      ),
    );

    next();
  };
}
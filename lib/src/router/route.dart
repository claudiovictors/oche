import 'dart:async';

import '../http/request.dart';
import '../http/response.dart';
import '../middleware/middleware.dart';
import 'path_matcher.dart';

/// A single route: an HTTP method, a path pattern and a chain of functions.
///
/// Routes are created by the router when you call `app.get`, `app.post`,
/// `app.all` and friends. You rarely need to build one by hand.
///
/// The [stack] runs in order. Each function must either send a response or
/// call `next()` to continue to the next function of the same route. When the
/// last function calls `next()`, control goes back to the router, which keeps
/// looking for other matching routes.
class Route {
  /// Creates a route.
  ///
  /// A `null` [method] makes the route match every HTTP method (this is what
  /// `app.all` does).
  Route(this.method, this.path, this.stack, {bool caseSensitive = false})
      : matcher = PathMatcher(path, caseSensitive: caseSensitive);

  /// The HTTP method in upper case, or `null` to accept any method.
  final String? method;

  /// The path pattern, such as `/users/:id`.
  final String path;

  /// The compiled matcher for [path].
  final PathMatcher matcher;

  /// The functions executed, in order, when this route matches.
  final List<Middleware> stack;

  /// Whether this route handles requests with the HTTP [requestMethod].
  ///
  /// As in Express, `HEAD` requests are handled by `GET` routes.
  bool handlesMethod(String requestMethod) {
    final m = requestMethod.toUpperCase();
    return method == null || method == m || (method == 'GET' && m == 'HEAD');
  }

  /// Runs the [stack] for [req] and [res].
  ///
  /// [done] is called when the whole stack has called `next()`, or as soon as
  /// one function reports an error.
  void dispatch(Request req, Response res, Next done) {
    var index = 0;

    void next([Object? error]) {
      if (error != null) {
        done(error);
        return;
      }
      if (index >= stack.length) {
        done();
        return;
      }
      unawaited(invokeMiddleware(stack[index++], req, res, next));
    }

    next();
  }
}

/// Adapts a two-argument [Handler] to the three-argument [Middleware] shape,
/// so that route handlers and middlewares can live in the same chain.
Middleware asMiddleware(Handler handler) =>
    (Request req, Response res, Next next) => handler(req, res);

/// Runs [fn] and routes every kind of failure to [next].
///
/// * Exceptions thrown synchronously are forwarded as `next(error)`.
/// * Errors of `async` functions (rejected futures) are forwarded too.
/// * Calling `next` more than once is ignored, so a function that calls
///   `next()` and then throws cannot advance the chain twice.
Future<void> invokeMiddleware(
  Middleware fn,
  Request req,
  Response res,
  Next next,
) async {
  var called = false;

  void guardedNext([Object? error]) {
    if (called) return;
    called = true;
    next(error);
  }

  try {
    await fn(req, res, guardedNext);
  } catch (error) {
    guardedNext(error);
  }
}

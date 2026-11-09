import 'dart:async';

import '../http/request.dart';
import '../http/response.dart';
import '../middleware/middleware.dart';
import 'path_matcher.dart';
import 'route.dart';
import '../middleware/body_reader.dart';
import '../webhooks/signature_verifier.dart';
import '../webhooks/webhook_middleware.dart';

/// A collection of routes and middlewares, like `express.Router()`.
///
/// Routers can be mounted inside other routers, which is the best way to split
/// a big application into modules:
///
/// ```dart
/// final users = Router();
///
/// users.get('/', (req, res) => res.json([]));
/// users.get('/:id', (req, res) => res.json({'id': req.params['id']}));
///
/// // Inside `users`, paths are relative to the mount point.
/// app.use('/users', users);
/// ```
///
/// Layers are tried in the order they were registered, so the order of the
/// `use`, `get`, `post`... calls matters.
class Router {
  /// Creates an empty router.
  ///
  /// Set [caseSensitive] to `true` to make `/Users` and `/users` different
  /// paths. It is `false` by default, as in Express.
  Router({this.caseSensitive = false});

  /// Whether path matching is case sensitive in this router.
  final bool caseSensitive;

  final List<_Layer> _layers = <_Layer>[];

    /// Registers a middleware, or mounts a middleware or router at a path.
  ///
  /// There are three ways to call it:
  ///
  /// ```dart
  /// app.use(myLogger);                              // every request
  /// app.use('/static', Oche.serveStatic('public')); // only under /static
  /// app.use('/api', apiRouter);                     // mount a router
  /// ```
  ///
  /// When a path is given, it is stripped from `req.path` while the
  /// middleware runs (and saved in `req.baseUrl`), exactly like Express.
  ///
  /// Dart has no overloading, so the arguments are typed as [Object]. Because
  /// of that, an inline closure passed to `use` gets untyped parameters.
  /// Either annotate them (`(Request req, Response res, Next next) { ... }`)
  /// or use a named function.
  ///
  /// Throws an [ArgumentError] if the arguments do not match one of the
  /// forms above.
  void use(Object first, [Object? second]) {
    final String path;
    final Object target;

    if (first is String) {
      if (second == null) {
        throw ArgumentError(
          'use("$first") needs a middleware or a router as second argument.',
        );
      }
      path = first;
      target = second;
    } else {
      path = '/';
      target = first;
    }

    final Middleware middleware;
    if (target is Router) {
      middleware = target.call;
    } else if (target is Middleware) {
      middleware = target;
    } else {
      throw ArgumentError.value(
        target,
        first is String ? 'second' : 'first',
        'Expected a Middleware (req, res, next) or a Router.',
      );
    }

    _layers.add(
      _Layer.middleware(
        PathMatcher(path, end: false, caseSensitive: caseSensitive),
        middleware,
      ),
    );
  }

    /// Registers a route that receives webhooks (always `POST`).
  ///
  /// The signature of every request is checked **before** [handler] runs, and
  /// requests that fail get a `401`. Choose how to verify with one of:
  ///
  /// * [secret] — a plain HMAC-SHA256 signature, as lowercase hex, in the
  ///   `X-Signature` header (see [HmacVerifier]).
  /// * [verifier] — any [WebhookVerifier], such as `HmacVerifier.github(...)`
  ///   or `StripeVerifier(...)`.
  ///
  /// ```dart
  /// app.webhook('/hooks/github', github.handle,
  ///     verifier: HmacVerifier.github('my-secret'));
  ///
  /// app.webhook('/hooks/generic', (req, res) {
  ///   print(req.body);
  ///   res.sendStatus(200);
  /// }, secret: 'my-secret');
  /// ```
  ///
  /// Answer quickly: senders give up on slow endpoints and retry. Do the heavy
  /// work in the background and reply `2xx` first.
  ///
  /// Throws an [ArgumentError] unless exactly one of [secret] and [verifier]
  /// is given.
  void webhook(
    String path,
    Handler handler, {
    String? secret,
    WebhookVerifier? verifier,
    int limit = defaultBodyLimit,
    List<Middleware> middlewares = const <Middleware>[],
  }) {
    if ((secret == null) == (verifier == null)) {
      throw ArgumentError(
        'webhook("$path") needs either "secret" or "verifier", but not both.',
      );
    }

    _addRoute('POST', path, handler, <Middleware>[
      webhookMiddleware(verifier ?? HmacVerifier(secret!), limit: limit),
      ...middlewares,
    ]);
  }

  /// Registers a route for `GET` requests (and `HEAD`, as Express does).
  ///
  /// The optional [middlewares] run before [handler], in order:
  ///
  /// ```dart
  /// app.get('/admin', (req, res) => res.send('Hi boss'),
  ///     middlewares: [requireLogin]);
  /// ```
  void get(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const <Middleware>[],
  }) =>
      _addRoute('GET', path, handler, middlewares);

  /// Registers a route for `POST` requests. See [get] for the parameters.
  void post(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const <Middleware>[],
  }) =>
      _addRoute('POST', path, handler, middlewares);

  /// Registers a route for `PUT` requests. See [get] for the parameters.
  void put(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const <Middleware>[],
  }) =>
      _addRoute('PUT', path, handler, middlewares);

  /// Registers a route for `DELETE` requests. See [get] for the parameters.
  void delete(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const <Middleware>[],
  }) =>
      _addRoute('DELETE', path, handler, middlewares);

  /// Registers a route for `PATCH` requests. See [get] for the parameters.
  void patch(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const <Middleware>[],
  }) =>
      _addRoute('PATCH', path, handler, middlewares);

  /// Registers a route for `HEAD` requests. See [get] for the parameters.
  void head(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const <Middleware>[],
  }) =>
      _addRoute('HEAD', path, handler, middlewares);

  /// Registers a route for `OPTIONS` requests. See [get] for the parameters.
  void options(
    String path,
    Handler handler, {
    List<Middleware> middlewares = const <Middleware>[],
  }) =>
      _addRoute('OPTIONS', path, handler, middlewares);

  /// Registers a [middleware] for [path] that runs for **every** HTTP method.
  ///
  /// Unlike [use], [path] must match the whole request path.
  ///
  /// ```dart
  /// app.all('/secret', (req, res, next) {
  ///   print('Accessing the secret section ...');
  ///   next(); // pass control to the next handler
  /// });
  /// ```
  void all(String path, Middleware middleware) {
    _layers.add(
      _Layer.route(
        Route(null, path, <Middleware>[middleware],
            caseSensitive: caseSensitive),
      ),
    );
  }

  /// Runs the request through this router.
  ///
  /// This makes a [Router] usable anywhere a [Middleware] is expected, which
  /// is what allows `app.use('/api', router)`.
  ///
  /// Layers are tried in registration order. [done] is called when no layer
  /// is left (the request was not handled here) or as soon as an error is
  /// reported with `next(error)`.
  void call(Request req, Response res, Next done) {
    var index = 0;

    void next([Object? error]) {
      if (error != null) {
        done(error);
        return;
      }

      while (index < _layers.length) {
        final layer = _layers[index++];
        final route = layer.route;

        if (route != null && !route.handlesMethod(req.method)) continue;

        final match = layer.matcher.match(req.path);
        if (match == null) continue;

        // Remember the request state so it can be restored when this layer
        // calls `next()`, which is what lets later layers see the original
        // path again.
        final savedParams = req.params;
        final savedBaseUrl = req.baseUrl;
        final savedPath = req.path;

        req.params = <String, String>{...savedParams, ...match.params};

        void proceed([Object? error]) {
          req.params = savedParams;
          req.baseUrl = savedBaseUrl;
          req.path = savedPath;
          next(error);
        }

        if (route != null) {
          route.dispatch(req, res, proceed);
        } else {
          // Mounted middleware: strip the mount prefix from the path.
          req.baseUrl = savedBaseUrl + match.matchedPath;
          req.path = match.remainingPath;
          unawaited(invokeMiddleware(layer.middleware!, req, res, proceed));
        }
        return;
      }

      done();
    }

    next();
  }

  void _addRoute(
    String method,
    String path,
    Handler handler,
    List<Middleware> middlewares,
  ) {
    _layers.add(
      _Layer.route(
        Route(
          method,
          path,
          <Middleware>[...middlewares, asMiddleware(handler)],
          caseSensitive: caseSensitive,
        ),
      ),
    );
  }
}

/// One entry of a router: either a route or a mounted middleware.
class _Layer {
  _Layer.route(Route this.route)
      : matcher = route.matcher,
        middleware = null;

  _Layer.middleware(this.matcher, Middleware this.middleware) : route = null;

  final PathMatcher matcher;
  final Route? route;
  final Middleware? middleware;
}

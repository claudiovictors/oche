import 'dart:async';
import 'dart:io';

import 'errors/error_handler.dart';
import 'http/request.dart';
import 'http/response.dart';
import 'middleware/middleware.dart';
import 'router/router.dart';
import 'middleware/body_reader.dart';
import 'middleware/cors.dart';
import 'middleware/json_parser.dart';
import 'middleware/logger.dart';
import 'middleware/static_files.dart';
import 'middleware/urlencoded_parser.dart';
import 'session/session_middleware.dart';
import 'session/session_store.dart';
import 'jwt/jwt_middleware.dart';
import 'view/oche_engine.dart';
import 'view/view_engine.dart';
import 'view/views.dart';

/// The Oche application: a [Router] that can also listen for HTTP requests.
///
/// ```dart
/// import 'package:oche/oche.dart';
///
/// Future<void> main() async {
///   final app = Oche();
///
///   app.get('/', (req, res) => res.send('Hello World!'));
///
///   await app.listen(3000, () => print('Listening on port 3000'));
/// }
/// ```
///
/// Since [Oche] extends [Router], everything a router can do (`use`, `get`,
/// `post`, `put`, `delete`, `all`...) is available directly on the app.
class Oche extends Router {
  /// Creates an application.
  ///
  /// [host] is the address the server binds to when [listen] is called. It
  /// can be a [String] or an [InternetAddress]. The default `'0.0.0.0'`
  /// accepts connections on every IPv4 interface. Use `'localhost'` to accept
  /// only local connections.
  Oche({super.caseSensitive, this.host = '0.0.0.0'});

    /// Parses JSON bodies into `req.body`. See [jsonBodyParser].
  static Middleware json({int limit = defaultBodyLimit}) =>
      jsonBodyParser(limit: limit);

  /// Parses form bodies into `req.body`. See [urlencodedBodyParser].
  static Middleware urlencoded({int limit = defaultBodyLimit}) =>
      urlencodedBodyParser(limit: limit);

  /// Serves the files of a directory. See [staticFiles].
  static Middleware serveStatic(
    String directory, {
    String index = 'index.html',
    Duration? maxAge,
    bool serveDotfiles = false,
  }) =>
      staticFiles(
        directory,
        index: index,
        maxAge: maxAge,
        serveDotfiles: serveDotfiles,
      );

  /// Adds CORS headers and answers preflight requests. See [corsMiddleware].
  static Middleware cors({
    String origin = '*',
    List<String> methods = const <String>[
      'GET',
      'HEAD',
      'PUT',
      'PATCH',
      'POST',
      'DELETE',
    ],
    List<String>? allowedHeaders,
    bool credentials = false,
    int? maxAge,
  }) =>
      corsMiddleware(
        origin: origin,
        methods: methods,
        allowedHeaders: allowedHeaders,
        credentials: credentials,
        maxAge: maxAge,
      );

  /// Logs one line per request. See [requestLogger].
  static Middleware logger({void Function(String line)? output}) =>
      requestLogger(output: output);

    /// Gives every request a session in `req.session`. See [sessionMiddleware].
  static Middleware session({
    required String secret,
    SessionStore? store,
    String cookieName = 'oche.sid',
    Duration maxAge = const Duration(days: 1),
    String path = '/',
    String? domain,
    bool secure = false,
    bool httpOnly = true,
    bool rolling = false,
  }) =>
      sessionMiddleware(
        secret: secret,
        store: store,
        cookieName: cookieName,
        maxAge: maxAge,
        path: path,
        domain: domain,
        secure: secure,
        httpOnly: httpOnly,
        rolling: rolling,
      );

      /// Protects routes with a JWT and fills `req.user`. See [jwtMiddleware].
  static Middleware jwt({
    required String secret,
    List<String> algorithms = const <String>['HS256'],
    String? issuer,
    String? audience,
    Duration clockTolerance = Duration.zero,
    bool credentialsRequired = true,
    String? Function(Request req)? getToken,
  }) =>
      jwtMiddleware(
        secret: secret,
        algorithms: algorithms,
        issuer: issuer,
        audience: audience,
        clockTolerance: clockTolerance,
        credentialsRequired: credentialsRequired,
        getToken: getToken,
      );

  /// The address the server binds to. See the constructor.
  final Object host;

  ErrorHandler _errorHandler = defaultErrorHandler;
  HttpServer? _server;

  /// The underlying `dart:io` server, or `null` before [listen] completes.
  HttpServer? get server => _server;

    Views? _views;

  /// Data available in every template (like `app.locals` in Express).
  ///
  /// ```dart
  /// app.locals['appName'] = 'My site';
  /// ```
  final Map<String, Object?> locals = <String, Object?>{};

  /// Turns on templates, so `res.render` works.
  ///
  /// [directory] is the folder with the template files. The default engine is
  /// [OcheEngine]; pass [engine] to use another one. Set [cache] to `true` in
  /// production to keep the templates in memory.
  ///
  /// ```dart
  /// app.views('views');
  /// app.views('views', engine: MyEngine(), cache: true);
  /// ```
  void views(String directory, {ViewEngine? engine, bool cache = false}) {
    _views = Views(
      directory,
      engine ?? const OcheEngine(),
      cache: cache,
      globals: locals,
    );
  }

  /// Replaces the function that turns errors into responses.
  ///
  /// It runs when a handler throws, or when a middleware calls
  /// `next(error)`:
  ///
  /// ```dart
  /// app.onError((error, req, res) {
  ///   if (error is HttpError) {
  ///     res.status(error.statusCode).json({'error': error.message});
  ///   } else {
  ///     res.status(500).json({'error': 'Something went wrong'});
  ///   }
  /// });
  /// ```
  void onError(ErrorHandler handler) => _errorHandler = handler;

  /// Starts the HTTP server on [port] and returns it.
  ///
  /// The optional [callback] runs once the server is ready to accept
  /// connections, like the callback of `app.listen` in Express.
  ///
  /// ```dart
  /// await app.listen(3000, () => print('Ready!'));
  /// ```
  ///
  /// The returned future fails when the port cannot be bound, for example
  /// when it is already in use.
  Future<HttpServer> listen(int port, [void Function()? callback]) async {
    final server = await HttpServer.bind(host, port);
    _server = server;
    server.listen(_handle);
    callback?.call();
    return server;
  }

  /// Stops the server.
  ///
  /// By default, in-flight requests are allowed to finish. With [force] set
  /// to `true`, open connections are closed immediately.
  Future<void> close({bool force = false}) async {
    await _server?.close(force: force);
    _server = null;
  }

  Future<void> _handle(HttpRequest raw) async {
    final req = Request(raw);
    final res = Response(raw.response);

    res.views = _views;

    try {
      call(req, res, ([Object? error]) {
        if (error == null) {
          _notFound(req, res);
        } else {
          unawaited(_fail(error, req, res));
        }
      });
    } catch (error) {
      await _fail(error, req, res);
    }
  }

  /// Runs when no route or middleware has handled the request.
  void _notFound(Request req, Response res) {
    if (res.finished) return;
    res.status(404).type('text').send('Cannot ${req.method} ${req.originalUrl}');
  }

  Future<void> _fail(Object error, Request req, Response res) async {
    if (res.finished) {
      // Too late to change the response: just make the error visible.
      stderr.writeln('Error after the response was sent: $error');
      return;
    }

    try {
      await _errorHandler(error, req, res);
    } catch (_) {
      // The error handler itself failed: fall back to a plain 500.
      try {
        if (!res.finished) {
          res.status(500).type('text').send('Internal Server Error');
        }
      } catch (_) {
        // The connection is gone; nothing else can be done.
      }
    }
  }
}
import '../session/session.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// An incoming HTTP request.
///
/// Wraps the [HttpRequest] from `dart:io` and exposes an Express-like API:
///
/// ```dart
/// app.get('/users/:id', (req, res) {
///   final id = req.params['id'];
///   final page = req.query['page'];
///   res.json({'id': id, 'page': page});
/// });
/// ```
class Request {
  /// Creates a request that wraps the given [raw] `dart:io` request.
  Request(this.raw) : path = raw.uri.path;

  /// The underlying `dart:io` request.
  ///
  /// Use it as an escape hatch when the Express-like API is not enough.
  final HttpRequest raw;

  /// Route parameters extracted from the matched path.
  ///
  /// For a route declared as `/users/:id` and a request to `/users/42`,
  /// `params['id']` is `'42'`. It is filled in by the router.
  Map<String, String> params = <String, String>{};

  /// The parsed request body.
  ///
  /// It is `null` until a body-parsing middleware (such as the JSON or
  /// urlencoded parsers) fills it in. For raw access use [bytes] or [text].
  Object? body;

  /// The authenticated user's data (the token claims).
  ///
  /// It is set by an authentication middleware such as `Oche.jwt`, and is
  /// `null` when the request is not authenticated.
  Map<String, Object?>? user;

  /// A per-request storage shared between middlewares and handlers.
  ///
  /// ```dart
  /// app.use((req, res, next) {
  ///   req.locals['startedAt'] = DateTime.now();
  ///   next();
  /// });
  /// ```
  final Map<String, Object?> locals = <String, Object?>{};

    Session? _session;

  /// The session of this request.
  ///
  /// It is filled in by the session middleware. Reading it without that
  /// middleware installed throws a [StateError].
  Session get session {
    final session = _session;
    if (session == null) {
      throw StateError(
        'No session available. Install the session middleware first: '
        "app.use(Oche.session(secret: '...'));",
      );
    }
    return session;
  }

  set session(Session value) => _session = value;

  /// The HTTP method in upper case, such as `GET` or `POST`.
  String get method => raw.method.toUpperCase();

  /// The full request URI, including path and query string.
  Uri get uri => raw.uri;

  /// The request path, without the query string. Example: `/users/42`.
  ///
  /// Behind a mount point such as `app.use('/api', router)`, the mount prefix
  /// is removed while the router runs, just like in Express. For a request to
  /// `/api/users`, handlers inside the router see `/users`. The removed prefix
  /// is available in [baseUrl] and the untouched URL in [originalUrl].
  ///
  /// It is written by the router; application code should only read it.
  String path;

  /// The mount prefix that was stripped from [path] by the current router.
  ///
  /// It is an empty string at the top level. Inside `app.use('/api', router)`
  /// it is `/api`, and routers mounted inside it append to it.
  String baseUrl = '';

  /// The path plus the query string, exactly as received.
  String get originalUrl => raw.uri.toString();

  /// The query string parameters.
  ///
  /// For `/search?q=dart&page=2`, `query` is `{'q': 'dart', 'page': '2'}`.
  Map<String, String> get query => raw.uri.queryParameters;

  /// The request headers.
  HttpHeaders get headers => raw.headers;

  /// Returns the value of the header [name], or `null` when it is absent.
  ///
  /// Header names are case-insensitive.
  String? header(String name) => raw.headers.value(name);

  /// The MIME type of the body without parameters, such as
  /// `application/json`, or `null` when no `Content-Type` was sent.
  String? get contentType => raw.headers.contentType?.mimeType;

  /// Returns `true` when the request `Content-Type` is exactly [mimeType].
  ///
  /// ```dart
  /// if (req.isContentType('application/json')) { ... }
  /// ```
  bool isContentType(String mimeType) =>
      contentType?.toLowerCase() == mimeType.toLowerCase();

  /// The cookies sent by the client.
  List<Cookie> get cookies => raw.cookies;

  /// The IP address of the client, or `null` when it is not available.
  String? get ip => raw.connectionInfo?.remoteAddress.address;

  /// The protocol of the request, either `http` or `https`.
  String get protocol => raw.requestedUri.scheme;

  /// Whether the request was made over a secure connection (HTTPS).
  bool get isSecure => protocol == 'https';

  /// The host name the client used to reach the server.
  String get hostname => raw.requestedUri.host;

  Future<List<int>>? _bytes;

  /// Reads the whole request body as bytes.
  ///
  /// A `dart:io` request body is a single-subscription stream, so it can only
  /// be consumed once. The result is cached, which makes it safe to call
  /// [bytes] and [text] several times, for example from different middlewares.
  Future<List<int>> bytes() => _bytes ??= _readBody();

  /// Reads the whole request body as a string decoded with [encoding].
  ///
  /// Defaults to UTF-8.
  Future<String> text({Encoding encoding = utf8}) async =>
      encoding.decode(await bytes());

  Future<List<int>> _readBody() async {
    final builder = await raw.fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (BytesBuilder b, Uint8List chunk) => b..add(chunk),
    );
    return builder.takeBytes();
  }
}

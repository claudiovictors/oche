import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/http_error.dart';
import 'status.dart';
import '../view/views.dart';

/// An outgoing HTTP response.
///
/// Wraps the [HttpResponse] from `dart:io` and exposes an Express-like API.
/// Most setters return the response itself, so calls can be chained:
///
/// ```dart
/// app.post('/users', (req, res) {
///   res.status(201).set('X-Powered-By', 'oche').json({'created': true});
/// });
/// ```
///
/// A response can be sent only once. Calling [send], [json], [sendStatus],
/// [redirect], [sendFile] or [end] a second time throws a [StateError].
class Response {
    /// Creates a response that wraps the given [raw] `dart:io` response.
  Response(this.raw) {
    // dart:io pre-fills "content-type: text/plain" on every response. Remove
    // it, so a type is only set when the user or the framework chooses one.
    raw.headers.removeAll(HttpHeaders.contentTypeHeader);
  }

  /// The underlying `dart:io` response.
  ///
  /// Use it as an escape hatch when the Express-like API is not enough.
  final HttpResponse raw;

  bool _finished = false;
  final List<FutureOr<void> Function()> _beforeSend =
      <FutureOr<void> Function()>[];

  /// Data available to the templates rendered through this response.
  ///
  /// Handy to share values between middlewares and `render`, like the logged
  /// user. It is merged over `app.locals`, and the data passed to [render]
  /// wins over both.
  final Map<String, Object?> locals = <String, Object?>{};

  /// The view setup of the application. Set by `Oche` before the handlers
  /// run, and `null` until `app.views(...)` is called.
  Views? views;

  /// Whether the response has already been sent.
  ///
  /// Middlewares can check it to avoid writing twice.
  bool get finished => _finished;

  /// The current status code of the response.
  int get statusCode => raw.statusCode;

  /// Registers a [hook] that runs just before the response is written.
  ///
  /// Hooks may be asynchronous and run in the order they were added. While
  /// they run, headers can still be changed, which makes this the right place
  /// to save state and set cookies (the session middleware does exactly that).
  ///
  /// If a hook throws, the client receives a `500 Internal Server Error`.
  ///
  /// Throws a [StateError] when the response was already sent.
  void onBeforeSend(FutureOr<void> Function() hook) {
    if (_finished) {
      throw StateError('The response has already been sent.');
    }
    _beforeSend.add(hook);
  }

  /// Sets the HTTP status [code] and returns this response for chaining.
  ///
  /// ```dart
  /// res.status(404).send('Not here');
  /// ```
  Response status(int code) {
    raw.statusCode = code;
    return this;
  }

  /// Sets the header [name] to [value], replacing any previous value.
  Response set(String name, Object value) {
    raw.headers.set(name, value);
    return this;
  }

  /// Adds [value] to the header [name], keeping any previous values.
  Response append(String name, Object value) {
    raw.headers.add(name, value);
    return this;
  }

  /// Returns the value of the response header [name], or `null`.
  String? get(String name) => raw.headers.value(name);

  /// Sets the `Content-Type` header.
  ///
  /// [value] can be a full MIME type or a short name:
  ///
  /// ```dart
  /// res.type('json');             // application/json; charset=utf-8
  /// res.type('text/csv');         // text/csv; charset=utf-8
  /// res.type('image/png');        // image/png
  /// ```
  ///
  /// Text and JSON types get `charset=utf-8` unless one is given.
  Response type(String value) {
    final mime = value.contains('/')
        ? value
        : (_mimeByName[value.replaceFirst('.', '').toLowerCase()] ??
            'application/octet-stream');
    final parsed = ContentType.parse(mime);
    final isText = parsed.primaryType == 'text' || parsed.subType == 'json';
    raw.headers.contentType = parsed.charset == null && isText
        ? ContentType(parsed.primaryType, parsed.subType, charset: 'utf-8')
        : parsed;
    return this;
  }

  /// Adds a `Set-Cookie` header.
  ///
  /// The cookie value is URI-encoded. Cookies are `httpOnly` by default.
  ///
  /// ```dart
  /// res.cookie('theme', 'dark', maxAge: Duration(days: 30));
  /// ```
  Response cookie(
    String name,
    String value, {
    Duration? maxAge,
    DateTime? expires,
    String? domain,
    String path = '/',
    bool secure = false,
    bool httpOnly = true,
  }) {
    final cookie = Cookie(name, Uri.encodeComponent(value))
      ..path = path
      ..domain = domain
      ..secure = secure
      ..httpOnly = httpOnly
      ..expires = expires
      ..maxAge = maxAge?.inSeconds;
    raw.cookies.add(cookie);
    return this;
  }

  /// Tells the client to delete the cookie [name].
  ///
  /// [path] and [domain] must match the ones used when the cookie was set.
  Response clearCookie(String name, {String path = '/', String? domain}) {
    final cookie = Cookie(name, '')
      ..path = path
      ..domain = domain
      ..maxAge = 0
      ..expires = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    raw.cookies.add(cookie);
    return this;
  }

    /// Renders the template [view] with [data] and sends it as HTML.
  ///
  /// ```dart
  /// app.get('/home', (req, res) => res.render('index', {'title': 'Hey'}));
  /// ```
  ///
  /// The name has no extension, and dots work as folders:
  /// `res.render('admin.users.index')` reads `admin/users/index.html`.
  ///
  /// Throws a [StateError] when `app.views(...)` was not called, and a
  /// `TemplateError` when the template is missing or invalid.
  Future<void> render(
    String view, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) async {
    final config = views;
    if (config == null) {
      throw StateError(
        "No views configured. Call app.views('views') before res.render.",
      );
    }
    send(await config.render(view, <String, Object?>{...locals, ...data}));
  }

  /// Sends the response with [body] and finishes it.
  ///
  /// The `Content-Type` is chosen from the type of [body], unless it was
  /// already set with [type] or [set]:
  ///
  /// * `null` — empty body.
  /// * [String] — `text/html; charset=utf-8`.
  /// * `List<int>` — `application/octet-stream` (raw bytes).
  /// * [Map] and [List] — encoded as JSON, same as [json].
  /// * anything else — `toString()` as `text/plain; charset=utf-8`.
  void send([Object? body]) {
    switch (body) {
      case null:
        end();
      case String text:
        _ensureType(ContentType.html);
        _write(utf8.encode(text));
      case List<int> bytes:
        _ensureType(ContentType.binary);
        _write(bytes);
      case Map<dynamic, dynamic>() || List<dynamic>():
        json(body);
      default:
        _ensureType(ContentType.text);
        _write(utf8.encode(body.toString()));
    }
  }

  /// Sends [data] encoded as JSON with `application/json; charset=utf-8`.
  ///
  /// [data] must be encodable by [jsonEncode]. Objects with a `toJson()`
  /// method are supported.
  ///
  /// ```dart
  /// res.json({'name': 'Suzana', 'langs': ['Dart', 'Go', 'PHP']});
  /// ```
  void json(Object? data) {
    _ensureType(ContentType.json);
    _write(utf8.encode(jsonEncode(data)));
  }

  /// Sets the status to [code] and sends its reason phrase as the body.
  ///
  /// ```dart
  /// res.sendStatus(404); // 404 with body "Not Found"
  /// ```
  void sendStatus(int code) {
    raw.statusCode = code;
    _ensureType(ContentType.text);
    send(reasonPhraseFor(code));
  }

  /// Redirects the client to [url] with the status [code] (default `302`).
  void redirect(String url, [int code = HttpStatus.found]) {
    raw.statusCode = code;
    raw.headers.set(HttpHeaders.locationHeader, url);
    end();
  }

  /// Sends the file at [path], streaming it from disk.
  ///
  /// The `Content-Type` is derived from the file extension (unless it was
  /// already set), and `Content-Length` and `Last-Modified` are filled in.
  /// With [headOnly], only the headers are sent, which is what `HEAD`
  /// requests need.
  ///
  /// ```dart
  /// app.get('/report', (req, res) => res.sendFile('files/report.pdf'));
  /// ```
  ///
  /// Throws an [HttpError] with status `404` when [path] is not a file.
  Future<void> sendFile(String path, {bool headOnly = false}) async {
    final file = File(path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) throw HttpError.notFound();

    _markFinished();
    if (!await _runBeforeSend()) {
      _flushFailure();
      return;
    }

    if (raw.headers.contentType == null) type(p.extension(path));
    raw.headers.set(HttpHeaders.lastModifiedHeader, stat.modified.toUtc());
    raw.contentLength = stat.size;

    if (!headOnly) await raw.addStream(file.openRead());
    await raw.close();
  }

  /// Finishes the response without a body.
  void end() => _write(const <int>[]);

  void _ensureType(ContentType type) {
    raw.headers.contentType ??= type;
  }

  void _markFinished() {
    if (_finished) {
      throw StateError('The response has already been sent.');
    }
    _finished = true;
  }

  void _write(List<int> bytes) {
    _markFinished();

    if (_beforeSend.isEmpty) {
      _flush(bytes);
      return;
    }
    unawaited(_flushAfterHooks(bytes));
  }

  Future<void> _flushAfterHooks(List<int> bytes) async {
    if (await _runBeforeSend()) {
      _flush(bytes);
    } else {
      _flushFailure();
    }
  }

  /// Runs the before-send hooks. Returns `false` when one of them failed.
  Future<bool> _runBeforeSend() async {
    try {
      for (final hook in _beforeSend) {
        await hook();
      }
      return true;
    } catch (error) {
      stderr.writeln('A before-send hook failed: $error');
      return false;
    }
  }

  void _flushFailure() {
    raw.statusCode = HttpStatus.internalServerError;
    raw.headers.contentType = ContentType.text;
    _flush(utf8.encode('Internal Server Error'));
  }

  void _flush(List<int> bytes) {
    // 204 and 304 responses must not carry a body.
    final bodyAllowed = raw.statusCode != HttpStatus.noContent &&
        raw.statusCode != HttpStatus.notModified;
    if (bodyAllowed) {
      raw.contentLength = bytes.length;
      if (bytes.isNotEmpty) raw.add(bytes);
    }
    raw.close().ignore();
  }
}

const Map<String, String> _mimeByName = <String, String>{
  'html': 'text/html',
  'text': 'text/plain',
  'txt': 'text/plain',
  'css': 'text/css',
  'csv': 'text/csv',
  'js': 'text/javascript',
  'json': 'application/json',
  'xml': 'application/xml',
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'svg': 'image/svg+xml',
  'ico': 'image/x-icon',
  'webp': 'image/webp',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'mp3': 'audio/mpeg',
  'mp4': 'video/mp4',
  'wasm': 'application/wasm',
  'map': 'application/json',
};  
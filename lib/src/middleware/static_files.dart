import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/http_error.dart';
import '../http/request.dart';
import '../http/response.dart';
import 'middleware.dart';

/// Creates a middleware that serves the files of [directory].
///
/// ```dart
/// app.use('/static', Oche.serveStatic('public'));
/// // GET /static/logo.png  ->  public/logo.png
/// ```
///
/// * Only `GET` and `HEAD` requests are handled. When no file matches, the
///   request continues to the next middleware, so a 404 is still possible.
/// * A request for a directory serves its [index] file.
/// * Paths that try to leave [directory] (such as `/../secret`) fail with
///   `403 Forbidden`.
/// * Files and folders starting with a dot (like `.env`) are ignored unless
///   [serveDotfiles] is `true`.
/// * When [maxAge] is set, a `Cache-Control: public, max-age=...` header is
///   added.
Middleware staticFiles(
  String directory, {
  String index = 'index.html',
  Duration? maxAge,
  bool serveDotfiles = false,
}) {
  final root = p.normalize(p.absolute(directory));

  return (Request req, Response res, Next next) async {
    if (req.method != 'GET' && req.method != 'HEAD') {
      next();
      return;
    }

    final String decoded;
    try {
      decoded = Uri.decodeComponent(req.path);
    } on FormatException {
      throw HttpError.badRequest('Malformed URL');
    }
    if (decoded.contains('\u0000')) throw HttpError.badRequest('Malformed URL');

    final relative = decoded.replaceFirst(RegExp(r'^/+'), '');

    final hasDotSegment = p
        .split(relative)
        .any((s) => s.startsWith('.') && s != '.' && s != '..');
    if (hasDotSegment && !serveDotfiles) {
      next();
      return;
    }

    var target = p.normalize(p.join(root, relative));
    if (target != root && !p.isWithin(root, target)) {
      throw HttpError.forbidden();
    }

    var type = await FileSystemEntity.type(target);
    if (type == FileSystemEntityType.directory) {
      target = p.join(target, index);
      type = await FileSystemEntity.type(target);
    }
    if (type != FileSystemEntityType.file) {
      next();
      return;
    }

    if (maxAge != null) {
      res.set('Cache-Control', 'public, max-age=${maxAge.inSeconds}');
    }
    await res.sendFile(target, headOnly: req.method == 'HEAD');
  };
}
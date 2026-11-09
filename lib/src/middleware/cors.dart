import '../http/request.dart';
import '../http/response.dart';
import 'middleware.dart';

/// Creates a middleware that adds CORS headers and answers preflight
/// (`OPTIONS`) requests.
///
/// ```dart
/// app.use(Oche.cors());                                   // any origin
/// app.use(Oche.cors(origin: 'https://myapp.com', credentials: true));
/// ```
///
/// * [origin] is sent in `Access-Control-Allow-Origin`.
/// * [methods] are the methods allowed in preflight answers.
/// * [allowedHeaders] are the request headers allowed in preflight answers.
///   When `null`, the headers asked by the browser are echoed back.
/// * [credentials] allows cookies and authorization headers. It cannot be
///   combined with the `'*'` origin, which the CORS spec forbids.
/// * [maxAge] is how many seconds the browser may cache the preflight answer.
///
/// Throws an [ArgumentError] when [credentials] is `true` and [origin] is `'*'`.
Middleware corsMiddleware({
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
}) {
  if (credentials && origin == '*') {
    throw ArgumentError(
      'CORS: "credentials" cannot be used with the "*" origin. '
      'Pass an explicit origin.',
    );
  }

  return (Request req, Response res, Next next) {
    res.set('Access-Control-Allow-Origin', origin);
    if (origin != '*') res.append('Vary', 'Origin');
    if (credentials) res.set('Access-Control-Allow-Credentials', 'true');

    final isPreflight = req.method == 'OPTIONS' &&
        req.header('access-control-request-method') != null;
    if (!isPreflight) {
      next();
      return;
    }

    res.set('Access-Control-Allow-Methods', methods.join(','));

    final headers = allowedHeaders?.join(',') ??
        req.header('access-control-request-headers');
    if (headers != null) res.set('Access-Control-Allow-Headers', headers);

    if (maxAge != null) res.set('Access-Control-Max-Age', '$maxAge');

    res.status(204).end();
  };
}
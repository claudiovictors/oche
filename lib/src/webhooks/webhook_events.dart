import '../http/request.dart';
import '../http/response.dart';
import '../middleware/middleware.dart';

/// Routes a webhook to a handler according to its event name.
///
/// ```dart
/// final github = WebhookEvents();
///
/// github.on('push', (req, res) {
///   print('Push received');
/// });
/// github.on('issues', (req, res) async { ... });
///
/// app.webhook(
///   '/hooks/github',
///   github.handle,
///   verifier: HmacVerifier.github('my-secret'),
/// );
/// ```
///
/// Senders retry deliveries that do not get a `2xx` answer, so [handle]
/// answers `200` by itself when the handler does not send a response, and
/// also for events nobody is listening to. If a handler throws, the error
/// goes to the application's error handler (usually a `500`), which makes the
/// sender try again later.
class WebhookEvents {
  /// Creates an empty event router.
  ///
  /// [resolveEvent] tells which event a request carries. By default it reads
  /// the `X-GitHub-Event` or `X-Event-Key` header, then the `type` or `event`
  /// field of a JSON body (which covers GitHub, Stripe and many others).
  WebhookEvents({String? Function(Request req)? resolveEvent})
      : _resolveEvent = resolveEvent ?? _defaultResolver;

  final String? Function(Request req) _resolveEvent;
  final Map<String, Handler> _handlers = <String, Handler>{};
  Handler? _fallback;

  /// Registers the [handler] for the event named [event].
  ///
  /// Registering the same event again replaces the previous handler.
  void on(String event, Handler handler) => _handlers[event] = handler;

  /// Registers a [handler] for events that have no handler of their own.
  void onUnknown(Handler handler) => _fallback = handler;

  /// The handler to pass to `app.webhook`.
  Future<void> handle(Request req, Response res) async {
    final event = _resolveEvent(req);
    final handler = (event == null ? null : _handlers[event]) ?? _fallback;

    if (handler != null) await handler(req, res);
    if (!res.finished) res.sendStatus(200);
  }

  static String? _defaultResolver(Request req) {
    final fromHeader = req.header('x-github-event') ?? req.header('x-event-key');
    if (fromHeader != null) return fromHeader;

    final body = req.body;
    if (body is Map) {
      final event = body['type'] ?? body['event'];
      if (event is String) return event;
    }
    return null;
  }
}
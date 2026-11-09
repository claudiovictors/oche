import 'cookie_signature.dart';

/// The data of one visitor, kept between requests.
///
/// Available as `req.session` once the session middleware is installed:
///
/// ```dart
/// app.use(Oche.session(secret: 'a-long-random-secret'));
///
/// app.get('/visits', (req, res) {
///   final visits = (req.session.get<int>('visits') ?? 0) + 1;
///   req.session['visits'] = visits;
///   res.json({'visits': visits});
/// });
/// ```
///
/// Values must be JSON-encodable (numbers, strings, booleans, lists and maps),
/// because stores may serialize them.
class Session {
  /// Creates a session. It is built by the session middleware; application
  /// code normally just uses `req.session`.
  Session(this._id, {Map<String, Object?>? data, this.isNew = true})
      : _data = Map<String, Object?>.of(data ?? const <String, Object?>{});

  String _id;
  final Map<String, Object?> _data;
  String? _previousId;
  bool _modified = false;
  bool _destroyed = false;

  /// The session identifier stored (signed) in the cookie.
  String get id => _id;

  /// Whether the session was created during this request, meaning the client
  /// did not send a valid session cookie.
  final bool isNew;

  /// Whether any value was written since the session was loaded.
  ///
  /// Sessions that were never modified are not saved, so anonymous visitors
  /// do not create empty sessions.
  bool get isModified => _modified;

  /// Whether [destroy] was called.
  bool get isDestroyed => _destroyed;

  /// The id this session had before [regenerate], or `null`.
  ///
  /// The middleware uses it to remove the old entry from the store.
  String? get previousId => _previousId;

  /// Returns the value stored under [key], or `null`.
  Object? operator [](String key) => _data[key];

  /// Stores [value] under [key].
  void operator []=(String key, Object? value) {
    _data[key] = value;
    _modified = true;
  }

  /// Returns the value stored under [key] when it is a [T], otherwise `null`.
  ///
  /// ```dart
  /// final userId = req.session.get<int>('userId');
  /// ```
  T? get<T>(String key) {
    final value = _data[key];
    return value is T ? value : null;
  }

  /// Whether a value exists under [key].
  bool containsKey(String key) => _data.containsKey(key);

  /// Removes [key] and returns its previous value, or `null`.
  Object? remove(String key) {
    if (!_data.containsKey(key)) return null;
    _modified = true;
    return _data.remove(key);
  }

  /// Removes every value, keeping the same session id.
  void clear() {
    if (_data.isEmpty) return;
    _data.clear();
    _modified = true;
  }

  /// An unmodifiable copy of the session data.
  Map<String, Object?> toMap() => Map<String, Object?>.unmodifiable(_data);

  /// Gives the session a new id, keeping its data.
  ///
  /// Call it right after a successful login: it prevents *session fixation*,
  /// where an attacker plants a known id in the victim's browser. The old id
  /// stops working.
  void regenerate() {
    _previousId ??= _id;
    _id = generateSessionId();
    _modified = true;
  }

  /// Ends the session: its data is deleted from the store and the cookie is
  /// cleared when the response is sent.
  ///
  /// Use it for logout.
  void destroy() {
    _destroyed = true;
  }
}
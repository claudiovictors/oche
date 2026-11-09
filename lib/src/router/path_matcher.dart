/// The result of a successful [PathMatcher.match].
class PathMatch {
  /// Creates a match result.
  const PathMatch({
    required this.params,
    required this.matchedPath,
    required this.remainingPath,
  });

  /// The route parameters extracted from the path.
  ///
  /// For the pattern `/users/:id` and the path `/users/42`, this is
  /// `{'id': '42'}`. A trailing wildcard (`*`) is stored under the key `'*'`.
  final Map<String, String> params;

  /// The part of the path that was consumed by the pattern, such as `/api`.
  ///
  /// It is empty when nothing was consumed (for example, a prefix match with
  /// the root pattern `/`).
  final String matchedPath;

  /// What is left of the path after [matchedPath], always starting with `/`.
  ///
  /// This is the path that a mounted router or middleware gets to see.
  final String remainingPath;
}

/// Compiles a path pattern, such as `/users/:id`, and matches request paths
/// against it.
///
/// Supported syntax:
///
/// * `/users` — a static segment.
/// * `/users/:id` — a named parameter that matches exactly one segment.
/// * `/files/*` — a wildcard that matches the rest of the path. It must be the
///   last segment and its value is stored under the key `'*'`.
///
/// Trailing slashes and repeated slashes are ignored, and matching is case
/// insensitive unless [caseSensitive] is `true`.
///
/// ```dart
/// final matcher = PathMatcher('/users/:id');
/// final match = matcher.match('/users/42');
/// print(match?.params); // {id: 42}
/// ```
///
/// With [end] set to `false` the pattern only has to match the *beginning* of
/// the path. This is how `app.use('/api', ...)` mounts work:
///
/// ```dart
/// final mount = PathMatcher('/api', end: false);
/// final match = mount.match('/api/users/42');
/// print(match?.matchedPath);   // /api
/// print(match?.remainingPath); // /users/42
/// ```
class PathMatcher {
  /// Creates a matcher for the given [pattern].
  ///
  /// Throws an [ArgumentError] when the pattern is invalid, for example when
  /// a parameter has no name or when `*` is not the last segment.
  PathMatcher(this.pattern, {this.end = true, this.caseSensitive = false})
      : _segments = _compile(pattern);

  /// The original pattern, such as `/users/:id`.
  final String pattern;

  /// Whether the pattern must match the whole path (`true`) or only its
  /// beginning (`false`).
  final bool end;

  /// Whether static segments are compared case sensitively.
  final bool caseSensitive;

  final List<_Segment> _segments;

  /// Matches [path] against the pattern.
  ///
  /// Returns a [PathMatch] on success and `null` otherwise. The [path] must
  /// not contain the query string. Parameter values are URI-decoded; when a
  /// value is not valid percent-encoding, the raw value is kept.
  PathMatch? match(String path) {
    final parts = _split(path);
    final params = <String, String>{};
    var consumed = 0;

    for (final segment in _segments) {
      switch (segment) {
        case _Wildcard():
          params['*'] = parts.skip(consumed).map(_decode).join('/');
          consumed = parts.length;
        case _Param(:final name):
          if (consumed >= parts.length) return null;
          params[name] = _decode(parts[consumed]);
          consumed++;
        case _Literal(:final value):
          if (consumed >= parts.length) return null;
          if (!_sameSegment(_decode(parts[consumed]), value)) return null;
          consumed++;
      }
    }

    if (end && consumed < parts.length) return null;

    if (consumed == 0) {
      // Nothing was consumed: leave the path exactly as it came.
      return PathMatch(params: params, matchedPath: '', remainingPath: path);
    }

    return PathMatch(
      params: params,
      matchedPath: '/${parts.take(consumed).join('/')}',
      remainingPath:
          consumed >= parts.length ? '/' : '/${parts.skip(consumed).join('/')}',
    );
  }

  bool _sameSegment(String a, String b) =>
      caseSensitive ? a == b : a.toLowerCase() == b.toLowerCase();

  static final RegExp _paramName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static List<String> _split(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  static String _decode(String part) {
    try {
      return Uri.decodeComponent(part);
    } on FormatException {
      return part;
    }
  }

  static List<_Segment> _compile(String pattern) {
    final parts = _split(pattern);
    final segments = <_Segment>[];

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];

      if (part == '*') {
        if (i != parts.length - 1) {
          throw ArgumentError.value(
            pattern,
            'pattern',
            'The wildcard "*" is only allowed as the last segment.',
          );
        }
        segments.add(const _Wildcard());
      } else if (part.startsWith(':')) {
        final name = part.substring(1);
        if (!_paramName.hasMatch(name)) {
          throw ArgumentError.value(
            pattern,
            'pattern',
            'Invalid parameter name "$name". Use letters, digits and "_".',
          );
        }
        segments.add(_Param(name));
      } else {
        segments.add(_Literal(part));
      }
    }
    return segments;
  }
}

sealed class _Segment {
  const _Segment();
}

final class _Literal extends _Segment {
  const _Literal(this.value);
  final String value;
}

final class _Param extends _Segment {
  const _Param(this.name);
  final String name;
}

final class _Wildcard extends _Segment {
  const _Wildcard();
}

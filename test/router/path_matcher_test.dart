import 'package:oche/src/router/path_matcher.dart';
import 'package:test/test.dart';

void main() {
  group('PathMatcher', () {
    test('matches the root path', () {
      expect(PathMatcher('/').match('/'), isNotNull);
      expect(PathMatcher('/').match('/users'), isNull);
    });

    test('matches static segments, ignoring case and trailing slash', () {
      final matcher = PathMatcher('/users');
      expect(matcher.match('/users'), isNotNull);
      expect(matcher.match('/USERS/'), isNotNull);
      expect(matcher.match('/users/42'), isNull);
    });

    test('respects caseSensitive', () {
      final matcher = PathMatcher('/users', caseSensitive: true);
      expect(matcher.match('/users'), isNotNull);
      expect(matcher.match('/Users'), isNull);
    });

    test('extracts named params', () {
      final match =
          PathMatcher('/users/:id/posts/:postId').match('/users/42/posts/7');
      expect(match, isNotNull);
      expect(match!.params, {'id': '42', 'postId': '7'});
    });

    test('does not match when a segment is missing', () {
      expect(PathMatcher('/users/:id').match('/users'), isNull);
    });

    test('decodes percent-encoded params', () {
      final match = PathMatcher('/files/:name').match('/files/hello%20world');
      expect(match!.params['name'], 'hello world');
    });

    test('wildcard captures the rest of the path', () {
      final match = PathMatcher('/files/*').match('/files/a/b/c.txt');
      expect(match!.params['*'], 'a/b/c.txt');
    });

    test('prefix mode strips the mount path', () {
      final match = PathMatcher('/api', end: false).match('/api/users/42');
      expect(match!.matchedPath, '/api');
      expect(match.remainingPath, '/users/42');
    });

    test('prefix mode returns "/" when the whole path is consumed', () {
      final match = PathMatcher('/api', end: false).match('/api');
      expect(match!.remainingPath, '/');
    });

    test('prefix mode on root leaves the path untouched', () {
      final match = PathMatcher('/', end: false).match('/anything/here');
      expect(match!.matchedPath, '');
      expect(match.remainingPath, '/anything/here');
    });

    test('prefix mode does not match a different prefix', () {
      expect(PathMatcher('/api', end: false).match('/apix/users'), isNull);
    });

    test('rejects a wildcard that is not the last segment', () {
      expect(() => PathMatcher('/*/x'), throwsArgumentError);
    });

    test('rejects a param without a name', () {
      expect(() => PathMatcher('/users/:'), throwsArgumentError);
    });
  });
}

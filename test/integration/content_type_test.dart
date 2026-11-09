import 'dart:convert';
import 'dart:io';

import 'package:oche_web/oche_web.dart';
import 'package:test/test.dart';

void main() {
  late Oche app;
  late HttpServer server;
  late HttpClient client;
  late Directory publicDir;

  Future<({int status, String? type, String body})> get(String path) async {
    final request = await client.get('127.0.0.1', server.port, path);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return (
      status: response.statusCode,
      type: response.headers.contentType?.mimeType,
      body: body,
    );
  }

  setUp(() async {
    publicDir = await Directory.systemTemp.createTemp('oche_test_');
    await File('${publicDir.path}/index.html').writeAsString('<h1>Hi</h1>');

    app = Oche(host: InternetAddress.loopbackIPv4);
    app.get('/json', (req, res) => res.json({'ok': true}));
    app.get('/html', (req, res) => res.send('<p>hi</p>'));
    app.get('/status', (req, res) => res.sendStatus(404));
    app.get('/csv', (req, res) => res.type('csv').send('a,b'));
    app.use('/static', Oche.serveStatic(publicDir.path));

    server = await app.listen(0);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await app.close(force: true);
    await publicDir.delete(recursive: true);
  });

  group('Content-Type', () {
    test('res.json sends application/json', () async {
      final response = await get('/json');

      expect(response.type, 'application/json');
      expect(response.body, '{"ok":true}');
    });

    test('res.send with a string sends text/html', () async {
      expect((await get('/html')).type, 'text/html');
    });

    test('res.sendStatus sends text/plain', () async {
      final response = await get('/status');

      expect(response.status, 404);
      expect(response.type, 'text/plain');
      expect(response.body, 'Not Found');
    });

    test('an explicit res.type wins', () async {
      expect((await get('/csv')).type, 'text/csv');
    });

    test('static files get their type from the extension', () async {
      final response = await get('/static/index.html');

      expect(response.type, 'text/html');
      expect(response.body, '<h1>Hi</h1>');
    });

    test('the default 404 is plain text', () async {
      final response = await get('/nowhere');

      expect(response.status, 404);
      expect(response.type, 'text/plain');
    });
  });
}
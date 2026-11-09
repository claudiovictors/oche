import 'package:oche/oche.dart';

Future<void> main() async {
  const jwtSecret = 'troque-por-um-segredo-com-32-caracteres-ou-mais';
  final app = Oche();

  app.use(Oche.logger());
  app.use(Oche.cors());
  app.use(Oche.json());
  app.use(Oche.urlencoded());
  app.use('/static', Oche.serveStatic('public'));

  app.use(Oche.session(secret: 'troque-por-um-segredo-longo-e-aleatorio'));

  app.views('views');
  app.locals['appName'] = 'Oche Demo';
  app.locals['year'] = DateTime.now().year;

  app.get('/', (req, res) => res.send('Hello World!'));
  app.post('/', (req, res) => res.send('Got a POST request'));
  app.put('/user', (req, res) => res.send('Got a PUT request at /user'));
  app.delete('/user', (req, res) => res.send('Got a DELETE request at /user'));

  // Route parameters and JSON.
  app.get('/users/:id', (req, res) => res.json({'id': req.params['id']}));

  // Errors: thrown exceptions become responses.
  app.get('/boom', (req, res) => throw HttpError.badRequest('Boom!'));

  // all + next
  app.all('/secret', (req, res, next) {
    print('Accessing the secret section ...');
    next();
  });
  app.get('/secret', (req, res) => res.send('Top secret'));

  // A mounted router.
  final api = Router();
  api.get('/ping', (req, res) => res.json({'pong': true}));
  app.use('/api', api);

  app.post('/echo', (req, res) => res.json({'received': req.body}));

    app.get('/visits', (req, res) {
    final visits = (req.session.get<int>('visits') ?? 0) + 1;
    req.session['visits'] = visits;
    res.json({'visits': visits});
  });

  app.post('/login', (req, res) {
    req.session.regenerate(); // evita session fixation
    req.session['userId'] = 1;
    res.json({'ok': true});
  });

  app.get('/me', (req, res) {
    final userId = req.session.get<int>('userId');
    if (userId == null) throw HttpError.unauthorized('Not logged in');
    res.json({'userId': userId});
  });

  app.post('/logout', (req, res) {
    req.session.destroy();
    res.json({'ok': true});
  });

    app.post('/auth/login', (req, res) {
    final body = req.body as Map<String, dynamic>? ?? <String, dynamic>{};
    if (body['email'] != 'user@example.com' || body['password'] != '1234') {
      throw HttpError.unauthorized('Wrong email or password');
    }

    final token = Jwt.sign(
      {'id': 1, 'email': body['email']},
      secret: jwtSecret,
      expiresIn: const Duration(hours: 1),
    );
    res.json({'token': token});
  });

  // Everything under /private requires a valid token.
  app.use('/private', Oche.jwt(secret: jwtSecret));
  app.get('/private/profile', (req, res) => res.json({'user': req.user}));
  
    // GitHub webhooks, routed by event name.
  final github = WebhookEvents();
  github.on('ping', (req, res) => print('GitHub says hello'));
  github.on('push', (req, res) {
    final body = req.body as Map<String, dynamic>;
    print('Push to ${body['repository']?['full_name']}');
  });
  app.webhook(
    '/hooks/github',
    github.handle,
    verifier: HmacVerifier.github('my-github-webhook-secret'),
  );

  // Generic webhook: HMAC-SHA256 (hex) in the X-Signature header.
  app.webhook('/hooks/generic', (req, res) {
    print('Webhook received: ${req.body}');
    res.sendStatus(200);
  }, secret: 'segredo');

    app.get('/home', (req, res) => res.render('index', {
        'user': {'name': 'Ana', 'age': 20, 'admin': false},
        'items': [
          {'name': 'Keyboard', 'price': 49.9},
          {'name': 'Mouse', 'price': 19.5},
        ],
        'banner': '<b>bold</b>',
    }));
  
  await app.listen(3000, () => print('Oche listening on http://localhost:3000'));
}
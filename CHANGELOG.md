## 0.1.0

Initial release.

- Express-like `Oche` application with `listen`, `close` and `onError`.
- Routing: `get`, `post`, `put`, `delete`, `patch`, `head`, `options`, `all`,
  route parameters, wildcards and mountable `Router`s.
- Middleware chain with `use` and `next`, including per-route middleware and
  error propagation.
- Built-in middleware: JSON and form body parsers, static files, CORS, logger.
- Sessions with signed cookies and a pluggable `SessionStore`.
- JWT (`HS256`, `HS384`, `HS512`) with a route-protecting middleware.
- Webhook receiving with HMAC verification (generic, GitHub, Stripe) and event
  routing.
- Views with `res.render` and a Blade-inspired template engine.
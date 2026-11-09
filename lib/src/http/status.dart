/// Returns the standard reason phrase for the HTTP [statusCode].
///
/// ```dart
/// reasonPhraseFor(404); // 'Not Found'
/// reasonPhraseFor(799); // 'Unknown'
/// ```
///
/// Only the most common codes are covered. Any other code yields `'Unknown'`.
String reasonPhraseFor(int statusCode) => _phrases[statusCode] ?? 'Unknown';

const Map<int, String> _phrases = <int, String>{
  // 2xx — Success
  200: 'OK',
  201: 'Created',
  202: 'Accepted',
  204: 'No Content',

  // 3xx — Redirection
  301: 'Moved Permanently',
  302: 'Found',
  303: 'See Other',
  304: 'Not Modified',
  307: 'Temporary Redirect',
  308: 'Permanent Redirect',

  // 4xx — Client errors
  400: 'Bad Request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not Found',
  405: 'Method Not Allowed',
  409: 'Conflict',
  410: 'Gone',
  413: 'Payload Too Large',
  415: 'Unsupported Media Type',
  422: 'Unprocessable Entity',
  429: 'Too Many Requests',

  // 5xx — Server errors
  500: 'Internal Server Error',
  501: 'Not Implemented',
  502: 'Bad Gateway',
  503: 'Service Unavailable',
  504: 'Gateway Timeout',
};

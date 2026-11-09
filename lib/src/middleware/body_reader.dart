import '../errors/http_error.dart';
import '../http/request.dart';

/// Default maximum size, in bytes, of a request body read by the built-in
/// body parsers (1 MiB).
const int defaultBodyLimit = 1024 * 1024;

/// Reads the body of [req] and enforces a [limit] in bytes.
///
/// Throws an [HttpError] with status `413 Payload Too Large` when the body is
/// bigger than [limit]. A declared `Content-Length` is checked first, so
/// oversized uploads are rejected before they are read.
Future<List<int>> readBody(Request req, int limit) async {
  if (req.raw.contentLength > limit) throw HttpError(413);

  final bytes = await req.bytes();
  if (bytes.length > limit) throw HttpError(413);
  return bytes;
}
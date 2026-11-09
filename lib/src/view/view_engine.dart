/// Reads the source of a template by its name.
///
/// Engines call it to load the template being rendered and any other
/// template it pulls in (includes, layouts).
typedef TemplateLoader = Future<String> Function(String name);

/// Turns a template and some data into text, usually HTML.
///
/// [OcheEngine] is the built-in implementation. To use another template
/// library, implement this interface:
///
/// ```dart
/// class MustacheEngine implements ViewEngine {
///   @override
///   String get extension => 'mustache';
///
///   @override
///   Future<String> render(
///     String name,
///     Map<String, Object?> data,
///     TemplateLoader loader,
///   ) async {
///     final source = await loader(name);
///     return Template(source).renderString(data);
///   }
/// }
///
/// app.views('views', engine: MustacheEngine());
/// ```
abstract interface class ViewEngine {
  /// The extension of the template files, without the dot (for example
  /// `html`). `res.render('index')` reads `index.<extension>`.
  String get extension;

  /// Renders the template called [name] with [data].
  ///
  /// [loader] returns the source of any template by name.
  Future<String> render(
    String name,
    Map<String, Object?> data,
    TemplateLoader loader,
  );
}

/// Thrown when a template cannot be found, parsed or rendered.
///
/// It carries the template name and, when known, the line of the problem.
class TemplateError implements Exception {
  /// Creates an error with a [message] and optional location.
  const TemplateError(this.message, {this.template, this.line});

  /// What went wrong.
  final String message;

  /// The name of the template where the problem happened.
  final String? template;

  /// The line (starting at 1) where the problem happened.
  final int? line;

  @override
  String toString() {
    final where = <String>[
      if (template != null) 'template "$template"',
      if (line != null) 'line $line',
    ].join(', ');
    return where.isEmpty
        ? 'TemplateError: $message'
        : 'TemplateError ($where): $message';
  }
}
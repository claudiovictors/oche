import 'dart:io';

import 'package:path/path.dart' as p;

import 'view_engine.dart';

/// The view setup of an application: where the templates live, which engine
/// renders them, and the data shared by every template.
///
/// You normally create it through `app.views('views')` and render with
/// `res.render`.
class Views {
  /// Creates a view setup.
  ///
  /// * [directory] holds the template files.
  /// * [engine] renders them.
  /// * [cache] keeps template sources in memory after the first read. Turn it
  ///   on in production; leave it off in development to see edits without
  ///   restarting.
  /// * [globals] is data added to every render (`app.locals`).
  Views(
    String directory,
    this.engine, {
    this.cache = false,
    Map<String, Object?>? globals,
  })  : directory = p.normalize(p.absolute(directory)),
        globals = globals ?? <String, Object?>{};

  /// The absolute path of the templates folder.
  final String directory;

  /// The engine that renders the templates.
  final ViewEngine engine;

  /// Whether template sources are cached in memory.
  final bool cache;

  /// Data available in every template.
  final Map<String, Object?> globals;

  final Map<String, String> _sources = <String, String>{};

  static final RegExp _validName =
      RegExp(r'^[A-Za-z0-9_\-]+(?:[./][A-Za-z0-9_\-]+)*$');

  /// Renders the template [name] with [data] (merged over [globals]).
  Future<String> render(
    String name, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) =>
      engine.render(name, <String, Object?>{...globals, ...data}, load);

  /// Reads the source of the template [name].
  ///
  /// Throws a [TemplateError] when the name is invalid or the file does not
  /// exist.
  Future<String> load(String name) async {
    final cached = _sources[name];
    if (cache && cached != null) return cached;

    final file = File(pathOf(name));
    if (!await file.exists()) {
      throw TemplateError(
        'Template "$name" was not found (looked for ${file.path}).',
        template: name,
      );
    }

    final source = await file.readAsString();
    if (cache) _sources[name] = source;
    return source;
  }

  /// The file path of the template [name].
  ///
  /// Dots and slashes both separate folders, so `admin.users.index` and
  /// `admin/users/index` are the same template. The name must not include the
  /// file extension.
  String pathOf(String name) {
    if (!_validName.hasMatch(name) || name.contains('..')) {
      throw TemplateError('Invalid template name "$name".', template: name);
    }
    final relative = name.replaceAll('.', '/');
    return p.join(directory, '$relative.${engine.extension}');
  }
}
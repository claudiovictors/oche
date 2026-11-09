import 'expression.dart';
import 'template_parser.dart';
import 'view_engine.dart';

/// Escapes the characters that have a meaning in HTML: `& < > " '`.
String escapeHtml(String text) => text.replaceAllMapped(
      RegExp('[&<>"\']'),
      (m) => switch (m[0]) {
        '&' => '&amp;',
        '<' => '&lt;',
        '>' => '&gt;',
        '"' => '&quot;',
        _ => '&#39;',
      },
    );

/// The built-in template engine, with a syntax inspired by Laravel Blade.
///
/// ```html
/// @extends('layouts.main')
///
/// @section('content')
///   <h1>Hello, {{ user.name }}!</h1>
///
///   @if(user.age >= 18)
///     <p>Welcome.</p>
///   @else
///     <p>Sorry, adults only.</p>
///   @endif
///
///   <ul>
///     @foreach(items as item)
///       <li>{{ loop.iteration }}. {{ item.name }}</li>
///     @endforeach
///   </ul>
/// @endsection
/// ```
///
/// **Output**
///
/// * `{{ expression }}` prints the value with HTML escaped.
/// * `{!! expression !!}` prints it raw. Use it only with trusted content: it
///   opens the door to XSS attacks.
/// * `{{-- comment --}}` is removed.
/// * `@@` prints a literal `@`.
///
/// **Directives**
///
/// * `@if(cond)`, `@elseif(cond)`, `@else`, `@endif`.
/// * `@foreach(items as item)` and `@foreach(items as key => value)`, closed
///   by `@endforeach`. Inside, `loop` has `index` (from 0), `iteration` (from
///   1), `first`, `last` and `count`.
/// * `@include('partials.header')` renders another template with the current
///   variables.
/// * `@extends('layouts.main')` makes the template fill a layout. The layout
///   prints each `@section('name') ... @endsection` with `@yield('name')` or
///   `@yield('name', 'default text')`.
///
/// **Expressions** can use variables with dots (`user.name`, `items.0`,
/// `items.length`), strings, numbers, `true`, `false`, `null`, the operators
/// `== != < > <= >=`, `&&`, `||`, `!` and parentheses. A variable that does
/// not exist is `null` and prints as an empty string. Objects are read
/// through their `toJson()` method.
class OcheEngine implements ViewEngine {
  /// Creates the engine.
  ///
  /// [extension] is the extension of the template files and [maxDepth] limits
  /// nested includes and layouts, which stops infinite loops.
  const OcheEngine({this.extension = 'html', this.maxDepth = 32});

  @override
  final String extension;

  /// How many includes and layouts may be nested.
  final int maxDepth;

  @override
  Future<String> render(
    String name,
    Map<String, Object?> data,
    TemplateLoader loader,
  ) =>
      _Renderer(loader, maxDepth).renderTemplate(
        name,
        Scope(data),
        const <String, List<TemplateNode>>{},
        0,
      );
}

class _Renderer {
  _Renderer(this._load, this._maxDepth);

  final TemplateLoader _load;
  final int _maxDepth;

  Future<String> renderTemplate(
    String name,
    Scope scope,
    Map<String, List<TemplateNode>> sections,
    int depth,
  ) async {
    if (depth > _maxDepth) {
      throw TemplateError(
        'Templates are nested too deeply. Is there an @include or @extends '
        'loop?',
        template: name,
      );
    }

    final nodes = parseTemplate(await _load(name), name);

    // A child template only contributes its sections; the layout decides
    // where they go. Sections of the most specific template win.
    final parent = nodes.whereType<ExtendsNode>().firstOrNull;
    if (parent != null) {
      final own = <String, List<TemplateNode>>{
        for (final section in nodes.whereType<SectionNode>())
          section.name: section.body,
      };
      return renderTemplate(
        parent.name,
        scope,
        <String, List<TemplateNode>>{...own, ...sections},
        depth + 1,
      );
    }

    final out = StringBuffer();
    await _renderNodes(nodes, scope, sections, out, depth);
    return out.toString();
  }

  Future<void> _renderNodes(
    List<TemplateNode> nodes,
    Scope scope,
    Map<String, List<TemplateNode>> sections,
    StringBuffer out,
    int depth,
  ) async {
    for (final node in nodes) {
      switch (node) {
        case TextNode(:final text):
          out.write(text);

        case OutputNode(:final expression, :final escape):
          final value = expression.evaluate(scope);
          final text = value == null ? '' : value.toString();
          out.write(escape ? escapeHtml(text) : text);

        case IfNode(:final branches):
          for (final branch in branches) {
            final condition = branch.condition;
            if (condition == null || isTruthy(condition.evaluate(scope))) {
              await _renderNodes(branch.body, scope, sections, out, depth);
              break;
            }
          }

        case ForeachNode(
            :final source,
            :final valueName,
            :final keyName,
            :final body,
          ):
          final entries = _entries(source.evaluate(scope));
          for (var i = 0; i < entries.length; i++) {
            final vars = <String, Object?>{
              valueName: entries[i].value,
              if (keyName != null) keyName: entries[i].key,
              'loop': <String, Object?>{
                'index': i,
                'iteration': i + 1,
                'first': i == 0,
                'last': i == entries.length - 1,
                'count': entries.length,
              },
            };
            await _renderNodes(body, Scope(vars, scope), sections, out, depth);
          }

        case IncludeNode(:final name):
          out.write(
            await renderTemplate(
              name,
              scope,
              const <String, List<TemplateNode>>{},
              depth + 1,
            ),
          );

        case YieldNode(:final name, :final fallback):
          final section = sections[name];
          if (section != null) {
            await _renderNodes(section, scope, sections, out, depth);
          } else if (fallback != null) {
            out.write(fallback);
          }

        case ExtendsNode() || SectionNode():
          // Handled by renderTemplate. A section only prints where a layout
          // asks for it with @yield.
          break;
      }
    }
  }

  List<MapEntry<Object?, Object?>> _entries(Object? collection) =>
      switch (collection) {
        Map<Object?, Object?> map => <MapEntry<Object?, Object?>>[
            for (final entry in map.entries)
              MapEntry<Object?, Object?>(entry.key, entry.value),
          ],
        Iterable<Object?> items => <MapEntry<Object?, Object?>>[
            for (final (index, value) in items.indexed)
              MapEntry<Object?, Object?>(index, value),
          ],
        _ => const <MapEntry<Object?, Object?>>[],
      };
}
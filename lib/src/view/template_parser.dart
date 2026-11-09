import 'expression.dart';
import 'view_engine.dart';

/// A piece of a parsed template.
sealed class TemplateNode {
  /// Creates a node.
  const TemplateNode();
}

/// Plain text, copied as it is.
final class TextNode extends TemplateNode {
  /// Creates a text node.
  const TextNode(this.text);

  /// The text.
  final String text;
}

/// `{{ expression }}` (escaped) or `{!! expression !!}` (raw).
final class OutputNode extends TemplateNode {
  /// Creates an output node.
  const OutputNode(this.expression, this.escape);

  /// What to print.
  final Expression expression;

  /// Whether HTML special characters are escaped.
  final bool escape;
}

/// One `@if`, `@elseif` or `@else` branch. A `null` [condition] is `@else`.
final class IfBranch {
  /// Creates a branch.
  const IfBranch(this.condition, this.body);

  /// The condition, or `null` for `@else`.
  final Expression? condition;

  /// What is rendered when the branch is chosen.
  final List<TemplateNode> body;
}

/// `@if ... @elseif ... @else ... @endif`.
final class IfNode extends TemplateNode {
  /// Creates an if node.
  const IfNode(this.branches);

  /// The branches in order.
  final List<IfBranch> branches;
}

/// `@foreach(items as item)` or `@foreach(items as key => value)`.
final class ForeachNode extends TemplateNode {
  /// Creates a foreach node.
  const ForeachNode(this.source, this.valueName, this.keyName, this.body);

  /// The collection to loop over.
  final Expression source;

  /// The variable that holds each value.
  final String valueName;

  /// The variable that holds each key or index, when asked for.
  final String? keyName;

  /// What is rendered for each item.
  final List<TemplateNode> body;
}

/// `@include('partials.header')`.
final class IncludeNode extends TemplateNode {
  /// Creates an include node.
  const IncludeNode(this.name);

  /// The template to include.
  final String name;
}

/// `@extends('layouts.main')`.
final class ExtendsNode extends TemplateNode {
  /// Creates an extends node.
  const ExtendsNode(this.name);

  /// The layout this template fills.
  final String name;
}

/// `@section('name') ... @endsection`.
final class SectionNode extends TemplateNode {
  /// Creates a section node.
  const SectionNode(this.name, this.body);

  /// The section name.
  final String name;

  /// The content of the section.
  final List<TemplateNode> body;
}

/// `@yield('name')` or `@yield('name', 'fallback')`.
final class YieldNode extends TemplateNode {
  /// Creates a yield node.
  const YieldNode(this.name, this.fallback);

  /// The section to print.
  final String name;

  /// Text used when the section is not defined.
  final String? fallback;
}

/// Parses the [source] of the template called [name].
///
/// Throws a [TemplateError] with the line of the problem when the template is
/// not valid.
List<TemplateNode> parseTemplate(String source, String name) {
  final tokens = _Lexer(source, name).lex();
  return _Parser(tokens, source, name).parse();
}

int _lineOf(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

sealed class _Token {
  const _Token(this.offset);

  final int offset;
}

final class _Text extends _Token {
  const _Text(this.text) : super(0);

  final String text;
}

final class _Output extends _Token {
  const _Output(this.source, this.escape, super.offset);

  final String source;
  final bool escape;
}

final class _Directive extends _Token {
  const _Directive(this.name, this.argument, super.offset);

  final String name;
  final String? argument;
}

/// Splits a template into text, `{{ }}` outputs and `@directives`.
class _Lexer {
  _Lexer(this._source, this._name);

  final String _source;
  final String _name;

  static final RegExp _directive = RegExp(
    r'@(if|elseif|else|endif|foreach|endforeach|include|extends|section|endsection|yield)(?![A-Za-z0-9_])',
  );

  static const Set<String> _withArgument = <String>{
    'if',
    'elseif',
    'foreach',
    'include',
    'extends',
    'section',
    'yield',
  };

  TemplateError _error(String message, int offset) => TemplateError(
        message,
        template: _name,
        line: _lineOf(_source, offset),
      );

  List<_Token> lex() {
    final tokens = <_Token>[];
    final text = StringBuffer();
    var i = 0;

    void flush() {
      if (text.isEmpty) return;
      tokens.add(_Text(text.toString()));
      text.clear();
    }

    while (i < _source.length) {
      if (_source.startsWith('{{--', i)) {
        final end = _source.indexOf('--}}', i + 4);
        if (end < 0) throw _error('Unclosed comment, missing "--}}"', i);
        i = end + 4;
      } else if (_source.startsWith('{!!', i)) {
        final end = _source.indexOf('!!}', i + 3);
        if (end < 0) throw _error('Missing "!!}"', i);
        flush();
        tokens.add(_Output(_source.substring(i + 3, end), false, i));
        i = end + 3;
      } else if (_source.startsWith('{{', i)) {
        final end = _source.indexOf('}}', i + 2);
        if (end < 0) throw _error('Missing "}}"', i);
        flush();
        tokens.add(_Output(_source.substring(i + 2, end), true, i));
        i = end + 2;
      } else if (_source.startsWith('@@', i)) {
        text.write('@');
        i += 2;
      } else if (_source[i] == '@') {
        final match = _directive.matchAsPrefix(_source, i);
        if (match == null) {
          // Not a directive (an e-mail address, for example): keep it.
          text.write('@');
          i++;
          continue;
        }

        final name = match[1]!;
        var next = match.end;
        String? argument;

        if (_withArgument.contains(name)) {
          var open = next;
          while (open < _source.length &&
              (_source[open] == ' ' || _source[open] == '\t')) {
            open++;
          }
          if (open >= _source.length || _source[open] != '(') {
            throw _error('@$name needs an argument in parentheses', i);
          }
          final read = _readArgument(open);
          argument = read.inner;
          next = read.end;
        }

        flush();
        tokens.add(_Directive(name, argument, i));
        i = next;
      } else {
        text.write(_source[i]);
        i++;
      }
    }

    flush();
    return tokens;
  }

  /// Reads a parenthesized argument starting at [open], respecting quotes and
  /// nested parentheses.
  ({String inner, int end}) _readArgument(int open) {
    var depth = 0;
    String? quote;

    for (var i = open; i < _source.length; i++) {
      final c = _source[i];
      if (quote != null) {
        if (c == r'\') {
          i++;
        } else if (c == quote) {
          quote = null;
        }
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) {
          return (inner: _source.substring(open + 1, i), end: i + 1);
        }
      }
    }
    throw _error('Missing ")"', open);
  }
}

/// Builds the node tree from the tokens.
class _Parser {
  _Parser(this._tokens, this._source, this._name);

  final List<_Token> _tokens;
  final String _source;
  final String _name;
  int _pos = 0;

  static const Set<String> _closers = <String>{
    'elseif',
    'else',
    'endif',
    'endforeach',
    'endsection',
  };

  static final RegExp _foreachPattern = RegExp(
    r'^(.+?)\s+as\s+(\w+)(?:\s*=>\s*(\w+))?\s*$',
    dotAll: true,
  );
  static final RegExp _oneString = RegExp(
    r'''^\s*(?:'([^']*)'|"([^"]*)")\s*$''',
  );
  static final RegExp _twoStrings = RegExp(
    r'''^\s*(?:'([^']*)'|"([^"]*)")\s*,\s*(?:'([^']*)'|"([^"]*)")\s*$''',
  );

  TemplateError _error(String message, int offset) => TemplateError(
        message,
        template: _name,
        line: _lineOf(_source, offset),
      );

  List<TemplateNode> parse() {
    final nodes = _block();
    if (_pos < _tokens.length) {
      final stray = _tokens[_pos] as _Directive;
      throw _error('Unexpected @${stray.name}', stray.offset);
    }
    return nodes;
  }

  /// Parses nodes until a closing directive (or the end) is reached. The
  /// closing directive is left for the caller.
  List<TemplateNode> _block() {
    final nodes = <TemplateNode>[];

    while (_pos < _tokens.length) {
      final token = _tokens[_pos];
      if (token is _Directive && _closers.contains(token.name)) break;
      _pos++;

      switch (token) {
        case _Text text:
          nodes.add(TextNode(text.text));
        case _Output output:
          nodes.add(
            OutputNode(
              _expression(output.source, output.offset),
              output.escape,
            ),
          );
        case _Directive directive:
          nodes.add(_directive(directive));
      }
    }
    return nodes;
  }

  TemplateNode _directive(_Directive d) {
    switch (d.name) {
      case 'if':
        return _if(d);
      case 'foreach':
        return _foreach(d);
      case 'include':
        return IncludeNode(_templateName(d));
      case 'extends':
        return ExtendsNode(_templateName(d));
      case 'section':
        {
          final name = _templateName(d);
          final body = _block();
          _close('endsection', d);
          return SectionNode(name, body);
        }
      case 'yield':
        {
          final argument = _argument(d);
          final two = _twoStrings.firstMatch(argument);
          if (two != null) {
            return YieldNode(two[1] ?? two[2]!, two[3] ?? two[4]!);
          }
          return YieldNode(_templateName(d), null);
        }
      default:
        throw _error('Unexpected @${d.name}', d.offset);
    }
  }

  TemplateNode _if(_Directive opener) {
    final branches = <IfBranch>[];
    Expression? condition = _expression(_argument(opener), opener.offset);

    while (true) {
      branches.add(IfBranch(condition, _block()));

      if (_pos >= _tokens.length) {
        throw _error('Missing @endif for this @if', opener.offset);
      }
      final next = _tokens[_pos++] as _Directive;

      switch (next.name) {
        case 'elseif':
          condition = _expression(_argument(next), next.offset);
        case 'else':
          condition = null;
        case 'endif':
          return IfNode(branches);
        default:
          throw _error('Unexpected @${next.name} inside @if', next.offset);
      }
    }
  }

  TemplateNode _foreach(_Directive opener) {
    final match = _foreachPattern.firstMatch(_argument(opener));
    if (match == null) {
      throw _error(
        'Invalid @foreach. Use @foreach(items as item) or '
        '@foreach(items as key => value)',
        opener.offset,
      );
    }

    final source = _expression(match[1]!, opener.offset);
    final hasKey = match[3] != null;
    final keyName = hasKey ? match[2] : null;
    final valueName = hasKey ? match[3]! : match[2]!;

    final body = _block();
    _close('endforeach', opener);
    return ForeachNode(source, valueName, keyName, body);
  }

  void _close(String name, _Directive opener) {
    if (_pos >= _tokens.length) {
      throw _error('Missing @$name for this @${opener.name}', opener.offset);
    }
    final token = _tokens[_pos];
    if (token is! _Directive || token.name != name) {
      throw _error(
        'Expected @$name for this @${opener.name}',
        opener.offset,
      );
    }
    _pos++;
  }

  String _argument(_Directive d) =>
      d.argument ?? (throw _error('@${d.name} needs an argument', d.offset));

  String _templateName(_Directive d) {
    final match = _oneString.firstMatch(_argument(d));
    if (match == null) {
      throw _error(
        "@${d.name} expects a quoted name, like @${d.name}('name')",
        d.offset,
      );
    }
    return match[1] ?? match[2]!;
  }

  Expression _expression(String source, int offset) {
    try {
      return parseExpression(source);
    } on TemplateError catch (error) {
      throw _error(error.message, offset);
    }
  }
}
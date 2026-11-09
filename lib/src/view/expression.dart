import 'view_engine.dart';

/// The variables visible while rendering, with an optional parent scope.
///
/// A `@foreach` body gets a child scope, so loop variables disappear when
/// the loop ends.
class Scope {
  /// Creates a scope with [vars] on top of an optional [parent].
  Scope(this.vars, [this.parent]);

  /// The variables of this scope.
  final Map<String, Object?> vars;

  /// The enclosing scope.
  final Scope? parent;

  /// Returns the variable [name], looking in the parents too, or `null`.
  Object? lookup(String name) {
    for (Scope? scope = this; scope != null; scope = scope.parent) {
      if (scope.vars.containsKey(name)) return scope.vars[name];
    }
    return null;
  }
}

/// Whether [value] counts as true in a condition.
///
/// `null`, `false`, `0`, empty strings and empty collections are false.
bool isTruthy(Object? value) => switch (value) {
      null => false,
      bool b => b,
      num n => n != 0,
      String s => s.isNotEmpty,
      Iterable<Object?> items => items.isNotEmpty,
      Map<Object?, Object?> map => map.isNotEmpty,
      _ => true,
    };

/// A parsed expression such as `user.age >= 18 && !banned`.
///
/// Supported: variables with dots (`user.name`, `items.0`, `items.length`),
/// strings (`'x'` or `"x"`), numbers, `true`, `false`, `null`, the operators
/// `== != < > <= >=`, `&&`, `||`, `!` and parentheses.
sealed class Expression {
  /// Creates an expression.
  const Expression();

  /// Computes the value of the expression in [scope].
  Object? evaluate(Scope scope);
}

/// Parses [source] into an [Expression].
///
/// Throws a [TemplateError] when the expression is invalid.
Expression parseExpression(String source) {
  final tokens = _tokenize(source);
  if (tokens.isEmpty) throw const TemplateError('Empty expression');
  return _ExpressionParser(tokens, source).parse();
}

final class _Literal extends Expression {
  const _Literal(this.value);

  final Object? value;

  @override
  Object? evaluate(Scope scope) => value;
}

final class _Path extends Expression {
  const _Path(this.parts);

  final List<String> parts;

  @override
  Object? evaluate(Scope scope) {
    Object? value = scope.lookup(parts.first);
    for (final part in parts.skip(1)) {
      if (value == null) return null;
      value = _member(value, part);
    }
    return value;
  }
}

final class _Not extends Expression {
  const _Not(this.operand);

  final Expression operand;

  @override
  Object? evaluate(Scope scope) => !isTruthy(operand.evaluate(scope));
}

final class _Binary extends Expression {
  const _Binary(this.operator, this.left, this.right);

  final String operator;
  final Expression left;
  final Expression right;

  @override
  Object? evaluate(Scope scope) {
    if (operator == '||') {
      return isTruthy(left.evaluate(scope)) || isTruthy(right.evaluate(scope));
    }
    if (operator == '&&') {
      return isTruthy(left.evaluate(scope)) && isTruthy(right.evaluate(scope));
    }

    final a = left.evaluate(scope);
    final b = right.evaluate(scope);
    if (operator == '==') return a == b;
    if (operator == '!=') return a != b;

    final order = _compare(a, b);
    if (order == null) return false;
    return switch (operator) {
      '<' => order < 0,
      '>' => order > 0,
      '<=' => order <= 0,
      _ => order >= 0,
    };
  }
}

int? _compare(Object? a, Object? b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  return null;
}

/// Reads [name] from [target]: a key of a map, an index of a list, or
/// `length`. Objects that have a `toJson()` method are read through it.
Object? _member(Object? target, String name) {
  if (target is Map) {
    if (target.containsKey(name)) return target[name];
    return name == 'length' ? target.length : null;
  }
  if (target is List) {
    final index = int.tryParse(name);
    if (index != null) {
      return index >= 0 && index < target.length ? target[index] : null;
    }
    return name == 'length' ? target.length : null;
  }
  if (target is String) return name == 'length' ? target.length : null;

  try {
    final json = (target as dynamic).toJson();
    if (json is Map) return json[name];
  } on NoSuchMethodError {
    // The object has no toJson(), so there is nothing to read from it.
  }
  return null;
}

enum _Kind { number, string, name, symbol }

class _Token {
  const _Token(this.kind, this.text);

  final _Kind kind;
  final String text;
}

final RegExp _tokenPattern = RegExp(
  r'''\s*(?:(\d+(?:\.\d+)?)|('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")|([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*)|(\|\||&&|==|!=|<=|>=|<|>|!|\(|\)))''',
);

List<_Token> _tokenize(String source) {
  final tokens = <_Token>[];
  var position = 0;

  while (position < source.length) {
    if (source.substring(position).trim().isEmpty) break;

    final match = _tokenPattern.matchAsPrefix(source, position);
    if (match == null) {
      throw TemplateError('Invalid expression "$source": unexpected character.');
    }
    position = match.end;

    if (match[1] != null) {
      tokens.add(_Token(_Kind.number, match[1]!));
    } else if (match[2] != null) {
      tokens.add(_Token(_Kind.string, match[2]!));
    } else if (match[3] != null) {
      tokens.add(_Token(_Kind.name, match[3]!));
    } else {
      tokens.add(_Token(_Kind.symbol, match[4]!));
    }
  }
  return tokens;
}

String _unquote(String raw) {
  final inner = raw.substring(1, raw.length - 1);
  return inner.replaceAllMapped(
    RegExp(r'\\(.)'),
    (m) => switch (m[1]) {
      'n' => '\n',
      't' => '\t',
      _ => m[1]!,
    },
  );
}

/// Precedence, from loosest to tightest:
/// `||`, `&&`, `== !=`, `< > <= >=`, `!`, then values and parentheses.
class _ExpressionParser {
  _ExpressionParser(this._tokens, this._source);

  final List<_Token> _tokens;
  final String _source;
  int _position = 0;

  Expression parse() {
    final result = _or();
    if (_position < _tokens.length) {
      throw _error('unexpected "${_tokens[_position].text}"');
    }
    return result;
  }

  TemplateError _error(String message) =>
      TemplateError('Invalid expression "$_source": $message.');

  bool _match(String symbol) {
    if (_position < _tokens.length &&
        _tokens[_position].kind == _Kind.symbol &&
        _tokens[_position].text == symbol) {
      _position++;
      return true;
    }
    return false;
  }

  Expression _or() {
    var left = _and();
    while (_match('||')) {
      left = _Binary('||', left, _and());
    }
    return left;
  }

  Expression _and() {
    var left = _equality();
    while (_match('&&')) {
      left = _Binary('&&', left, _equality());
    }
    return left;
  }

  Expression _equality() {
    var left = _relational();
    while (true) {
      if (_match('==')) {
        left = _Binary('==', left, _relational());
      } else if (_match('!=')) {
        left = _Binary('!=', left, _relational());
      } else {
        return left;
      }
    }
  }

  Expression _relational() {
    var left = _unary();
    while (true) {
      String? operator;
      for (final candidate in const ['<=', '>=', '<', '>']) {
        if (_match(candidate)) {
          operator = candidate;
          break;
        }
      }
      if (operator == null) return left;
      left = _Binary(operator, left, _unary());
    }
  }

  Expression _unary() {
    if (_match('!')) return _Not(_unary());
    return _primary();
  }

  Expression _primary() {
    if (_position >= _tokens.length) throw _error('it ends too early');

    final token = _tokens[_position++];
    switch (token.kind) {
      case _Kind.number:
        return _Literal(
          token.text.contains('.')
              ? double.parse(token.text)
              : int.parse(token.text),
        );
      case _Kind.string:
        return _Literal(_unquote(token.text));
      case _Kind.name:
        return switch (token.text) {
          'true' => const _Literal(true),
          'false' => const _Literal(false),
          'null' => const _Literal(null),
          _ => _Path(token.text.split('.')),
        };
      case _Kind.symbol:
        if (token.text == '(') {
          final inner = _or();
          if (!_match(')')) throw _error('missing ")"');
          return inner;
        }
        throw _error('unexpected "${token.text}"');
    }
  }
}
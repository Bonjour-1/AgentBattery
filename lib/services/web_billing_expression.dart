import 'api_client.dart' show JsonPathExtractor;

/// Fixed, safe error used for all processing-expression parse/evaluation errors.
/// It deliberately contains neither the expression nor response data.
class WebBillingExpressionException implements Exception {
  const WebBillingExpressionException();

  static const safeMessage = '账单数据处理表达式无效';
}

/// A deliberately small, non-Turing-complete arithmetic DSL for billing data.
///
/// Supported operands are decimal numbers, scalar JSON paths, numeric system
/// variables supplied by [systemVariables], and `sum(PATH)`. Only `+`, `-`,
/// `*`, `/`, and parentheses are supported. The evaluator has no code loading,
/// file, network, reflection, or arbitrary function execution capability.
class WebBillingExpression {
  WebBillingExpression._(this._root, this._systemVariables);

  final _ExpressionNode _root;
  final Map<String, num> _systemVariables;

  static double evaluate(
    String expression,
    Object? json, {
    Map<String, num> systemVariables = const {},
  }) {
    try {
      final parser = _ExpressionParser(expression, systemVariables);
      final parsed = parser.parse();
      final value = WebBillingExpression._(
        parsed,
        Map.unmodifiable(systemVariables),
      )._evaluate(json);
      if (!value.isFinite) throw const WebBillingExpressionException();
      return value;
    } on WebBillingExpressionException {
      rethrow;
    } catch (_) {
      throw const WebBillingExpressionException();
    }
  }

  double _evaluate(Object? json) => _root.evaluate(this, json);

  double scalarPath(String path, Object? json) {
    final value = JsonPathExtractor.extract(json, _normalisePath(path));
    return _asFiniteNumber(value);
  }

  double sumPath(String path, Object? json) {
    final values = JsonPathExtractor.extractAll(json, _normalisePath(path));
    if (values == null || values.isEmpty) {
      throw const WebBillingExpressionException();
    }
    var total = 0.0;
    for (final value in values) {
      total += _asFiniteNumber(value);
      if (!total.isFinite) throw const WebBillingExpressionException();
    }
    return total;
  }

  double systemVariable(String name) {
    final value = _systemVariables[name];
    if (value == null || !value.isFinite) {
      throw const WebBillingExpressionException();
    }
    return value.toDouble();
  }

  static double _asFiniteNumber(Object? value) {
    final parsed = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text.trim()),
      _ => null,
    };
    if (parsed == null || !parsed.isFinite) {
      throw const WebBillingExpressionException();
    }
    return parsed;
  }

  static String _normalisePath(String path) =>
      path.trim().replaceFirst(RegExp(r'^\$\.?'), '').replaceAll('[*]', '[]');
}

sealed class _ExpressionNode {
  double evaluate(WebBillingExpression expression, Object? json);
}

class _NumberNode extends _ExpressionNode {
  _NumberNode(this.value);
  final double value;
  @override
  double evaluate(WebBillingExpression expression, Object? json) => value;
}

class _PathNode extends _ExpressionNode {
  _PathNode(this.path);
  final String path;
  @override
  double evaluate(WebBillingExpression expression, Object? json) =>
      expression.scalarPath(path, json);
}

class _SystemVariableNode extends _ExpressionNode {
  _SystemVariableNode(this.name);
  final String name;
  @override
  double evaluate(WebBillingExpression expression, Object? json) =>
      expression.systemVariable(name);
}

class _SumNode extends _ExpressionNode {
  _SumNode(this.path);
  final String path;
  @override
  double evaluate(WebBillingExpression expression, Object? json) =>
      expression.sumPath(path, json);
}

class _BinaryNode extends _ExpressionNode {
  _BinaryNode(this.left, this.operator, this.right);
  final _ExpressionNode left;
  final String operator;
  final _ExpressionNode right;

  @override
  double evaluate(WebBillingExpression expression, Object? json) {
    final a = left.evaluate(expression, json);
    final b = right.evaluate(expression, json);
    final value = switch (operator) {
      '+' => a + b,
      '-' => a - b,
      '*' => a * b,
      '/' when b != 0 => a / b,
      _ => throw const WebBillingExpressionException(),
    };
    if (!value.isFinite) throw const WebBillingExpressionException();
    return value;
  }
}

class _ExpressionParser {
  _ExpressionParser(this.source, this.systemVariables);

  final String source;
  final Map<String, num> systemVariables;
  var _offset = 0;

  _ExpressionNode parse() {
    if (source.trim().isEmpty) throw const WebBillingExpressionException();
    final value = _additive();
    _skipWhitespace();
    if (_offset != source.length) throw const WebBillingExpressionException();
    return value;
  }

  _ExpressionNode _additive() {
    var value = _multiplicative();
    while (true) {
      if (_consume('+')) {
        value = _BinaryNode(value, '+', _multiplicative());
      } else if (_consume('-')) {
        value = _BinaryNode(value, '-', _multiplicative());
      } else {
        return value;
      }
    }
  }

  _ExpressionNode _multiplicative() {
    var value = _primary();
    while (true) {
      if (_consume('*')) {
        value = _BinaryNode(value, '*', _primary());
      } else if (_consume('/')) {
        value = _BinaryNode(value, '/', _primary());
      } else {
        return value;
      }
    }
  }

  _ExpressionNode _primary() {
    _skipWhitespace();
    if (_consume('(')) {
      final value = _additive();
      if (!_consume(')')) throw const WebBillingExpressionException();
      return value;
    }
    final number = _readNumber();
    if (number != null) return _NumberNode(number);
    final token = _readPathToken();
    if (token == null) throw const WebBillingExpressionException();
    if (token == 'sum' && _consume('(')) {
      final path = _readPathToken();
      if (path == null || !_isPath(path) || !_consume(')')) {
        throw const WebBillingExpressionException();
      }
      return _SumNode(path);
    }
    if (systemVariables.containsKey(token)) return _SystemVariableNode(token);
    if (!_isPath(token) || token.contains('[*]')) {
      throw const WebBillingExpressionException();
    }
    return _PathNode(token);
  }

  bool _consume(String expected) {
    _skipWhitespace();
    if (source.startsWith(expected, _offset)) {
      _offset += expected.length;
      return true;
    }
    return false;
  }

  double? _readNumber() {
    _skipWhitespace();
    final match = RegExp(
      r'(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?',
    ).matchAsPrefix(source, _offset);
    if (match == null) return null;
    _offset = match.end;
    final value = double.tryParse(match.group(0)!);
    if (value == null || !value.isFinite) {
      throw const WebBillingExpressionException();
    }
    return value;
  }

  String? _readPathToken() {
    _skipWhitespace();
    final match = RegExp(
      r'\$?[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*|\[(?:\*|[0-9]+)\])*',
    ).matchAsPrefix(source, _offset);
    if (match == null) return null;
    _offset = match.end;
    return match.group(0)!;
  }

  bool _isPath(String value) => RegExp(
    r'^\$?[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*|\[(?:\*|[0-9]+)\])*$',
  ).hasMatch(value);

  void _skipWhitespace() {
    while (_offset < source.length && source.codeUnitAt(_offset) <= 32) {
      _offset++;
    }
  }
}

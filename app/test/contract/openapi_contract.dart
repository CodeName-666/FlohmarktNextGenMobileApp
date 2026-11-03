import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

/// The backend specification copied into the tests (KAN-590), with its origin.
///
/// Validation is strict: an object with `properties` but no
/// `additionalProperties` rejects undocumented fields, so neither the app nor
/// a fixture can drift from the shared contract unnoticed.
class OpenApiContract {
  final Map<String, Object?> document;
  final Map<String, Object?> source;
  OpenApiContract._(this.document, this.source);

  static const directory = 'test/contract/openapi';

  static OpenApiContract load() {
    final text = File('$directory/marketmate.yaml').readAsStringSync();
    final source =
        jsonDecode(File('$directory/source.json').readAsStringSync())
            as Map<String, Object?>;
    return OpenApiContract._(
      _plain(loadYaml(text)) as Map<String, Object?>,
      source,
    );
  }

  /// SHA-256 of the copy with LF line endings, as recorded in `source.json`.
  static String copySha256() => sha256
      .convert(
        utf8.encode(
          File(
            '$directory/marketmate.yaml',
          ).readAsStringSync().replaceAll('\r\n', '\n'),
        ),
      )
      .toString();

  static Object? _plain(Object? node) {
    if (node is YamlMap) {
      return {for (final e in node.entries) '${e.key}': _plain(e.value)};
    }
    if (node is YamlList) return [for (final v in node) _plain(v)];
    return node;
  }

  Map<String, Object?> get _paths => document['paths'] as Map<String, Object?>;

  /// Finds the operation for a concrete request path, preferring static segments.
  ({String template, Map<String, String> params, Map<String, Object?> op})?
  operation(String method, String path) {
    final candidates = <({String template, Map<String, String> params})>[];
    for (final template in _paths.keys) {
      final names = <String>[];
      final pattern = RegExp(
        '^${template.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (m) {
          names.add(m[1]!);
          return '([^/]+)';
        })}\$',
      );
      final match = pattern.firstMatch(path);
      if (match == null) continue;
      candidates.add((
        template: template,
        params: {
          for (var i = 0; i < names.length; i++) names[i]: match[i + 1]!,
        },
      ));
    }
    candidates.sort((a, b) => a.params.length.compareTo(b.params.length));
    for (final candidate in candidates) {
      final item = _paths[candidate.template] as Map<String, Object?>;
      final op = item[method.toLowerCase()];
      if (op is Map<String, Object?>) {
        return (template: candidate.template, params: candidate.params, op: op);
      }
    }
    return null;
  }

  Object? resolve(Object? node) {
    var current = node;
    while (current is Map && current[r'$ref'] is String) {
      final ref = current[r'$ref'] as String;
      Object? target = document;
      for (final part in ref.substring(2).split('/')) {
        target = (target as Map)[part];
      }
      current = target;
    }
    return current;
  }

  /// Every violation of the documented request: path, query, auth and body.
  List<String> checkRequest(http.Request request, {String basePath = ''}) {
    final path = request.url.path.substring(basePath.length);
    final found = operation(request.method, path);
    if (found == null) {
      return ['${request.method} $path ist nicht spezifiziert'];
    }
    final errors = <String>[];
    final op = found.op;
    final declared = <String, Map<String, Object?>>{};
    for (final raw in (op['parameters'] as List? ?? [])) {
      final param = resolve(raw) as Map<String, Object?>;
      declared['${param['in']}:${param['name']}'] = param;
    }
    found.params.forEach((name, value) {
      final param = declared['path:$name'];
      if (param == null) {
        errors.add('Pfadparameter $name nicht deklariert');
      } else {
        errors.addAll(
          validate(
            param['schema'],
            _coerce(param['schema'], value),
            'path.$name',
          ),
        );
      }
    });
    request.url.queryParameters.forEach((name, value) {
      final param = declared['query:$name'];
      if (param == null) {
        errors.add('Query-Parameter $name nicht deklariert');
      } else {
        errors.addAll(
          validate(
            param['schema'],
            _coerce(param['schema'], value),
            'query.$name',
          ),
        );
      }
    });
    final security = op['security'] ?? document['security'];
    if (security is List && security.isNotEmpty) {
      if (!(request.headers['Authorization'] ?? '').startsWith('Bearer ')) {
        errors.add('Bearer-Token fehlt');
      }
    }
    final body = resolve(op['requestBody']) as Map<String, Object?>?;
    if (request.body.isEmpty) {
      if (body?['required'] == true) errors.add('Request-Body fehlt');
    } else if (body == null) {
      errors.add('Request-Body ist nicht spezifiziert');
    } else {
      final schema =
          ((body['content'] as Map)['application/json'] as Map)['schema'];
      errors.addAll(validate(schema, jsonDecode(request.body), r'$'));
    }
    return errors;
  }

  /// Every violation of the documented response for this status.
  List<String> checkResponse(
    String method,
    String path,
    int status,
    String body,
  ) {
    final found = operation(method, path);
    if (found == null) return ['$method $path ist nicht spezifiziert'];
    final responses = found.op['responses'] as Map<String, Object?>;
    final response = resolve(responses['$status']) as Map<String, Object?>?;
    if (response == null) {
      return ['$method $path: Status $status ist nicht spezifiziert'];
    }
    final content = response['content'] as Map<String, Object?>?;
    if (content == null) {
      return body.isEmpty
          ? []
          : ['$method $path $status: Body nicht spezifiziert'];
    }
    final schema =
        (content['application/json'] as Map<String, Object?>)['schema'];
    return validate(schema, jsonDecode(body), r'$');
  }

  static Object? _coerce(Object? schema, String value) {
    final type = schema is Map ? schema['type'] : null;
    if (type == 'integer') return int.tryParse(value) ?? value;
    if (type == 'number') return num.tryParse(value) ?? value;
    if (type == 'boolean') {
      return value == 'true'
          ? true
          : value == 'false'
          ? false
          : value;
    }
    return value;
  }

  List<String> validate(Object? rawSchema, Object? value, String at) {
    final schema = resolve(rawSchema);
    if (schema == null || schema == true) return [];
    if (schema is! Map<String, Object?>) return ['$at: ungültiges Schema'];
    if (value == null && schema['nullable'] == true) return [];
    final errors = <String>[];
    if (schema['allOf'] is List) {
      for (final part in schema['allOf'] as List) {
        errors.addAll(_validateLoose(part, value, at));
      }
      errors.addAll(_unknownKeys(schema, value, at));
    }
    for (final key in ['oneOf', 'anyOf']) {
      if (schema[key] is! List) continue;
      final passing = (schema[key] as List)
          .where((part) => validate(part, value, at).isEmpty)
          .length;
      if (key == 'oneOf' ? passing != 1 : passing == 0) {
        errors.add(
          '$at: passt auf $passing statt ${key == 'oneOf' ? 'genau 1' : 'mind. 1'} Varianten',
        );
      }
    }
    final types = switch (schema['type']) {
      String t => [t],
      List t => t.cast<String>(),
      _ => <String>[],
    };
    if (types.isNotEmpty && !types.any((t) => _isType(t, value))) {
      return [
        ...errors,
        '$at: erwartet ${types.join('|')}, erhalten ${_typeName(value)}',
      ];
    }
    if (schema['enum'] is List && !(schema['enum'] as List).contains(value)) {
      errors.add('$at: $value nicht in ${schema['enum']}');
    }
    if (value is Map) {
      for (final name in (schema['required'] as List? ?? [])) {
        if (!value.containsKey(name)) {
          errors.add('$at.$name: Pflichtfeld fehlt');
        }
      }
      final properties = schema['properties'] as Map<String, Object?>? ?? {};
      for (final entry in value.entries) {
        final key = '${entry.key}';
        if (properties.containsKey(key)) {
          errors.addAll(validate(properties[key], entry.value, '$at.$key'));
        } else if (schema['additionalProperties'] is Map) {
          errors.addAll(
            validate(schema['additionalProperties'], entry.value, '$at.$key'),
          );
        }
      }
      if (schema['allOf'] is! List) {
        errors.addAll(_unknownKeys(schema, value, at));
      }
    }
    if (value is List) {
      final min = schema['minItems'];
      if (min is int && value.length < min) {
        errors.add('$at: weniger als $min Einträge');
      }
      for (var i = 0; i < value.length; i++) {
        errors.addAll(validate(schema['items'], value[i], '$at[$i]'));
      }
    }
    if (value is String) {
      final pattern = schema['pattern'];
      if (pattern is String && !RegExp(pattern).hasMatch(value)) {
        errors.add('$at: "$value" passt nicht zu $pattern');
      }
      if (schema['format'] == 'date-time' && DateTime.tryParse(value) == null) {
        errors.add('$at: "$value" ist kein Zeitpunkt');
      }
      if (schema['format'] == 'date' &&
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        errors.add('$at: "$value" ist kein Datum');
      }
    }
    if (value is num) {
      final minimum = schema['minimum'];
      final maximum = schema['maximum'];
      if (minimum is num && value < minimum) {
        errors.add('$at: $value < $minimum');
      }
      if (maximum is num && value > maximum) {
        errors.add('$at: $value > $maximum');
      }
    }
    return errors;
  }

  /// allOf parts are checked without their own unknown-key rule; the union decides.
  List<String> _validateLoose(Object? part, Object? value, String at) {
    final schema = resolve(part);
    if (schema is! Map<String, Object?>) return [];
    return validate({...schema, 'additionalProperties': true}, value, at);
  }

  List<String> _unknownKeys(
    Map<String, Object?> schema,
    Object? value,
    String at,
  ) {
    if (value is! Map) return [];
    final known = _declaredKeys(schema);
    if (known == null) return [];
    return [
      for (final key in value.keys)
        if (!known.contains('$key')) '$at.$key: nicht spezifiziertes Feld',
    ];
  }

  /// Declared property names, or null when additional properties are allowed.
  Set<String>? _declaredKeys(Object? raw) {
    final schema = resolve(raw);
    if (schema is! Map<String, Object?>) return null;
    if (schema.containsKey('additionalProperties') &&
        schema['additionalProperties'] != false) {
      return null;
    }
    final keys = <String>{
      ...(schema['properties'] as Map? ?? {}).keys.cast<String>(),
    };
    for (final part in (schema['allOf'] as List? ?? [])) {
      final nested = _declaredKeys(part);
      if (nested == null) return null;
      keys.addAll(nested);
    }
    if (keys.isEmpty &&
        schema['allOf'] == null &&
        schema['properties'] == null) {
      return null;
    }
    return keys;
  }

  static bool _isType(String type, Object? value) => switch (type) {
    'null' => value == null,
    'string' => value is String,
    'integer' => value is int,
    'number' => value is num,
    'boolean' => value is bool,
    'array' => value is List,
    'object' => value is Map,
    _ => true,
  };

  static String _typeName(Object? value) => switch (value) {
    null => 'null',
    String _ => 'string',
    int _ => 'integer',
    num _ => 'number',
    bool _ => 'boolean',
    List _ => 'array',
    Map _ => 'object',
    _ => value.runtimeType.toString(),
  };
}

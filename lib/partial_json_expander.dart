import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

final _log = Logger('expandPartialJson');

/// Expands partial JSON according to a schema, repairing incomplete JSON
/// and applying schema defaults.
///
/// Returns the parsed JSON value which could be any valid JSON type
/// (object, array, string, number, boolean, or null).
dynamic expandPartialJson(
  JsonSchema schema,
  String partialJson,
) {
  // Handle empty input based on schema type
  if (partialJson.trim().isEmpty) {
    return _getDefaultForSchema(schema);
  }

  final repaired = _closePartialJson(partialJson, schema);
  if (repaired == null) return null;

  final decoded = json.decode(repaired);
  return _applySchemaDefaults(schema, decoded);
}

/// Generates random chunks of JSON for testing streaming scenarios.
Stream<String> randomChunkedJson(
  String json, {
  required int seed,
  int minChunk = 1,
  int maxChunk = 12,
}) async* {
  assert(minChunk > 0 && maxChunk >= minChunk);
  final rng = Random(seed);
  var idx = 0;
  while (idx < json.length) {
    final remaining = json.length - idx;
    final size =
        min(remaining, minChunk + rng.nextInt(maxChunk - minChunk + 1));
    yield json.substring(idx, idx + size);
    idx += size;
    await Future<dynamic>.delayed(Duration.zero);
  }
}

/* ---------- internal helpers ---------- */

String? _closePartialJson(String src, JsonSchema schema) {
  final text = src.trim();
  if (text.isEmpty) return null;

  // First, try to detect the type of value we're dealing with
  final rootType = _detectRootType(text);

  // Handle different root types
  switch (rootType) {
    case _JsonType.string:
      return _closePartialString(text);
    case _JsonType.number:
      return _closePartialNumber(text);
    case _JsonType.boolean:
      return _closePartialBoolean(text);
    case _JsonType.null_:
      return _closePartialNull(text);
    case _JsonType.array:
      return _closePartialArray(text, schema);
    case _JsonType.object:
      return _closePartialObject(text, schema);
    case _JsonType.unknown:
      // Try to close as object by default if schema expects object
      if (schema.typeList?.contains(SchemaType.object) ?? true) {
        return _closePartialObject(text, schema);
      }
      return null;
  }
}

enum _JsonType { object, array, string, number, boolean, null_, unknown }

_JsonType _detectRootType(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return _JsonType.unknown;

  final firstChar = trimmed[0];
  if (firstChar == '{') return _JsonType.object;
  if (firstChar == '[') return _JsonType.array;
  if (firstChar == '"') return _JsonType.string;
  if (firstChar == 't' || firstChar == 'f') return _JsonType.boolean;
  if (firstChar == 'n') return _JsonType.null_;
  if (firstChar == '-' || RegExp(r'^\d').hasMatch(firstChar)) {
    return _JsonType.number;
  }

  return _JsonType.unknown;
}

String? _closePartialString(String text) {
  if (!text.startsWith('"')) return null;

  // Count unescaped quotes
  var quoteCount = 0;
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == r'\' && !escaped) {
      escaped = true;
      continue;
    }
    if (text[i] == '"' && !escaped) {
      quoteCount++;
    }
    escaped = false;
  }

  // If odd number of quotes, close the string
  if (quoteCount.isOdd) {
    return '$text"';
  }
  return text;
}

String? _closePartialNumber(String text) {
  // Remove trailing incomplete parts
  var cleaned = text.trim();

  // Handle incomplete exponent
  if (RegExp(r'[eE]$').hasMatch(cleaned)) {
    cleaned = cleaned.substring(0, cleaned.length - 1);
  } else if (RegExp(r'[eE][+-]?$').hasMatch(cleaned)) {
    cleaned = cleaned.substring(0, cleaned.lastIndexOf(RegExp('[eE]')));
  }

  // Handle trailing decimal point
  if (cleaned.endsWith('.')) {
    cleaned = cleaned.substring(0, cleaned.length - 1);
  }

  // Handle incomplete negative
  if (cleaned == '-') {
    return '0';
  }

  return cleaned;
}

String? _closePartialBoolean(String text) {
  final trimmed = text.trim();
  if ('true'.startsWith(trimmed)) return 'true';
  if ('false'.startsWith(trimmed)) return 'false';
  return null;
}

String? _closePartialNull(String text) {
  final trimmed = text.trim();
  if ('null'.startsWith(trimmed)) return 'null';
  return null;
}

String? _closePartialArray(String text, JsonSchema schema) {
  var working = text.trim();
  if (!working.startsWith('[')) return null;

  // Remove trailing comma
  working = working.replaceAll(RegExp(r',\s*$'), '');

  // Handle incomplete values inside array
  final lastComma = working.lastIndexOf(',');
  final lastOpen = working.lastIndexOf('[');

  if (lastComma > lastOpen) {
    // We have a partial value after the last comma
    final partial = working.substring(lastComma + 1).trim();
    if (partial.isNotEmpty) {
      // Try to complete the partial value
      final completed = _completePartialValue(partial, schema.items);
      if (completed != null) {
        working = working.substring(0, lastComma + 1) + completed;
      }
    }
  }

  // Balance brackets
  final openBrackets = '['.allMatches(working).length;
  final closeBrackets = ']'.allMatches(working).length;

  if (closeBrackets > openBrackets) return null;

  return working + ']' * (openBrackets - closeBrackets);
}

String? _closePartialObject(String text, JsonSchema schema) {
  var working = text.trimRight();
  working = working.replaceAll(RegExp(r',\s*$'), '');

  // Handle incomplete key
  final incompleteKey = RegExp(r'[,{]\s*"([^":]*)$').firstMatch(working);
  if (incompleteKey != null) {
    final unfinished = incompleteKey.group(1)!;
    final matches =
        schema.properties.keys.where((k) => k.startsWith(unfinished)).toList();

    // Also check pattern properties if no exact matches
    if (matches.isEmpty && schema.patternProperties.isNotEmpty) {
      // For pattern properties, we can't auto-complete, so remove the
      // incomplete key
      final idx = incompleteKey.start;
      working = working.substring(0, idx);
      if (working.endsWith(',')) {
        working = working.substring(0, working.length - 1);
      }
    } else if (matches.length == 1) {
      // Complete the key and add a colon
      final idx = incompleteKey.start + incompleteKey.group(0)!.indexOf('"');
      working = '${working.substring(0, idx)}"${matches.first}":';
    } else {
      _log.fine('Ambiguous incomplete key "$unfinished"');
      return null;
    }
  }

  // Check if we end with a colon (missing value)
  if (working.endsWith(':')) {
    // Try to determine the expected type from schema
    final lastKey = _extractLastKey(working);
    if (lastKey != null && schema.properties.containsKey(lastKey)) {
      final propSchema = schema.properties[lastKey]!;
      final defaultValue = _getDefaultForSchema(propSchema);
      working += json.encode(defaultValue);
    } else {
      working += 'null';
    }
  }

  // Check if we're in the middle of a string value
  final quoteCount = '"'.allMatches(working).length;
  if (quoteCount.isOdd) {
    working += '"';
  }

  // Remove trailing comma if it exists
  working = working.replaceAll(RegExp(r',\s*$'), '');

  // Balance braces
  final openBraces = '{'.allMatches(working).length;
  final closeBraces = '}'.allMatches(working).length;
  final openBrackets = '['.allMatches(working).length;
  final closeBrackets = ']'.allMatches(working).length;

  if (closeBraces > openBraces || closeBrackets > openBrackets) return null;

  working += ']' * (openBrackets - closeBrackets);
  working += '}' * (openBraces - closeBraces);

  return working;
}

String? _completePartialValue(String partial, JsonSchema? schema) {
  final type = _detectRootType(partial);

  switch (type) {
    case _JsonType.string:
      return _closePartialString(partial);
    case _JsonType.number:
      return _closePartialNumber(partial);
    case _JsonType.boolean:
      return _closePartialBoolean(partial);
    case _JsonType.null_:
      return _closePartialNull(partial);
    case _JsonType.array:
      return _closePartialArray(partial, schema ?? JsonSchema.create({}));
    case _JsonType.object:
      return _closePartialObject(partial, schema ?? JsonSchema.create({}));
    case _JsonType.unknown:
      return null;
  }
}

String? _extractLastKey(String json) {
  final keyMatch = RegExp(r'"([^"]+)"\s*:\s*$').firstMatch(json);
  return keyMatch?.group(1);
}

dynamic _getDefaultForSchema(JsonSchema schema) {
  // First check if there's an explicit default
  if (schema.defaultValue != null) {
    return schema.defaultValue;
  }

  // Then try to infer from type
  if (schema.typeList != null && schema.typeList!.isNotEmpty) {
    final type = schema.typeList!.first;
    switch (type) {
      case SchemaType.object:
        return <String, dynamic>{};
      case SchemaType.array:
        return <dynamic>[];
      case SchemaType.string:
        return '';
      case SchemaType.number:
      case SchemaType.integer:
        return 0;
      case SchemaType.boolean:
        return false;
      case SchemaType.nullValue:
        return null;
    }
  }

  return null;
}

dynamic _applySchemaDefaults(JsonSchema schema, dynamic value) {
  if (value is Map<String, dynamic>) {
    return _mergeObjectDefaults(schema, value);
  } else if (value is List) {
    return _mergeArrayDefaults(schema, value);
  } else {
    // For primitive types, return the value as-is or the default if null
    return value ?? schema.defaultValue;
  }
}

Map<String, dynamic> _mergeObjectDefaults(
    JsonSchema schema, Map<String, dynamic> obj) {
  final merged = Map<String, dynamic>.from(obj);

  // Apply defaults for defined properties
  for (final entry in schema.properties.entries) {
    final key = entry.key;
    final propSchema = entry.value;

    if (!merged.containsKey(key)) {
      final defaultValue = _getDefaultForSchema(propSchema);
      if (defaultValue != null) {
        merged[key] = defaultValue;
      }
    } else if (merged[key] == null) {
      merged[key] = _getDefaultForSchema(propSchema);
    } else {
      // Recursively apply defaults to nested structures
      final current = merged[key];
      if (current is Map<String, dynamic>) {
        merged[key] = _mergeObjectDefaults(propSchema, current);
      } else if (current is List) {
        merged[key] = _mergeArrayDefaults(propSchema, current);
      }
    }
  }

  // Handle pattern properties
  if (schema.patternProperties.isNotEmpty) {
    for (final key in merged.keys.toList()) {
      if (!schema.properties.containsKey(key)) {
        // Check if key matches any pattern
        for (final pattern in schema.patternProperties.keys) {
          if (pattern.hasMatch(key)) {
            final propSchema = schema.patternProperties[pattern]!;
            final current = merged[key];
            if (current is Map<String, dynamic>) {
              merged[key] = _mergeObjectDefaults(propSchema, current);
            } else if (current is List) {
              merged[key] = _mergeArrayDefaults(propSchema, current);
            }
            break;
          }
        }
      }
    }
  }

  // Remove additional properties if not allowed
  if (schema.additionalPropertiesBool == false) {
    merged.removeWhere((k, _) {
      // Keep if it's a defined property
      if (schema.properties.containsKey(k)) return false;

      // Keep if it matches a pattern property
      for (final pattern in schema.patternProperties.keys) {
        if (pattern.hasMatch(k)) return false;
      }

      return true;
    });
  }

  return merged;
}

List<dynamic> _mergeArrayDefaults(JsonSchema schema, List<dynamic> arr) {
  if (schema.items == null) return arr;

  return arr.map((item) {
    if (item is Map<String, dynamic>) {
      return _mergeObjectDefaults(schema.items!, item);
    } else if (item is List) {
      return _mergeArrayDefaults(schema.items!, item);
    } else if (item == null) {
      return _getDefaultForSchema(schema.items!);
    }
    return item;
  }).toList();
}

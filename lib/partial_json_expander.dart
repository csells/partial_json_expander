import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

final _log = Logger('expandPartialJson');

Map<String, dynamic>? expandPartialJson(
  JsonSchema schema,
  String partialJson,
) {
  final repaired = _closePartialJson(partialJson, schema);
  if (repaired == null) return null;

  late final Map<String, dynamic> decoded;
  decoded = json.decode(repaired) as Map<String, dynamic>;
  return _mergeDefaults(schema, decoded);
}

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
  var text = src.trimRight();
  text = text.replaceAll(RegExp(r',\s*\$'), '');

  // Check for incomplete key (e.g. {"tim or {"time":23,"temp)
  final incompleteKey = RegExp(r'[,{]\s*"([^":]*)$').firstMatch(text);
  if (incompleteKey != null) {
    final unfinished = incompleteKey.group(1)!;
    final matches =
        schema.properties.keys.where((k) => k.startsWith(unfinished)).toList();
    if (matches.length == 1) {
      // Complete the key and add a colon
      final idx = incompleteKey.start + incompleteKey.group(0)!.indexOf('"');
      text = '${text.substring(0, idx)}"${matches.first}":';
    } else {
      _log.fine('Ambiguous incomplete key "$unfinished"');
      return null;
    }
  }

  // Check if we end with a colon (missing value)
  if (text.endsWith(':')) {
    text += 'null';
  }

  // Check if we're in the middle of a string value
  final quoteCount = '"'.allMatches(text).length;
  if (quoteCount.isOdd) {
    // We're in the middle of a string value, close it
    text += '"';
  }

  // Remove trailing comma if it exists
  text = text.replaceAll(RegExp(r',\s*$'), '');

  final openBraces = '{'.allMatches(text).length;
  final closeBraces = '}'.allMatches(text).length;
  final openBrackets = '['.allMatches(text).length;
  final closeBrackets = ']'.allMatches(text).length;
  if (closeBraces > openBraces || closeBrackets > openBrackets) return null;

  text += ']' * (openBrackets - closeBrackets);
  text += '}' * (openBraces - closeBraces);

  return text;
}

Map<String, dynamic> _mergeDefaults(
    JsonSchema schema, Map<String, dynamic> obj) {
  final merged = Map<String, dynamic>.from(obj);
  for (final entry in schema.properties.entries) {
    final key = entry.key;
    final propSchema = entry.value;

    if (!merged.containsKey(key) || merged[key] == null) {
      if (propSchema.defaultValue != null) {
        merged[key] = propSchema.defaultValue;
      } else if (propSchema.typeList?.any((t) => t == SchemaType.object) ??
          false) {
        merged[key] = {};
      } else if (propSchema.typeList?.any((t) => t == SchemaType.array) ??
          false) {
        merged[key] = propSchema.defaultValue ?? [];
      }
    }

    final current = merged[key];
    if (current is Map<String, dynamic> &&
        (propSchema.typeList?.any((t) => t == SchemaType.object) ?? false)) {
      merged[key] = _mergeDefaults(propSchema, current);
    } else if (current is List &&
        (propSchema.typeList?.any((t) => t == SchemaType.array) ?? false) &&
        propSchema.items != null) {
      merged[key] = current
          .map((e) => e is Map<String, dynamic>
              ? _mergeDefaults(propSchema.items!, e)
              : e)
          .toList();
    }
  }

  if (schema.additionalPropertiesBool == false) {
    merged.removeWhere((k, _) => !schema.properties.containsKey(k));
  }

  return merged;
}

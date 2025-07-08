import 'dart:async';
import 'dart:math';

import 'package:json_schema/json_schema.dart';

import 'src/partial_json_parser.dart';

/// Expands partial JSON according to a schema, repairing incomplete JSON
/// and applying schema defaults.
///
/// Returns the parsed JSON value which could be any valid JSON type
/// (object, array, string, number, boolean, or null).
dynamic expandPartialJson(JsonSchema schema, String partialJson) {
  // Use the new custom parser
  final parser = PartialJsonParser();
  final completer = PartialJsonCompleter();

  final parseTree = parser.parse(partialJson, schema);

  // If parsing failed and we have non-empty input, it's malformed
  if (parseTree == null && partialJson.trim().isNotEmpty) {
    return null;
  }

  return completer.complete(parseTree, schema);
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
    final size = min(
      remaining,
      minChunk + rng.nextInt(maxChunk - minChunk + 1),
    );
    yield json.substring(idx, idx + size);
    idx += size;
    await Future<dynamic>.delayed(Duration.zero);
  }
}

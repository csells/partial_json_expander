// ignore_for_file: avoid_print

import 'package:json_schema/json_schema.dart';
import 'package:partial_json_expander/partial_json_expander.dart';

void main() async {
  final schemaJson = {
    'type': 'object',
    'properties': {
      'time': {'type': 'string', 'default': '00:00'},
      'temperature': {'type': 'number', 'default': 0},
      'units': {'type': 'string', 'default': 'C'}
    },
    'required': ['time']
  };
  final schema = JsonSchema.create(schemaJson);

  const json = '{"time":"12:30","temperature":23,"units":"F"}';
  final stream = randomChunkedJson(json, seed: 42, minChunk: 1, maxChunk: 10);

  final accumulated = StringBuffer();
  await for (final chunk in stream) {
    accumulated.write(chunk);
    final expanded = expandPartialJson(schema, accumulated.toString());
    print("accumulated='$accumulated' => $expanded");
  }
}

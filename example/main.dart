// ignore_for_file: avoid_print

import 'package:json_schema/json_schema.dart';
import 'package:partial_json_expander/partial_json_expander.dart';

void main() async {
  // Example 1: Original object schema with chunked streaming
  final objectSchema = JsonSchema.create({
    'type': 'object',
    'properties': {
      'time': {'type': 'string', 'default': '00:00'},
      'temperature': {'type': 'number', 'default': 0},
      'units': {'type': 'string', 'default': 'C'},
    },
  });

  print('Example 1: Object schema with chunked streaming');
  const json = '{"time":"12:30","temperature":23,"units":"F"}';
  final stream = randomChunkedJson(json, seed: 42, minChunk: 1, maxChunk: 10);

  final accumulated = StringBuffer();
  await for (final chunk in stream) {
    accumulated.write(chunk);
    final expanded = expandPartialJson(objectSchema, accumulated.toString());
    print("accumulated='$accumulated' => $expanded");
  }

  print('\nExample 2: Root-level array support');
  final arraySchema = JsonSchema.create({
    'type': 'array',
    'items': {'type': 'number'},
    'default': [1, 2, 3],
  });

  print("expandPartialJson('[1,2,') => "
      "${expandPartialJson(arraySchema, '[1,2,')}");
  print("expandPartialJson('') => ${expandPartialJson(arraySchema, '')}");

  print('\nExample 3: Partial primitive completion');
  final boolSchema = JsonSchema.create({'type': 'boolean'});
  final stringSchema = JsonSchema.create({'type': 'string'});
  final numberSchema = JsonSchema.create({'type': 'number'});

  print("expandPartialJson('tr') => ${expandPartialJson(boolSchema, 'tr')}");
  print("expandPartialJson('fal') => ${expandPartialJson(boolSchema, 'fal')}");
  print("expandPartialJson('\"hello') => "
      "${expandPartialJson(stringSchema, '"hello')}");
  print("expandPartialJson('123.') => "
      "${expandPartialJson(numberSchema, '123.')}");
  print("expandPartialJson('1e5') => "
      "${expandPartialJson(numberSchema, '1e5')}");

  print('\nExample 4: Complex nested structure with defaults');
  final complexSchema = JsonSchema.create({
    'type': 'object',
    'properties': {
      'user': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'default': 'Anonymous'},
          'settings': {
            'type': 'object',
            'properties': {
              'theme': {'type': 'string', 'default': 'light'},
              'notifications': {'type': 'boolean', 'default': true},
            },
          },
        },
      },
      'data': {
        'type': 'array',
        'default': [],
        'items': {
          'type': 'object',
          'properties': {
            'id': {'type': 'integer'},
            'value': {'type': 'string', 'default': 'N/A'},
          },
        },
      },
    },
  });

  const partialComplex = '{"user":{"name":"John","settings":{"theme":"dark';
  print('Partial complex: $partialComplex');
  print('Result: ${expandPartialJson(complexSchema, partialComplex)}');

  print('\nExample 5: Empty input handling');
  print('Empty string with object schema: '
      '${expandPartialJson(objectSchema, '')}');
  print('Empty string with array schema: '
      '${expandPartialJson(arraySchema, '')}');
  print('Empty string with string schema: '
      '${expandPartialJson(stringSchema, '')}');
}

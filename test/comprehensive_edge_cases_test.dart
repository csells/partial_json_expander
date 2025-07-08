// ignore_for_file: avoid_dynamic_calls

import 'package:json_schema/json_schema.dart';
import 'package:partial_json_expander/partial_json_expander.dart';
import 'package:test/test.dart';

void main() {
  group('Root Level Values', () {
    test('handles atomic string at root level', () async {
      final schema = JsonSchema.create({'type': 'string', 'default': 'hello'});

      // Test various partial strings
      expect(expandPartialJson(schema, '"'), equals(''));
      expect(expandPartialJson(schema, '"hel'), equals('hel'));
      expect(expandPartialJson(schema, '"hello"'), equals('hello'));

      // Test with empty string should return the default
      expect(expandPartialJson(schema, ''), equals('hello'));
    });

    test('handles atomic number at root level', () async {
      final schema = JsonSchema.create({'type': 'number', 'default': 42.5});

      expect(expandPartialJson(schema, '123'), equals(123));
      expect(expandPartialJson(schema, '123.'), equals(123));
      expect(expandPartialJson(schema, '123.4'), equals(123.4));
      expect(expandPartialJson(schema, '-123.4'), equals(-123.4));
      expect(expandPartialJson(schema, '1.23e'), equals(1.23));
      expect(expandPartialJson(schema, '1.23e5'), equals(123000));
    });

    test('handles atomic boolean at root level', () async {
      final schema = JsonSchema.create({'type': 'boolean', 'default': true});

      expect(expandPartialJson(schema, 'true'), equals(true));
      expect(expandPartialJson(schema, 'false'), equals(false));

      // Partial booleans complete to the matching boolean
      expect(expandPartialJson(schema, 'tr'), equals(true));
      expect(expandPartialJson(schema, 'tru'), equals(true));
      expect(expandPartialJson(schema, 'fa'), equals(false));
      expect(expandPartialJson(schema, 'fals'), equals(false));
    });

    test('handles null at root level', () async {
      final schema = JsonSchema.create({'type': 'null', 'default': null});

      expect(expandPartialJson(schema, 'null'), isNull);
    });

    test('handles array at root level', () async {
      final schema = JsonSchema.create({
        'type': 'array',
        'items': {'type': 'number'},
        'default': [1, 2, 3]
      });

      expect(expandPartialJson(schema, '['), equals([]));
      expect(expandPartialJson(schema, '[1'), equals([1]));
      expect(expandPartialJson(schema, '[1,2'), equals([1, 2]));
      expect(expandPartialJson(schema, '[1,2,3]'), equals([1, 2, 3]));
      expect(
          expandPartialJson(schema, '[[1],[2'),
          equals([
            [1],
            [2]
          ]));
    });
  });

  group('Complex Nested Structures with Defaults', () {
    test('handles deeply nested objects with defaults at each level', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'level1': {
            'type': 'object',
            'default': {'name': 'L1'},
            'properties': {
              'name': {'type': 'string'},
              'level2': {
                'type': 'object',
                'default': {'name': 'L2'},
                'properties': {
                  'name': {'type': 'string'},
                  'level3': {
                    'type': 'object',
                    'default': {'name': 'L3'},
                    'properties': {
                      'name': {'type': 'string'},
                      'value': {'type': 'number', 'default': 42}
                    }
                  }
                }
              }
            }
          }
        }
      });

      // Empty object should get all defaults
      expect(
          expandPartialJson(schema, '{}'),
          equals({
            'level1': {'name': 'L1'}
          }));

      // Partial nested should merge with defaults
      expect(
          expandPartialJson(schema, '{"level1":{"level2":{}}}'),
          equals({
            'level1': {
              'name': 'L1',
              'level2': {'name': 'L2'}
            }
          }));

      // Deep partial
      expect(
          expandPartialJson(schema, '{"level1":{"level2":{"level3":{'),
          equals({
            'level1': {
              'name': 'L1',
              'level2': {
                'name': 'L2',
                'level3': {'name': 'L3', 'value': 42}
              }
            }
          }));
    });

    test('handles arrays of objects with defaults', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'users': {
            'type': 'array',
            'default': [
              {'name': 'Default User', 'role': 'guest'}
            ],
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string', 'default': 'Anonymous'},
                'role': {'type': 'string', 'default': 'user'},
                'permissions': {
                  'type': 'array',
                  'default': ['read'],
                  'items': {'type': 'string'}
                }
              }
            }
          }
        }
      });

      // Empty gets array default
      expect(
          expandPartialJson(schema, '{}'),
          equals({
            'users': [
              {'name': 'Default User', 'role': 'guest'}
            ]
          }));

      // Partial array item gets item defaults
      expect(
          expandPartialJson(schema, '{"users":[{'),
          equals({
            'users': [
              {
                'name': 'Anonymous',
                'role': 'user',
                'permissions': ['read']
              }
            ]
          }));

      // Multiple partial items
      expect(
          expandPartialJson(schema, '{"users":[{"name":"Alice"},{"name":"Bob"'),
          equals({
            'users': [
              {
                'name': 'Alice',
                'role': 'user',
                'permissions': ['read']
              },
              {
                'name': 'Bob',
                'role': 'user',
                'permissions': ['read']
              }
            ]
          }));
    });
  });

  group('Schema Validation Edge Cases', () {
    test('handles required properties', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'required': ['name', 'age'],
        'properties': {
          'name': {'type': 'string'},
          'age': {'type': 'number'},
          'optional': {'type': 'string', 'default': 'N/A'}
        }
      });

      // Missing required should still parse
      expect(expandPartialJson(schema, '{"optional":"value"}'),
          equals({'optional': 'value'}));

      // Partial with required
      expect(expandPartialJson(schema, '{"name":"John","age":'),
          equals({'name': 'John', 'age': null, 'optional': 'N/A'}));
    });

    test('handles minItems and maxItems', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'tags': {
            'type': 'array',
            'minItems': 2,
            'maxItems': 5,
            'default': ['tag1', 'tag2'],
            'items': {'type': 'string'}
          }
        }
      });

      // Empty gets default which satisfies minItems
      expect(
          expandPartialJson(schema, '{}'),
          equals({
            'tags': ['tag1', 'tag2']
          }));

      // Too many items still parses
      expect(
          expandPartialJson(schema, '{"tags":["a","b","c","d","e","f"]}'),
          equals({
            'tags': ['a', 'b', 'c', 'd', 'e', 'f']
          }));
    });

    test('handles pattern properties', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'patternProperties': {
          '^S_': {'type': 'string'},
          '^I_': {'type': 'integer'}
        },
        'additionalProperties': false
      });

      expect(expandPartialJson(schema, '{"S_name":"value","I_count":42}'),
          equals({'S_name': 'value', 'I_count': 42}));

      // Non-matching pattern should be removed
      expect(expandPartialJson(schema, '{"S_name":"value","badKey":"remove"}'),
          equals({'S_name': 'value'}));
    });
  });

  group('Special Characters and Escape Sequences', () {
    test('handles various escape sequences in strings', () {
      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      // Test various escapes
      expect(expandPartialJson(schema, r'{"tab":"a\tb"}'),
          equals({'tab': 'a\tb'}));

      expect(expandPartialJson(schema, r'{"newline":"a\nb"}'),
          equals({'newline': 'a\nb'}));

      expect(expandPartialJson(schema, r'{"quote":"a\"b"}'),
          equals({'quote': 'a"b'}));

      expect(expandPartialJson(schema, r'{"backslash":"a\\b"}'),
          equals({'backslash': r'a\b'}));

      expect(expandPartialJson(schema, r'{"unicode":"a\u0041b"}'),
          equals({'unicode': 'aAb'}));

      // Partial escape sequences
      expect(expandPartialJson(schema, r'{"partial":"a\'),
          equals({'partial': 'a'}));

      expect(expandPartialJson(schema, r'{"partial":"a\u00'),
          equals({'partial': 'a'}));
    });

    test('handles Unicode edge cases', () {
      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      // Various Unicode characters
      expect(expandPartialJson(schema, '{"emoji":"😀🎉🌍"}'),
          equals({'emoji': '😀🎉🌍'}));

      expect(expandPartialJson(schema, '{"chinese":"你好世界"}'),
          equals({'chinese': '你好世界'}));

      expect(expandPartialJson(schema, '{"arabic":"مرحبا"}'),
          equals({'arabic': 'مرحبا'}));

      expect(expandPartialJson(schema, '{"mixed":"Hello 世界 🌍"}'),
          equals({'mixed': 'Hello 世界 🌍'}));

      // Partial Unicode
      expect(expandPartialJson(schema, '{"partial":"你好'),
          equals({'partial': '你好'}));
    });
  });

  group('Number Format Edge Cases', () {
    test('handles various number formats', () {
      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      // Scientific notation
      expect(expandPartialJson(schema, '{"sci":1.23e10}'),
          equals({'sci': 1.23e10}));

      expect(expandPartialJson(schema, '{"sci":1.23E-10}'),
          equals({'sci': 1.23e-10}));

      // Very large numbers (within JS safe integer range)
      expect(expandPartialJson(schema, '{"big":9007199254740991}'),
          equals({'big': 9007199254740991}));

      // Very small numbers
      expect(expandPartialJson(schema, '{"small":0.000000000000001}'),
          equals({'small': 0.000000000000001}));

      // Leading zeros
      expect(
          expandPartialJson(schema, '{"zero":0.123}'), equals({'zero': 0.123}));

      // Negative zero
      expect(
          expandPartialJson(schema, '{"negZero":-0}'), equals({'negZero': -0}));

      // Partial numbers
      expect(expandPartialJson(schema, '{"partial":123.'),
          equals({'partial': 123}));

      expect(
          expandPartialJson(schema, '{"partial":-'), equals({'partial': null}));

      expect(
          expandPartialJson(schema, '{"partial":1e'), equals({'partial': 1}));
    });
  });

  group('Empty Values at Various Levels', () {
    test('handles empty objects and arrays at various nesting levels', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'empty': {'type': 'object', 'default': {}},
          'emptyArray': {'type': 'array', 'default': []},
          'nested': {
            'type': 'object',
            'properties': {
              'emptyInner': {'type': 'object', 'default': {}},
              'arrayOfEmpty': {
                'type': 'array',
                'default': [{}, {}],
                'items': {'type': 'object'}
              }
            }
          }
        }
      });

      expect(
          expandPartialJson(schema, '{}'),
          equals({
            'empty': {},
            'emptyArray': [],
            'nested': {
              'emptyInner': {},
              'arrayOfEmpty': [{}, {}]
            }
          }));

      expect(
          expandPartialJson(schema, '{"nested":{"arrayOfEmpty":[{},{},{}]}}'),
          equals({
            'empty': {},
            'emptyArray': [],
            'nested': {
              'emptyInner': {},
              'arrayOfEmpty': [{}, {}, {}]
            }
          }));
    });
  });

  group('Complex Schema Features', () {
    test('handles oneOf schemas', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'value': {
            'oneOf': [
              {'type': 'string'},
              {'type': 'number'},
              {'type': 'boolean'}
            ]
          }
        }
      });

      expect(expandPartialJson(schema, '{"value":"text"}'),
          equals({'value': 'text'}));

      expect(
          expandPartialJson(schema, '{"value":123}'), equals({'value': 123}));

      expect(
          expandPartialJson(schema, '{"value":true}'), equals({'value': true}));
    });

    test('handles anyOf schemas', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'flexible': {
            'anyOf': [
              {'type': 'string', 'minLength': 5},
              {
                'type': 'array',
                'items': {'type': 'string'}
              }
            ]
          }
        }
      });

      expect(expandPartialJson(schema, '{"flexible":"hello world"}'),
          equals({'flexible': 'hello world'}));

      expect(
          expandPartialJson(schema, '{"flexible":["a","b"]}'),
          equals({
            'flexible': ['a', 'b']
          }));
    });

    test('handles enum values', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'status': {
            'type': 'string',
            'enum': ['pending', 'active', 'completed'],
            'default': 'pending'
          },
          'priority': {
            'type': 'integer',
            'enum': [1, 2, 3],
            'default': 2
          }
        }
      });

      expect(expandPartialJson(schema, '{}'),
          equals({'status': 'pending', 'priority': 2}));

      expect(expandPartialJson(schema, '{"status":"active"}'),
          equals({'status': 'active', 'priority': 2}));

      // Invalid enum value still parses
      expect(expandPartialJson(schema, '{"status":"invalid"}'),
          equals({'status': 'invalid', 'priority': 2}));
    });

    test('handles const values', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'version': {'const': '1.0.0'},
          'type': {'const': 'config'}
        }
      });

      expect(expandPartialJson(schema, '{"version":"1.0.0"}'),
          equals({'version': '1.0.0'}));

      // Different const value still parses
      expect(expandPartialJson(schema, '{"version":"2.0.0"}'),
          equals({'version': '2.0.0'}));
    });
  });

  group('Mixed Type Arrays', () {
    test('handles arrays with mixed types', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'mixed': {
            'type': 'array',
            'items': {} // Any type allowed
          }
        }
      });

      expect(
          expandPartialJson(
              schema, '{"mixed":[1,"two",true,null,{"a":1},[1,2]]}'),
          equals({
            'mixed': [
              1,
              'two',
              true,
              null,
              {'a': 1},
              [1, 2]
            ]
          }));

      // Partial mixed array
      expect(
          expandPartialJson(schema, '{"mixed":[1,"two",tru'),
          equals({
            'mixed': [1, 'two', true]
          }));
    });

    test('handles tuple validation', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'coordinate': {
            'type': 'array',
            'items': [
              {'type': 'number'}, // x
              {'type': 'number'}, // y
              {'type': 'string'} // label
            ],
            'minItems': 3,
            'maxItems': 3
          }
        }
      });

      expect(
          expandPartialJson(schema, '{"coordinate":[1.5,2.5,"point"]}'),
          equals({
            'coordinate': [1.5, 2.5, 'point']
          }));

      // Partial tuple
      expect(
          expandPartialJson(schema, '{"coordinate":[1.5,2.5'),
          equals({
            'coordinate': [1.5, 2.5]
          }));
    });
  });

  group('Very Long Content', () {
    test('handles very long strings', () {
      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      final longString = 'a' * 10000;
      final json = '{"long":"$longString"}';

      expect(expandPartialJson(schema, json), equals({'long': longString}));

      // Partial long string
      final partialLong = 'a' * 5000;
      final partialJson = '{"long":"$partialLong';

      expect(expandPartialJson(schema, partialJson),
          equals({'long': partialLong}));
    });

    test('handles deeply nested structures', () {
      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      // Build a deeply nested structure
      final expected = <String, dynamic>{};
      var current = expected;

      final json = StringBuffer('{');
      for (var i = 0; i < 20; i++) {
        json.write('"level$i":{');
        current['level$i'] = <String, dynamic>{};
        current = current['level$i'] as Map<String, dynamic>;
      }

      current['value'] = 'deep';
      json.write('"value":"deep"}');
      for (var i = 0; i < 20; i++) {
        json.write('}');
      }
      json.write('}');

      expect(expandPartialJson(schema, json.toString()), equals(expected));

      // Partial deep nesting
      final partialJson = json.toString().substring(0, json.length ~/ 2);
      final result = expandPartialJson(schema, partialJson);
      if (result != null) {
        expect(result, isA<Map<String, dynamic>>());
      }
    });
  });

  group('Property Name Completion Edge Cases', () {
    test('handles ambiguous property name prefixes', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'temperature': {'type': 'number', 'default': 20},
          'temp': {'type': 'string', 'default': 'temporary'},
          'template': {'type': 'string', 'default': 'default template'}
        }
      });

      // Ambiguous prefix should fail
      expect(expandPartialJson(schema, '{"tem'), isNull);

      // Unique prefix should complete
      expect(
          expandPartialJson(schema, '{"templ'),
          equals({
            'template': 'default template',
            'temperature': 20,
            'temp': 'temporary'
          }));
    });

    test('handles property names with special characters', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'with-dash': {'type': 'string', 'default': 'dashed'},
          'with_underscore': {'type': 'string', 'default': 'underscored'},
          'with.dot': {'type': 'string', 'default': 'dotted'},
          'with space': {'type': 'string', 'default': 'spaced'}
        }
      });

      expect(
          expandPartialJson(schema, '{"with-'),
          equals({
            'with-dash': 'dashed',
            'with_underscore': 'underscored',
            'with.dot': 'dotted',
            'with space': 'spaced'
          }));
    });
  });

  group('Streaming Simulation with Complex Schemas', () {
    test('progressively builds complex object with defaults', () async {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'metadata': {
            'type': 'object',
            'properties': {
              'version': {'type': 'string', 'default': '1.0.0'},
              'created': {'type': 'string', 'default': '2024-01-01'},
              'author': {'type': 'string', 'default': 'system'}
            }
          },
          'config': {
            'type': 'object',
            'properties': {
              'debug': {'type': 'boolean', 'default': false},
              'timeout': {'type': 'integer', 'default': 30},
              'retries': {'type': 'integer', 'default': 3}
            }
          },
          'data': {
            'type': 'array',
            'default': [],
            'items': {
              'type': 'object',
              'properties': {
                'id': {'type': 'integer'},
                'value': {'type': 'string'}
              }
            }
          }
        }
      });

      const complexJson = '''
{
  "metadata": {
    "version": "2.0.0",
    "created": "2024-03-15",
    "author": "user"
  },
  "config": {
    "debug": true,
    "timeout": 60
  },
  "data": [
    {"id": 1, "value": "first"},
    {"id": 2, "value": "second"}
  ]
}''';

      // Test progressive building with different chunk sizes
      for (final chunkSize in [1, 5, 10, 20]) {
        final chunks = <String>[];
        for (var i = 0; i < complexJson.length; i += chunkSize) {
          chunks.add(complexJson.substring(
              i,
              i + chunkSize > complexJson.length
                  ? complexJson.length
                  : i + chunkSize));
        }

        final buffer = StringBuffer();
        Map<String, dynamic>? lastValidParse;

        for (final chunk in chunks) {
          buffer.write(chunk);
          final result = expandPartialJson(schema, buffer.toString());
          if (result != null) {
            lastValidParse = result;

            // Verify defaults are applied to incomplete parts
            expect(result, isA<Map<String, dynamic>>());

            // Check if defaults are present when expected
            if (!buffer.toString().contains('"config"')) {
              expect(result['config'], isNull);
            }

            if (buffer.toString().contains('"config":{') &&
                !buffer.toString().contains('"retries"')) {
              final config = result['config'] as Map<String, dynamic>?;
              if (config != null) {
                expect(config['retries'], equals(3));
              }
            }
          }
        }

        // Final result should match expected
        expect(lastValidParse, isNotNull);
        final metadata = lastValidParse!['metadata'] as Map<String, dynamic>;
        expect(metadata['version'], equals('2.0.0'));

        final config = lastValidParse['config'] as Map<String, dynamic>;
        expect(config['debug'], equals(true));
        expect(config['timeout'], equals(60));
        expect(config['retries'], equals(3)); // From default

        final data = lastValidParse['data'] as List;
        expect(data.length, equals(2));
      }
    });
  });
}

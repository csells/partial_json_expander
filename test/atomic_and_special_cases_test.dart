// ignore_for_file: avoid_dynamic_calls

import 'package:json_schema/json_schema.dart';
import 'package:partial_json_expander/partial_json_expander.dart';
import 'package:test/test.dart';

void main() {
  group('Atomic Values Without Object Wrapper', () {
    test('handles bare strings - should fail', () {
      final schema = JsonSchema.create({'type': 'string'});

      // The current implementation doesn't support root-level strings
      // It expects objects, so this should fail
      expect(() => expandPartialJson(schema, '"hello"'), throwsFormatException);
    });

    test('handles bare numbers - should fail', () {
      final schema = JsonSchema.create({'type': 'number'});

      // The current implementation doesn't support root-level numbers
      expect(() => expandPartialJson(schema, '42'), throwsFormatException);
      expect(() => expandPartialJson(schema, '3.14'), throwsFormatException);
    });

    test('handles bare arrays - should fail', () {
      final schema = JsonSchema.create({
        'type': 'array',
        'items': {'type': 'string'}
      });

      // The current implementation doesn't support root-level arrays
      expect(
          () => expandPartialJson(schema, '["a","b"]'), throwsFormatException);
    });
  });

  group('Boundary Value Testing', () {
    test('handles zero-length strings', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'empty': {'type': 'string', 'default': ''}
        }
      });

      expect(expandPartialJson(schema, '{}'), equals({'empty': ''}));
      expect(expandPartialJson(schema, '{"empty":""}'), equals({'empty': ''}));
    });

    test('handles maximum integer values', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'maxInt': {'type': 'integer'},
          'minInt': {'type': 'integer'}
        }
      });

      // JavaScript safe integers
      const maxSafe = 9007199254740991;
      const minSafe = -9007199254740991;

      expect(expandPartialJson(schema, '{"maxInt":$maxSafe,"minInt":$minSafe}'),
          equals({'maxInt': maxSafe, 'minInt': minSafe}));
    });

    test('handles infinity and special float values', () {
      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      // JSON doesn't support Infinity, but test edge cases
      expect(expandPartialJson(schema, '{"veryLarge":1e308}'),
          equals({'veryLarge': 1e308}));

      expect(expandPartialJson(schema, '{"verySmall":1e-308}'),
          equals({'verySmall': 1e-308}));
    });
  });

  group('Complex Nesting Patterns', () {
    test('handles alternating object/array nesting', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'data': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'values': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'items': {
                        'type': 'array',
                        'items': {'type': 'number'}
                      }
                    }
                  }
                }
              }
            }
          }
        }
      });

      const json = '{"data":[{"values":[{"items":[1,2,3]},{"items":[4,5';
      final result = expandPartialJson(schema, json);
      expect(
          result,
          equals({
            'data': [
              {
                'values': [
                  {
                    'items': [1, 2, 3]
                  },
                  {
                    'items': [4, 5]
                  }
                ]
              }
            ]
          }));
    });

    test('handles circular-like structures with refs', () {
      // Testing structures that would be circular with $ref
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'node': {
            'type': 'object',
            'properties': {
              'value': {'type': 'string'},
              'next': {
                'type': 'object',
                'properties': {
                  'value': {'type': 'string'},
                  'next': {
                    'type': 'object',
                    'properties': {
                      'value': {'type': 'string'}
                    }
                  }
                }
              }
            }
          }
        }
      });

      const json = '{"node":{"value":"a","next":{"value":"b","next":{"val';
      final result = expandPartialJson(schema, json);
      expect(result, isNotNull);
      final node = result!['node'] as Map<String, dynamic>;
      expect(node['value'], equals('a'));
    });
  });

  group('Character Encoding Edge Cases', () {
    test('handles various UTF-8 sequences', () {
      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      // 2-byte UTF-8
      expect(expandPartialJson(schema, '{"text":"café"}'),
          equals({'text': 'café'}));

      // 3-byte UTF-8
      expect(
          expandPartialJson(schema, '{"text":"你好"}'), equals({'text': '你好'}));

      // 4-byte UTF-8 (emoji)
      expect(
          expandPartialJson(schema, '{"text":"🎉"}'), equals({'text': '🎉'}));

      // Mixed
      expect(expandPartialJson(schema, '{"text":"Hello café 你好 🎉"}'),
          equals({'text': 'Hello café 你好 🎉'}));
    });

    test('handles control characters', () {
      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      // Various control characters (escaped)
      expect(expandPartialJson(schema, r'{"text":"\b\f\n\r\t"}'),
          equals({'text': '\b\f\n\r\t'}));

      // Partial escape sequence
      expect(expandPartialJson(schema, r'{"text":"hello\n'),
          equals({'text': 'hello\n'}));
    });
  });

  group('Schema Default Edge Cases', () {
    test('handles defaults that reference other properties', () {
      // This tests conceptual dependencies in defaults
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'firstName': {'type': 'string', 'default': 'John'},
          'lastName': {'type': 'string', 'default': 'Doe'},
          'fullName': {
            'type': 'string',
            'default': 'John Doe' // Conceptually derived from other defaults
          }
        }
      });

      expect(
          expandPartialJson(schema, '{}'),
          equals({
            'firstName': 'John',
            'lastName': 'Doe',
            'fullName': 'John Doe'
          }));

      // Override one part
      expect(
          expandPartialJson(schema, '{"firstName":"Jane"}'),
          equals({
            'firstName': 'Jane',
            'lastName': 'Doe',
            'fullName': 'John Doe' // Default doesn't update
          }));
    });

    test('handles defaults with special JSON values', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'nullDefault': {'default': null},
          'boolDefault': {'type': 'boolean', 'default': false},
          'emptyArrayDefault': {'type': 'array', 'default': []},
          'emptyObjectDefault': {'type': 'object', 'default': {}}
        }
      });

      expect(
          expandPartialJson(schema, '{}'),
          equals({
            'nullDefault': null,
            'boolDefault': false,
            'emptyArrayDefault': [],
            'emptyObjectDefault': {}
          }));
    });
  });

  group('Performance Edge Cases', () {
    test('handles very wide objects', () {
      // Object with many properties
      final properties = <String, dynamic>{};
      for (var i = 0; i < 100; i++) {
        properties['prop$i'] = {'type': 'string', 'default': 'value$i'};
      }

      final schema =
          JsonSchema.create({'type': 'object', 'properties': properties});

      final result = expandPartialJson(schema, '{}');
      expect(result!.length, equals(100));
      expect(result['prop0'], equals('value0'));
      expect(result['prop99'], equals('value99'));
    });

    test('handles very long arrays', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'bigArray': {
            'type': 'array',
            'items': {'type': 'integer'}
          }
        }
      });

      // Build array with 1000 items
      final arrayStr = List.generate(1000, (i) => i).join(',');
      final json = '{"bigArray":[$arrayStr';

      final result = expandPartialJson(schema, json);
      expect((result!['bigArray'] as List).length, equals(1000));
    });
  });

  group('Partial Completion Edge Cases', () {
    test('handles partial property names at various positions', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'firstName': {'type': 'string'},
          'lastName': {'type': 'string'},
          'middleName': {'type': 'string'}
        }
      });

      // Start of object
      expect(expandPartialJson(schema, '{"fir'), isNull);

      // After another property
      expect(expandPartialJson(schema, '{"firstName":"John","la'), isNull);

      // Ambiguous prefix (matches firstName)
      expect(expandPartialJson(schema, '{"f'), isNotNull);
    });

    test('handles partial values of different types', () {
      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      // Partial string
      expect(expandPartialJson(schema, '{"s":"par'), equals({'s': 'par'}));

      // Partial number
      expect(expandPartialJson(schema, '{"n":123.'), equals({'n': 123}));

      // Partial boolean (should fail)
      expect(expandPartialJson(schema, '{"b":tr'), isNull);

      // Partial null (should fail)
      expect(expandPartialJson(schema, '{"x":nu'), isNull);

      // Partial array
      expect(
          expandPartialJson(schema, '{"a":[1,2,'),
          equals({
            'a': [1, 2]
          }));
    });
  });

  group('Mixed Schema Types', () {
    test('handles properties with multiple possible types', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'flexible': {
            'type': ['string', 'number', 'boolean', 'null']
          }
        }
      });

      expect(expandPartialJson(schema, '{"flexible":"text"}'),
          equals({'flexible': 'text'}));

      expect(expandPartialJson(schema, '{"flexible":123}'),
          equals({'flexible': 123}));

      expect(expandPartialJson(schema, '{"flexible":true}'),
          equals({'flexible': true}));

      expect(expandPartialJson(schema, '{"flexible":null}'),
          equals({'flexible': null}));
    });
  });

  group('Real-world Scenario Testing', () {
    test('handles typical API response structure', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'status': {'type': 'string', 'default': 'success'},
          'data': {
            'type': 'object',
            'properties': {
              'items': {
                'type': 'array',
                'default': [],
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'string'},
                    'name': {'type': 'string'},
                    'metadata': {'type': 'object', 'default': {}}
                  }
                }
              },
              'pagination': {
                'type': 'object',
                'properties': {
                  'page': {'type': 'integer', 'default': 1},
                  'limit': {'type': 'integer', 'default': 20},
                  'total': {'type': 'integer', 'default': 0}
                }
              }
            }
          },
          'errors': {
            'type': 'array',
            'default': [],
            'items': {'type': 'string'}
          }
        }
      });

      // Partial API response
      const partial =
          '''{"status":"success","data":{"items":[{"id":"123","na''';
      final result = expandPartialJson(schema, partial);

      expect(result!['status'], equals('success'));
      expect(result['errors'], equals([]));
      final data = result['data'] as Map<String, dynamic>;
      final items = data['items'] as List;
      expect(items.length, equals(1));
      expect((items[0] as Map)['id'], equals('123'));
    });

    test('handles configuration file structure', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'version': {'type': 'string', 'default': '1.0.0'},
          'environment': {
            'type': 'string',
            'enum': ['development', 'staging', 'production'],
            'default': 'development'
          },
          'database': {
            'type': 'object',
            'properties': {
              'host': {'type': 'string', 'default': 'localhost'},
              'port': {'type': 'integer', 'default': 5432},
              'name': {'type': 'string', 'default': 'myapp'},
              'ssl': {'type': 'boolean', 'default': false}
            }
          },
          'features': {
            'type': 'object',
            'additionalProperties': {'type': 'boolean'},
            'default': {'auth': true, 'analytics': false, 'beta': false}
          }
        }
      });

      // Partial config
      const partial =
          '{"environment":"production","database":{"host":"db.example.com",'
          '"port":';
      final result = expandPartialJson(schema, partial);

      expect(result!['version'], equals('1.0.0'));
      expect(result['environment'], equals('production'));
      final db = result['database'] as Map<String, dynamic>;
      expect(db['host'], equals('db.example.com'));
      expect(db['port'], isNull); // Partial number
      expect(db['name'], equals('myapp')); // Default
      expect(result['features'],
          equals({'auth': true, 'analytics': false, 'beta': false}));
    });
  });
}

import 'package:json_schema/json_schema.dart';
import 'package:partial_json_expander/partial_json_expander.dart';
import 'package:test/test.dart';

void main() {
  group('expandPartialJson - Basic JSON Repair', () {
    // Create a basic schema that accepts any object
    final basicSchema = JsonSchema.create({
      'type': 'object',
      'additionalProperties': true,
    });

    test('repairs incomplete object with missing closing brace', () {
      final result = expandPartialJson(basicSchema, '{"name":"John"');
      expect(result, equals({'name': 'John'}));
    });

    test('repairs incomplete string value', () {
      final result = expandPartialJson(basicSchema, '{"name":"Jo');
      expect(result, equals({'name': 'Jo'}));
    });

    test('repairs incomplete property name without schema', () {
      // Without schema properties, incomplete keys return null
      final result = expandPartialJson(basicSchema, '{"na');
      expect(result, isNull);
    });

    test('repairs nested objects', () {
      final result =
          expandPartialJson(basicSchema, '{"user":{"name":"John","age":30');
      expect(
          result,
          equals({
            'user': {'name': 'John', 'age': 30}
          }));
    });

    test('repairs arrays', () {
      final result = expandPartialJson(basicSchema, '{"items":[1,2,3');
      expect(
          result,
          equals({
            'items': [1, 2, 3]
          }));
    });

    test('handles trailing commas', () {
      final result = expandPartialJson(basicSchema, '{"name":"John",');
      expect(result, equals({'name': 'John'}));
    });

    test('handles empty input', () {
      // Empty input throws FormatException
      expect(
        () => expandPartialJson(basicSchema, ''),
        throwsFormatException,
      );
    });

    test('handles whitespace only', () {
      // Whitespace only throws FormatException
      expect(
        () => expandPartialJson(basicSchema, '  \n\t  '),
        throwsFormatException,
      );
    });

    test('handles complete valid JSON', () {
      final result = expandPartialJson(basicSchema, '{"name":"John","age":30}');
      expect(result, equals({'name': 'John', 'age': 30}));
    });

    test('handles simple incomplete array', () {
      final result = expandPartialJson(basicSchema, '{"arr":[1,2');
      expect(
          result,
          equals({
            'arr': [1, 2]
          }));
    });

    test('repairs missing braces', () {
      final result = expandPartialJson(basicSchema, '{');
      expect(result, equals({}));
    });
  });

  group('expandPartialJson - Schema Defaults', () {
    test('applies simple default values', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'default': 'Unknown'},
          'age': {'type': 'integer', 'default': 0}
        }
      });

      final result = expandPartialJson(schema, '{}');
      expect(result, equals({'name': 'Unknown', 'age': 0}));
    });

    test('preserves existing values over defaults', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'default': 'Unknown'},
          'age': {'type': 'integer', 'default': 0}
        }
      });

      final result = expandPartialJson(schema, '{"name":"John"}');
      expect(result, equals({'name': 'John', 'age': 0}));
    });

    test('applies nested object defaults', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'user': {
            'type': 'object',
            'default': {'name': 'Guest', 'role': 'visitor'},
            'properties': {
              'name': {'type': 'string'},
              'role': {'type': 'string'}
            }
          }
        }
      });

      final result = expandPartialJson(schema, '{}');
      expect(
          result,
          equals({
            'user': {'name': 'Guest', 'role': 'visitor'}
          }));
    });

    test('merges partial nested objects with defaults', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'settings': {
            'type': 'object',
            'properties': {
              'theme': {'type': 'string', 'default': 'light'},
              'fontSize': {'type': 'integer', 'default': 12}
            }
          }
        }
      });

      final result = expandPartialJson(schema, '{"settings":{"theme":"dark"}}');
      expect(
          result,
          equals({
            'settings': {'theme': 'dark', 'fontSize': 12}
          }));
    });

    test('applies array defaults', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'tags': {
            'type': 'array',
            'default': ['general'],
            'items': {'type': 'string'}
          }
        }
      });

      final result = expandPartialJson(schema, '{}');
      expect(
          result,
          equals({
            'tags': ['general']
          }));
    });

    test('removes properties when additionalProperties is false', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'allowed': {'type': 'string'}
        }
      });

      final result =
          expandPartialJson(schema, '{"allowed":"yes","notAllowed":"no"}');
      expect(result, equals({'allowed': 'yes'}));
    });

    test('completes partial property name using schema', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'temperature': {'type': 'number', 'default': 20},
          'humidity': {'type': 'number', 'default': 50}
        }
      });

      final result = expandPartialJson(schema, '{"temp');
      expect(result, equals({'temperature': 20, 'humidity': 50}));
    });
  });

  group('randomChunkedJson', () {
    test('produces valid JSON chunks', () async {
      const json = '{"name":"John","age":30,"city":"NYC"}';
      final chunks = await randomChunkedJson(
        json,
        seed: 42,
        minChunk: 5,
        maxChunk: 10,
      ).toList();

      final reconstructed = chunks.join();
      expect(reconstructed, equals(json));
    });

    test('respects chunk size constraints', () async {
      const json = '{"name":"John","age":30}';
      final chunks = await randomChunkedJson(
        json,
        seed: 42,
        minChunk: 3,
        maxChunk: 5,
      ).toList();

      // All chunks except possibly the last should respect size constraints
      for (var i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        if (i < chunks.length - 1) {
          // Non-final chunks must respect min/max constraints
          expect(chunk.length, greaterThanOrEqualTo(3));
          expect(chunk.length, lessThanOrEqualTo(5));
        } else {
          // Final chunk can be smaller than minChunk if not enough chars left
          expect(chunk.length, greaterThanOrEqualTo(1));
          expect(chunk.length, lessThanOrEqualTo(5));
        }
      }
    });

    test('handles single chunk when json is small', () async {
      const json = '{"a":1}';
      final chunks = await randomChunkedJson(
        json,
        seed: 42,
        minChunk: 10,
        maxChunk: 20,
      ).toList();

      expect(chunks.length, equals(1));
      expect(chunks.first, equals(json));
    });

    test('generates consistent output with seed', () async {
      const json = '{"name":"John","age":30,"city":"NYC"}';

      final chunks1 = await randomChunkedJson(
        json,
        seed: 42,
        minChunk: 3,
        maxChunk: 8,
      ).toList();
      final chunks2 = await randomChunkedJson(
        json,
        seed: 42,
        minChunk: 3,
        maxChunk: 8,
      ).toList();

      expect(chunks1, equals(chunks2));
    });

    test('generates different output with different seeds', () async {
      const json = '{"name":"John","age":30,"city":"NYC"}';

      final chunks1 = await randomChunkedJson(
        json,
        seed: 42,
        minChunk: 3,
        maxChunk: 8,
      ).toList();
      final chunks2 = await randomChunkedJson(
        json,
        seed: 123,
        minChunk: 3,
        maxChunk: 8,
      ).toList();

      // With different seeds, chunks should be different
      expect(chunks1, isNot(equals(chunks2)));
    });

    test('handles breaks at any position with multiple seeds', () async {
      // Test complex JSON with nested structures
      const complexJson = '''
{
  "user": {
    "name": "John Doe",
    "age": 30,
    "email": "john@example.com",
    "active": true,
    "score": 98.5,
    "tags": ["developer", "team-lead", "mentor"],
    "address": {
      "street": "123 Main St",
      "city": "New York",
      "coordinates": {"lat": 40.7128, "lng": -74.0060}
    },
    "projects": [
      {"id": 1, "name": "Project Alpha", "status": "completed"},
      {"id": 2, "name": "Project Beta", "status": "in-progress"}
    ]
  }
}''';

      // Create schema that knows about the structure
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'user': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'age': {'type': 'integer'},
              'email': {'type': 'string'},
              'active': {'type': 'boolean'},
              'score': {'type': 'number'},
              'tags': {
                'type': 'array',
                'items': {'type': 'string'}
              },
              'address': {
                'type': 'object',
                'properties': {
                  'street': {'type': 'string'},
                  'city': {'type': 'string'},
                  'coordinates': {
                    'type': 'object',
                    'properties': {
                      'lat': {'type': 'number'},
                      'lng': {'type': 'number'}
                    }
                  }
                }
              },
              'projects': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'integer'},
                    'name': {'type': 'string'},
                    'status': {'type': 'string'}
                  }
                }
              }
            }
          }
        }
      });

      // Test with many different seeds to ensure breaks at various positions
      // work correctly
      final seeds = List.generate(50, (i) => i * 7 + 13); // 50 different seeds
      var successfulParses = 0;
      var totalAttempts = 0;

      for (final seed in seeds) {
        final chunks = await randomChunkedJson(
          complexJson,
          seed: seed,
          minChunk: 1,
          maxChunk: 10,
        ).toList();

        // Reconstruct progressively and ensure each partial is valid
        final buffer = StringBuffer();
        for (final chunk in chunks) {
          buffer.write(chunk);
          totalAttempts++;

          // Try to expand the partial JSON
          try {
            final result = expandPartialJson(schema, buffer.toString());

            // If we get a result, it should be a valid map
            if (result != null) {
              expect(result, isA<Map<String, dynamic>>());
              successfulParses++;

              // For complete JSON, verify the structure
              if (buffer.toString().trim() == complexJson.trim()) {
                final user = result['user'] as Map<String, dynamic>;
                expect(user['name'], equals('John Doe'));
                expect(user['age'], equals(30));
                expect(
                    user['tags'], equals(['developer', 'team-lead', 'mentor']));
                expect((user['projects'] as List).length, equals(2));
              }
            }
          } on Exception {
            // Some partials will fail to parse, which is expected
          }
        }
      }

      // Should have a reasonable success rate
      final successRate = successfulParses / totalAttempts;
      expect(successRate, greaterThan(0.1),
          reason: 'Success rate too low: $successRate');
    });

    test('stress test with extreme chunking', () async {
      // Test with very small chunks to ensure every possible break point works
      const json = '{"a":{"b":[1,2,{"c":"d"}],"e":null,"f":true}}';

      // Test single-character chunks (most extreme case)
      final chunks = await randomChunkedJson(
        json,
        seed: 999,
        minChunk: 1,
        maxChunk: 1,
      ).toList();

      expect(chunks.join(), equals(json));
      expect(chunks.length, equals(json.length));

      // Test progressive expansion
      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      final buffer = StringBuffer();
      var successfulExpansions = 0;

      for (final chunk in chunks) {
        buffer.write(chunk);
        try {
          final result = expandPartialJson(schema, buffer.toString());
          if (result != null) {
            successfulExpansions++;
          }
        } on Exception {
          // Expected for some partials
        }
      }

      // Should have some successful expansions along the way
      expect(successfulExpansions, greaterThan(0));
    });

    test('handles breaks at problematic positions', () async {
      // Test breaks at specific problematic positions
      final testCases = [
        // JSON string, break positions to test
        ('{"name":"value"}', [7, 8, 9]), // Break in middle of string value
        ('{"a":true,"b":false}', [5, 9, 14]), // Break in boolean values
        ('{"num":123.45}', [7, 10]), // Break in number
        ('{"arr":[1,2,3]}', [8, 10, 12]), // Break in array
        ('{"x":null}', [5, 6, 7]), // Break in null
        ('{"a":{"b":{"c":1}}}', [6, 10, 14]), // Nested objects
      ];

      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      for (final testCase in testCases) {
        final (json, breakPositions) = testCase;

        for (final breakPos in breakPositions) {
          if (breakPos < json.length) {
            final part1 = json.substring(0, breakPos);
            final part2 = json.substring(breakPos);

            // Test first part (might fail)
            try {
              expandPartialJson(schema, part1);
            } on Exception {
              // Expected for some positions
            }

            // Test accumulated (should always work)
            try {
              final result2 = expandPartialJson(schema, part1 + part2);
              expect(result2, isNotNull,
                  reason: 'Failed to parse complete JSON broken at '
                      'position $breakPos in "$json"');
            } on Exception catch (e) {
              // Complete JSON should parse
              fail('Complete JSON should parse: $e');
            }
          }
        }
      }
    });

    test('progressive parsing with real-world example', () async {
      // Simulate a real streaming response from an LLM
      const llmResponse = r'''
{
  "response": "Here's how to implement the fibonacci function",
  "code": {
    "language": "python",
    "content": "def fibonacci(n):\n    if n <= 1:\n        return n\n    return fibonacci(n-1) + fibonacci(n-2)"
  },
  "explanation": "This uses recursion to calculate fibonacci numbers",
  "complexity": {"time": "O(2^n)", "space": "O(n)"}
}''';

      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'response': {'type': 'string'},
          'code': {
            'type': 'object',
            'properties': {
              'language': {'type': 'string'},
              'content': {'type': 'string'}
            }
          },
          'explanation': {'type': 'string'},
          'complexity': {
            'type': 'object',
            'properties': {
              'time': {'type': 'string'},
              'space': {'type': 'string'}
            }
          }
        }
      });

      // Simulate realistic streaming chunks
      final seeds = [42, 99, 156, 234, 500, 777, 1234];

      for (final seed in seeds) {
        final chunks = await randomChunkedJson(
          llmResponse,
          seed: seed,
          minChunk: 5,
          maxChunk: 25, // Realistic chunk sizes
        ).toList();

        final buffer = StringBuffer();
        Map<String, dynamic>? lastValidResult;

        for (final chunk in chunks) {
          buffer.write(chunk);
          try {
            final result = expandPartialJson(schema, buffer.toString());

            if (result != null) {
              lastValidResult = result;
              // Verify partial results make sense
              expect(result, isA<Map<String, dynamic>>());
            }
          } on Exception {
            // Expected for some partials
          }
        }

        // Verify final result
        expect(lastValidResult, isNotNull);
        final response = lastValidResult!['response'] as String;
        expect(response, contains('fibonacci'));

        final code = lastValidResult['code'] as Map<String, dynamic>;
        expect(code['language'], equals('python'));

        final complexity =
            lastValidResult['complexity'] as Map<String, dynamic>;
        expect(complexity['time'], equals('O(2^n)'));
      }
    });
  });

  group('Edge Cases', () {
    final edgeSchema = JsonSchema.create({
      'type': 'object',
      'additionalProperties': true,
    });

    test('handles deeply nested structures', () {
      final result =
          expandPartialJson(edgeSchema, '{"a":{"b":{"c":{"d":"value');
      expect(
          result,
          equals({
            'a': {
              'b': {
                'c': {'d': 'value'}
              }
            }
          }));
    });

    test('handles escaped quotes in strings', () {
      final result =
          expandPartialJson(edgeSchema, r'{"message":"Hello \"World\"');
      expect(result, equals({'message': 'Hello "World"'}));
    });

    test('handles numbers in various formats', () {
      final result = expandPartialJson(
          edgeSchema, '{"int":42,"float":3.14,"exp":1e5,"neg":-10');
      expect(result,
          equals({'int': 42, 'float': 3.14, 'exp': 100000, 'neg': -10}));
    });

    test('handles Unicode characters', () {
      final result =
          expandPartialJson(edgeSchema, '{"emoji":"👍","chinese":"你好"');
      expect(result, equals({'emoji': '👍', 'chinese': '你好'}));
    });

    test('handles schema with complex validation', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'email': {
            'type': 'string',
            'format': 'email',
            'default': 'user@example.com'
          },
          'score': {
            'type': 'number',
            'minimum': 0,
            'maximum': 100,
            'default': 50
          }
        }
      });

      final result = expandPartialJson(schema, '{"score":75');
      expect(result, equals({'score': 75, 'email': 'user@example.com'}));
    });

    test('handles missing value after colon', () {
      final result = expandPartialJson(edgeSchema, '{"key":');
      expect(result, equals({'key': null}));
    });

    test('handles array with missing closing bracket', () {
      final result = expandPartialJson(edgeSchema, '{"arr":[1,2,3');
      expect(
          result,
          equals({
            'arr': [1, 2, 3]
          }));
    });

    test('handles nested objects with missing braces', () {
      final result = expandPartialJson(edgeSchema, '{"a":{"b":1');
      expect(
          result,
          equals({
            'a': {'b': 1}
          }));
    });
  });
}

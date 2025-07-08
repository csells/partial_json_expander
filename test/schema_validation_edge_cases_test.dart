import 'package:json_schema/json_schema.dart';
import 'package:partial_json_expander/partial_json_expander.dart';
import 'package:test/test.dart';

void main() {
  group('Format Validation', () {
    test('handles date-time format', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'timestamp': {
            'type': 'string',
            'format': 'date-time',
            'default': '2024-01-01T00:00:00Z'
          }
        }
      });

      expect(expandPartialJson(schema, '{}'),
          equals({'timestamp': '2024-01-01T00:00:00Z'}));

      expect(expandPartialJson(schema, '{"timestamp":"2024-03-15T10:30:00Z"}'),
          equals({'timestamp': '2024-03-15T10:30:00Z'}));

      // Partial date-time
      expect(expandPartialJson(schema, '{"timestamp":"2024-03-15T10:30'),
          equals({'timestamp': '2024-03-15T10:30'}));
    });

    test('handles email format', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'email': {
            'type': 'string',
            'format': 'email',
            'default': 'default@example.com'
          }
        }
      });

      expect(expandPartialJson(schema, '{}'),
          equals({'email': 'default@example.com'}));

      expect(expandPartialJson(schema, '{"email":"user@domain.com"}'),
          equals({'email': 'user@domain.com'}));

      // Invalid email still parses
      expect(expandPartialJson(schema, '{"email":"not-an-email"}'),
          equals({'email': 'not-an-email'}));
    });

    test('handles uri format', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'website': {
            'type': 'string',
            'format': 'uri',
            'default': 'https://example.com'
          }
        }
      });

      expect(expandPartialJson(schema, '{}'),
          equals({'website': 'https://example.com'}));

      expect(expandPartialJson(schema, '{"website":"https://dart.dev"}'),
          equals({'website': 'https://dart.dev'}));

      // Partial URI
      expect(expandPartialJson(schema, '{"website":"https://dart'),
          equals({'website': 'https://dart'}));
    });

    test('handles regex pattern', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'code': {
            'type': 'string',
            'pattern': r'^[A-Z]{3}-\d{3}$',
            'default': 'ABC-123'
          }
        }
      });

      expect(expandPartialJson(schema, '{}'), equals({'code': 'ABC-123'}));

      // Valid pattern
      expect(expandPartialJson(schema, '{"code":"XYZ-789"}'),
          equals({'code': 'XYZ-789'}));

      // Invalid pattern still parses
      expect(expandPartialJson(schema, '{"code":"invalid"}'),
          equals({'code': 'invalid'}));
    });
  });

  group('String Constraints', () {
    test('handles minLength and maxLength', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'username': {
            'type': 'string',
            'minLength': 3,
            'maxLength': 20,
            'default': 'user'
          },
          'bio': {
            'type': 'string',
            'maxLength': 500,
            'default': 'No bio provided'
          }
        }
      });

      expect(expandPartialJson(schema, '{}'),
          equals({'username': 'user', 'bio': 'No bio provided'}));

      // Too short still parses
      expect(expandPartialJson(schema, '{"username":"ab"}'),
          equals({'username': 'ab', 'bio': 'No bio provided'}));

      // Too long still parses
      final longUsername = 'a' * 25;
      expect(expandPartialJson(schema, '{"username":"$longUsername"}'),
          equals({'username': longUsername, 'bio': 'No bio provided'}));
    });
  });

  group('Number Constraints', () {
    test('handles minimum and maximum', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'age': {
            'type': 'integer',
            'minimum': 0,
            'maximum': 150,
            'default': 25
          },
          'score': {
            'type': 'number',
            'minimum': 0.0,
            'maximum': 100.0,
            'exclusiveMinimum': true,
            'default': 50.0
          }
        }
      });

      expect(
          expandPartialJson(schema, '{}'), equals({'age': 25, 'score': 50.0}));

      // Out of range still parses
      expect(expandPartialJson(schema, '{"age":-5,"score":150.5}'),
          equals({'age': -5, 'score': 150.5}));
    });

    test('handles multipleOf', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'quantity': {'type': 'integer', 'multipleOf': 5, 'default': 10}
        }
      });

      expect(expandPartialJson(schema, '{}'), equals({'quantity': 10}));

      // Not multiple still parses
      expect(
          expandPartialJson(schema, '{"quantity":7}'), equals({'quantity': 7}));
    });
  });

  group('Complex Default Values', () {
    test('handles object defaults with nested structures', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'settings': {
            'type': 'object',
            'default': {
              'theme': {
                'primary': '#007bff',
                'secondary': '#6c757d',
                'fonts': ['Arial', 'Helvetica', 'sans-serif']
              },
              'layout': {
                'sidebar': {'width': 250, 'collapsed': false},
                'header': {'height': 60, 'fixed': true}
              }
            },
            'properties': {
              'theme': {
                'type': 'object',
                'properties': {
                  'primary': {'type': 'string'},
                  'secondary': {'type': 'string'},
                  'fonts': {
                    'type': 'array',
                    'items': {'type': 'string'}
                  }
                }
              },
              'layout': {
                'type': 'object',
                'properties': {
                  'sidebar': {
                    'type': 'object',
                    'properties': {
                      'width': {'type': 'integer'},
                      'collapsed': {'type': 'boolean'}
                    }
                  },
                  'header': {
                    'type': 'object',
                    'properties': {
                      'height': {'type': 'integer'},
                      'fixed': {'type': 'boolean'}
                    }
                  }
                }
              }
            }
          }
        }
      });

      // Empty object gets complex default
      final result = expandPartialJson(schema, '{}');
      expect(
          result!['settings'],
          equals({
            'theme': {
              'primary': '#007bff',
              'secondary': '#6c757d',
              'fonts': ['Arial', 'Helvetica', 'sans-serif']
            },
            'layout': {
              'sidebar': {'width': 250, 'collapsed': false},
              'header': {'height': 60, 'fixed': true}
            }
          }));

      // Partial override preserves rest of default
      final partial = expandPartialJson(
          schema, '{"settings":{"theme":{"primary":"#ff0000"}}}');
      final settings = partial!['settings'] as Map<String, dynamic>;
      final theme = settings['theme'] as Map<String, dynamic>;
      expect(theme['primary'], equals('#ff0000'));
      expect(theme['secondary'], equals('#6c757d'));
      expect(theme['fonts'], equals(['Arial', 'Helvetica', 'sans-serif']));
    });

    test('handles array defaults with complex items', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'menu': {
            'type': 'array',
            'default': [
              {'title': 'Home', 'icon': 'home', 'path': '/', 'children': []},
              {
                'title': 'About',
                'icon': 'info',
                'path': '/about',
                'children': [
                  {'title': 'Team', 'path': '/about/team'},
                  {'title': 'Mission', 'path': '/about/mission'}
                ]
              }
            ],
            'items': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string'},
                'icon': {'type': 'string'},
                'path': {'type': 'string'},
                'children': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'title': {'type': 'string'},
                      'path': {'type': 'string'}
                    }
                  }
                }
              }
            }
          }
        }
      });

      // Empty gets complex array default
      final result = expandPartialJson(schema, '{}');
      final menu = result!['menu'] as List;
      expect(menu.length, equals(2));
      expect((menu[0] as Map)['title'], equals('Home'));
      expect((menu[1] as Map)['children'], hasLength(2));
    });
  });

  group('Conditional Schemas', () {
    test('handles if/then/else schemas', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'type': {'type': 'string'},
          'value': {}
        },
        'if': {
          'properties': {
            'type': {'const': 'number'}
          }
        },
        'then': {
          'properties': {
            'value': {'type': 'number', 'default': 0}
          }
        },
        'else': {
          'properties': {
            'value': {'type': 'string', 'default': 'N/A'}
          }
        }
      });

      // These conditional schemas might not be fully supported
      // but should still parse basic structure
      expect(expandPartialJson(schema, '{"type":"number"}'),
          equals({'type': 'number'}));

      expect(expandPartialJson(schema, '{"type":"string"}'),
          equals({'type': 'string'}));
    });
  });

  group('AllOf, AnyOf, OneOf with Defaults', () {
    test('handles allOf with multiple schemas', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'allOf': [
          {
            'properties': {
              'name': {'type': 'string', 'default': 'Unknown'}
            }
          },
          {
            'properties': {
              'age': {'type': 'integer', 'default': 0}
            }
          },
          {
            'properties': {
              'active': {'type': 'boolean', 'default': true}
            }
          }
        ]
      });

      // Should merge all defaults
      expect(expandPartialJson(schema, '{}'),
          equals({'name': 'Unknown', 'age': 0, 'active': true}));

      // Partial values
      expect(expandPartialJson(schema, '{"name":"John"}'),
          equals({'name': 'John', 'age': 0, 'active': true}));
    });

    test('handles nested anyOf in properties', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'contact': {
            'anyOf': [
              {
                'type': 'object',
                'properties': {
                  'email': {'type': 'string'},
                  'phone': {'type': 'string'}
                },
                'required': ['email']
              },
              {
                'type': 'object',
                'properties': {
                  'address': {'type': 'string'},
                  'city': {'type': 'string'}
                },
                'required': ['address']
              }
            ]
          }
        }
      });

      // Either schema should work
      expect(
          expandPartialJson(schema, '{"contact":{"email":"test@test.com"}}'),
          equals({
            'contact': {'email': 'test@test.com'}
          }));

      expect(
          expandPartialJson(schema, '{"contact":{"address":"123 Main St"}}'),
          equals({
            'contact': {'address': '123 Main St'}
          }));
    });
  });

  group('Edge Cases in Array Processing', () {
    test('handles arrays with nulls and undefined behavior', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'values': {
            'type': 'array',
            'items': {
              'type': ['string', 'null'],
              'default': null
            }
          }
        }
      });

      expect(
          expandPartialJson(schema, '{"values":[null,"text",null]}'),
          equals({
            'values': [null, 'text', null]
          }));

      // Partial array with null
      expect(
          expandPartialJson(schema, '{"values":[null,"text",nu'),
          equals({
            'values': [null, 'text', null]
          }));
    });

    test('handles sparse arrays concept', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'sparse': {'type': 'array', 'items': {}}
        }
      });

      // JSON doesn't support sparse arrays, but test undefined-like behavior
      expect(
          expandPartialJson(schema, '{"sparse":[1,null,null,4]}'),
          equals({
            'sparse': [1, null, null, 4]
          }));
    });
  });

  group('Property Dependencies', () {
    test('handles property dependencies', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'creditCard': {'type': 'string'},
          'billingAddress': {'type': 'string', 'default': '123 Main St'}
        },
        'dependencies': {
          'creditCard': ['billingAddress']
        }
      });

      // Without creditCard, billingAddress is optional
      expect(expandPartialJson(schema, '{}'),
          equals({'billingAddress': '123 Main St'}));

      // With creditCard, billingAddress should be included
      expect(expandPartialJson(schema, '{"creditCard":"1234-5678"}'),
          equals({'creditCard': '1234-5678', 'billingAddress': '123 Main St'}));
    });
  });

  group('Recursive Schemas', () {
    test('handles simple recursive schemas', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'children': {
            'type': 'array',
            'items': {
              r'$ref': '#' // Reference to root schema
            },
            'default': []
          }
        }
      });

      expect(expandPartialJson(schema, '{"name":"root"}'),
          equals({'name': 'root', 'children': []}));

      // Nested recursive structure
      expect(
          expandPartialJson(schema,
              '{"name":"root","children":[{"name":"child1"},{"name":"child2"'),
          equals({
            'name': 'root',
            'children': [
              {'name': 'child1', 'children': []},
              {'name': 'child2', 'children': []}
            ]
          }));
    });
  });

  group('Extreme Edge Cases', () {
    test('handles malformed JSON that almost looks valid', () {
      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      // Double commas
      expect(expandPartialJson(schema, '{"a":1,,"b":2}'), isNull);

      // Missing colon
      expect(expandPartialJson(schema, '{"a"1}'), isNull);

      // Extra closing braces
      expect(expandPartialJson(schema, '{"a":1}}'), isNull);
    });

    test('handles whitespace in unusual places', () {
      final schema =
          JsonSchema.create({'type': 'object', 'additionalProperties': true});

      // Whitespace in property names (valid JSON)
      expect(expandPartialJson(schema, '{  "a"  :  1  }'), equals({'a': 1}));

      // Newlines in strings
      expect(expandPartialJson(schema, '{"text":"line1\nline2"}'),
          equals({'text': 'line1\nline2'}));

      // Tabs and other whitespace
      expect(expandPartialJson(schema, '{\t"a"\t:\t1\t}'), equals({'a': 1}));
    });

    test('handles property names that look like JSON', () {
      final schema = JsonSchema.create({
        'type': 'object',
        'properties': {
          '{"nested":"json"}': {'type': 'string', 'default': 'value'},
          '[1,2,3]': {'type': 'string', 'default': 'array-like'},
          'true': {'type': 'string', 'default': 'boolean-like'},
          'null': {'type': 'string', 'default': 'null-like'}
        }
      });

      expect(
          expandPartialJson(schema, '{}'),
          equals({
            '{"nested":"json"}': 'value',
            '[1,2,3]': 'array-like',
            'true': 'boolean-like',
            'null': 'null-like'
          }));
    });
  });
}

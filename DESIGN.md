# Partial JSON Expander Design

## Overview

The `partial_json_expander` package provides functionality to repair incomplete
JSON strings and apply schema defaults, particularly useful for processing
streaming LLM output where JSON responses arrive in chunks.

## Core Components

### 1. `expandPartialJson()`
The main entry point that orchestrates the JSON repair and default merging
process.

**Process:**
1. Attempts to repair the partial JSON string
2. If repair succeeds, parses the JSON
3. Merges schema defaults into the parsed object
4. Returns null if repair or parsing fails

### 2. `_closePartialJson()`
The JSON repair engine that handles various incomplete JSON scenarios.

**Repair Strategies:**
- **Trailing cleanup**: Removes trailing whitespace and commas
- **Incomplete key completion**: Detects partial property keys and attempts to
  complete them by matching against schema properties
- **Missing values**: Adds `null` for properties ending with `:`
- **String balancing**: Closes unclosed string literals
- **Bracket/brace balancing**: Adds missing closing brackets and braces

**Failure cases:**
- Ambiguous partial keys (multiple schema properties match)
- More closing brackets/braces than opening ones
- Malformed JSON that can't be repaired

### 3. `_mergeDefaults()`
Recursively applies schema defaults to the parsed JSON object.

**Features:**
- Applies default values for missing properties
- Creates empty objects/arrays for missing properties based on type
- Recursively processes nested objects and arrays
- Removes properties not defined in schema when `additionalProperties: false`

### 4. `randomChunkedJson()`
A utility function for testing that simulates streaming JSON by breaking a
complete JSON string into random chunks.

## Comprehensive Testing Coverage

The expanded test suite validates the library's robustness across all JSON types and schema combinations:

### Root-Level Value Support
- **Atomic values**: Strings, numbers, booleans, null at root level
- **Complex types**: Arrays and objects as root-level values
- **Edge cases**: Empty values, boundary conditions

### Complex Nested Structures
- **Deep nesting**: Multi-level object/array combinations
- **Alternating patterns**: Objects containing arrays containing objects
- **Circular-like structures**: Self-referential patterns within schemas
- **Wide structures**: Objects with many properties (100+ properties tested)

### Schema Validation Edge Cases
- **Format validation**: date-time, email, URI, regex patterns
- **Constraints**: minLength, maxLength, minimum, maximum, multipleOf
- **Required properties**: Handling missing required fields
- **Array constraints**: minItems, maxItems, tuple validation
- **Pattern properties**: Dynamic property name matching
- **Conditional schemas**: if/then/else, allOf, anyOf, oneOf
- **Property dependencies**: Inter-property requirements

### Character Encoding & Special Values
- **UTF-8 sequences**: 2-byte, 3-byte, 4-byte Unicode characters
- **Escape sequences**: All JSON escape codes (\n, \t, \", \\, \uXXXX)
- **Control characters**: Handling of special control sequences
- **Mixed encoding**: Unicode combined with ASCII in same values

### Number Format Variations
- **Scientific notation**: Positive and negative exponents
- **Boundary values**: Maximum/minimum safe integers
- **Precision**: Very small and very large floating-point numbers
- **Edge formats**: Leading zeros, negative zero, partial numbers

### String Processing
- **Long strings**: 10,000+ character strings
- **Partial strings**: Incomplete string values at various positions
- **Special characters**: Property names with dashes, underscores, spaces
- **JSON-like names**: Property names that look like JSON structures

### Default Value Complexity
- **Nested defaults**: Multi-level object defaults with inheritance
- **Array defaults**: Complex item structures with defaults
- **Conditional defaults**: Defaults that depend on other properties
- **Special value defaults**: null, empty objects/arrays as defaults

### Property Name Completion
- **Unique completion**: Single matching property from partial name
- **Ambiguous prefixes**: Multiple possible completions (returns null)
- **Special characters**: Completion with non-alphanumeric characters
- **Case sensitivity**: Proper case handling in completions

### Streaming Simulation
- **Multiple seeds**: 50+ different random seeds tested
- **Chunk size variations**: 1-character to 25-character chunks
- **Progressive parsing**: Validation at each accumulation step
- **Success rate analysis**: Statistical validation of parsing reliability

### Performance Edge Cases
- **Deep nesting**: 20+ levels of nested structures
- **Large arrays**: 1,000+ item arrays
- **Wide objects**: 100+ properties in single object
- **Memory efficiency**: Handling of large JSON structures

### Real-World Scenarios
- **API responses**: Typical REST API response structures
- **Configuration files**: Complex config with environment settings
- **LLM outputs**: Realistic streaming AI response patterns
- **Database records**: Nested data with relationships

## Implementation Details

### Type Checking
Uses `JsonSchema.typeList` to check for specific types, handling cases where a
property can have multiple valid types:
```dart
propSchema.typeList?.any((t) => t == SchemaType.object)
```

### Key Completion Algorithm
1. Uses regex `[,{]\\s*\"([^\":]*)$` to find incomplete keys
2. Filters schema properties that start with the partial key
3. Only completes if there's exactly one match (unambiguous)

### Quote Balancing
Counts total quotes and adds a closing quote if the count is odd, indicating
we're in the middle of a string value.

### Error Handling Strategy
- **Graceful degradation**: Returns null instead of throwing exceptions
- **Partial success**: Accepts incomplete JSON that can be reasonably repaired
- **Statistical validation**: Ensures reasonable success rates across random inputs

### Edge Cases Handled
- Empty input (throws FormatException)
- Partial strings in property values
- Trailing commas
- Missing colons after keys
- Nested objects and arrays
- Multiple possible property completions
- Malformed JSON structures
- Unicode and escape sequences
- Very large or deeply nested structures

## Supported JSON Fragment Types & Expansion Examples

The following examples show how various partial JSON fragments are processed and expanded by the library:

### 1. Incomplete Object Structure

**Schema:**
```json
{
  "type": "object",
  "properties": {
    "name": {"type": "string", "default": "Unknown"},
    "age": {"type": "integer", "default": 0},
    "active": {"type": "boolean", "default": true}
  }
}
```

**Examples:**
```javascript
// Missing closing brace
'{"name":"John"' → {"name": "John", "age": 0, "active": true}

// Empty object
'{}' → {"name": "Unknown", "age": 0, "active": true}

// Partial property value
'{"name":"Jo' → {"name": "Jo", "age": 0, "active": true}

// Trailing comma
'{"name":"John",' → {"name": "John", "age": 0, "active": true}

// Missing value after colon
'{"name":' → {"name": null, "age": 0, "active": true}
```

### 2. Incomplete Property Names

**Schema:**
```json
{
  "type": "object",
  "properties": {
    "temperature": {"type": "number", "default": 20},
    "humidity": {"type": "number", "default": 50}
  }
}
```

**Examples:**
```javascript
// Unique prefix completion
'{"temp' → {"temperature": 20, "humidity": 50}

// Ambiguous prefix (returns null)
'{"te' → null  // Could match "temperature" or other "te*" properties

// Complete property name
'{"temperature":25' → {"temperature": 25, "humidity": 50}
```

### 3. Array Processing

**Schema:**
```json
{
  "type": "object",
  "properties": {
    "items": {
      "type": "array",
      "items": {"type": "string"},
      "default": []
    }
  }
}
```

**Examples:**
```javascript
// Missing closing bracket
'{"items":["a","b","c"' → {"items": ["a", "b", "c"]}

// Partial array element
'{"items":["a","b' → {"items": ["a", "b"]}

// Empty array
'{"items":[' → {"items": []}

// Nested array structures
'{"items":[["a"],["b"' → {"items": [["a"], ["b"]]}
```

### 4. Nested Object Expansion

**Schema:**
```json
{
  "type": "object",
  "properties": {
    "user": {
      "type": "object",
      "properties": {
        "profile": {
          "type": "object",
          "properties": {
            "name": {"type": "string", "default": "Guest"},
            "theme": {"type": "string", "default": "light"}
          }
        }
      }
    }
  }
}
```

**Examples:**
```javascript
// Deep nesting with missing braces
'{"user":{"profile":{"name":"John"' → {
  "user": {
    "profile": {
      "name": "John",
      "theme": "light"
    }
  }
}

// Partial nested structure
'{"user":{"prof' → {"user": {}} // No unique match for "prof"

// Complete nested path
'{"user":{"profile":{' → {
  "user": {
    "profile": {
      "name": "Guest",
      "theme": "light"
    }
  }
}
```

### 5. Mixed Arrays and Objects

**Schema:**
```json
{
  "type": "object",
  "properties": {
    "data": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id": {"type": "integer"},
          "tags": {"type": "array", "items": {"type": "string"}}
        }
      }
    }
  }
}
```

**Examples:**
```javascript
// Complex nested structure
'{"data":[{"id":1,"tags":["a","b"]},{"id":2,"tags":["c"' → {
  "data": [
    {"id": 1, "tags": ["a", "b"]},
    {"id": 2, "tags": ["c"]}
  ]
}

// Incomplete object in array
'{"data":[{"id":1' → {"data": [{"id": 1}]}

// Mixed complete and incomplete elements
'{"data":[{"id":1,"tags":["a"]},{"id"' → {
  "data": [
    {"id": 1, "tags": ["a"]},
    {"id": null}
  ]
}
```

### 6. String Value Completion

**Examples:**
```javascript
// Unclosed string
'{"name":"John Doe' → {"name": "John Doe"}

// Escaped characters
'{"path":"C:\\Users\\name' → {"path": "C:\\Users\\name"}

// Unicode characters
'{"emoji":"🎉' → {"emoji": "🎉"}

// Empty string
'{"name":"' → {"name": ""}
```

### 7. Number Value Completion

**Examples:**
```javascript
// Incomplete decimal
'{"price":19.' → {"price": 19}

// Scientific notation
'{"value":1.23e' → {"value": 1.23}

// Negative numbers
'{"temp":-' → {"temp": null}

// Large numbers
'{"big":123456789' → {"big": 123456789}
```

### 8. Boolean and Null Values

**Examples:**
```javascript
// Complete boolean
'{"active":true' → {"active": true}

// Partial boolean (fails)
'{"active":tr' → null

// Null value
'{"value":null' → {"value": null}

// Partial null (fails)
'{"value":nu' → null
```

### 9. Schema Default Application

**Schema with Complex Defaults:**
```json
{
  "type": "object",
  "properties": {
    "config": {
      "type": "object",
      "default": {
        "theme": "dark",
        "fontSize": 14,
        "features": ["autocomplete", "syntax-highlighting"]
      }
    },
    "timestamp": {"type": "string", "default": "2024-01-01T00:00:00Z"}
  }
}
```

**Examples:**
```javascript
// Empty object gets all defaults
'{}' → {
  "config": {
    "theme": "dark",
    "fontSize": 14,
    "features": ["autocomplete", "syntax-highlighting"]
  },
  "timestamp": "2024-01-01T00:00:00Z"
}

// Partial override preserves other defaults
'{"config":{"theme":"light"}' → {
  "config": {
    "theme": "light",
    "fontSize": 14,
    "features": ["autocomplete", "syntax-highlighting"]
  },
  "timestamp": "2024-01-01T00:00:00Z"
}
```

### 10. Error Cases (Returns null)

**Examples:**
```javascript
// Empty input
'' → throws FormatException

// Ambiguous property completion
'{"te' → null  // Multiple matches possible

// Malformed JSON
'{"a":1,,"b":2}' → null

// Unbalanced braces
'{"a":1}}}' → null

// Partial boolean/null
'{"flag":tr' → null
'{"value":nu' → null
```

## Example Flow

Given partial JSON: `{"time":"12:30","temp`

1. **Repair Phase**:
   - Detects incomplete key "temp"
   - Matches against schema properties
   - Finds "temperature" as unique match
   - Completes to: `{"time":"12:30","temperature":`
   - Adds null value: `{"time":"12:30","temperature":null`
   - Balances braces: `{"time":"12:30","temperature":null}`

2. **Parse Phase**:
   - Successfully parses the repaired JSON

3. **Merge Defaults Phase**:
   - Applies schema default for "temperature" (0)
   - Adds missing "units" property with default ("C")
   - Returns: `{time: "12:30", temperature: 0, units: "C"}`

## Design Decisions

1. **Fail-safe approach**: Returns null rather than throwing exceptions when
   repair is impossible
2. **Schema-guided repair**: Uses schema property names to intelligently
   complete partial keys
3. **Progressive enhancement**: Each chunk builds on previous state in streaming
   scenarios
4. **Type safety**: Leverages Dart's type system and json_schema validation
5. **Comprehensive testing**: Validates against all JSON types and schema patterns
6. **Performance awareness**: Handles large and complex structures efficiently

## Testing Strategy

The comprehensive test suite includes:
- **35 basic tests**: Core functionality validation
- **50+ edge case tests**: Boundary conditions and error cases
- **100+ schema variations**: All JSON Schema features tested
- **Multiple random seeds**: Statistical validation of streaming scenarios
- **Real-world examples**: Practical usage patterns

## Future Enhancements

1. Support for more complex partial JSON scenarios (nested incomplete objects)
2. Configurable repair strategies
3. Better error reporting with specific failure reasons
4. Performance optimizations for large schemas
5. Support for JSON Schema draft versions beyond the current implementation
6. Streaming parser optimization for very large JSON structures
7. Advanced property name completion with fuzzy matching
8. Support for custom default value generators
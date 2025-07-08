# partial_json_expander

Progressive JSON repair + schema defaults for streaming LLM output.

## Features

- **Repairs incomplete JSON** strings that arrive in chunks
- **Applies schema defaults** to missing properties
- **Schema-guided completion** for partial property names
- **Handles common streaming scenarios** like incomplete strings, missing
  brackets, and dangling commas
- **Fail-safe design** returns null for unrepairable JSON
- **Advanced parser** with state machine-based parsing for better error handling
- **JSON Schema support** including allOf, required properties, pattern properties
- **Deep nested defaults** with intelligent merging
- **Flexible property completion** supporting both single-char and meaningful prefixes

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  partial_json_expander: ^0.1.0
```

## Usage

### Basic Example

```dart
import 'package:json_schema/json_schema.dart';
import 'package:partial_json_expander/partial_json_expander.dart';

void main() {
  // Define your schema with defaults
  final schema = JsonSchema.create({
    'type': 'object',
    'properties': {
      'name': {'type': 'string', 'default': 'Unknown'},
      'age': {'type': 'number', 'default': 0},
      'active': {'type': 'boolean', 'default': true}
    }
  });

  // Repair partial JSON
  final partial = '{"name":"John","ag';
  final result = expandPartialJson(schema, partial);
  
  print(result); // {name: John, age: 0, active: true}
}
```

### Streaming Example

```dart
// Simulate streaming JSON chunks
final json = '{"time":"12:30","temperature":23,"units":"F"}';
final stream = randomChunkedJson(json, seed: 42);

final accumulated = StringBuffer();
await for (final chunk in stream) {
  accumulated.write(chunk);
  final expanded = expandPartialJson(schema, accumulated.toString());
  if (expanded != null) {
    print('Valid JSON: $expanded');
  }
}
```

## How It Works

1. **Parse Phase**: Uses a state machine parser to handle incomplete JSON:
   - Completes partial property names using schema when unique match exists
   - Tracks incomplete strings, missing brackets, trailing commas
   - Builds a parse tree with completion status for each node

2. **Complete Phase**: Applies schema defaults and fills in missing data:
   - Properties with colons but missing values get their schema defaults
   - Completed property names (like `{"temp` → `"temperature"`) get their schema defaults  
   - Missing properties entirely get their schema defaults (explicit or type-based)
   - Nested objects are created with their own property defaults
   - Required properties don't get defaults if missing (validation handled elsewhere)

## Supported Scenarios

### Basic JSON Repair
✅ Incomplete property names: `{"temp` → `{"temperature":20, "humidity":50}`  
✅ Missing values after colon: `{"name":` → `{"name":"Unknown", "age":0, "active":true}`  
✅ Unclosed strings: `{"name":"Joh` → `{"name":"Joh", "age":0, "active":true}`  
✅ Missing brackets: `{"items":[1,2` → `{"items":[1,2]}`  
✅ Schema defaults for missing properties: `{"name":"John"}` → `{"name":"John","age":0,"active":true}`

### Advanced Features
✅ **Property name completion**: `{"temp` → `{"temperature":20, "humidity":50}` (completes any unique prefix)  
✅ **No arbitrary limits**: `{"tempera` → `{"temperature":20, ...}` (works for any length)  
✅ **Works everywhere**: In root objects, nested objects, and inside arrays  
✅ **Partial literals**: `{"active":tr` → `{"active":true}`, `{"value":nu` → `{"value":null}`  
✅ **Nested defaults**: Empty objects get all nested property defaults from schema  
✅ **AllOf schema merging**: Combines multiple schema definitions seamlessly  
✅ **Required property handling**: Doesn't add defaults for missing required fields  
✅ **Null preservation**: Keeps null values when null is valid schema type  
✅ **Pattern properties**: Supports regex-based property validation  
✅ **Deep merging**: Schema defaults merge with parsed values at all levels  

### Error Detection
❌ **Ambiguous prefixes**: `{"te` → `null` (multiple possible matches)  
❌ **Malformed JSON**: `{"a":1,,"b":2}` → `null` (double commas)  
❌ **Invalid structure**: `{"a":1}}}` → `null` (extra closing braces)

## API Reference

### `expandPartialJson()`

```dart
Map<String, dynamic>? expandPartialJson(
  JsonSchema schema,
  String partialJson,
)
```

Attempts to repair a partial JSON string and apply schema defaults.

**Parameters:**
- `schema`: A `JsonSchema` instance defining the expected structure and defaults
- `partialJson`: The incomplete JSON string to repair

**Returns:**
- A `Map<String, dynamic>` with the repaired and completed JSON
- `null` if the JSON cannot be repaired

### `randomChunkedJson()`

```dart
Stream<String> randomChunkedJson(
  String json, {
  required int seed,
  int minChunk = 1,
  int maxChunk = 12,
})
```

Utility function for testing that breaks a complete JSON string into random
chunks.

**Parameters:**
- `json`: Complete JSON string to chunk
- `seed`: Random seed for reproducible chunking
- `minChunk`: Minimum chunk size (default: 1)
- `maxChunk`: Maximum chunk size (default: 12)

## Limitations & Known Issues

### Current Limitations
- Property name completion only works when there's a unique match in the schema
- Complex nested incomplete structures may not be repairable
- Arrays must have consistent types as defined in the schema

### Known Limitations (By Design)
- **Recursive schemas**: Array items with `$ref: '#'` don't get recursive defaults (avoids infinite expansion)
- **Property dependencies**: Schema dependencies not fully implemented
- **Performance**: Large schemas or deeply nested content may be slower

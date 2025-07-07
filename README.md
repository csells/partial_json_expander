# partial_json_expander

Progressive JSON repair + schema defaults for streaming LLM output.

## Features

- **Repairs incomplete JSON** strings that arrive in chunks
- **Applies schema defaults** to missing properties
- **Schema-guided completion** for partial property names
- **Handles common streaming scenarios** like incomplete strings, missing
  brackets, and dangling commas
- **Fail-safe design** returns null for unrepairable JSON

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

1. **Repair Phase**: Attempts to fix incomplete JSON by:
   - Completing partial property names using schema
   - Adding missing quotes, brackets, and braces
   - Handling trailing commas and whitespace

2. **Parse Phase**: Parses the repaired JSON string

3. **Merge Phase**: Applies schema defaults to missing properties

## Supported Scenarios

✅ Incomplete property names: `{"temp` → `{"temperature":null}`  
✅ Missing values: `{"name":` → `{"name":null}`  
✅ Unclosed strings: `{"name":"Joh` → `{"name":"Joh"}`  
✅ Missing brackets: `{"items":[1,2` → `{"items":[1,2]}`  
✅ Schema defaults: `{"name":"John"}` → `{"name":"John","age":0}`

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

## Limitations

- Property name completion only works when there's a unique match in the schema
- Complex nested incomplete structures may not be repairable
- Arrays must have consistent types as defined in the schema

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

## Implementation Details

### Type Checking
Uses `JsonSchema.typeList` to check for specific types, handling cases where a
property can have multiple valid types:
```dart
propSchema.typeList?.any((t) => t == SchemaType.object)
```

### Key Completion Algorithm
1. Uses regex `[,{]\s*"([^":]*)$` to find incomplete keys
2. Filters schema properties that start with the partial key
3. Only completes if there's exactly one match (unambiguous)

### Quote Balancing
Counts total quotes and adds a closing quote if the count is odd, indicating
we're in the middle of a string value.

### Edge Cases Handled
- Empty input
- Partial strings in property values
- Trailing commas
- Missing colons after keys
- Nested objects and arrays
- Multiple possible property completions

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

## Future Enhancements

1. Support for more complex partial JSON scenarios (nested incomplete objects)
2. Configurable repair strategies
3. Better error reporting with specific failure reasons
4. Performance optimizations for large schemas
5. Support for JSON Schema draft versions beyond the current implementation
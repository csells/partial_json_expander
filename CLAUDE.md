# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Dart package called `partial_json_expander` that provides progressive JSON repair and schema defaults for streaming LLM output. The main functionality includes:
- Repairing incomplete/partial JSON strings
- Applying schema defaults to missing fields
- Simulating chunked JSON streaming for testing

## Development Commands

### Dependencies
```bash
dart pub get              # Install dependencies
```

### Static Analysis
```bash
dart analyze              # Run static analysis (no issues)
```

### Running Examples
```bash
dart run example/main.dart  # Run the example showing chunked JSON processing
```

## Architecture

The package consists of:
- **lib/partial_json_expander.dart**: Core library with two main functions:
  - `expandPartialJson()`: Completes partial JSON using schema context and applies defaults
  - `randomChunkedJson()`: Utility for simulating chunked JSON streaming
- **lib/src/partial_json_parser.dart**: State machine-based JSON parser with schema awareness
  
### Key Implementation Details

1. **State Machine Parser** (`PartialJsonParser`):
   - Replaces regex-based approach with robust state machine parsing
   - Tracks parse position for better error reporting
   - Builds parse tree with completion metadata
   - Detects malformed JSON (double commas, extra braces)
   - Supports property name completion when unique match exists
   
2. **JSON Completion** (`PartialJsonCompleter`):
   - Completes partial property names based purely on uniqueness (no length limits)
   - Works inside arrays and nested objects
   - Completes partial boolean/null literals ("tr" → true, "nu" → null)
   - Applies schema defaults intelligently based on property requirements
   - Handles nested object creation with deep default merging
   - Preserves null values when valid per schema
   - Supports advanced schema features (allOf, pattern properties, etc.)

## Test Status

- ✅ **All tests passing** - Core functionality working well
- 📈 **High success rate** on random chunked JSON scenarios
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
dart analyze              # Run static analysis (currently has 5 errors related to json_schema API usage)
```

### Running Examples
```bash
dart run example/main.dart  # Run the example showing chunked JSON processing
```

## Architecture

The package consists of:
- **lib/partial_json_expander.dart**: Core library with two main functions:
  - `expandPartialJson()`: Repairs partial JSON and applies schema defaults
  - `randomChunkedJson()`: Utility for simulating chunked JSON streaming
  
### Key Implementation Details

1. **JSON Repair Strategy** (`_closePartialJson`):
   - Trims trailing whitespace and commas
   - Attempts to complete dangling property keys by matching against schema
   - Balances quotes, braces, and brackets
   
2. **Schema Default Merging** (`_mergeDefaults`):
   - Recursively applies defaults from JsonSchema
   - Handles nested objects and arrays
   - Removes properties not in schema when `additionalProperties: false`

## Known Issues

The code has analyzer errors due to API changes in the `json_schema` package:
- `SchemaType.contains()` method is not available
- `JsonSchema.additionalProperties` getter is not available

These need to be addressed based on the current `json_schema` package API.
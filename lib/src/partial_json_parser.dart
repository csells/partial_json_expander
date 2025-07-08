import 'dart:convert';
import 'dart:math' as math;

import 'package:json_schema/json_schema.dart';

/// Parsing states for the state machine
enum ParseState {
  start,
  inObject,
  inObjectKey,
  inObjectColon,
  inObjectValue,
  inObjectComma,
  inArray,
  inArrayValue,
  inArrayComma,
  inString,
  inStringEscape,
  inNumber,
  inTrue,
  inFalse,
  inNull,
  complete,
}

/// Represents a position in the input
class Position {
  const Position(this.offset, this.line, this.column);
  final int offset;
  final int line;
  final int column;

  @override
  String toString() => 'line $line, column $column';
}

/// Node in the parse tree
abstract class ParseNode {
  const ParseNode(this.start, this.end);
  final Position start;
  final Position? end;

  bool get isComplete => end != null;
}

class ObjectNode extends ParseNode {
  ObjectNode(super.start, super.end, this.entries);
  final List<ObjectEntry> entries;

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};
    for (final entry in entries) {
      if (entry.key != null && entry.value != null) {
        result[entry.key!] = _nodeToJson(entry.value!);
      }
    }
    return result;
  }
}

class ObjectEntry {
  const ObjectEntry(this.key, this.value, this.hasColon);
  final String? key;
  final ParseNode? value;
  final bool hasColon;
}

class ArrayNode extends ParseNode {
  ArrayNode(super.start, super.end, this.elements);
  final List<ParseNode> elements;

  List<dynamic> toJson() => elements.map(_nodeToJson).toList();
}

class StringNode extends ParseNode {
  StringNode(super.start, super.end, this.value, this.closed);
  final String value;
  final bool closed;
}

class NumberNode extends ParseNode {
  NumberNode(super.start, super.end, this.value);
  final String value;
}

class BoolNode extends ParseNode {
  BoolNode(super.start, super.end, this.value);
  final bool value;
}

class NullNode extends ParseNode {
  NullNode(super.start, super.end);
}

dynamic _nodeToJson(ParseNode node) {
  if (node is ObjectNode) return node.toJson();
  if (node is ArrayNode) return node.toJson();
  if (node is StringNode) return node.value;
  if (node is NumberNode) return num.tryParse(node.value) ?? 0;
  if (node is BoolNode) return node.value;
  if (node is NullNode) return null;
  return null;
}

/// Context for parsing, including schema information
class ParseContext {
  ParseContext(this.input, this.schema);

  final String input;
  final JsonSchema schema;
  int _offset = 0;
  int _line = 1;
  int _column = 1;

  // Stack to track nested structures
  final List<ParseFrame> _stack = [];

  Position get position => Position(_offset, _line, _column);
  bool get isEof => _offset >= input.length;
  String? get current => isEof ? null : input[_offset];
  String? peek(int ahead) {
    final pos = _offset + ahead;
    return pos >= input.length ? null : input[pos];
  }

  void advance() {
    if (!isEof) {
      if (input[_offset] == '\n') {
        _line++;
        _column = 1;
      } else {
        _column++;
      }
      _offset++;
    }
  }

  void push(ParseFrame frame) => _stack.add(frame);
  ParseFrame? pop() => _stack.isEmpty ? null : _stack.removeLast();
  ParseFrame? get currentFrame => _stack.isEmpty ? null : _stack.last;

  String substring(int start, int end) {
    final safeEnd = math.min(end, input.length);
    return input.substring(start, safeEnd);
  }
}

/// Frame in the parsing stack
class ParseFrame {
  ParseFrame(this.state, this.node);
  ParseState state;
  ParseNode node;
  JsonSchema? schema;
}

/// Main parser class
class PartialJsonParser {
  ParseNode? parse(String input, JsonSchema schema) {
    if (input.trim().isEmpty) return null;

    final ctx = ParseContext(input, schema);
    _skipWhitespace(ctx);

    if (ctx.isEof) return null;

    final value = _parseValue(ctx, schema);
    if (value == null) return null;
    
    // Check for extra characters after complete JSON
    _skipWhitespace(ctx);
    if (!ctx.isEof && value.isComplete) {
      // Extra characters after complete JSON make it invalid
      // unless it's just incomplete (like missing closing braces)
      final remaining = ctx.input.substring(ctx._offset).trim();
      // Check if remaining chars are valid incomplete JSON
      if (remaining.isNotEmpty && !_isValidIncomplete(remaining)) {
        return null;
      }
    }
    
    return value;
  }
  
  bool _isValidIncomplete(String str) {
    // Empty or whitespace only is valid
    if (str.trim().isEmpty) return true;
    
    // Extra closing braces/brackets are invalid
    if (str.startsWith('}') || str.startsWith(']')) return false;
    
    // Other characters might be part of incomplete JSON
    return true;
  }

  ParseNode? _parseValue(ParseContext ctx, JsonSchema schema) {
    _skipWhitespace(ctx);
    if (ctx.isEof) return null;

    final ch = ctx.current!;
    switch (ch) {
      case '{':
        return _parseObject(ctx, schema);
      case '[':
        return _parseArray(ctx, schema);
      case '"':
        return _parseString(ctx);
      case 't':
      case 'f':
        return _parseBool(ctx);
      case 'n':
        return _parseNull(ctx);
      default:
        if (_isNumberStart(ch)) {
          return _parseNumber(ctx);
        }
        return null;
    }
  }

  ObjectNode? _parseObject(ParseContext ctx, JsonSchema schema) {
    final start = ctx.position;
    ctx.advance(); // skip '{'

    final entries = <ObjectEntry>[];
    _skipWhitespace(ctx);

    while (!ctx.isEof && ctx.current != '}') {
      // Parse key
      String? key;
      if (ctx.current == '"') {
        final keyNode = _parseString(ctx);
        key = keyNode.value;
      } else {
        // Handle incomplete key
        key = _parseIncompleteKey(ctx, schema);
      }

      _skipWhitespace(ctx);

      // Check for colon
      var hasColon = false;
      if (!ctx.isEof && ctx.current == ':') {
        hasColon = true;
        ctx.advance();
        _skipWhitespace(ctx);
      }

      // Parse value
      ParseNode? value;
      if (hasColon && !ctx.isEof && ctx.current != ',' && ctx.current != '}') {
        final propSchema = key != null && schema.properties.containsKey(key)
            ? schema.properties[key]!
            : JsonSchema.create({});
        value = _parseValue(ctx, propSchema);
      }

      entries.add(ObjectEntry(key, value, hasColon));

      _skipWhitespace(ctx);

      // Check for comma
      if (!ctx.isEof && ctx.current == ',') {
        ctx.advance();
        _skipWhitespace(ctx);
        
        // Check for double comma (malformed JSON)
        if (!ctx.isEof && ctx.current == ',') {
          // Double comma is invalid
          return null;
        }
      } else if (!ctx.isEof && ctx.current != '}') {
        // Invalid character, stop parsing
        break;
      }
    }

    // Check for closing brace
    Position? end;
    if (!ctx.isEof && ctx.current == '}') {
      ctx.advance();
      end = ctx.position;
    }

    return ObjectNode(start, end, entries);
  }

  ArrayNode _parseArray(ParseContext ctx, JsonSchema schema) {
    final start = ctx.position;
    ctx.advance(); // skip '['

    final elements = <ParseNode>[];
    _skipWhitespace(ctx);

    while (!ctx.isEof && ctx.current != ']') {
      final element = _parseValue(ctx, schema.items ?? JsonSchema.create({}));
      if (element != null) {
        elements.add(element);
      } else {
        // Couldn't parse element, stop
        break;
      }

      _skipWhitespace(ctx);

      // Check for comma
      if (!ctx.isEof && ctx.current == ',') {
        ctx.advance();
        _skipWhitespace(ctx);
      } else if (!ctx.isEof && ctx.current != ']') {
        // Invalid character, stop parsing
        break;
      }
    }

    // Check for closing bracket
    Position? end;
    if (!ctx.isEof && ctx.current == ']') {
      ctx.advance();
      end = ctx.position;
    }

    return ArrayNode(start, end, elements);
  }

  StringNode _parseString(ParseContext ctx) {
    final start = ctx.position;
    ctx.advance(); // skip '"'

    final buffer = StringBuffer();
    var closed = false;

    while (!ctx.isEof) {
      final ch = ctx.current!;
      if (ch == '"') {
        ctx.advance();
        closed = true;
        break;
      } else if (ch == r'\') {
        ctx.advance();
        if (!ctx.isEof) {
          final escaped = _parseEscapeSequence(ctx);
          if (escaped != null) {
            buffer.write(escaped);
          }
        }
      } else {
        buffer.write(ch);
        ctx.advance();
      }
    }

    final end = closed ? ctx.position : null;
    return StringNode(start, end, buffer.toString(), closed);
  }

  String? _parseEscapeSequence(ParseContext ctx) {
    if (ctx.isEof) return null;

    final ch = ctx.current!;
    ctx.advance();

    switch (ch) {
      case '"':
        return '"';
      case r'\':
        return r'\';
      case '/':
        return '/';
      case 'b':
        return '\b';
      case 'f':
        return '\f';
      case 'n':
        return '\n';
      case 'r':
        return '\r';
      case 't':
        return '\t';
      case 'u':
        return _parseUnicodeEscape(ctx);
      default:
        return ch;
    }
  }

  String? _parseUnicodeEscape(ParseContext ctx) {
    final start = ctx._offset;
    for (var i = 0; i < 4; i++) {
      if (ctx.isEof || !_isHexDigit(ctx.current!)) {
        // Incomplete unicode escape
        return null;
      }
      ctx.advance();
    }
    final hex = ctx.substring(start, ctx._offset);
    final code = int.parse(hex, radix: 16);
    return String.fromCharCode(code);
  }

  NumberNode _parseNumber(ParseContext ctx) {
    final start = ctx.position;
    final startOffset = ctx._offset;

    // Optional minus
    if (ctx.current == '-') {
      ctx.advance();
    }

    // Integer part
    if (ctx.isEof) {
      return NumberNode(start, null, ctx.substring(startOffset, ctx._offset));
    }

    if (ctx.current == '0') {
      ctx.advance();
    } else if (_isDigit(ctx.current!)) {
      while (!ctx.isEof && _isDigit(ctx.current!)) {
        ctx.advance();
      }
    } else {
      // Invalid number
      return NumberNode(start, null, ctx.substring(startOffset, ctx._offset));
    }

    // Fractional part
    if (!ctx.isEof && ctx.current == '.') {
      ctx.advance();
      if (ctx.isEof || !_isDigit(ctx.current!)) {
        // Incomplete fraction, backtrack
        return NumberNode(
          start,
          ctx.position,
          ctx.substring(startOffset, ctx._offset - 1),
        );
      }
      while (!ctx.isEof && _isDigit(ctx.current!)) {
        ctx.advance();
      }
    }

    // Exponent part
    if (!ctx.isEof && (ctx.current == 'e' || ctx.current == 'E')) {
      final expStart = ctx._offset;
      ctx.advance();
      if (!ctx.isEof && (ctx.current == '+' || ctx.current == '-')) {
        ctx.advance();
      }
      if (ctx.isEof || !_isDigit(ctx.current!)) {
        // Incomplete exponent, backtrack
        return NumberNode(
          start,
          ctx.position,
          ctx.substring(startOffset, expStart),
        );
      }
      while (!ctx.isEof && _isDigit(ctx.current!)) {
        ctx.advance();
      }
    }

    return NumberNode(
      start,
      ctx.position,
      ctx.substring(startOffset, ctx._offset),
    );
  }

  ParseNode? _parseBool(ParseContext ctx) {
    final start = ctx.position;

    if (_matchWord(ctx, 'true')) {
      return BoolNode(start, ctx.position, true);
    } else if (_matchWord(ctx, 'false')) {
      return BoolNode(start, ctx.position, false);
    }

    // Partial boolean
    final partial = _readPartialWord(ctx);
    if ('true'.startsWith(partial)) {
      return BoolNode(start, null, true);
    } else if ('false'.startsWith(partial)) {
      return BoolNode(start, null, false);
    }

    return null;
  }

  NullNode? _parseNull(ParseContext ctx) {
    final start = ctx.position;

    if (_matchWord(ctx, 'null')) {
      return NullNode(start, ctx.position);
    }

    // Check if it's a partial "null"
    final partial = _readPartialWord(ctx);
    if ('null'.startsWith(partial)) {
      return NullNode(start, null);
    }

    return null;
  }

  String? _parseIncompleteKey(ParseContext ctx, JsonSchema schema) {
    final buffer = StringBuffer();
    while (!ctx.isEof &&
        ctx.current != ':' &&
        ctx.current != ',' &&
        ctx.current != '}' &&
        ctx.current != ' ' &&
        ctx.current != '\n' &&
        ctx.current != '\r' &&
        ctx.current != '\t') {
      buffer.write(ctx.current);
      ctx.advance();
    }

    final partial = buffer.toString();
    if (partial.isEmpty) return null;

    // Try to match against schema properties
    final matches =
        schema.properties.keys.where((key) => key.startsWith(partial)).toList();

    if (matches.length == 1) {
      return matches.first;
    }

    return partial;
  }

  bool _matchWord(ParseContext ctx, String word) {
    final start = ctx._offset;
    for (var i = 0; i < word.length; i++) {
      if (ctx.isEof || ctx.current != word[i]) {
        // Reset position
        while (ctx._offset > start) {
          ctx._offset--;
        }
        return false;
      }
      ctx.advance();
    }
    return true;
  }

  String _readPartialWord(ParseContext ctx) {
    final buffer = StringBuffer();
    while (!ctx.isEof && _isAlpha(ctx.current!)) {
      buffer.write(ctx.current);
      ctx.advance();
    }
    return buffer.toString();
  }

  void _skipWhitespace(ParseContext ctx) {
    while (!ctx.isEof && _isWhitespace(ctx.current!)) {
      ctx.advance();
    }
  }

  bool _isWhitespace(String ch) => ' \t\n\r'.contains(ch);
  bool _isDigit(String ch) => '0123456789'.contains(ch);
  bool _isHexDigit(String ch) => '0123456789abcdefABCDEF'.contains(ch);
  bool _isAlpha(String ch) =>
      'abcdefghijklmnopqrstuvwxyz'.contains(ch.toLowerCase());
  bool _isNumberStart(String ch) => ch == '-' || _isDigit(ch);
}

/// Merges multiple schemas together for allOf support
JsonSchema _mergeSchemas(List<dynamic> schemaDefinitions) {
  if (schemaDefinitions.isEmpty) return JsonSchema.create({});
  
  // Convert schema definitions to JsonSchema objects
  final schemas = schemaDefinitions
      .map((def) => def is JsonSchema ? def : JsonSchema.create(def))
      .toList();
  
  if (schemas.length == 1) return schemas.first;
  
  // Start with empty merged properties
  final mergedProperties = <String, dynamic>{};
  final mergedRequired = <String>[];
  dynamic mergedDefault;
  
  for (final schema in schemas) {
    // Get schema as JSON to access all properties
    final schemaJson = jsonDecode(schema.toJson()) as Map<String, dynamic>;
    
    // Merge properties
    if (schemaJson['properties'] != null) {
      final props = schemaJson['properties'] as Map<String, dynamic>;
      mergedProperties.addAll(props);
    }
    
    // Merge required fields
    if (schemaJson['required'] != null) {
      final reqs = schemaJson['required'] as List<dynamic>;
      mergedRequired.addAll(reqs.cast<String>());
    }
    
    // Take the last non-null default
    if (schema.defaultValue != null) {
      mergedDefault = schema.defaultValue;
    }
  }
  
  // Create merged schema
  return JsonSchema.create({
    'type': 'object',
    'properties': mergedProperties,
    if (mergedRequired.isNotEmpty) 'required': mergedRequired.toSet().toList(),
    if (mergedDefault != null) 'default': mergedDefault,
  });
}

/// Resolves a schema considering allOf, anyOf, oneOf
JsonSchema _resolveSchema(JsonSchema schema) {
  // Get schema as JSON to check for allOf
  final schemaJson = jsonDecode(schema.toJson()) as Map<String, dynamic>;
  
  // Check for allOf
  if (schemaJson['allOf'] != null) {
    final allOfSchemas = schemaJson['allOf'] as List<dynamic>;
    if (allOfSchemas.isNotEmpty) {
      return _mergeSchemas(allOfSchemas);
    }
  }
  
  // For now, just return the schema as-is for anyOf/oneOf
  // These require more complex logic to determine which schema to use
  return schema;
}

/// Completes a partial JSON parse result
class PartialJsonCompleter {
  dynamic complete(ParseNode? node, JsonSchema schema) {
    // Resolve any allOf/anyOf/oneOf before processing
    final resolvedSchema = _resolveSchema(schema);
    
    if (node == null) {
      return _getDefaultForSchema(resolvedSchema);
    }

    if (node.isComplete) {
      // Node is complete, just convert to JSON and apply defaults
      final value = _nodeToJson(node);
      return _applySchemaDefaults(resolvedSchema, value);
    }

    // Node is incomplete, complete it based on type
    if (node is ObjectNode) {
      final completed = _completeObject(node, resolvedSchema);
      // If the object has no valid entries, return null
      if (completed.isEmpty && node.entries.isNotEmpty) {
        // Check if any entry has a recognized key
        final hasRecognizedKeys = node.entries.any((entry) =>
            entry.key != null &&
            (resolvedSchema.properties.containsKey(entry.key) || 
             entry.hasColon));
        if (!hasRecognizedKeys) {
          return null;
        }
      }
      return completed;
    } else if (node is ArrayNode) {
      return _completeArray(node, resolvedSchema);
    } else if (node is StringNode) {
      return node.value; // Return partial string
    } else if (node is NumberNode) {
      return _completeNumber(node);
    } else if (node is BoolNode) {
      return node.value;
    } else if (node is NullNode) {
      return null;
    }

    return null;
  }

  Map<String, dynamic> _completeObject(ObjectNode node, JsonSchema schema) {
    // Get required properties
    final schemaJson = jsonDecode(schema.toJson()) as Map<String, dynamic>;
    final requiredProps = (schemaJson['required'] as List<dynamic>?)
        ?.cast<String>()
        .toSet() ?? {};

    final result = <String, dynamic>{};

    // Get pattern properties
    final patternProps = 
        (schemaJson['patternProperties'] as Map<String, dynamic>?) ?? {};

    for (final entry in node.entries) {
      if (entry.key == null) continue;

      final key = entry.key!;
      
      // Find matching schema for this property
      JsonSchema? propSchema;
      if (schema.properties.containsKey(key)) {
        propSchema = schema.properties[key];
      } else {
        // Check pattern properties
        for (final patternEntry in patternProps.entries) {
          if (RegExp(patternEntry.key).hasMatch(key)) {
            propSchema = JsonSchema.create(patternEntry.value);
            break;
          }
        }
      }
      
      // If no schema found, use empty schema
      propSchema ??= JsonSchema.create({});
      
      if (entry.value != null) {
        result[key] = complete(entry.value, propSchema);
      } else if (entry.hasColon) {
        // Key with colon but no value, use default
        // For required properties, only use explicit defaults,
        // not type defaults
        final isRequired = requiredProps.contains(key);
        result[key] = _getDefaultForSchema(propSchema, 
            useTypeDefaults: !isRequired);
      }
      // If no colon, skip the entry
    }

    // If schema has a default object value, merge it with our result
    if (schema.defaultValue is Map<String, dynamic>) {
      final schemaDefault = schema.defaultValue as Map<String, dynamic>;
      // Merge schema default with result - result values take precedence
      final merged = _deepMerge(schemaDefault, result);
      
      // Apply schema defaults for missing properties
      // But skip required properties - they should not get defaults if missing
      for (final propEntry in schema.properties.entries) {
        if (!merged.containsKey(propEntry.key) && 
            !requiredProps.contains(propEntry.key)) {
          // Check if property has an explicit default
          if (propEntry.value.defaultValue != null) {
            merged[propEntry.key] = propEntry.value.defaultValue;
          }
        }
      }
      
      return merged;
    }

    // No schema default - just apply property defaults
    for (final propEntry in schema.properties.entries) {
      if (!result.containsKey(propEntry.key) && 
          !requiredProps.contains(propEntry.key)) {
        // Check if property has an explicit default
        if (propEntry.value.defaultValue != null) {
          result[propEntry.key] = propEntry.value.defaultValue;
        }
      }
    }

    return result;
  }

  List<dynamic> _completeArray(ArrayNode node, JsonSchema schema) {
    final itemSchema = schema.items ?? JsonSchema.create({});
    return node.elements
        .map((element) => complete(element, itemSchema))
        .toList();
  }

  num _completeNumber(NumberNode node) {
    var value = node.value;

    // Remove incomplete exponent
    if (RegExp(r'[eE]$').hasMatch(value)) {
      value = value.substring(0, value.length - 1);
    } else if (RegExp(r'[eE][+-]?$').hasMatch(value)) {
      value = value.substring(0, value.lastIndexOf(RegExp('[eE]')));
    }

    // Remove trailing decimal point
    if (value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }

    // Handle lone minus
    if (value == '-') {
      return 0;
    }

    return num.tryParse(value) ?? 0;
  }

  dynamic _getDefaultForSchema(JsonSchema schema, 
      {bool useTypeDefaults = true}) {
    if (schema.defaultValue != null) {
      return schema.defaultValue;
    }

    if (useTypeDefaults && 
        schema.typeList != null && 
        schema.typeList!.isNotEmpty) {
      final type = schema.typeList!.first;
      switch (type) {
        case SchemaType.object:
          return <String, dynamic>{};
        case SchemaType.array:
          return <dynamic>[];
        case SchemaType.string:
          return '';
        case SchemaType.number:
        case SchemaType.integer:
          return 0;
        case SchemaType.boolean:
          return false;
        case SchemaType.nullValue:
          return null;
      }
    }

    return null;
  }

  dynamic _applySchemaDefaults(JsonSchema schema, dynamic value) {
    // Special case: if value is an empty object and schema has an object
    // default, use the default directly without adding extra properties
    if (value is Map<String, dynamic> &&
        value.isEmpty &&
        schema.defaultValue is Map<String, dynamic>) {
      return schema.defaultValue;
    }
    
    // If schema has a default and value is an object, merge them
    if (schema.defaultValue != null && value is Map<String, dynamic>) {
      if (schema.defaultValue is Map<String, dynamic>) {
        // Deep merge the default with the value
        final merged = _deepMerge(
          schema.defaultValue as Map<String, dynamic>,
          value,
        );
        return _mergeObjectDefaults(schema, merged);
      }
    }

    if (value is Map<String, dynamic>) {
      return _mergeObjectDefaults(schema, value);
    } else if (value is List) {
      return _mergeArrayDefaults(schema, value);
    } else {
      return value ?? schema.defaultValue;
    }
  }

  Map<String, dynamic> _mergeObjectDefaults(
    JsonSchema schema,
    Map<String, dynamic> obj,
  ) {
    final merged = Map<String, dynamic>.from(obj);
    
    // Get required properties
    final schemaJson = jsonDecode(schema.toJson()) as Map<String, dynamic>;
    final requiredProps = (schemaJson['required'] as List<dynamic>?)
        ?.cast<String>()
        .toSet() ?? {};

    // Apply defaults for defined properties
    for (final entry in schema.properties.entries) {
      final key = entry.key;
      final propSchema = entry.value;
      final isRequired = requiredProps.contains(key);

      if (!merged.containsKey(key)) {
        // Only add defaults for non-required properties with explicit defaults
        if (!isRequired && propSchema.defaultValue != null) {
          merged[key] = propSchema.defaultValue;
        }
      } else if (merged[key] == null && !isRequired) {
        // Only replace null with default for non-required properties
        merged[key] = _getDefaultForSchema(propSchema);
      } else if (merged[key] != null) {
        // Recursively apply defaults to nested structures
        merged[key] = _applySchemaDefaults(propSchema, merged[key]);
      }
    }

    // Remove additional properties if not allowed
    if (schema.additionalPropertiesBool == false) {
      // Check pattern properties
      final patternProps = 
          (schemaJson['patternProperties'] as Map<String, dynamic>?) ?? {};
      
      merged.removeWhere((key, _) {
        // Keep if it's a defined property
        if (schema.properties.containsKey(key)) return false;
        
        // Keep if it matches a pattern property
        for (final pattern in patternProps.keys) {
          if (RegExp(pattern).hasMatch(key)) return false;
        }
        
        // Remove if it doesn't match any pattern
        return true;
      });
    }

    return merged;
  }

  List<dynamic> _mergeArrayDefaults(JsonSchema schema, List<dynamic> arr) {
    if (schema.items == null) return arr;

    return arr.map((item) {
      if (item == null) {
        // Check if null is allowed in the schema
        final itemSchema = schema.items!;
        if (itemSchema.typeList != null && 
            itemSchema.typeList!.contains(SchemaType.nullValue)) {
          // Null is allowed, preserve it
          return null;
        }
        // Null not allowed, use default
        return _getDefaultForSchema(itemSchema);
      }
      return _applySchemaDefaults(schema.items!, item);
    }).toList();
  }

  /// Deep merges two maps, with values from [override] taking precedence
  Map<String, dynamic> _deepMerge(
    Map<String, dynamic> base,
    Map<String, dynamic> override,
  ) {
    final result = Map<String, dynamic>.from(base);

    for (final entry in override.entries) {
      final key = entry.key;
      final value = entry.value;

      if (result.containsKey(key) &&
          result[key] is Map<String, dynamic> &&
          value is Map<String, dynamic>) {
        // Recursively merge nested objects
        result[key] = _deepMerge(
          result[key] as Map<String, dynamic>,
          value,
        );
      } else {
        // Override the value
        result[key] = value;
      }
    }

    return result;
  }
}

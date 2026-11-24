import 'dart:convert';

import 'codec.dart';

/// The default failure classification, shared by all four codecs.
///
/// Status first, body second: 429 and 5xx are retryable regardless of what
/// the body says, and the body only matters for the cases status cannot
/// decide — a 400 that is really "your quota is gone" (some providers report
/// billing failures as bad requests) and the provider-specific error types
/// Anthropic and Gemini put in their JSON.
AiErrorKind classifyHttpError(int statusCode, String bodySnippet) {
  if (statusCode == 408 || statusCode == 409 || statusCode == 429) {
    return AiErrorKind.retryable;
  }
  if (statusCode >= 500) return AiErrorKind.retryable;
  final lower = bodySnippet.toLowerCase();
  if (lower.contains('insufficient_quota') ||
      lower.contains('quota') ||
      lower.contains('rate_limit') ||
      lower.contains('rate limit') ||
      lower.contains('resource_exhausted') ||
      lower.contains('overloaded')) {
    return AiErrorKind.retryable;
  }
  return AiErrorKind.fatal;
}

/// Decodes a JSON object body, or an empty map when it is not one.
///
/// Provider error bodies are not always JSON — a proxy's HTML 502 page, an
/// empty body on a timeout — and a codec that threw while *classifying* an
/// error would lose the error entirely.
Map<String, Object?> jsonObjectOrEmpty(String body) {
  try {
    final value = jsonDecode(body);
    if (value is Map) return value.cast<String, Object?>();
  } on FormatException {
    // fall through
  }
  return const <String, Object?>{};
}

/// Reads a nested object field, or null.
Map<String, Object?>? jsonObjectField(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is Map ? value.cast<String, Object?>() : null;
}

/// Reads a nested list field, or an empty list.
List<Object?> jsonListField(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is List ? value : const <Object?>[];
}

/// Reads a string field, or null.
String? jsonStringField(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

/// Views [value] as a JSON object: a `Map` passes through, a JSON-encoded
/// `String` is decoded, anything else becomes an empty map.
///
/// The String case exists because SSE fixtures and some providers hand codecs
/// pre-encoded fragments; everywhere else callers pass the decoded `Map`.
Map<String, Object?> asObject(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  if (value is String) return jsonObjectOrEmpty(value);
  return const <String, Object?>{};
}

/// Views [value] as a list, or an empty list.
List<Object?> asList(Object? value) =>
    value is List ? value : const <Object?>[];

/// Reads a numeric field that providers variously send as int or double.
int? jsonIntField(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is double) return value.round();
  return null;
}

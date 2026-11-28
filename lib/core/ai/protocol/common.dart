import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../ai_message.dart';
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

/// Decodes an OpenAI-shaped `/models` body (`{"data": [{"id": ...}]}`) into
/// catalogue entries, keeping the metadata richer endpoints add on top.
///
/// Three shapes share this envelope:
///
/// - plain OpenAI: `id` only — every extra stays null;
/// - OpenRouter-compatible (Kilo): `context_length` plus `pricing` with
///   per-token prices as strings, `"0"` meaning free;
/// - Zen: `limit.context` plus `cost.text.{input,output}.price` as numbers.
///
/// A negative price (`"-1"` on OpenRouter auto routers) means "varies", so
/// it counts as unknown rather than paid.
List<AiCatalogModel> decodeOpenAiCatalog(String body) {
  final json = jsonObjectOrEmpty(body);
  final models = <AiCatalogModel>[];
  for (final entry in asList(json['data'])) {
    final model = asObject(entry);
    final id = jsonStringField(model, 'id');
    if (id == null) continue;
    models.add(
      AiCatalogModel(
        id: id,
        contextTokens: _catalogContext(model),
        isFree: _catalogIsFree(model),
        label:
            _nonEmpty(jsonStringField(model, 'name')) ??
            _nonEmpty(jsonStringField(model, 'display_name')),
      ),
    );
  }
  return models;
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

int? _catalogContext(Map<String, Object?> model) {
  final direct = jsonIntField(model, 'context_length');
  if (direct != null) return direct;
  return jsonIntField(asObject(model['limit']), 'context');
}

/// Whether the model is reported free. OpenRouter puts prices under
/// `pricing`, Zen under `cost.text.*.price`; either pair being all zeros
/// means free, any positive price means paid, anything else is unknown.
bool? _catalogIsFree(Map<String, Object?> model) {
  final pricing = asObject(model['pricing']);
  final prompt = _priceValue(pricing['prompt']);
  final completion = _priceValue(pricing['completion']);
  if (prompt != null && completion != null) {
    return prompt == 0 && completion == 0;
  }
  final cost = asObject(asObject(model['cost'])['text']);
  final input = _priceValue(asObject(cost['input'])['price']);
  final output = _priceValue(asObject(cost['output'])['price']);
  if (input != null && output != null) {
    return input == 0 && output == 0;
  }
  return null;
}

/// How much of a response head is buffered while deciding whether it is
/// SSE. Real streams declare themselves in the first line; anything this
/// large without a marker is a plain document.
const _sniffHeadLimit = 64 * 1024;

enum _BodyKind { undecided, sse, document }

/// Decodes a chat response body that *should* be `text/event-stream` but
/// might not be.
///
/// Some OpenAI-compatible endpoints accept `stream: true` and still answer
/// with one JSON document. Feeding that to [AiCodec.decodeStream] yields
/// zero frames — an empty 200 that looks like a successful blank reply.
/// This sniffs the head: an SSE field line routes to [AiCodec.decodeStream]
/// with the buffered prefix re-attached, anything else is collected whole
/// and decoded through [AiCodec.decodeResponse], re-emitted as stream
/// events so every consumer sees one shape.
Stream<AiStreamEvent> sniffedDecodeStream(
  AiCodec codec,
  Stream<List<int>> bodyBytes,
) async* {
  final iterator = StreamIterator<List<int>>(bodyBytes);
  final head = BytesBuilder(copy: false);
  var kind = _BodyKind.undecided;
  try {
    while (await iterator.moveNext()) {
      head.add(iterator.current);
      kind = _sniffBodyKind(utf8.decode(head.toBytes(), allowMalformed: true));
      if (kind != _BodyKind.undecided || head.length >= _sniffHeadLimit) {
        break;
      }
    }
    if (kind == _BodyKind.sse) {
      yield* codec.decodeStream(_withPrefix(head.toBytes(), iterator));
      return;
    }
    while (await iterator.moveNext()) {
      head.add(iterator.current);
    }
    yield* _documentEvents(
      codec,
      utf8.decode(head.toBytes(), allowMalformed: true),
    );
  } finally {
    await iterator.cancel();
  }
}

/// The sniffed prefix followed by every chunk [iterator] has not yielded
/// yet — the codec sees one continuous byte stream.
Stream<List<int>> _withPrefix(
  List<int> prefix,
  StreamIterator<List<int>> iterator,
) async* {
  yield prefix;
  while (await iterator.moveNext()) {
    yield iterator.current;
  }
}

_BodyKind _sniffBodyKind(String text) {
  final trimmed = text.replaceFirst('\uFEFF', '').trimLeft();
  if (trimmed.isEmpty) return _BodyKind.undecided;
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return _BodyKind.document;
  }
  final newline = trimmed.indexOf('\n');
  final firstLine = (newline < 0 ? trimmed : trimmed.substring(0, newline))
      .trimRight();
  for (final prefix in const ['data:', 'event:', 'id:', 'retry:']) {
    if (firstLine.startsWith(prefix)) return _BodyKind.sse;
  }
  // A `:`-led line is an SSE comment (keep-alive); nothing else legal
  // opens a stream, so a `{`/`[` check above already took the documents.
  if (firstLine.startsWith(':')) return _BodyKind.sse;
  return _BodyKind.undecided;
}

/// Folds a non-SSE body into the same event shapes a stream would have
/// produced, so [_observeStream] and the gateway need no second path.
Stream<AiStreamEvent> _documentEvents(AiCodec codec, String body) async* {
  if (jsonObjectOrEmpty(body).isEmpty) {
    yield AiStreamEvent.error(
      'the provider did not return an event stream or a JSON response',
    );
    yield AiStreamEvent.done();
    return;
  }
  final reply = codec.decodeResponse(body);
  if (reply.content.isNotEmpty) yield AiStreamEvent.textDelta(reply.content);
  for (final call in reply.toolCalls) {
    yield AiStreamEvent.toolCall(call);
  }
  if (reply.usage != AiUsage.empty) yield AiStreamEvent.usage(reply.usage);
  yield AiStreamEvent.done();
}

/// A price as a non-negative number, or null when absent, unparseable or
/// negative ("-1" prices mean "varies", not "free" or "paid").
double? _priceValue(Object? value) {
  final parsed = switch (value) {
    num n => n.toDouble(),
    String s => double.tryParse(s),
    _ => null,
  };
  if (parsed == null || parsed < 0) return null;
  return parsed;
}

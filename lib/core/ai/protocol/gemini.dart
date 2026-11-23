import 'dart:async';
import 'dart:convert';

import '../ai_message.dart';
import 'codec.dart';
import 'common.dart';
import 'sse_parser.dart';

/// Google Gemini: `POST {base}/v1beta/models/{model}:generateContent`.
///
/// Gemini's shape differs enough to earn its own codec: roles are `user` /
/// `model` (never `assistant`), the system prompt is a sibling
/// `systemInstruction` rather than a message, content is a list of `parts`,
/// and usage arrives as `usageMetadata` with differently-named counters.
/// Function calling exists but is mapped best-effort — see [_encodeMessage].
final class GeminiCodec implements AiCodec {
  const GeminiCodec();

  @override
  AiProtocol get protocol => AiProtocol.gemini;

  static String _trim(String baseUrl) => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  @override
  AiRequestSpec encodeChat(
    AiChatRequest request, {
    required String baseUrl,
    required String model,
    String? apiKey,
  }) {
    final system = <String>[
      for (final m in request.messages)
        if (m.role == AiRole.system && m.content.isNotEmpty) m.content,
    ];
    final contents = <Map<String, Object?>>[
      for (final m in request.messages)
        if (m.role != AiRole.system) _encodeMessage(m),
    ];
    final body = <String, Object?>{
      'contents': contents,
      if (system.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': system.join('\n\n')},
          ],
        },
      'generationConfig': {
        if (request.temperature != null) 'temperature': request.temperature,
        if (request.maxTokens != null) 'maxOutputTokens': request.maxTokens,
        if (request.topP != null) 'topP': request.topP,
        if (request.stop != null && request.stop!.isNotEmpty)
          'stopSequences': request.stop,
      },
    };
    return AiRequestSpec(
      method: 'POST',
      url:
          '${_trim(baseUrl)}/v1beta/models/$model'
          '${request.stream ? ':streamGenerateContent?alt=sse' : ':generateContent'}',
      headers: {
        'content-type': 'application/json',
        if (apiKey != null && apiKey.isNotEmpty) 'x-goog-api-key': apiKey,
      },
      body: jsonEncode(body),
    );
  }

  Map<String, Object?> _encodeMessage(AiMessage message) {
    final role = switch (message.role) {
      AiRole.assistant => 'model',
      // Gemini has no tool role; a tool result is folded into a user turn
      // the same way a caller would paste it. Function-call *results* in
      // Gemini's own dialect (functionResponse parts) arrive with the
      // function-calling work, not with text chat.
      AiRole.tool => 'user',
      _ => 'user',
    };
    final parts = <Map<String, Object?>>[];
    if (message.role == AiRole.assistant && message.toolCalls.isNotEmpty) {
      for (final call in message.toolCalls) {
        parts.add({
          'functionCall': {
            'name': call.name,
            'args': _tryJsonObject(call.arguments),
          },
        });
      }
    }
    final text = message.role == AiRole.tool
        ? '[tool ${message.name ?? 'result'} ${message.toolCallId ?? ''}]\n'
              '${message.content}'
        : message.content;
    if (text.isNotEmpty) parts.add({'text': text});
    if (parts.isEmpty) parts.add({'text': ''});
    return {'role': role, 'parts': parts};
  }

  Object? _tryJsonObject(String raw) {
    try {
      final value = jsonDecode(raw);
      return value is Map ? value : <String, Object?>{'value': value};
    } on FormatException {
      return <String, Object?>{'raw': raw};
    }
  }

  @override
  AiChatResponse decodeResponse(String body) {
    var content = StringBuffer();
    final calls = <AiToolCall>[];
    AiUsage? usage;
    for (final chunk in _chunks(body)) {
      content.write(chunk.content);
      calls.addAll(chunk.toolCalls);
      usage ??= chunk.usage;
    }
    return AiChatResponse(
      content: content.toString(),
      toolCalls: calls,
      usage: usage ?? AiUsage.empty,
    );
  }

  /// One `generateContent` response body yields exactly one chunk; the list
  /// exists so the stream path can concatenate many.
  List<({String content, List<AiToolCall> toolCalls, AiUsage? usage})> _chunks(
    String body,
  ) {
    final json = jsonObjectOrEmpty(body);
    if (json.isEmpty) return const [];
    return [_decodeChunk(json)];
  }

  ({String content, List<AiToolCall> toolCalls, AiUsage? usage}) _decodeChunk(
    Map<String, Object?> json,
  ) {
    final text = StringBuffer();
    final calls = <AiToolCall>[];
    for (final candidate in asList(json['candidates'])) {
      final content = asObject(asObject(candidate)['content']);
      for (final part in asList(content['parts'])) {
        final p = asObject(part);
        final t = jsonStringField(p, 'text');
        if (t != null) text.write(t);
        final functionCall = asObject(p['functionCall']);
        if (functionCall.isNotEmpty) {
          calls.add(
            AiToolCall(
              id: 'call_${calls.length}',
              name: jsonStringField(functionCall, 'name') ?? '',
              arguments: jsonEncode(
                functionCall['args'] ?? const <String, Object?>{},
              ),
            ),
          );
        }
      }
    }
    return (
      content: text.toString(),
      toolCalls: calls,
      usage: _decodeUsage(json['usageMetadata']),
    );
  }

  AiUsage? _decodeUsage(Object? raw) {
    final json = asObject(raw);
    if (json.isEmpty) return null;
    final prompt = jsonIntField(json, 'promptTokenCount');
    final completion = jsonIntField(json, 'candidatesTokenCount');
    return AiUsage(
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens:
          jsonIntField(json, 'totalTokenCount') ??
          ((prompt ?? 0) + (completion ?? 0)),
    );
  }

  @override
  Stream<AiStreamEvent> decodeStream(Stream<List<int>> bodyBytes) async* {
    await for (final frame in parseSse(bodyBytes)) {
      final json = jsonObjectOrEmpty(frame.data);
      if (json.isEmpty) continue;
      final chunk = _decodeChunk(json);
      if (chunk.content.isNotEmpty) {
        yield AiStreamEvent.textDelta(chunk.content);
      }
      for (final call in chunk.toolCalls) {
        yield AiStreamEvent.toolCall(call);
      }
      if (chunk.usage != null) yield AiStreamEvent.usage(chunk.usage!);
    }
    yield AiStreamEvent.done();
  }

  @override
  AiErrorKind classifyError(int statusCode, String bodySnippet) {
    final json = jsonObjectOrEmpty(bodySnippet);
    final error = asObject(json['error']);
    switch (jsonStringField(error, 'status')) {
      case 'RESOURCE_EXHAUSTED':
      case 'UNAVAILABLE':
      case 'INTERNAL':
      case 'DEADLINE_EXCEEDED':
      case 'ABORTED':
        return AiErrorKind.retryable;
      case 'UNAUTHENTICATED':
      case 'PERMISSION_DENIED':
      case 'NOT_FOUND':
      case 'INVALID_ARGUMENT':
        return AiErrorKind.fatal;
      default:
        return classifyHttpError(statusCode, bodySnippet);
    }
  }

  @override
  AiRequestSpec? modelsSpec({required String baseUrl, String? apiKey}) =>
      AiRequestSpec(
        method: 'GET',
        url: '${_trim(baseUrl)}/v1beta/models',
        headers: {
          if (apiKey != null && apiKey.isNotEmpty) 'x-goog-api-key': apiKey,
        },
      );

  @override
  List<String> decodeModels(String body) {
    final json = jsonObjectOrEmpty(body);
    return [
      for (final entry in asList(json['models']))
        if (jsonStringField(asObject(entry), 'name') case final name?)
          name.startsWith('models/') ? name.substring(7) : name,
    ];
  }
}

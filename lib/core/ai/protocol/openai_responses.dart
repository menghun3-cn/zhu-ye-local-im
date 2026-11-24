import 'dart:async';
import 'dart:convert';

import '../ai_message.dart';
import 'codec.dart';
import 'common.dart';
import 'sse_parser.dart';

/// OpenAI Responses: `POST {base}/responses`.
///
/// The newest OpenAI API — the one Codex speaks. It differs from Chat
/// Completions in ways that matter: `messages` become typed `input` items,
/// assistant output text uses the `output_text` content type, tool calls are
/// `function_call` / `function_call_output` items rather than message fields,
/// and a streamed reply is a sequence of `response.*` lifecycle events whose
/// terminal `response.completed` carries the assembled output and usage.
final class OpenAiResponsesCodec implements AiCodec {
  const OpenAiResponsesCodec();

  @override
  AiProtocol get protocol => AiProtocol.openaiResponses;

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
    final input = <Map<String, Object?>>[
      for (final m in request.messages) ..._encodeMessage(m),
    ];
    final body = <String, Object?>{
      'model': model,
      'input': input,
      'stream': request.stream,
      if (request.temperature != null) 'temperature': request.temperature,
      if (request.maxTokens != null) 'max_output_tokens': request.maxTokens,
      if (request.topP != null) 'top_p': request.topP,
      if (request.stop != null && request.stop!.isNotEmpty)
        'stop': request.stop,
    };
    return AiRequestSpec(
      method: 'POST',
      url: '${_trim(baseUrl)}/responses',
      headers: {
        'content-type': 'application/json',
        if (apiKey != null && apiKey.isNotEmpty)
          'authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );
  }

  /// One canonical message may become several input items — an assistant turn
  /// with tool calls is a message item *plus* one `function_call` per call.
  List<Map<String, Object?>> _encodeMessage(AiMessage message) {
    switch (message.role) {
      case AiRole.tool:
        return [
          {
            'type': 'function_call_output',
            'call_id': message.toolCallId,
            'output': message.content,
          },
        ];
      case AiRole.assistant when message.toolCalls.isNotEmpty:
        return [
          if (message.content.isNotEmpty)
            {
              'type': 'message',
              'role': 'assistant',
              'content': [
                {'type': 'output_text', 'text': message.content},
              ],
            },
          for (final call in message.toolCalls)
            {
              'type': 'function_call',
              'call_id': call.id,
              'name': call.name,
              'arguments': call.arguments,
            },
        ];
      default:
        final isAssistant = message.role == AiRole.assistant;
        return [
          {
            'type': 'message',
            'role': message.role.name,
            'content': [
              {
                'type': isAssistant ? 'output_text' : 'input_text',
                'text': message.content,
              },
            ],
          },
        ];
    }
  }

  @override
  AiChatResponse decodeResponse(String body) {
    final json = jsonObjectOrEmpty(body);
    final output = asList(json['output']);
    final text = StringBuffer();
    final calls = <AiToolCall>[];
    for (final entry in output) {
      final item = asObject(entry);
      switch (jsonStringField(item, 'type')) {
        case 'message':
          for (final part in asList(item['content'])) {
            final p = asObject(part);
            if (jsonStringField(p, 'type') == 'output_text') {
              text.write(jsonStringField(p, 'text') ?? '');
            }
          }
        case 'function_call':
          calls.add(
            AiToolCall(
              id:
                  jsonStringField(item, 'call_id') ??
                  jsonStringField(item, 'id') ??
                  '',
              name: jsonStringField(item, 'name') ?? '',
              arguments: jsonStringField(item, 'arguments') ?? '{}',
            ),
          );
      }
    }
    return AiChatResponse(
      content: text.toString(),
      toolCalls: calls,
      usage: _decodeUsage(json['usage']) ?? AiUsage.empty,
    );
  }

  AiUsage? _decodeUsage(Object? raw) {
    final json = asObject(raw);
    if (json.isEmpty) return null;
    final input = jsonIntField(json, 'input_tokens');
    final output = jsonIntField(json, 'output_tokens');
    return AiUsage(
      promptTokens: input,
      completionTokens: output,
      totalTokens:
          jsonIntField(json, 'total_tokens') ?? ((input ?? 0) + (output ?? 0)),
      cachedTokens: jsonIntField(
        asObject(json['input_tokens_details']),
        'cached_tokens',
      ),
    );
  }

  @override
  Stream<AiStreamEvent> decodeStream(Stream<List<int>> bodyBytes) async* {
    await for (final frame in parseSse(bodyBytes)) {
      final type = frame.event ?? _eventType(frame.data);
      switch (type) {
        case 'response.output_text.delta':
          final json = jsonObjectOrEmpty(frame.data);
          final delta = jsonStringField(json, 'delta');
          if (delta != null && delta.isNotEmpty) {
            yield AiStreamEvent.textDelta(delta);
          }
        case 'response.output_item.done':
          final json = jsonObjectOrEmpty(frame.data);
          final item = asObject(json['item']);
          if (jsonStringField(item, 'type') == 'function_call') {
            yield AiStreamEvent.toolCall(
              AiToolCall(
                id:
                    jsonStringField(item, 'call_id') ??
                    jsonStringField(item, 'id') ??
                    '',
                name: jsonStringField(item, 'name') ?? '',
                arguments: jsonStringField(item, 'arguments') ?? '{}',
              ),
            );
          }
        case 'response.completed':
          final json = jsonObjectOrEmpty(frame.data);
          final response = asObject(json['response']);
          final usage = _decodeUsage(response['usage']);
          if (usage != null) yield AiStreamEvent.usage(usage);
          yield AiStreamEvent.done();
          return;
        case 'response.failed' || 'response.incomplete' || 'error':
          final json = jsonObjectOrEmpty(frame.data);
          final response = asObject(json['response']);
          final error = asObject(response['error']);
          yield AiStreamEvent.error(
            jsonStringField(error, 'message') ??
                jsonStringField(asObject(json['error']), 'message') ??
                'the provider reported a failed response',
          );
          yield AiStreamEvent.done();
          return;
      }
    }
    yield AiStreamEvent.done();
  }

  /// Responses events carry their type in the JSON `type` field even when the
  /// SSE `event:` line is absent, which some compatible providers omit.
  String? _eventType(String data) =>
      jsonStringField(jsonObjectOrEmpty(data), 'type');

  @override
  AiErrorKind classifyError(int statusCode, String bodySnippet) {
    final json = jsonObjectOrEmpty(bodySnippet);
    final error = asObject(json['error']);
    final code = jsonStringField(error, 'code') ?? '';
    final type = jsonStringField(error, 'type') ?? '';
    if (code.contains('insufficient_quota') ||
        type == 'insufficient_quota' ||
        type == 'rate_limit_exceeded') {
      return AiErrorKind.retryable;
    }
    return classifyHttpError(statusCode, bodySnippet);
  }

  @override
  AiRequestSpec? modelsSpec({required String baseUrl, String? apiKey}) =>
      AiRequestSpec(
        method: 'GET',
        url: '${_trim(baseUrl)}/models',
        headers: {
          if (apiKey != null && apiKey.isNotEmpty)
            'authorization': 'Bearer $apiKey',
        },
      );

  @override
  List<String> decodeModels(String body) {
    final json = jsonObjectOrEmpty(body);
    return [
      for (final entry in asList(json['data']))
        ?jsonStringField(asObject(entry), 'id'),
    ];
  }
}

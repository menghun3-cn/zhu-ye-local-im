import 'dart:async';
import 'dart:convert';

import '../ai_message.dart';
import 'codec.dart';
import 'common.dart';
import 'sse_parser.dart';

/// Anthropic Messages: `POST {base}/v1/messages`.
///
/// Differences that shape this codec: `max_tokens` is required (there is no
/// server default, so the codec supplies one when the caller did not), system
/// turns lift out of `messages` into a top-level field, tool results travel
/// as `tool_result` blocks inside a *user* message, and the stream is a typed
/// event sequence (`content_block_delta`, `message_delta`, …) rather than
/// OpenAI's single `choices[].delta` shape.
final class AnthropicCodec implements AiCodec {
  const AnthropicCodec();

  /// Sent when the caller leaves [AiChatRequest.maxTokens] unset — Anthropic
  /// rejects the request outright without one, and "however much the model
  /// feels like" is not an answer the API accepts.
  static const int defaultMaxTokens = 8192;

  static const _apiVersion = '2023-06-01';

  @override
  AiProtocol get protocol => AiProtocol.anthropic;

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
    final messages = <Map<String, Object?>>[
      for (final m in request.messages)
        if (m.role != AiRole.system) _encodeMessage(m),
    ];
    final body = <String, Object?>{
      'model': model,
      'max_tokens': request.maxTokens ?? defaultMaxTokens,
      'messages': messages,
      'stream': request.stream,
      if (system.isNotEmpty) 'system': system.join('\n\n'),
      if (request.temperature != null) 'temperature': request.temperature,
      if (request.topP != null) 'top_p': request.topP,
      if (request.stop != null && request.stop!.isNotEmpty)
        'stop_sequences': request.stop,
    };
    return AiRequestSpec(
      method: 'POST',
      url: '${_trim(baseUrl)}/v1/messages',
      headers: {
        'content-type': 'application/json',
        'anthropic-version': _apiVersion,
        if (apiKey != null && apiKey.isNotEmpty) 'x-api-key': apiKey,
      },
      body: jsonEncode(body),
    );
  }

  Map<String, Object?> _encodeMessage(AiMessage message) {
    switch (message.role) {
      case AiRole.user:
        return {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': message.content},
          ],
        };
      case AiRole.assistant:
        return {
          'role': 'assistant',
          'content': [
            if (message.content.isNotEmpty)
              {'type': 'text', 'text': message.content},
            for (final call in message.toolCalls)
              {
                'type': 'tool_use',
                'id': call.id,
                'name': call.name,
                'input': _tryJsonObject(call.arguments),
              },
          ],
        };
      case AiRole.tool:
        // Anthropic has no tool role: a result is a user turn carrying a
        // tool_result block keyed by the call it answers.
        return {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': message.toolCallId,
              'content': message.content,
            },
          ],
        };
      case AiRole.system:
        // Filtered out by the caller; unreachable in a well-formed request.
        return {'role': 'user', 'content': message.content};
    }
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
    final json = jsonObjectOrEmpty(body);
    final content = asList(json['content']);
    final text = StringBuffer();
    final calls = <AiToolCall>[];
    for (final entry in content) {
      final block = asObject(entry);
      switch (jsonStringField(block, 'type')) {
        case 'text':
          text.write(jsonStringField(block, 'text') ?? '');
        case 'tool_use':
          calls.add(
            AiToolCall(
              id: jsonStringField(block, 'id') ?? '',
              name: jsonStringField(block, 'name') ?? '',
              arguments: jsonEncode(
                block['input'] ?? const <String, Object?>{},
              ),
            ),
          );
        default:
          break;
      }
    }
    return AiChatResponse(
      content: text.toString(),
      toolCalls: calls,
      usage: _decodeUsage(json['usage']),
    );
  }

  AiUsage _decodeUsage(Object? raw) {
    final json = asObject(raw);
    if (json.isEmpty) return AiUsage.empty;
    return AiUsage(
      promptTokens: jsonIntField(json, 'input_tokens'),
      completionTokens: jsonIntField(json, 'output_tokens'),
      totalTokens:
          (jsonIntField(json, 'input_tokens') ?? 0) +
          (jsonIntField(json, 'output_tokens') ?? 0),
      cachedTokens: jsonIntField(json, 'cache_read_input_tokens'),
      cacheWriteTokens: jsonIntField(json, 'cache_creation_input_tokens'),
    );
  }

  @override
  Stream<AiStreamEvent> decodeStream(Stream<List<int>> bodyBytes) async* {
    // Tool calls stream as start/delta/stop triples keyed by content-block
    // index, so the index is the correlation id until the stop event.
    final openCalls = <int, ({String id, String name, StringBuffer args})>{};
    int? promptTokens;
    int? completionTokens;

    await for (final frame in parseSse(bodyBytes)) {
      if (frame.event == 'message_stop' || frame.data == '[DONE]') {
        break;
      }
      final json = jsonObjectOrEmpty(frame.data);
      if (json.isEmpty) continue;
      switch (frame.event ?? jsonStringField(json, 'type')) {
        case 'content_block_start':
          final block = asObject(json['content_block']);
          if (jsonStringField(block, 'type') == 'tool_use') {
            final index = json['index'] as int? ?? 0;
            openCalls[index] = (
              id: jsonStringField(block, 'id') ?? '',
              name: jsonStringField(block, 'name') ?? '',
              args: StringBuffer(),
            );
          }
        case 'content_block_delta':
          final delta = asObject(json['delta']);
          switch (jsonStringField(delta, 'type')) {
            case 'text_delta':
              final text = jsonStringField(delta, 'text');
              if (text != null && text.isNotEmpty) {
                yield AiStreamEvent.textDelta(text);
              }
            case 'thinking_delta':
              final thinking = jsonStringField(delta, 'thinking');
              if (thinking != null && thinking.isNotEmpty) {
                yield AiStreamEvent.reasoningDelta(thinking);
              }
            case 'input_json_delta':
              final partial = jsonStringField(delta, 'partial_json');
              final index = json['index'] as int? ?? 0;
              if (partial != null) openCalls[index]?.args.write(partial);
          }
        case 'content_block_stop':
          final index = json['index'] as int? ?? 0;
          final call = openCalls.remove(index);
          if (call != null) {
            yield AiStreamEvent.toolCall(
              AiToolCall(
                id: call.id,
                name: call.name,
                arguments: call.args.isEmpty ? '{}' : call.args.toString(),
              ),
            );
          }
        case 'message_start':
          promptTokens ??= jsonIntField(
            asObject(asObject(json['message'])['usage']),
            'input_tokens',
          );
        case 'message_delta':
          completionTokens ??= jsonIntField(
            asObject(json['usage']),
            'output_tokens',
          );
      }
    }
    if (promptTokens != null || completionTokens != null) {
      yield AiStreamEvent.usage(
        AiUsage(
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: (promptTokens ?? 0) + (completionTokens ?? 0),
        ),
      );
    }
    yield AiStreamEvent.done();
  }

  @override
  AiErrorKind classifyError(int statusCode, String bodySnippet) {
    final json = jsonObjectOrEmpty(bodySnippet);
    final error = asObject(json['error']);
    switch (jsonStringField(error, 'type')) {
      case 'overloaded_error':
      case 'rate_limit_error':
      case 'api_error':
        return AiErrorKind.retryable;
      case 'authentication_error':
      case 'permission_error':
      case 'not_found_error':
      case 'invalid_request_error':
        return AiErrorKind.fatal;
      default:
        return classifyHttpError(statusCode, bodySnippet);
    }
  }

  @override
  AiRequestSpec? modelsSpec({required String baseUrl, String? apiKey}) =>
      AiRequestSpec(
        method: 'GET',
        url: '${_trim(baseUrl)}/v1/models',
        headers: {
          'anthropic-version': _apiVersion,
          if (apiKey != null && apiKey.isNotEmpty) 'x-api-key': apiKey,
        },
      );

  @override
  List<String> decodeModels(String body) => [
    for (final model in decodeModelCatalog(body)) model.id,
  ];

  // Anthropic's own listing is a bare `data[].id` envelope, but gateways
  // like Zen answer the same URL with the rich OpenAI-style catalogue —
  // the shared parser reads both, display_name included.
  @override
  List<AiCatalogModel> decodeModelCatalog(String body) =>
      decodeOpenAiCatalog(body);
}

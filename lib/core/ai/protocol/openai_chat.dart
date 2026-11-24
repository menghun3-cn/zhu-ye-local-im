import 'dart:async';
import 'dart:convert';

import '../ai_message.dart';
import 'codec.dart';
import 'common.dart';
import 'sse_parser.dart';

/// OpenAI Chat Completions: `POST {base}/chat/completions`.
///
/// The protocol most compatible endpoints speak — DeepSeek, Kimi, GLM,
/// Ollama, LM Studio and every "OpenAI-compatible" relay all land here, which
/// is why it is also the codec the local gateway will speak on the way in.
final class OpenAiChatCodec implements AiCodec {
  const OpenAiChatCodec();

  @override
  AiProtocol get protocol => AiProtocol.openaiChat;

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
    final body = <String, Object?>{
      'model': model,
      'messages': [for (final m in request.messages) _encodeMessage(m)],
      'stream': request.stream,
      if (request.temperature != null) 'temperature': request.temperature,
      if (request.maxTokens != null) 'max_tokens': request.maxTokens,
      if (request.topP != null) 'top_p': request.topP,
      if (request.stop != null && request.stop!.isNotEmpty)
        'stop': request.stop,
      if (request.stream) 'stream_options': {'include_usage': true},
    };
    return AiRequestSpec(
      method: 'POST',
      url: '${_trim(baseUrl)}/chat/completions',
      headers: {
        'content-type': 'application/json',
        if (apiKey != null && apiKey.isNotEmpty)
          'authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );
  }

  Map<String, Object?> _encodeMessage(AiMessage message) {
    final out = <String, Object?>{'role': message.role.name};
    switch (message.role) {
      case AiRole.assistant:
        if (message.toolCalls.isNotEmpty) {
          out['tool_calls'] = [
            for (final call in message.toolCalls)
              {
                'id': call.id,
                'type': 'function',
                'function': {'name': call.name, 'arguments': call.arguments},
              },
          ];
          if (message.content.isNotEmpty) out['content'] = message.content;
        } else {
          out['content'] = message.content;
        }
      case AiRole.tool:
        out['tool_call_id'] = message.toolCallId;
        if (message.name != null) out['name'] = message.name;
        out['content'] = message.content;
      case AiRole.system || AiRole.user:
        out['content'] = message.content;
    }
    return out;
  }

  @override
  AiChatResponse decodeResponse(String body) {
    final json = jsonObjectOrEmpty(body);
    final choices = asList(json['choices']);
    final message = choices.isEmpty
        ? const <String, Object?>{}
        : asObject(asObject(choices.first)['message']);
    return AiChatResponse(
      content: jsonStringField(message, 'content') ?? '',
      toolCalls: _decodeToolCalls(asList(message['tool_calls'])),
      usage: _decodeUsage(json['usage']),
    );
  }

  List<AiToolCall> _decodeToolCalls(List<Object?> raw) {
    final calls = <AiToolCall>[];
    for (final entry in raw) {
      final call = asObject(entry);
      final function = asObject(call['function']);
      calls.add(
        AiToolCall(
          id: jsonStringField(call, 'id') ?? '',
          name: jsonStringField(function, 'name') ?? '',
          arguments:
              jsonStringField(function, 'arguments') ??
              jsonEncode(const <String, Object?>{}),
        ),
      );
    }
    return calls;
  }

  AiUsage _decodeUsage(Object? raw) {
    final json = asObject(raw);
    if (json.isEmpty) return AiUsage.empty;
    return AiUsage(
      promptTokens: jsonIntField(json, 'prompt_tokens'),
      completionTokens: jsonIntField(json, 'completion_tokens'),
      totalTokens: jsonIntField(json, 'total_tokens'),
      cachedTokens: jsonIntField(
        asObject(json['prompt_tokens_details']),
        'cached_tokens',
      ),
    );
  }

  @override
  Stream<AiStreamEvent> decodeStream(Stream<List<int>> bodyBytes) async* {
    // OpenAI streams tool calls as fragments: each delta carries an `index`,
    // an optional `id`/`name` on the first fragment, and a slice of the JSON
    // `arguments` string. A fragment is not a call, so they accumulate per
    // index and flush as complete calls before `done`.
    final pendingCalls = <int, _PendingToolCall>{};

    await for (final frame in parseSse(bodyBytes)) {
      if (frame.data == '[DONE]') break;
      final json = jsonObjectOrEmpty(frame.data);
      if (json.isEmpty) continue;

      final choices = asList(json['choices']);
      if (choices.isNotEmpty) {
        final delta = asObject(asObject(choices.first)['delta']);
        final content = jsonStringField(delta, 'content');
        if (content != null && content.isNotEmpty) {
          yield AiStreamEvent.textDelta(content);
        }
        for (final raw in asList(delta['tool_calls'])) {
          final entry = asObject(raw);
          final index = entry['index'] is int ? entry['index'] as int : 0;
          final call = pendingCalls.putIfAbsent(index, _PendingToolCall.new);
          final id = jsonStringField(entry, 'id');
          if (id != null && id.isNotEmpty) call.id = id;
          final name = jsonStringField(asObject(entry['function']), 'name');
          if (name != null && name.isNotEmpty) call.name = name;
          final args = asObject(entry['function'])['arguments'];
          if (args is String) {
            call.arguments.write(args);
          } else if (args != null) {
            // A few compatible providers send the whole object at once.
            call.arguments
              ..clear()
              ..write(jsonEncode(args));
          }
        }
      }
      final usage = _decodeUsage(json['usage']);
      if (usage.totalTokens != null ||
          usage.promptTokens != null ||
          usage.completionTokens != null) {
        yield AiStreamEvent.usage(usage);
      }
    }
    for (final call in pendingCalls.values) {
      if (call.name.isEmpty) continue;
      yield AiStreamEvent.toolCall(
        AiToolCall(
          id: call.id,
          name: call.name,
          arguments: call.arguments.isEmpty ? '{}' : call.arguments.toString(),
        ),
      );
    }
    yield AiStreamEvent.done();
  }

  @override
  AiErrorKind classifyError(int statusCode, String bodySnippet) =>
      classifyHttpError(statusCode, bodySnippet);

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

/// Mutable accumulator for one streamed `tool_calls` entry while its
/// fragments arrive. Records can't hold this because fields arrive piecemeal.
final class _PendingToolCall {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}

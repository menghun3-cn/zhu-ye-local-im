import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ai_message.dart';
import 'ai_router.dart';
import 'gateway_token.dart';
import 'provider_store.dart';

/// The local AI gateway: an OpenAI-compatible endpoint on `127.0.0.1` that
/// serves the providers configured inside the app.
///
/// This is the piece that makes "configure once, use everywhere" true for
/// tools that only know how to speak OpenAI: Claude Code, Codex, OpenCode or
/// a curl one-liner can point at `http://127.0.0.1:<port>/v1` with the
/// gateway token and reach every enabled model — including routing groups,
/// which appear in `/v1/models` as `group/<id>` exactly as magpie exposes
/// them.
///
/// Loopback only, by design: the gateway exists so *this machine's* tools
/// can use *this device's* providers. Binding wider would publish the
/// owner's API keys to the LAN, which the per-device configuration decision
/// explicitly ruled out.
///
/// v1 speaks two endpoints — `GET /v1/models` and
/// `POST /v1/chat/completions`, streaming included. Anthropic- and
/// Gemini-shaped inbound endpoints are a later addition; the codec layer
/// already translates both directions, so they are endpoints, not new
/// machinery.
final class AiGateway {
  AiGateway({
    required this.store,
    required this.router,
    required this.token,
    this.maxRequestBytes = 1 << 20,
  });

  /// Where configuration is re-read for every request, so a settings edit
  /// takes effect without a gateway restart.
  final AiConfigStore store;

  /// Resolves model references and fails over across routing groups.
  final AiRouter router;

  /// The bearer token callers must present.
  final AiGatewayToken token;

  /// Bodies larger than this are refused with 413 — a chat request is
  /// kilobytes, and an unbounded read is a memory bomb on loopback.
  final int maxRequestBytes;

  HttpServer? _server;
  int? _actualPort;

  /// The port actually bound — meaningful only while [isRunning].
  int? get actualPort => _actualPort;

  bool get isRunning => _server != null;

  /// The base URL callers configure, e.g. `http://127.0.0.1:51234/v1`.
  String? get endpoint =>
      _actualPort == null ? null : 'http://127.0.0.1:$_actualPort/v1';

  /// Binds loopback. [preferredPort] 0 — the default — takes any free port,
  /// which is the honest answer for a service whose port is displayed in
  /// the UI rather than written into configs.
  Future<void> start({int preferredPort = 0}) async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        preferredPort,
      );
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    _actualPort = _server!.port;
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _actualPort = null;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.headers.value('authorization') != 'Bearer ${token.value}') {
        _writeError(request, 401, 'missing or invalid gateway token');
        return;
      }
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/models') {
        await _models(request);
      } else if (request.method == 'POST' && path == '/v1/chat/completions') {
        await _chatCompletions(request);
      } else {
        _writeError(request, 404, 'unknown endpoint: ${request.method} $path');
      }
    } on Object catch (error) {
      // A handler that throws must still answer: a hung socket looks like a
      // dead gateway, and the caller cannot tell the difference.
      _writeError(request, 500, '$error');
    }
  }

  Future<void> _models(HttpRequest request) async {
    final refs = await router.exposedModelRefs();
    _writeJson(request, 200, {
      'object': 'list',
      'data': [
        for (final ref in refs)
          {
            'id': ref,
            'object': 'model',
            'created': 0,
            'owned_by': 'local-transfer',
          },
      ],
    });
  }

  Future<void> _chatCompletions(HttpRequest request) async {
    final raw = await _readBody(request);
    if (raw == null) {
      _writeError(request, 413, 'request body too large');
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      _writeError(request, 400, 'request body is not valid JSON');
      return;
    }
    if (decoded is! Map) {
      _writeError(request, 400, 'request body must be a JSON object');
      return;
    }
    final body = decoded.cast<String, Object?>();

    final model = body['model'];
    final rawMessages = body['messages'];
    if (model is! String || model.isEmpty) {
      _writeError(request, 400, '"model" is required');
      return;
    }
    if (rawMessages is! List || rawMessages.isEmpty) {
      _writeError(request, 400, '"messages" must be a non-empty list');
      return;
    }

    final wantsStream = body['stream'] == true;
    final chatRequest = AiChatRequest(
      model: model,
      stream: wantsStream,
      temperature: _number(body['temperature']),
      maxTokens: _int(body['max_tokens']),
      topP: _number(body['top_p']),
      stop: _stringList(body['stop']),
      messages: [
        for (final entry in rawMessages)
          if (entry is Map) _canonicalMessage(entry.cast<String, Object?>()),
      ],
    );

    final AiReply reply;
    try {
      reply = await router.chat(chatRequest);
    } on AiRequestException catch (error) {
      _writeError(request, 502, error.message);
      return;
    }

    if (wantsStream) {
      await _streamReply(request, reply);
    } else {
      await _fullReply(request, reply);
    }
  }

  /// Answers a non-streamed request. A streamed reply arriving here means a
  /// caller asked for stream but the member could not — drained into one
  /// response rather than left hanging.
  Future<void> _fullReply(HttpRequest request, AiReply reply) async {
    if (reply is AiStreamReply) {
      reply = AiFullReply(
        servedBy: reply.servedBy,
        response: await _collect(reply.events),
      );
    }
    _writeJson(request, 200, _completionJson(reply as AiFullReply));
  }

  /// Pipes canonical stream events out as OpenAI `chat.completion.chunk`
  /// frames, finishing with the literal `data: [DONE]` every OpenAI client
  /// waits for.
  Future<void> _streamReply(HttpRequest request, AiReply reply) async {
    final response = request.response
      ..statusCode = 200
      ..headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      )
      ..headers.set('cache-control', 'no-cache');

    Stream<AiStreamEvent> events;
    String servedBy;
    if (reply is AiStreamReply) {
      events = reply.events;
      servedBy = reply.servedBy;
    } else {
      // A member that answered whole to a streaming request still gets a
      // well-formed stream: one chunk, then DONE.
      servedBy = reply.servedBy;
      final full = (reply as AiFullReply).response;
      events = Stream.fromIterable([
        if (full.content.isNotEmpty) AiStreamEvent.textDelta(full.content),
        for (final call in full.toolCalls) AiStreamEvent.toolCall(call),
        if (full.usage != AiUsage.empty) AiStreamEvent.usage(full.usage),
        AiStreamEvent.done(),
      ]);
    }

    var toolCallIndex = 0;
    try {
      await for (final event in events) {
        switch (event.kind) {
          case AiStreamKind.textDelta:
            _writeSse(response, _chunkJson(servedBy, {'content': event.text}));
          case AiStreamKind.toolCall:
            _writeSse(
              response,
              _chunkJson(servedBy, {
                'tool_calls': [
                  {
                    'index': toolCallIndex++,
                    'id': event.toolCall!.id,
                    'type': 'function',
                    'function': {
                      'name': event.toolCall!.name,
                      'arguments': event.toolCall!.arguments,
                    },
                  },
                ],
              }),
            );
          case AiStreamKind.usage:
            _writeSse(response, _usageChunkJson(servedBy, event.usage!));
          case AiStreamKind.done:
            break;
          case AiStreamKind.error:
            _writeSse(response, {
              'error': {'message': event.text ?? 'stream error'},
            });
        }
        await response.flush();
      }
    } on Object catch (error) {
      // The status line is already gone; the only honest signal left is an
      // error frame before DONE.
      _writeSse(response, {
        'error': {'message': '$error'},
      });
    }
    response.write('data: [DONE]\n\n');
    await response.close();
  }

  /// Folds a stream into one reply — the non-streaming path's fallback.
  Future<AiChatResponse> _collect(Stream<AiStreamEvent> events) async {
    final text = StringBuffer();
    final calls = <AiToolCall>[];
    AiUsage usage = AiUsage.empty;
    String? error;
    await for (final event in events) {
      switch (event.kind) {
        case AiStreamKind.textDelta:
          text.write(event.text);
        case AiStreamKind.toolCall:
          calls.add(event.toolCall!);
        case AiStreamKind.usage:
          usage = event.usage!;
        case AiStreamKind.error:
          error = event.text;
        case AiStreamKind.done:
          break;
      }
    }
    if (error != null) {
      throw AiRequestException(error);
    }
    return AiChatResponse(
      content: text.toString(),
      toolCalls: calls,
      usage: usage,
    );
  }

  Map<String, Object?> _completionJson(AiFullReply full) {
    final response = full.response;
    final message = <String, Object?>{
      'role': 'assistant',
      'content': response.toolCalls.isEmpty ? response.content : null,
      if (response.toolCalls.isNotEmpty)
        'tool_calls': [
          for (final call in response.toolCalls)
            {
              'id': call.id,
              'type': 'function',
              'function': {'name': call.name, 'arguments': call.arguments},
            },
        ],
    };
    return {
      'id': 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}',
      'object': 'chat.completion',
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'model': full.servedBy,
      'choices': [
        {'index': 0, 'message': message, 'finish_reason': 'stop'},
      ],
      'usage': {
        if (response.usage.promptTokens != null)
          'prompt_tokens': response.usage.promptTokens,
        if (response.usage.completionTokens != null)
          'completion_tokens': response.usage.completionTokens,
        if (response.usage.totalTokens != null)
          'total_tokens': response.usage.totalTokens,
      },
    };
  }

  Map<String, Object?> _chunkJson(
    String servedBy,
    Map<String, Object?> delta,
  ) => {
    'id': 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}',
    'object': 'chat.completion.chunk',
    'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'model': servedBy,
    'choices': [
      {'index': 0, 'delta': delta, 'finish_reason': null},
    ],
  };

  Map<String, Object?> _usageChunkJson(String servedBy, AiUsage usage) => {
    'id': 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}',
    'object': 'chat.completion.chunk',
    'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'model': servedBy,
    'choices': const [],
    'usage': {
      if (usage.promptTokens != null) 'prompt_tokens': usage.promptTokens,
      if (usage.completionTokens != null)
        'completion_tokens': usage.completionTokens,
      if (usage.totalTokens != null) 'total_tokens': usage.totalTokens,
    },
  };

  void _writeSse(HttpResponse response, Object? payload) {
    response.write('data: ${jsonEncode(payload)}\n\n');
  }

  /// Maps one OpenAI-shaped inbound message to canonical form. Content may
  /// be a plain string or the parts array newer clients send; tool calls
  /// and tool results pass through by their wire names.
  AiMessage _canonicalMessage(Map<String, Object?> json) {
    final roleName = json['role'] as String? ?? 'user';
    final role = AiRole.values.asNameMap()[roleName] ?? AiRole.user;
    return AiMessage(
      role: role,
      content: _contentText(json['content']),
      toolCalls: _inboundToolCalls(json['tool_calls']),
      toolCallId: json['tool_call_id'] as String?,
      name: json['name'] as String?,
    );
  }

  String _contentText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final text = StringBuffer();
      for (final part in content) {
        if (part is Map) {
          final p = part.cast<String, Object?>();
          final t = p['text'];
          if (t is String) text.write(t);
        } else if (part is String) {
          text.write(part);
        }
      }
      return text.toString();
    }
    return '';
  }

  List<AiToolCall> _inboundToolCalls(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          () {
            final call = entry.cast<String, Object?>();
            final function = call['function'];
            final fn = function is Map
                ? function.cast<String, Object?>()
                : const <String, Object?>{};
            return AiToolCall(
              id: call['id'] as String? ?? '',
              name: fn['name'] as String? ?? '',
              arguments: fn['arguments'] is String
                  ? fn['arguments'] as String
                  : jsonEncode(fn['arguments'] ?? const <String, Object?>{}),
            );
          }(),
    ];
  }

  /// Reads the request body, or null when it exceeds [maxRequestBytes].
  Future<String?> _readBody(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > maxRequestBytes) return null;
    }
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }

  void _writeJson(HttpRequest request, int status, Object? body) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    unawaited(request.response.close());
  }

  /// OpenAI-shaped error body: `{"error": {"message": ...}}` is what every
  /// client already knows how to print.
  void _writeError(HttpRequest request, int status, String message) {
    _writeJson(request, status, {
      'error': {'message': message, 'type': 'gateway_error'},
    });
  }

  double? _number(Object? value) => value is num ? value.toDouble() : null;

  int? _int(Object? value) => value is num ? value.toInt() : null;

  List<String>? _stringList(Object? value) {
    if (value is String) return [value];
    if (value is List) {
      final out = [
        for (final v in value)
          if (v is String) v,
      ];
      return out.isEmpty ? null : out;
    }
    return null;
  }
}

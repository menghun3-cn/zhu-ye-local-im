import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ai_message.dart';
import 'ai_router.dart';
import 'gateway_keys.dart';
import 'provider.dart';
import 'provider_store.dart';

/// The local AI gateway: an OpenAI-compatible endpoint that serves the
/// providers configured inside the app.
///
/// This is the piece that makes "configure once, use everywhere" true for
/// tools that only know how to speak OpenAI: Claude Code, Codex, OpenCode or
/// a curl one-liner can point at `http://<host>:<port>/v1` with the gateway
/// token and reach every enabled model — including routing groups, which
/// appear in `/v1/models` as `group/<id>` exactly as magpie exposes them.
///
/// Two scopes, both behind the bearer token: `loopback` binds `127.0.0.1`
/// only, the default; `lan` binds `0.0.0.0`, which answers on loopback *and*
/// every LAN address — how another machine on the network reaches the same
/// configured providers. Wider exposure is opt-in because the token is the
/// only thing between the LAN and the owner's API keys.
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
    required this.keySource,
    this.maxRequestBytes = 1 << 20,
  });

  /// Where configuration is re-read for every request, so a settings edit
  /// takes effect without a gateway restart.
  final AiConfigStore store;

  /// Resolves model references and fails over across routing groups.
  final AiRouter router;

  /// The keyring, read on every request so adding or deleting a key in
  /// settings takes effect without a rebind.
  final Future<List<AiGatewayKey>> Function() keySource;

  /// Bodies larger than this are refused with 413 — a chat request is
  /// kilobytes, and an unbounded read is a memory bomb on loopback.
  final int maxRequestBytes;

  HttpServer? _server;
  int? _actualPort;
  AiGatewayScope _scope = AiGatewayScope.loopback;
  List<String> _lanAddresses = const [];

  /// The port actually bound — meaningful only while [isRunning].
  int? get actualPort => _actualPort;

  /// The scope this server was started with.
  AiGatewayScope get scope => _scope;

  /// Non-loopback IPv4 addresses the LAN scope answers on, discovered at
  /// bind time. Empty under loopback scope — and possibly empty under LAN
  /// too, when the machine has no usable interface; the endpoint list then
  /// just shows loopback, which still works because `0.0.0.0` covers it.
  List<String> get lanAddresses => _lanAddresses;

  bool get isRunning => _server != null;

  /// The base URL callers on this machine configure,
  /// e.g. `http://127.0.0.1:51234/v1`. Works under both scopes: `0.0.0.0`
  /// answers loopback too.
  String? get endpoint =>
      _actualPort == null ? null : 'http://127.0.0.1:$_actualPort/v1';

  /// Binds [scope]. [preferredPort] 0 — or any port already taken — falls
  /// back to whatever the OS assigns; [AiGatewayConfig.defaultPort] is what
  /// the persisted configuration asks for, so a configured client keeps a
  /// stable endpoint across restarts.
  Future<void> start({
    int preferredPort = 0,
    AiGatewayScope scope = AiGatewayScope.loopback,
  }) async {
    if (_server != null) return;
    final address = scope == AiGatewayScope.lan
        ? InternetAddress.anyIPv4
        : InternetAddress.loopbackIPv4;
    try {
      _server = await HttpServer.bind(address, preferredPort);
    } on SocketException {
      _server = await HttpServer.bind(address, 0);
    }
    _scope = scope;
    _actualPort = _server!.port;
    if (scope == AiGatewayScope.lan) {
      _lanAddresses = await _listLanAddresses();
    }
    _server!.listen(_handle);
  }

  /// Every usable LAN IPv4 address, for the settings page to print. A
  /// failure here must not take the gateway down — an empty list just
  /// means the UI shows loopback alone.
  static Future<List<String>> _listLanAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final addresses = [
        for (final interface in interfaces)
          if (!_isVirtualInterface(interface.name))
            for (final addr in interface.addresses)
              if (!addr.isLoopback &&
                  !addr.isLinkLocal &&
                  !_isVirtualSubnet(addr.address))
                addr.address,
      ];
      // Interface enumeration order is arbitrary, and overlay networks
      // (Tailscale's 100.64/10, VPNs) routinely come first — but the
      // address a LAN peer actually dials is the RFC1918 one. Rank
      // private ranges ahead so "the" gateway address is the LAN's.
      return addresses..sort(compareLanAddresses);
    } on Object {
      return const [];
    }
  }

  /// `dart:io` reports virtual adapters as plain ethernet interfaces — a
  /// Hyper-V `vEthernet`, a VMware host-only NIC and the real LAN card are
  /// indistinguishable by type. The name is the only signal available, so
  /// the known virtual-adapter names are filtered out; a renamed virtual
  /// NIC can still slip through, which costs a stray endpoint row, never a
  /// wrong bind (the socket is `0.0.0.0` regardless).
  static final RegExp _virtualInterfaceName = RegExp(
    r'vethernet|vmware|virtualbox|vbox|hyper-?v|docker|wsl|'
    r'tap-|tun|vpn|loopback|bluetooth|teredo|isatap|npcap|wan miniport',
    caseSensitive: false,
  );

  /// The LAN endpoint ordering: RFC1918 space a LAN peer would dial
  /// before overlay/CGNAT and anything else, alphabetically within a
  /// rank. Public because it is a pure function — the settings surface
  /// and tests exercise it without needing real interfaces.
  static int compareLanAddresses(String a, String b) {
    final byRank = _lanAddressRank(a).compareTo(_lanAddressRank(b));
    return byRank != 0 ? byRank : a.compareTo(b);
  }

  /// 0 for RFC1918 space a LAN peer would dial, 1 for overlay/CGNAT and
  /// anything else — the sort key that keeps Tailscale from outranking the
  /// real LAN address.
  static int _lanAddressRank(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return 1;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return 1;
    if (a == 10 || a == 192 && b == 168) return 0;
    if (a == 172 && b >= 16 && b <= 31) return 0;
    return 1;
  }

  static bool _isVirtualInterface(String name) =>
      _virtualInterfaceName.hasMatch(name);

  /// VirtualBox's default host-only subnet. Its adapter often carries a
  /// generic localised name ("以太网 4") that the name filter cannot catch,
  /// and 192.168.56.0/24 is the one virtual range common enough to be worth
  /// a hard-coded exclusion — a real LAN on that exact /24 loses only the
  /// display row, not connectivity.
  static bool _isVirtualSubnet(String address) {
    final parts = address.split('.');
    return parts.length == 4 &&
        parts[0] == '192' &&
        parts[1] == '168' &&
        parts[2] == '56';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _actualPort = null;
    _lanAddresses = const [];
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final key = await _authorizedKey(request);
      if (key == null) {
        _writeError(request, 401, 'missing or invalid gateway key');
        return;
      }
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/models') {
        await _models(request);
      } else if (request.method == 'POST' && path == '/v1/chat/completions') {
        await _chatCompletions(request, key.name);
      } else {
        _writeError(request, 404, 'unknown endpoint: ${request.method} $path');
      }
    } on Object {
      // A handler that throws must still answer: a hung socket looks like a
      // dead gateway, and the caller cannot tell the difference. The body
      // stays generic — under LAN scope the exception text is internal
      // detail a stranger does not need.
      try {
        _writeError(request, 500, 'internal gateway error');
      } on Object {
        // Nothing left to tell the caller; the socket is the only witness.
      }
    }
  }

  /// The key matching the request's bearer credential, or null. The
  /// keyring is re-read per request so a settings edit is live immediately.
  Future<AiGatewayKey?> _authorizedKey(HttpRequest request) async {
    final auth = request.headers.value('authorization');
    if (auth == null) return null;
    // RFC 7235: the auth scheme is case-insensitive — `bearer`, `BEARER`
    // and `Bearer` are the same credential.
    final space = auth.indexOf(' ');
    if (space <= 0 || auth.substring(0, space).toLowerCase() != 'bearer') {
      return null;
    }
    final secret = auth.substring(space + 1).trim();
    if (secret.isEmpty) return null;
    for (final key in await keySource()) {
      if (_secretsEqual(key.secret, secret)) return key;
    }
    return null;
  }

  /// Constant-time secret comparison: `==` short-circuits on the first
  /// differing byte, which leaks prefix length to a LAN observer timing
  /// responses. XOR-accumulate over the longer input so neither length
  /// nor content shows in the timing.
  static bool _secretsEqual(String a, String b) {
    final ab = utf8.encode(a);
    final bb = utf8.encode(b);
    var diff = ab.length ^ bb.length;
    final n = ab.length > bb.length ? ab.length : bb.length;
    for (var i = 0; i < n; i++) {
      diff |= (i < ab.length ? ab[i] : 0) ^ (i < bb.length ? bb[i] : 0);
    }
    return diff == 0;
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

  Future<void> _chatCompletions(HttpRequest request, String keyName) async {
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
    final messages = [
      for (final entry in rawMessages)
        if (entry is Map) _canonicalMessage(entry.cast<String, Object?>()),
    ];
    if (messages.isEmpty) {
      _writeError(request, 400, '"messages" contains no usable entries');
      return;
    }
    // Upstream is always asked for a stream, even when the caller wants a
    // whole response: the stream is the only shape that carries a
    // time-to-first-token and per-chunk usage, which the request log
    // records. `_fullReply` folds the stream back into one completion, so
    // the caller sees exactly what it asked for.
    final chatRequest = AiChatRequest(
      model: model,
      stream: true,
      temperature: _number(body['temperature']),
      maxTokens: _int(body['max_tokens']),
      topP: _number(body['top_p']),
      stop: _stringList(body['stop']),
      messages: messages,
    );

    final AiReply reply;
    try {
      reply = await router.chat(chatRequest, clientKey: keyName);
    } on AiRequestException catch (error) {
      _writeError(request, 502, _errorDetail(error));
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
      try {
        reply = AiFullReply(
          servedBy: reply.servedBy,
          response: await _collect(reply.events),
        );
      } on AiRequestException catch (error) {
        _writeError(request, 502, _errorDetail(error));
        return;
      }
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

    // One id and timestamp for the whole response: OpenAI clients match
    // chunks to a completion by id, and a fresh one per event would make
    // every delta look like a different answer.
    final completionId = 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var toolCallIndex = 0;
    var sawToolCall = false;
    var finished = false;
    try {
      await for (final event in events) {
        switch (event.kind) {
          case AiStreamKind.textDelta:
            _writeSse(
              response,
              _chunkJson(servedBy, completionId, created, {
                'content': event.text,
              }),
            );
          case AiStreamKind.reasoningDelta:
            // Reasoning is forwarded under the DeepSeek/OpenRouter delta
            // field; clients that do not know it ignore the key.
            _writeSse(
              response,
              _chunkJson(servedBy, completionId, created, {
                'reasoning_content': event.text,
              }),
            );
          case AiStreamKind.toolCall:
            sawToolCall = true;
            _writeSse(
              response,
              _chunkJson(servedBy, completionId, created, {
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
            _writeSse(
              response,
              _usageChunkJson(servedBy, completionId, created, event.usage!),
            );
          case AiStreamKind.done:
            break;
          case AiStreamKind.error:
            _writeSse(response, {
              'error': {'message': event.text ?? 'stream error'},
            });
        }
        await response.flush();
      }
      finished = true;
    } on Object {
      // The status line is already gone; the only honest signal left is an
      // error frame before DONE — generic, same as the 500 path: the raw
      // exception is internal detail, not something a LAN peer should read.
      try {
        _writeSse(response, {
          'error': {'message': 'stream interrupted'},
        });
      } on Object {
        // The peer is gone; there is nowhere left to report it.
      }
    }
    if (finished) {
      // OpenAI streams close with an empty-delta chunk carrying the finish
      // reason — clients wait for it before treating the answer as complete.
      _writeSse(
        response,
        _chunkJson(
          servedBy,
          completionId,
          created,
          const {},
          finishReason: sawToolCall ? 'tool_calls' : 'stop',
        ),
      );
    }
    try {
      response.write('data: [DONE]\n\n');
      await response.close();
    } on Object {
      // Client hung up mid-stream; nothing to do but let the socket die.
    }
  }

  /// The message a client sees for a failed route: the provider-facing
  /// text only. The socket-level cause (upstream host, errno, timeout
  /// detail) stays home — under LAN scope a stranger dialing the gateway
  /// does not get to read this machine's network internals.
  static String _errorDetail(AiRequestException error) => error.message;

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
        case AiStreamKind.reasoningDelta:
          // Reasoning never joins a folded response's content.
          break;
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
    final now = DateTime.now().millisecondsSinceEpoch;
    final completionId = 'chatcmpl-$now';
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
      'id': completionId,
      'object': 'chat.completion',
      'created': now ~/ 1000,
      'model': full.servedBy,
      'choices': [
        {
          'index': 0,
          'message': message,
          'finish_reason': response.toolCalls.isEmpty ? 'stop' : 'tool_calls',
        },
      ],
      'usage': {
        if (response.usage.promptTokens != null)
          'prompt_tokens': response.usage.promptTokens,
        if (response.usage.completionTokens != null)
          'completion_tokens': response.usage.completionTokens,
        if (response.usage.totalTokens != null)
          'total_tokens': response.usage.totalTokens,
        if (response.usage.cachedTokens != null)
          'prompt_tokens_details': {
            'cached_tokens': response.usage.cachedTokens,
          },
      },
    };
  }

  Map<String, Object?> _chunkJson(
    String servedBy,
    String completionId,
    int created,
    Map<String, Object?> delta, {
    String? finishReason,
  }) => {
    'id': completionId,
    'object': 'chat.completion.chunk',
    'created': created,
    'model': servedBy,
    'choices': [
      {'index': 0, 'delta': delta, 'finish_reason': finishReason},
    ],
  };

  Map<String, Object?> _usageChunkJson(
    String servedBy,
    String completionId,
    int created,
    AiUsage usage,
  ) => {
    'id': completionId,
    'object': 'chat.completion.chunk',
    'created': created,
    'model': servedBy,
    'choices': const [],
    'usage': {
      if (usage.promptTokens != null) 'prompt_tokens': usage.promptTokens,
      if (usage.completionTokens != null)
        'completion_tokens': usage.completionTokens,
      if (usage.totalTokens != null) 'total_tokens': usage.totalTokens,
      if (usage.cachedTokens != null)
        'prompt_tokens_details': {'cached_tokens': usage.cachedTokens},
    },
  };

  void _writeSse(HttpResponse response, Object? payload) {
    response.write('data: ${jsonEncode(payload)}\n\n');
  }

  /// Maps one OpenAI-shaped inbound message to canonical form. Content may
  /// be a plain string or the parts array newer clients send; tool calls
  /// and tool results pass through by their wire names.
  AiMessage _canonicalMessage(Map<String, Object?> json) {
    // 'developer' is OpenAI's newer name for the system role; both mean
    // "instructions ahead of the conversation" to every codec.
    final roleName = json['role'] as String? ?? 'user';
    final role = switch (roleName) {
      'developer' => AiRole.system,
      _ => AiRole.values.asNameMap()[roleName] ?? AiRole.user,
    };
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
  /// Once over the limit the rest is drained up to one more budget's
  /// worth: answering 413 while unread request bytes are still in flight
  /// resets the socket, and the client never sees the status. Past the
  /// drain budget the peer is abusive — the connection is allowed to
  /// reset instead of being read forever.
  Future<String?> _readBody(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    var tooLarge = false;
    var discarded = 0;
    await for (final chunk in request) {
      if (tooLarge) {
        discarded += chunk.length;
        if (discarded > maxRequestBytes) return null;
        continue;
      }
      builder.add(chunk);
      if (builder.length > maxRequestBytes) {
        tooLarge = true;
        builder.clear();
      }
    }
    if (tooLarge) return null;
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }

  void _writeJson(HttpRequest request, int status, Object? body) {
    try {
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      unawaited(request.response.close().catchError((Object _) {}));
    } on Object {
      // The peer is gone before the answer could be written; the socket
      // dies on its own and there is nobody left to tell.
    }
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

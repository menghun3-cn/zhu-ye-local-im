import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ai_message.dart';
import 'provider.dart';
import 'provider_store.dart';
import 'protocol/codec.dart';
import 'protocol/openai_chat.dart';
import 'protocol/openai_responses.dart';
import 'protocol/anthropic.dart';
import 'protocol/gemini.dart';

/// The codec registry: one stateless instance per protocol.
AiCodec codecFor(AiProtocol protocol) => switch (protocol) {
  AiProtocol.openaiChat => const OpenAiChatCodec(),
  AiProtocol.openaiResponses => const OpenAiResponsesCodec(),
  AiProtocol.anthropic => const AnthropicCodec(),
  AiProtocol.gemini => const GeminiCodec(),
};

/// Sends a prepared request and returns the raw response.
///
/// An interface so tests can answer from fixtures; [IoAiTransport] is the
/// dart:io implementation the app uses.
abstract interface class AiTransport {
  Future<AiHttpResponse> send(AiRequestSpec request);
}

/// [AiTransport] over `dart:io`'s [HttpClient].
///
/// Plain HTTP, no proxy handling and no certificate overrides — provider
/// endpoints are public HTTPS APIs and "trust everything" is not a feature.
final class IoAiTransport implements AiTransport {
  IoAiTransport({
    this.connectTimeout = const Duration(seconds: 30),
    this.totalTimeout = const Duration(minutes: 5),
  });

  final Duration connectTimeout;
  final Duration totalTimeout;

  @override
  Future<AiHttpResponse> send(AiRequestSpec request) async {
    final client = HttpClient()
      ..connectionTimeout = connectTimeout
      ..autoUncompress = true;
    try {
      final uri = Uri.parse(request.url);
      final ioRequest = await client.openUrl(request.method, uri);
      request.headers.forEach(ioRequest.headers.set);
      final body = request.body;
      if (body != null) ioRequest.write(body);
      final response = await ioRequest.close().timeout(totalTimeout);
      return AiHttpResponse(
        statusCode: response.statusCode,
        // The response stream stays open for the caller; closing the client
        // now would kill it, so the client is closed when the body ends.
        bodyBytes: response.transform(
          StreamTransformer.fromHandlers(
            handleDone: (sink) {
              sink.close();
              client.close(force: false);
            },
          ),
        ),
      );
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }
}

/// A request the router refused to fail over on, or every member failed.
final class AiRequestException implements Exception {
  const AiRequestException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() =>
      'AiRequestException: $message'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}'
      '${cause == null ? '' : ': $cause'}';
}

/// The answer to [AiRouter.chat]: either a stream of events or one whole
/// reply, plus which member actually served it — surfaced so the UI can show
/// "answered by fallback" when failover happened.
sealed class AiReply {
  const AiReply({required this.servedBy});

  /// The concrete `provider/model` that produced this reply.
  final String servedBy;
}

/// A non-streamed reply.
final class AiFullReply extends AiReply {
  const AiFullReply({required super.servedBy, required this.response});

  final AiChatResponse response;
}

/// A streamed reply; events arrive until [AiStreamKind.done] or the stream
/// fails. Once events start flowing no further failover is possible — a
/// half-written answer is worse than an honest error.
final class AiStreamReply extends AiReply {
  const AiStreamReply({required super.servedBy, required this.events});

  final Stream<AiStreamEvent> events;
}

/// Resolves `provider/model` and `group/<id>` references to concrete upstream
/// calls, failing over across a routing group's members on retryable errors.
///
/// The router reads [AiConfigStore] on every call rather than caching, so a
/// settings-page edit takes effect on the very next request without a reload
/// handshake. Cooldowns live in memory only: a restarted app gives every
/// member a fresh chance, which is the behaviour a quota that resets daily
/// wants anyway.
final class AiRouter {
  AiRouter({
    required this.store,
    AiTransport? transport,
    this.cooldown = const Duration(minutes: 1),
  }) : _transport = transport ?? IoAiTransport();

  /// Where the configuration is read from on every [chat] call.
  final AiConfigStore store;
  final AiTransport _transport;

  /// How long a member that failed retryably sits out.
  final Duration cooldown;

  final _cooledDownUntil = <String, DateTime>{};

  /// Sends [request] and returns the reply from the first member that works.
  ///
  /// Throws [AiRequestException] when the reference is unresolvable, every
  /// member failed fatally, or every member failed retryably — the last case
  /// carries the most recent failure as its cause.
  Future<AiReply> chat(AiChatRequest request) async {
    final config = await store.load();
    final members = _expand(request.model, config);
    AiRequestException? lastRetryable;

    for (final member in members) {
      if (_isCoolingDown(member)) continue;
      try {
        return await _call(member, request, config);
      } on _RetryableFailure catch (failure) {
        _cooledDownUntil[member] = DateTime.now().add(cooldown);
        lastRetryable = failure.error;
      }
    }

    throw lastRetryable ??
        AiRequestException(
          'no member of "$request.model" could serve the request',
        );
  }

  /// Every model reference callers may ask for: enabled provider models plus
  /// routing groups — what `GET /v1/models` on the gateway lists.
  Future<List<String>> exposedModelRefs() async {
    final config = await store.load();
    return config.exposedModelRefs();
  }

  /// Fetches the model list a provider reports for [protocol].
  ///
  /// Returns an empty list when the provider has no endpoint or the codec
  /// has no listing for that protocol — "this provider cannot say" is an
  /// answer the settings UI renders, not an exception.
  Future<List<String>> listModels(
    String providerId,
    AiProtocol protocol,
  ) async {
    final config = await store.load();
    final provider = config.providerNamed(providerId);
    if (provider == null) return const [];
    return fetchModels(provider, protocol);
  }

  /// [listModels] for a provider object the caller already holds — the
  /// settings editor fetches against unsaved endpoint edits, which the
  /// persisted document does not know about yet.
  Future<List<String>> fetchModels(
    AiProvider provider,
    AiProtocol protocol,
  ) async {
    final baseUrl = provider.endpointFor(protocol);
    if (baseUrl == null) return const [];
    final codec = codecFor(protocol);
    final spec = codec.modelsSpec(baseUrl: baseUrl, apiKey: provider.apiKey);
    if (spec == null) return const [];
    final response = await _transport.send(spec);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }
    final body = await _readBody(response.bodyBytes);
    return codec.decodeModels(body);
  }

  /// Expands [ref] into concrete `provider/model` members, depth-first.
  ///
  /// Group cycles are cut rather than reported: a group that contains itself
  /// would otherwise recurse forever, and the honest reading of "try these
  /// members" is "try each once".
  List<String> _expand(String ref, AiConfig config) {
    final parsed = AiModelRef.parse(ref);
    if (parsed == null) {
      throw AiRequestException('"$ref" is not a provider/model reference');
    }
    if (!parsed.isGroup) return [parsed.raw];
    return _expandGroup(parsed.groupId!, config, <String>{});
  }

  List<String> _expandGroup(String groupId, AiConfig config, Set<String> seen) {
    if (!seen.add(groupId)) return const [];
    final group = config.groupNamed(groupId);
    if (group == null) {
      throw AiRequestException('unknown routing group "group/$groupId"');
    }
    final members = <String>[];
    for (final member in group.members) {
      final parsed = AiModelRef.parse(member);
      if (parsed == null) continue;
      if (parsed.isGroup) {
        members.addAll(_expandGroup(parsed.groupId!, config, seen));
      } else {
        members.add(parsed.raw);
      }
    }
    return members;
  }

  bool _isCoolingDown(String member) {
    final until = _cooledDownUntil[member];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _cooledDownUntil.remove(member);
      return false;
    }
    return true;
  }

  Future<AiReply> _call(
    String member,
    AiChatRequest request,
    AiConfig config,
  ) async {
    final parsed = AiModelRef.parse(member)!;
    final provider = config.providerNamed(parsed.providerId!);
    if (provider == null || !provider.enabled) {
      throw AiRequestException('unknown provider "${parsed.providerId}"');
    }
    final model = provider.modelNamed(parsed.modelId!);
    if (model == null || !model.enabled) {
      throw AiRequestException(
        '"${parsed.modelId}" is not an enabled model of ${provider.id}',
      );
    }
    final baseUrl = provider.endpointFor(model.protocol);
    if (baseUrl == null) {
      throw AiRequestException(
        '${provider.id} has no ${model.protocol.name} endpoint',
      );
    }

    final codec = codecFor(model.protocol);
    final spec = codec.encodeChat(
      request,
      baseUrl: baseUrl,
      model: parsed.modelId!,
      apiKey: provider.apiKey.isEmpty ? null : provider.apiKey,
    );
    final AiHttpResponse response;
    try {
      response = await _transport.send(spec);
    } catch (error) {
      // A socket that never opened is the purest transient failure there is.
      throw _RetryableFailure(
        AiRequestException('could not reach ${provider.id}', cause: error),
      );
    }

    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) {
      final snippet = await _readSnippet(response.bodyBytes);
      final kind = codec.classifyError(response.statusCode, snippet);
      final error = AiRequestException(
        '${provider.id} answered HTTP ${response.statusCode}',
        statusCode: response.statusCode,
        cause: snippet.isEmpty ? null : snippet,
      );
      if (kind == AiErrorKind.retryable) throw _RetryableFailure(error);
      throw error;
    }

    if (request.stream) {
      return AiStreamReply(
        servedBy: member,
        events: codec.decodeStream(response.bodyBytes),
      );
    }
    final body = await _readBody(response.bodyBytes);
    return AiFullReply(servedBy: member, response: codec.decodeResponse(body));
  }

  /// Reads a whole response body as text. [utf8.decoder] buffers partial
  /// multi-byte sequences across chunk boundaries, which a per-chunk decode
  /// would mangle.
  Future<String> _readBody(Stream<List<int>> bytes) async {
    final buffer = StringBuffer();
    await for (final chunk in bytes.transform(utf8.decoder)) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  /// Enough of an error body to recognise provider-specific quota errors,
  /// without buffering an arbitrarily large failure page.
  Future<String> _readSnippet(
    Stream<List<int>> bytes, {
    int limit = 8192,
  }) async {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in bytes) {
      buffer.add(chunk);
      if (buffer.length >= limit) break;
    }
    return utf8.decode(buffer.takeBytes(), allowMalformed: true);
  }
}

/// Internal signal: this member failed in a way the next member might survive.
final class _RetryableFailure implements Exception {
  const _RetryableFailure(this.error);

  final AiRequestException error;
}

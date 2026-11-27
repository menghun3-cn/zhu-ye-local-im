import '../ai_message.dart';

/// The four wire protocols a provider can speak.
///
/// Order matters only for stable serialization; [AiProviderModel.protocol]
/// records which one a given model uses.
enum AiProtocol {
  /// OpenAI Chat Completions (`/chat/completions`).
  openaiChat,

  /// OpenAI Responses (`/responses`) — the newer stateful API Codex uses.
  openaiResponses,

  /// Anthropic Messages (`/v1/messages`).
  anthropic,

  /// Google Gemini (`/v1beta/models/{model}:generateContent`).
  gemini,
}

/// How a request should be classified when it fails.
///
/// The router fails over on [quota] and [transient] only. [fatal] means the
/// request itself was wrong — a bad key, an unknown model, a malformed body —
/// and trying the next member would fail the same way while hiding the real
/// error from the user.
enum AiErrorKind {
  /// Retryable: rate limit, quota exhausted, 5xx, timeouts, network errors.
  retryable,

  /// Not retryable: the request or credentials are wrong.
  fatal,
}

/// A prepared outbound HTTP request, before any transport sees it.
///
/// Codecs produce these so the router can stay transport-agnostic: tests feed
/// canned responses through a fake transport and never open a socket.
final class AiRequestSpec {
  const AiRequestSpec({
    required this.method,
    required this.url,
    required this.headers,
    this.body,
    this.proxy,
  });

  final String method;
  final String url;
  final Map<String, String> headers;

  /// The JSON body, already encoded. Null for GET.
  final String? body;

  /// The provider's configured HTTP proxy, copied on by the router — the
  /// codec builds the wire shape and knows nothing about routing policy.
  /// Null means the transport connects directly.
  final String? proxy;
}

/// What came back on the wire, reduced to what codecs need.
///
/// [bodyBytes] is single-subscription: whoever reads it — the codec for a
/// stream, or the router collecting it for a plain response — owns it.
final class AiHttpResponse {
  const AiHttpResponse({required this.statusCode, required this.bodyBytes});

  final int statusCode;
  final Stream<List<int>> bodyBytes;
}

/// One protocol's translation between [AiChatRequest] and the wire.
///
/// A codec knows its own URL paths, headers and body shapes; it does not know
/// where the base URL or key came from — those arrive per call so the same
/// codec serves every provider configured for that protocol.
abstract interface class AiCodec {
  /// Which protocol this codec speaks.
  AiProtocol get protocol;

  /// Builds the HTTP request for [request] against [baseUrl].
  ///
  /// [model] is the concrete provider model id (the part after `/` in a
  /// `provider/model` reference), not the whole reference.
  AiRequestSpec encodeChat(
    AiChatRequest request, {
    required String baseUrl,
    required String model,
    String? apiKey,
  });

  /// Decodes a non-streamed response body into canonical form.
  AiChatResponse decodeResponse(String body);

  /// Decodes a `text/event-stream` body into canonical events.
  Stream<AiStreamEvent> decodeStream(Stream<List<int>> bodyBytes);

  /// Classifies a failed response. [bodySnippet] is a bounded prefix of the
  /// body — enough to recognise provider-specific quota errors.
  AiErrorKind classifyError(int statusCode, String bodySnippet);

  /// Builds the request that lists the model ids this provider offers, or
  /// null when the protocol has no listing endpoint the codec knows.
  AiRequestSpec? modelsSpec({required String baseUrl, String? apiKey}) => null;

  /// Decodes a model-listing response body into model ids.
  ///
  /// Only called when [modelsSpec] returned a spec; the default answers
  /// empty so a codec that forgot to override both fails loudly at the
  /// call site rather than silently listing nothing.
  List<String> decodeModels(String body) => const <String>[];

  /// Decodes a model-listing response body into [AiCatalogModel]s, keeping
  /// whatever metadata the endpoint volunteers (context window, pricing,
  /// display name). The default wraps [decodeModels], so a codec that only
  /// knows ids still produces a usable catalogue.
  List<AiCatalogModel> decodeModelCatalog(String body) => [
    for (final id in decodeModels(body)) AiCatalogModel(id: id),
  ];
}

/// One entry of a provider's model catalogue as the listing endpoint
/// reported it.
///
/// Every field past [id] is optional because listing endpoints differ
/// wildly: OpenAI returns bare ids, OpenRouter adds `context_length` and
/// `pricing`, Zen adds `limit.context` and `cost`, Gemini adds token
/// limits. A null means "the endpoint did not say", never "zero".
final class AiCatalogModel {
  const AiCatalogModel({
    required this.id,
    this.contextTokens,
    this.isFree,
    this.label,
  });

  /// The model id as the provider knows it.
  final String id;

  /// Total context window in tokens, when the endpoint reports one.
  final int? contextTokens;

  /// Whether the endpoint reports the model as free. Null means the
  /// endpoint said nothing about pricing — unknown, not paid.
  final bool? isFree;

  /// Human-friendly name when it differs from [id].
  final String? label;
}

/// The vendor-neutral shape every AI protocol codec converts to and from.
///
/// The app never speaks OpenAI, Anthropic or Gemini wire format directly:
/// callers build an [AiChatRequest] in this canonical form and a codec turns
/// it into whichever protocol the chosen provider speaks. Keeping one shape
/// is what makes "any provider for any feature" possible without a
/// provider-by-feature matrix — the same trick magpie's gateway plays, minus
/// the gateway.
library;

/// Who said a message.
enum AiRole { system, user, assistant, tool }

/// A function call an assistant asked for, with its arguments still in the
/// raw JSON text the provider produced.
///
/// The arguments stay a string rather than a parsed map because the four
/// protocols disagree on escaping and ordering just enough that round-tripping
/// through `Map<String, Object?>` would not survive a codec boundary intact.
/// Codecs that can pass tool calls through do so verbatim; ones that cannot
/// yet map them lose them, which the caller sees as a reply with no calls.
final class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// The provider-issued call id, echoed back on the tool result.
  final String id;

  /// The function name.
  final String name;

  /// The raw JSON argument object, exactly as a JSON string.
  final String arguments;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'arguments': arguments,
  };

  factory AiToolCall.fromJson(Map<String, Object?> json) => AiToolCall(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    arguments: json['arguments'] as String? ?? '{}',
  );
}

/// A function definition offered to the model — the canonical form of an
/// entry in a chat request's `tools` array.
///
/// [parameters] is the JSON Schema object kept decoded: codecs re-encode it
/// into whichever schema dialect their protocol speaks (OpenAI passes it
/// through verbatim, Anthropic calls it `input_schema`, Gemini wraps it as
/// `parametersJsonSchema`). Null means "the caller declared no schema" —
/// codecs substitute their protocol's empty-object schema rather than
/// dropping the tool.
final class AiToolDefinition {
  const AiToolDefinition({
    required this.name,
    this.description,
    this.parameters,
  });

  final String name;
  final String? description;
  final Map<String, Object?>? parameters;
}

/// How the model may use the offered tools.
enum AiToolChoiceKind {
  /// The model decides whether and which tools to call.
  auto,

  /// The model must not call tools.
  none,

  /// The model must call at least one tool.
  required,

  /// The model must call exactly the named function.
  named,
}

/// The canonical form of a request's `tool_choice`.
final class AiToolChoice {
  const AiToolChoice._(this.kind, this.name);

  const AiToolChoice.auto() : this._(AiToolChoiceKind.auto, null);
  const AiToolChoice.none() : this._(AiToolChoiceKind.none, null);
  const AiToolChoice.required() : this._(AiToolChoiceKind.required, null);
  const AiToolChoice.named(String name) : this._(AiToolChoiceKind.named, name);

  final AiToolChoiceKind kind;

  /// The forced function name; only meaningful for [AiToolChoiceKind.named].
  final String? name;
}

/// One turn of a conversation, in canonical form.
final class AiMessage {
  const AiMessage({
    required this.role,
    this.content = '',
    this.toolCalls = const <AiToolCall>[],
    this.toolCallId,
    this.name,
  });

  final AiRole role;

  /// The text of the turn. Empty when [toolCalls] carries the payload.
  final String content;

  /// Calls the assistant asked for; only meaningful on [AiRole.assistant].
  final List<AiToolCall> toolCalls;

  /// Which call this result answers; only meaningful on [AiRole.tool].
  final String? toolCallId;

  /// The function name a [AiRole.tool] result belongs to.
  final String? name;

  Map<String, Object?> toJson() => {
    'role': role.name,
    'content': content,
    if (toolCalls.isNotEmpty)
      'tool_calls': [for (final call in toolCalls) call.toJson()],
    if (toolCallId != null) 'tool_call_id': toolCallId,
    if (name != null) 'name': name,
  };

  factory AiMessage.fromJson(Map<String, Object?> json) {
    final rawCalls = json['tool_calls'];
    return AiMessage(
      role: AiRole.values.asNameMap()[json['role']] ?? AiRole.user,
      content: json['content'] as String? ?? '',
      toolCalls: [
        if (rawCalls is List)
          for (final entry in rawCalls)
            if (entry is Map)
              AiToolCall.fromJson(entry.cast<String, Object?>()),
      ],
      toolCallId: json['tool_call_id'] as String?,
      name: json['name'] as String?,
    );
  }
}

/// Token accounting, as much of it as the provider reported.
final class AiUsage {
  const AiUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.cachedTokens,
    this.cacheWriteTokens,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  /// Prompt tokens the provider served from its cache — a subset of
  /// [promptTokens], reported under a different name by each protocol
  /// (OpenAI's `prompt_tokens_details.cached_tokens`, Anthropic's
  /// `cache_read_input_tokens`, Gemini's `cachedContentTokenCount`).
  final int? cachedTokens;

  /// Prompt tokens the provider *wrote into* its cache — Anthropic's
  /// `cache_creation_input_tokens`. Only Anthropic reports this; the rest
  /// leave it null and callers show 0.
  final int? cacheWriteTokens;

  static const AiUsage empty = AiUsage();

  Map<String, Object?> toJson() => {
    if (promptTokens != null) 'prompt_tokens': promptTokens,
    if (completionTokens != null) 'completion_tokens': completionTokens,
    if (totalTokens != null) 'total_tokens': totalTokens,
    if (cachedTokens != null) 'cached_tokens': cachedTokens,
    if (cacheWriteTokens != null) 'cache_write_tokens': cacheWriteTokens,
  };

  factory AiUsage.fromJson(Map<String, Object?> json) => AiUsage(
    promptTokens: json['prompt_tokens'] as int?,
    completionTokens: json['completion_tokens'] as int?,
    totalTokens: json['total_tokens'] as int?,
    cachedTokens: json['cached_tokens'] as int?,
    cacheWriteTokens: json['cache_write_tokens'] as int?,
  );
}

/// Everything a caller needs to ask for a completion.
///
/// [model] is a model reference as the router understands it —
/// `provider/model` for one model or `group/<id>` for a routing group. The
/// router resolves it; codecs only ever see the concrete provider model id.
final class AiChatRequest {
  const AiChatRequest({
    required this.model,
    required this.messages,
    this.stream = false,
    this.temperature,
    this.maxTokens,
    this.topP,
    this.stop,
    this.tools = const <AiToolDefinition>[],
    this.toolChoice,
  });

  /// The model or routing-group reference, e.g. `deepseek/deepseek-chat`.
  final String model;

  final List<AiMessage> messages;

  /// Whether the reply should stream. The router honours it per codec: a
  /// codec that cannot stream answers non-streamed instead of pretending.
  final bool stream;

  final double? temperature;
  final int? maxTokens;
  final double? topP;
  final List<String>? stop;

  /// Function definitions the model may call. Empty means the request
  /// offers no tools — codecs then omit the tools field entirely rather
  /// than sending an empty array some providers reject.
  final List<AiToolDefinition> tools;

  /// How the model may pick among [tools]; null lets the provider default
  /// (equivalent to `auto` on every codec that has one).
  final AiToolChoice? toolChoice;
}

/// A finished, non-streamed reply.
final class AiChatResponse {
  const AiChatResponse({
    required this.content,
    this.toolCalls = const <AiToolCall>[],
    this.usage = AiUsage.empty,
  });

  /// The assistant's text. Empty when [toolCalls] carries the payload.
  final String content;

  final List<AiToolCall> toolCalls;
  final AiUsage usage;
}

/// What kind of thing a stream event carries.
enum AiStreamKind {
  /// More assistant text arrived.
  textDelta,

  /// More reasoning/thinking text arrived. Never part of the answer's
  /// content, but it is still generated output — consumers measuring
  /// time-to-first-token count it.
  reasoningDelta,

  /// A complete tool call was assembled from the stream.
  toolCall,

  /// Token accounting arrived (usually just before the end).
  usage,

  /// The provider finished cleanly.
  done,

  /// The provider reported an error mid-stream.
  error,
}

/// One event on a streamed reply.
///
/// A flat bag rather than a sealed hierarchy because every codec produces the
/// same shapes and the consumer (a chat view, a summariser) only ever
/// switches on [kind].
final class AiStreamEvent {
  const AiStreamEvent._(this.kind, {this.text, this.toolCall, this.usage});

  final AiStreamKind kind;

  /// Text payload for [AiStreamKind.textDelta],
  /// [AiStreamKind.reasoningDelta], and [AiStreamKind.error].
  final String? text;

  /// The assembled call for [AiStreamKind.toolCall].
  final AiToolCall? toolCall;

  /// Accounting for [AiStreamKind.usage].
  final AiUsage? usage;

  factory AiStreamEvent.textDelta(String text) =>
      AiStreamEvent._(AiStreamKind.textDelta, text: text);

  factory AiStreamEvent.reasoningDelta(String text) =>
      AiStreamEvent._(AiStreamKind.reasoningDelta, text: text);

  factory AiStreamEvent.toolCall(AiToolCall call) =>
      AiStreamEvent._(AiStreamKind.toolCall, toolCall: call);

  factory AiStreamEvent.usage(AiUsage usage) =>
      AiStreamEvent._(AiStreamKind.usage, usage: usage);

  factory AiStreamEvent.done() => const AiStreamEvent._(AiStreamKind.done);

  factory AiStreamEvent.error(String message) =>
      AiStreamEvent._(AiStreamKind.error, text: message);
}

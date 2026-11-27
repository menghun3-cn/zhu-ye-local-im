import 'provider.dart';
import 'protocol/codec.dart';

/// Providers the app writes into `providers.json` on first run.
///
/// These are public endpoints with a shared credential — no signup, no key
/// management — so they ship enabled and usable out of the box. Everything
/// about them stays editable: the user can repoint the endpoint (a regional
/// host, a relay), swap the key for their own, disable the provider, or
/// delete it outright. [AiConfig.builtinsSeeded] guarantees the seed happens
/// once, so none of those choices is ever overwritten by a later launch.
///
/// The seeded model lists are deliberately small and best-effort: both
/// upstreams rotate their free catalogue, and a stale id simply errors on
/// use until the user pulls a fresh list from the editor. What must not be
/// stale is the endpoint and credential — those are verified facts.
final List<AiProvider> aiBuiltinProviders = [
  AiProvider(
    id: 'opencode-zen',
    name: 'OpenCode Zen',
    kind: AiProviderKind.builtin,
    endpoints: {
      AiProtocol.openaiChat: 'https://opencode.ai/zen/v1',
      AiProtocol.openaiResponses: 'https://opencode.ai/zen/v1',
      // Anthropic roots have no /v1 — the codec appends /v1/messages itself.
      AiProtocol.anthropic: 'https://opencode.ai/zen',
    },
    apiKey: 'public',
    models: [
      AiProviderModel(
        id: 'mimo-v2.6-flash-free',
        protocol: AiProtocol.openaiChat,
        enabled: true,
      ),
      AiProviderModel(
        id: 'deepseek-v4.1-flash-free',
        protocol: AiProtocol.openaiChat,
        enabled: true,
      ),
    ],
    enabled: true,
  ),
  AiProvider(
    id: 'kilo',
    name: 'Kilo',
    kind: AiProviderKind.builtin,
    endpoints: {AiProtocol.openaiChat: 'https://api.kilo.ai/api/openrouter/v1'},
    apiKey: 'anonymous',
    models: [
      // Virtual routers: they resolve to whatever free model is available,
      // so they survive catalogue churn better than pinned ids.
      AiProviderModel(
        id: 'kilo-auto/free',
        protocol: AiProtocol.openaiChat,
        enabled: true,
      ),
      AiProviderModel(
        id: 'openrouter/free',
        protocol: AiProtocol.openaiChat,
        enabled: true,
      ),
    ],
    enabled: true,
  ),
];

import 'provider.dart';
import 'protocol/codec.dart';

/// A vendor preset: a name, a kind and the default base URL per protocol.
///
/// Presets are starting points, not locks — every endpoint and the key stay
/// editable, because the same vendor is reachable through regional hosts and
/// third-party relays that a hard-coded URL would lock out.
final class AiProviderPreset {
  const AiProviderPreset({
    required this.id,
    required this.label,
    required this.kind,
    this.endpoints = const <AiProtocol, String>{},
  });

  /// Preset slug; becomes the provider id when the user adds it.
  final String id;

  /// Display name.
  final String label;

  final AiProviderKind kind;

  /// Default base URL per protocol the vendor speaks.
  final Map<AiProtocol, String> endpoints;
}

/// The preset catalogue, ordered roughly by how often each vendor comes up.
///
/// Endpoint facts verified against each vendor's public docs as of
/// 2026-11; where a vendor speaks several protocols the entry lists each.
const List<AiProviderPreset> aiProviderPresets = [
  AiProviderPreset(
    id: 'anthropic',
    label: 'Anthropic',
    kind: AiProviderKind.preset,
    endpoints: {AiProtocol.anthropic: 'https://api.anthropic.com'},
  ),
  AiProviderPreset(
    id: 'openai',
    label: 'OpenAI',
    kind: AiProviderKind.preset,
    endpoints: {
      AiProtocol.openaiChat: 'https://api.openai.com/v1',
      AiProtocol.openaiResponses: 'https://api.openai.com/v1',
    },
  ),
  AiProviderPreset(
    id: 'google',
    label: 'Google Gemini',
    kind: AiProviderKind.preset,
    endpoints: {AiProtocol.gemini: 'https://generativelanguage.googleapis.com'},
  ),
  AiProviderPreset(
    id: 'deepseek',
    label: 'DeepSeek',
    kind: AiProviderKind.preset,
    endpoints: {
      AiProtocol.openaiChat: 'https://api.deepseek.com/v1',
      AiProtocol.anthropic: 'https://api.deepseek.com/anthropic',
    },
  ),
  AiProviderPreset(
    id: 'kimi',
    label: 'Kimi (Moonshot)',
    kind: AiProviderKind.preset,
    endpoints: {AiProtocol.openaiChat: 'https://api.moonshot.ai/v1'},
  ),
  AiProviderPreset(
    id: 'zhipu',
    label: 'Zhipu GLM',
    kind: AiProviderKind.preset,
    endpoints: {AiProtocol.openaiChat: 'https://open.bigmodel.cn/api/paas/v4'},
  ),
  AiProviderPreset(
    id: 'minimax',
    label: 'MiniMax',
    kind: AiProviderKind.preset,
    endpoints: {AiProtocol.openaiChat: 'https://api.minimaxi.com/v1'},
  ),
  AiProviderPreset(
    id: 'qwen',
    label: 'Qwen (DashScope)',
    kind: AiProviderKind.preset,
    endpoints: {
      AiProtocol.openaiChat:
          'https://dashscope.aliyuncs.com/compatible-mode/v1',
    },
  ),
  AiProviderPreset(
    id: 'mistral',
    label: 'Mistral',
    kind: AiProviderKind.preset,
    endpoints: {AiProtocol.openaiChat: 'https://api.mistral.ai/v1'},
  ),
  AiProviderPreset(
    id: 'groq',
    label: 'Groq',
    kind: AiProviderKind.preset,
    endpoints: {AiProtocol.openaiChat: 'https://api.groq.com/openai/v1'},
  ),
  AiProviderPreset(
    id: 'xai',
    label: 'xAI',
    kind: AiProviderKind.preset,
    endpoints: {AiProtocol.openaiChat: 'https://api.x.ai/v1'},
  ),
  AiProviderPreset(
    id: 'ollama',
    label: 'Ollama',
    kind: AiProviderKind.local,
    endpoints: {AiProtocol.openaiChat: 'http://localhost:11434/v1'},
  ),
  AiProviderPreset(
    id: 'lmstudio',
    label: 'LM Studio',
    kind: AiProviderKind.local,
    endpoints: {AiProtocol.openaiChat: 'http://localhost:1234/v1'},
  ),
];

/// Finds a preset by id, or null.
AiProviderPreset? aiProviderPresetNamed(String id) {
  for (final preset in aiProviderPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

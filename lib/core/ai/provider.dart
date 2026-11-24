import 'protocol/codec.dart';

/// Where a provider's credentials and endpoints came from.
enum AiProviderKind {
  /// A built-in vendor preset whose endpoints can still be overridden.
  preset,

  /// A provider the app seeds on first run (OpenCode Zen, Kilo) — public
  /// endpoints with a shared credential, enabled out of the box.
  builtin,

  /// An arbitrary OpenAI/Anthropic/Gemini-compatible endpoint the user typed.
  custom,

  /// A model running on this machine or LAN (Ollama, LM Studio) — no key.
  local,
}

/// One model a provider offers, with the protocol it must be spoken in.
///
/// The protocol lives on the *model*, not the provider, because a custom
/// endpoint can front several upstream APIs and the same model id may exist
/// under more than one of them.
final class AiProviderModel {
  const AiProviderModel({
    required this.id,
    required this.protocol,
    this.enabled = false,
    this.label,
  });

  /// The model id as the provider knows it (`deepseek-chat`, `claude-opus-4-6`).
  final String id;

  /// Which codec speaks to this model.
  final AiProtocol protocol;

  /// Whether chats and the gateway may pick this model.
  final bool enabled;

  /// Optional display name when it differs from [id].
  final String? label;

  AiProviderModel copyWith({bool? enabled, String? label}) => AiProviderModel(
    id: id,
    protocol: protocol,
    enabled: enabled ?? this.enabled,
    label: label ?? this.label,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'protocol': protocol.name,
    'enabled': enabled,
    if (label != null) 'label': label,
  };

  factory AiProviderModel.fromJson(Map<String, Object?> json) =>
      AiProviderModel(
        id: json['id'] as String? ?? '',
        protocol:
            AiProtocol.values.asNameMap()[json['protocol']] ??
            AiProtocol.openaiChat,
        enabled: json['enabled'] as bool? ?? false,
        label: json['label'] as String?,
      );
}

/// A configured upstream: endpoints, key and known models.
final class AiProvider {
  AiProvider({
    required this.id,
    required this.name,
    required this.kind,
    this.endpoints = const <AiProtocol, String>{},
    this.apiKey = '',
    this.models = const <AiProviderModel>[],
    this.enabled = true,
  });

  /// Stable slug used in `provider/model` references. Once persisted it must
  /// not change — references in routing groups and chats point at it.
  final String id;

  /// Display name.
  final String name;

  final AiProviderKind kind;

  /// Base URL per protocol. A missing entry means that protocol is not
  /// available for this provider, whatever its models claim.
  final Map<AiProtocol, String> endpoints;

  /// The API key in plaintext — callers only ever see this in memory; the
  /// store seals it before it touches disk (see `secret_box.dart`).
  final String apiKey;

  /// The fetched catalogue plus enable flags. New fetches update the
  /// catalogue without auto-enabling, so a refresh cannot silently widen
  /// what the gateway exposes.
  final List<AiProviderModel> models;

  final bool enabled;

  /// The base URL for [protocol], or null when this provider does not speak it.
  String? endpointFor(AiProtocol protocol) {
    final url = endpoints[protocol];
    return url == null || url.isEmpty ? null : url;
  }

  /// The enabled model with [modelId], or null.
  AiProviderModel? modelNamed(String modelId) {
    for (final model in models) {
      if (model.id == modelId) return model;
    }
    return null;
  }

  AiProvider copyWith({
    String? name,
    Map<AiProtocol, String>? endpoints,
    String? apiKey,
    List<AiProviderModel>? models,
    bool? enabled,
  }) => AiProvider(
    id: id,
    name: name ?? this.name,
    kind: kind,
    endpoints: endpoints ?? this.endpoints,
    apiKey: apiKey ?? this.apiKey,
    models: models ?? this.models,
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'endpoints': {
      for (final entry in endpoints.entries) entry.key.name: entry.value,
    },
    'apiKey': apiKey,
    'models': [for (final model in models) model.toJson()],
    'enabled': enabled,
  };

  factory AiProvider.fromJson(Map<String, Object?> json) {
    final rawEndpoints = json['endpoints'];
    final endpoints = <AiProtocol, String>{};
    if (rawEndpoints is Map) {
      for (final entry in rawEndpoints.entries) {
        final protocol = AiProtocol.values.asNameMap()[entry.key];
        if (protocol != null && entry.value is String) {
          endpoints[protocol] = entry.value as String;
        }
      }
    }
    final rawModels = json['models'];
    return AiProvider(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      kind:
          AiProviderKind.values.asNameMap()[json['kind']] ??
          AiProviderKind.custom,
      endpoints: endpoints,
      apiKey: json['apiKey'] as String? ?? '',
      models: [
        if (rawModels is List)
          for (final entry in rawModels)
            if (entry is Map)
              AiProviderModel.fromJson(entry.cast<String, Object?>()),
      ],
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

/// An ordered list of model references tried in sequence.
///
/// Members are `provider/model` strings or `group/<id>` for nesting. Order is
/// the failover order: the router tries each member until one answers, and a
/// member that fails retryably sits out for its cooldown.
final class AiRoutingGroup {
  AiRoutingGroup({
    required this.id,
    required this.name,
    this.members = const [],
  });

  final String id;
  final String name;
  final List<String> members;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'members': members};

  factory AiRoutingGroup.fromJson(Map<String, Object?> json) => AiRoutingGroup(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    members: [
      if (json['members'] is List)
        for (final member in json['members'] as List)
          if (member is String) member,
    ],
  );
}

/// Which interfaces the local AI gateway listens on.
enum AiGatewayScope {
  /// `127.0.0.1` only — tools on this machine reach it, nothing else can.
  loopback,

  /// Every IPv4 interface (`0.0.0.0`) — loopback *and* each LAN address.
  /// The bearer token is the only thing between the LAN and the configured
  /// providers' keys, so this mode is opt-in, never the default.
  lan,
}

/// Whether the local AI gateway binds at startup, and where.
final class AiGatewayConfig {
  const AiGatewayConfig({
    this.enabled = true,
    this.port = 0,
    this.scope = AiGatewayScope.loopback,
  });

  /// When true the gateway listens for as long as the app runs. On by
  /// default: the endpoint is how local tools discover the configured
  /// providers, and loopback exposure is nil-risk behind the token.
  final bool enabled;

  /// Preferred port; 0 means "any free port" and the actual one is reported
  /// back through the running server, never assumed.
  final int port;

  /// Loopback-only or every interface.
  final AiGatewayScope scope;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'port': port,
    'scope': scope.name,
  };

  factory AiGatewayConfig.fromJson(Map<String, Object?>? json) =>
      AiGatewayConfig(
        enabled: json?['enabled'] as bool? ?? true,
        port: json?['port'] as int? ?? 0,
        scope: switch (json?['scope']) {
          'lan' => AiGatewayScope.lan,
          _ => AiGatewayScope.loopback,
        },
      );
}

/// Everything `providers.json` holds.
final class AiConfig {
  AiConfig({
    this.providers = const <AiProvider>[],
    this.routingGroups = const <AiRoutingGroup>[],
    this.gateway = const AiGatewayConfig(),
    this.builtinsSeeded = false,
  });

  final List<AiProvider> providers;
  final List<AiRoutingGroup> routingGroups;
  final AiGatewayConfig gateway;

  /// Whether the first-run built-in providers were already written. Seeded
  /// once and never again: a user who deletes one keeps it deleted, and a
  /// user who edits its endpoints is not overwritten by the next launch.
  final bool builtinsSeeded;

  AiProvider? providerNamed(String id) {
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  AiRoutingGroup? groupNamed(String id) {
    for (final group in routingGroups) {
      if (group.id == id) return group;
    }
    return null;
  }

  /// Every model reference the gateway may offer: enabled provider models as
  /// `provider/model`, plus every routing group as `group/<id>`.
  List<String> exposedModelRefs() => [
    for (final provider in providers)
      if (provider.enabled)
        for (final model in provider.models)
          if (model.enabled) '${provider.id}/${model.id}',
    for (final group in routingGroups) 'group/${group.id}',
  ];

  AiConfig copyWith({
    List<AiProvider>? providers,
    List<AiRoutingGroup>? routingGroups,
    AiGatewayConfig? gateway,
    bool? builtinsSeeded,
  }) => AiConfig(
    providers: providers ?? this.providers,
    routingGroups: routingGroups ?? this.routingGroups,
    gateway: gateway ?? this.gateway,
    builtinsSeeded: builtinsSeeded ?? this.builtinsSeeded,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'providers': [for (final p in providers) p.toJson()],
    'routingGroups': [for (final g in routingGroups) g.toJson()],
    'gateway': gateway.toJson(),
    'builtinsSeeded': builtinsSeeded,
  };

  factory AiConfig.fromJson(Map<String, Object?> json) {
    List<T> read<T>(Object? raw, T Function(Map<String, Object?>) parse) => [
      if (raw is List)
        for (final entry in raw)
          if (entry is Map) parse(entry.cast<String, Object?>()),
    ];
    return AiConfig(
      providers: read(json['providers'], AiProvider.fromJson),
      routingGroups: read(json['routingGroups'], AiRoutingGroup.fromJson),
      gateway: AiGatewayConfig.fromJson(
        json['gateway'] is Map
            ? (json['gateway'] as Map).cast<String, Object?>()
            : null,
      ),
      builtinsSeeded: json['builtinsSeeded'] as bool? ?? false,
    );
  }
}

/// A parsed `provider/model` or `group/<id>` reference.
final class AiModelRef {
  const AiModelRef._(this.raw, {this.providerId, this.modelId, this.groupId})
    : isGroup = groupId != null;

  /// The reference exactly as written.
  final String raw;

  /// Set for `provider/model` references.
  final String? providerId;
  final String? modelId;

  /// Set for `group/<id>` references.
  final String? groupId;

  final bool isGroup;

  /// Parses [raw]. Returns null for anything that is not
  /// `<non-empty>/<non-empty>` or `group/<non-empty>`.
  static AiModelRef? parse(String raw) {
    if (raw.startsWith('group/')) {
      final id = raw.substring(6);
      return id.isEmpty ? null : AiModelRef._(raw, groupId: id);
    }
    final slash = raw.indexOf('/');
    if (slash <= 0 || slash == raw.length - 1) return null;
    return AiModelRef._(
      raw,
      providerId: raw.substring(0, slash),
      modelId: raw.substring(slash + 1),
    );
  }

  @override
  String toString() => raw;
}

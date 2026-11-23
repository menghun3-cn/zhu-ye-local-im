import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../feedback.dart';
import '../l10n/generated/app_localizations.dart';
import '../seams.dart';
import '../top_toast.dart';
import '../wechat/theme.dart';
import '../widgets.dart';

/// The AI surface: providers, routing groups and the local gateway.
///
/// Everything on this page is a view over one [AiConfig] document plus the
/// [AiRuntime] that persists it — there is no second copy of "what is
/// configured" kept in widget state. Each edit loads the document, changes
/// it, and hands it back through [AiRuntime.save], which is also what keeps
/// the gateway's bind in step with the flag.
class AiSettingsPage extends StatefulWidget {
  /// Builds the surface over [runtime]; null on a Device with nowhere
  /// durable to keep AI configuration.
  const AiSettingsPage({super.key, required this.runtime, required this.seams});

  /// The AI stack, or null when this Device cannot persist one.
  final AiRuntime? runtime;

  /// Platform facts — only the clipboard is needed, to copy the endpoint
  /// and token a local tool asks for.
  final PlatformSeams seams;

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  AiConfig? _config;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final runtime = widget.runtime;
    if (runtime == null) return;
    try {
      final config = await runtime.load();
      if (mounted) {
        setState(() {
          _config = config;
          _failure = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  /// Persists [next] and redraws from what was actually stored — the gateway
  /// flag's effect on the bound socket is the runtime's business, and the
  /// page's only honest summary of it is "is there an endpoint".
  Future<void> _save(AiConfig next) async {
    final runtime = widget.runtime;
    if (runtime == null) return;
    await runtime.save(next);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final runtime = widget.runtime;
    if (runtime == null) {
      return ListView(
        padding: WeChat.pagePadding,
        children: [HintText(l10n.aiUnavailableHere)],
      );
    }
    final config = _config;
    if (config == null) {
      return Center(
        child: _failure == null
            ? const CircularProgressIndicator()
            : HintText('${l10n.aiLoadFailed}: $_failure'),
      );
    }
    return ListView(
      padding: WeChat.pagePadding,
      children: [
        _GatewayCard(
          config: config,
          endpoint: runtime.endpoint,
          token: runtime.token.value,
          onChanged: (gateway) => _save(config.copyWith(gateway: gateway)),
          onCopy: (text) => unawaited(_copy(text)),
        ),
        const SizedBox(height: WeChat.sectionGap),
        SectionHeader(title: l10n.aiSectionProviders),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(WeChat.cardPadding),
            child: Column(
              children: [
                for (final provider in config.providers)
                  _ProviderTile(
                    provider: provider,
                    onToggle: (enabled) => unawaited(
                      guarded(
                        context,
                        () => _save(
                          config.copyWith(
                            providers: [
                              for (final p in config.providers)
                                identical(p, provider)
                                    ? p.copyWith(enabled: enabled)
                                    : p,
                            ],
                          ),
                        ),
                      ),
                    ),
                    onEdit: () => unawaited(
                      guarded(context, () => _editProvider(provider)),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        unawaited(guarded(context, () => _addProvider(config))),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.aiAddProvider),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: WeChat.sectionGap),
        SectionHeader(title: l10n.aiSectionGroups),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(WeChat.cardPadding),
            child: Column(
              children: [
                for (final group in config.routingGroups)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.alt_route, size: 20),
                    title: Text(group.name),
                    subtitle: Text(
                      l10n.aiGroupMemberCount(group.members.length),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        unawaited(guarded(context, () => _editGroup(group))),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => unawaited(_editGroup(null)),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.aiAddGroup),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: WeChat.sectionGap),
        HintText(l10n.aiPageHint),
      ],
    );
  }

  Future<void> _copy(String text) async {
    // The overlay is taken before the await for the same reason `guarded`
    // takes it: the page may be gone by the time the write answers.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final l10n = AppLocalizations.of(context);
    await widget.seams.clipboard.write(text);
    if (overlay != null) {
      await TopToast.showIn(overlay, l10n.aiCopied);
    }
  }

  /// Lets the user pick a preset or a custom endpoint, then opens the
  /// editor on the new provider.
  Future<void> _addProvider(AiConfig config) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.aiAddProvider),
        children: [
          for (final preset in aiProviderPresets)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(preset),
              child: Text(preset.label),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('custom'),
            child: Text(l10n.aiProviderCustom),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    AiProvider provider;
    if (choice is AiProviderPreset) {
      provider = AiProvider(
        id: _uniqueProviderId(config, choice.id),
        name: choice.label,
        kind: choice.kind,
        endpoints: choice.endpoints,
      );
    } else {
      provider = AiProvider(
        id: _uniqueProviderId(config, 'custom'),
        name: l10n.aiProviderCustom,
        kind: AiProviderKind.custom,
      );
    }
    await _save(config.copyWith(providers: [...config.providers, provider]));
    if (!mounted) return;
    await _editProvider(provider);
  }

  /// A slug no existing provider already owns — references point at ids, so
  /// a collision would merge two providers into one name.
  String _uniqueProviderId(AiConfig config, String base) {
    var id = base;
    var suffix = 2;
    while (config.providerNamed(id) != null) {
      id = '$base-$suffix';
      suffix++;
    }
    return id;
  }

  /// Opens the provider editor; resolves when the dialog closes.
  Future<void> _editProvider(AiProvider provider) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ProviderEditorDialog(
        runtime: widget.runtime!,
        provider: provider,
        onSave: _saveProvider,
        onDelete: () => _deleteProvider(provider),
      ),
    );
    if (saved == true) await _reload();
  }

  /// Writes [next] over the provider with the same id — or appends it, which
  /// is the path a provider created moments ago takes.
  ///
  /// The document is re-read here rather than closed over from the tile that
  /// opened the editor: a fetch or a second edit may have landed while the
  /// dialog was up, and saving a stale copy would silently drop it.
  Future<void> _saveProvider(AiProvider next) async {
    final config = _config;
    if (config == null) return;
    final providers = [
      for (final p in config.providers) p.id == next.id ? next : p,
    ];
    if (!providers.any((p) => identical(p, next))) {
      providers.add(next);
    }
    await _save(config.copyWith(providers: providers));
  }

  /// Removes the provider and every group member that pointed at it — a
  /// dangling `provider/model` ref would fail every request it was ordered
  /// into, which is a worse answer than a quietly shorter list.
  Future<void> _deleteProvider(AiProvider provider) async {
    final config = _config;
    if (config == null) return;
    final prefix = '${provider.id}/';
    await _save(
      config.copyWith(
        providers: [
          for (final p in config.providers)
            if (p.id != provider.id) p,
        ],
        routingGroups: [
          for (final g in config.routingGroups)
            AiRoutingGroup(
              id: g.id,
              name: g.name,
              members: [
                for (final m in g.members)
                  if (!m.startsWith(prefix)) m,
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _editGroup(AiRoutingGroup? group) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _GroupEditorDialog(
        config: _config!,
        group: group,
        onSave: (next) async {
          final config = _config;
          if (config == null) return;
          final groups = group == null
              ? [...config.routingGroups, next]
              : [
                  for (final g in config.routingGroups)
                    g.id == next.id ? next : g,
                ];
          await _save(config.copyWith(routingGroups: groups));
        },
      ),
    );
    if (saved == true) await _reload();
  }
}

/// The gateway card: the switch, and — while it listens — the two values a
/// local tool needs, each one copyable.
class _GatewayCard extends StatelessWidget {
  const _GatewayCard({
    required this.config,
    required this.endpoint,
    required this.token,
    required this.onChanged,
    required this.onCopy,
  });

  final AiConfig config;
  final String? endpoint;
  final String token;
  final ValueChanged<AiGatewayConfig> onChanged;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = config.gateway.enabled;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(WeChat.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: (value) => onChanged(
                AiGatewayConfig(enabled: value, port: config.gateway.port),
              ),
              title: Text(l10n.aiGatewayTitle),
              subtitle: Text(enabled ? l10n.aiGatewayOn : l10n.aiGatewayOff),
            ),
            if (enabled) ...[
              const SizedBox(height: 8),
              _CopyableField(
                label: l10n.aiGatewayEndpoint,
                value: endpoint ?? l10n.aiGatewayNotListening,
                enabled: endpoint != null,
                onCopy: onCopy,
              ),
              const SizedBox(height: 8),
              _CopyableField(
                label: l10n.aiGatewayToken,
                value: token,
                onCopy: onCopy,
              ),
              const SizedBox(height: 8),
              HintText(
                endpoint == null
                    ? l10n.aiGatewayNotListeningHint
                    : l10n.aiGatewayHint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A read-only value with a copy button — the endpoint and token are facts
/// to hand to another program, not preferences to edit.
class _CopyableField extends StatelessWidget {
  const _CopyableField({
    required this.label,
    required this.value,
    required this.onCopy,
    this.enabled = true,
  });

  final String label;
  final String value;
  final ValueChanged<String> onCopy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: WeChat.fontSizePreview,
            color: colors.secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: value,
          readOnly: true,
          enableInteractiveSelection: true,
          style: const TextStyle(fontSize: WeChat.fontSizeInput),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: colors.surfaceSunken,
            suffixIcon: IconButton(
              tooltip: l10n.copySelection,
              onPressed: enabled ? () => onCopy(value) : null,
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WeChat.controlRadius),
              borderSide: BorderSide(color: colors.divider),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }
}

/// One provider row: name and kind on the left, enable switch and an edit
/// affordance on the right.
class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.provider,
    required this.onToggle,
    required this.onEdit,
  });

  final AiProvider provider;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabledModels = provider.models.where((m) => m.enabled).length;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.dns_outlined, size: 20),
      title: Text(provider.name),
      subtitle: Text(
        '${_kindLabel(l10n, provider.kind)} · '
        '${l10n.aiProviderModelCount(enabledModels)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(value: provider.enabled, onChanged: onToggle),
          IconButton(
            tooltip: l10n.editRemark,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
        ],
      ),
      onTap: onEdit,
    );
  }

  String _kindLabel(AppLocalizations l10n, AiProviderKind kind) =>
      switch (kind) {
        AiProviderKind.preset => l10n.aiKindPreset,
        AiProviderKind.custom => l10n.aiKindCustom,
        AiProviderKind.local => l10n.aiKindLocal,
      };
}

/// The provider editor: identity, key, one base-URL row per protocol, and
/// the model catalogue with per-model enable switches and a fetch button.
class _ProviderEditorDialog extends StatefulWidget {
  const _ProviderEditorDialog({
    required this.runtime,
    required this.provider,
    required this.onSave,
    required this.onDelete,
  });

  final AiRuntime runtime;
  final AiProvider provider;
  final Future<void> Function(AiProvider next) onSave;
  final Future<void> Function() onDelete;

  @override
  State<_ProviderEditorDialog> createState() => _ProviderEditorDialogState();
}

class _ProviderEditorDialogState extends State<_ProviderEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _apiKey;
  late final Map<AiProtocol, TextEditingController> _endpoints;
  late AiProvider _draft;
  bool _busy = false;
  String? _fetchNote;

  @override
  void initState() {
    super.initState();
    _draft = widget.provider;
    _name = TextEditingController(text: widget.provider.name);
    _apiKey = TextEditingController(text: widget.provider.apiKey);
    _endpoints = {
      for (final protocol in AiProtocol.values)
        protocol: TextEditingController(
          text: widget.provider.endpoints[protocol] ?? '',
        ),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _apiKey.dispose();
    for (final controller in _endpoints.values) {
      controller.dispose();
    }
    super.dispose();
  }

  AiProvider _collect() => AiProvider(
    id: _draft.id,
    name: _name.text.trim().isEmpty ? _draft.name : _name.text.trim(),
    kind: _draft.kind,
    endpoints: {
      for (final entry in _endpoints.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim(),
    },
    apiKey: _apiKey.text.trim(),
    models: _draft.models,
    enabled: _draft.enabled,
  );

  Future<void> _persist() async {
    setState(() => _busy = true);
    try {
      await widget.onSave(_collect());
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Merges the ids a provider reports into the catalogue. Existing entries
  /// keep their enable flag — a refresh must not silently widen what the
  /// gateway exposes, the same rule the store documents.
  Future<void> _fetchModels(AiProtocol protocol) async {
    setState(() {
      _busy = true;
      _fetchNote = null;
    });
    try {
      // Fetch against the *draft's* endpoints, not the persisted ones: the
      // user may have just corrected a URL and expects the fetch to use it.
      final ids = await widget.runtime.router.fetchModels(_collect(), protocol);
      if (!mounted) return;
      final existing = {
        for (final m in _draft.models) '${m.protocol.name}/${m.id}': m,
      };
      final merged = <AiProviderModel>[
        for (final model in _draft.models) model,
      ];
      for (final id in ids) {
        final key = '${protocol.name}/$id';
        if (existing.containsKey(key)) continue;
        merged.add(AiProviderModel(id: id, protocol: protocol));
      }
      setState(() {
        _draft = _draft.copyWith(models: merged);
        _fetchNote = ids.isEmpty
            ? AppLocalizations.of(context).aiFetchEmpty
            : AppLocalizations.of(context).aiFetchAdded(ids.length);
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _fetchNote = '$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return AlertDialog(
      title: Text(l10n.aiEditProvider),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: l10n.aiProviderName),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKey,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.aiProviderApiKey,
                  helperText: l10n.aiProviderApiKeyHint,
                ),
              ),
              const SizedBox(height: 12),
              for (final protocol in AiProtocol.values) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _protocolLabel(l10n, protocol),
                        style: TextStyle(
                          fontSize: WeChat.fontSizePreview,
                          color: colors.secondaryText,
                        ),
                      ),
                    ),
                    if (_endpoints[protocol]!.text.trim().isNotEmpty)
                      IconButton(
                        tooltip: l10n.aiFetchModels,
                        onPressed: _busy
                            ? null
                            : () => unawaited(_fetchModels(protocol)),
                        icon: const Icon(
                          Icons.cloud_download_outlined,
                          size: 18,
                        ),
                      ),
                  ],
                ),
                TextField(
                  controller: _endpoints[protocol],
                  decoration: InputDecoration(
                    hintText: l10n.aiEndpointHint,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_fetchNote != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: HintText(_fetchNote!),
                ),
              if (_draft.models.isNotEmpty) ...[
                Text(
                  l10n.aiProviderModels,
                  style: TextStyle(
                    fontSize: WeChat.fontSizePreview,
                    color: colors.secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
                for (final model in _draft.models)
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: model.enabled,
                    onChanged: (value) => setState(() {
                      _draft = _draft.copyWith(
                        models: [
                          for (final m in _draft.models)
                            identical(m, model)
                                ? m.copyWith(enabled: value)
                                : m,
                        ],
                      );
                    }),
                    title: Text(model.label ?? model.id),
                    subtitle: Text(
                      '${model.id} · ${_protocolLabel(l10n, model.protocol)}',
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => unawaited(
                          guarded(context, () async {
                            await widget.onDelete();
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          }),
                        ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(l10n.deleteMessage),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_persist()),
          child: Text(l10n.save),
        ),
      ],
    );
  }

  String _protocolLabel(AppLocalizations l10n, AiProtocol protocol) =>
      switch (protocol) {
        AiProtocol.openaiChat => l10n.aiProtocolOpenaiChat,
        AiProtocol.openaiResponses => l10n.aiProtocolOpenaiResponses,
        AiProtocol.anthropic => l10n.aiProtocolAnthropic,
        AiProtocol.gemini => l10n.aiProtocolGemini,
      };
}

/// The routing-group editor: a name, and an ordered member list — order *is*
/// the failover order, so members can be moved up and down, not just added
/// and removed.
class _GroupEditorDialog extends StatefulWidget {
  const _GroupEditorDialog({
    required this.config,
    required this.group,
    required this.onSave,
  });

  final AiConfig config;
  final AiRoutingGroup? group;
  final Future<void> Function(AiRoutingGroup next) onSave;

  @override
  State<_GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends State<_GroupEditorDialog> {
  late final TextEditingController _name;
  late List<String> _members;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.group?.name ?? '');
    _members = [...?widget.group?.members];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// References a member may point at: every exposed model plus other
  /// groups — never this group itself, whose members are already on screen.
  List<String> get _choices {
    final self = widget.group == null ? null : 'group/${widget.group!.id}';
    return [
      for (final ref in widget.config.exposedModelRefs())
        if (ref != self && !_members.contains(ref)) ref,
    ];
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _members.length) return;
    setState(() {
      final member = _members.removeAt(index);
      _members.insert(target, member);
    });
  }

  Future<void> _persist() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final group = widget.group;
    try {
      await widget.onSave(
        AiRoutingGroup(
          id: group?.id ?? _uniqueGroupId(),
          name: name,
          members: _members,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _uniqueGroupId() {
    var n = 1;
    while (widget.config.groupNamed('group-$n') != null) {
      n++;
    }
    return 'group-$n';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    final choices = _choices;
    return AlertDialog(
      title: Text(l10n.aiEditGroup),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: l10n.aiGroupName),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.aiGroupMembers,
                style: TextStyle(
                  fontSize: WeChat.fontSizePreview,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 4),
              if (_members.isEmpty) HintText(l10n.aiGroupEmpty),
              for (var i = 0; i < _members.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.subdirectory_arrow_right, size: 18),
                  title: Text(_members[i]),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l10n.aiMoveUp,
                        onPressed: i == 0 ? null : () => _move(i, -1),
                        icon: const Icon(Icons.arrow_upward, size: 16),
                      ),
                      IconButton(
                        tooltip: l10n.aiMoveDown,
                        onPressed: i == _members.length - 1
                            ? null
                            : () => _move(i, 1),
                        icon: const Icon(Icons.arrow_downward, size: 16),
                      ),
                      IconButton(
                        tooltip: l10n.removeAttachment,
                        onPressed: () => setState(() => _members.removeAt(i)),
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                ),
              if (choices.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: null,
                  decoration: InputDecoration(
                    labelText: l10n.aiAddMember,
                    isDense: true,
                  ),
                  items: [
                    for (final ref in choices)
                      DropdownMenuItem(value: ref, child: Text(ref)),
                  ],
                  onChanged: (ref) {
                    if (ref == null) return;
                    setState(() => _members.add(ref));
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_persist()),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

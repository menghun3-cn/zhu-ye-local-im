import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/core.dart';
import '../feedback.dart';
import '../l10n/generated/app_localizations.dart';
import '../seams.dart';
import '../top_toast.dart';
import '../wechat/theme.dart';
import '../widgets.dart';
import 'ai_routing_page.dart';

/// The AI surface: routing, providers, the local gateway and routing groups.
///
/// Everything on this page is a view over one [AiConfig] document plus the
/// [AiRuntime] that persists it — there is no second copy of "what is
/// configured" kept in widget state. Each edit loads the document, changes
/// it, and hands it back through [AiRuntime.save], which is also what keeps
/// the gateway's bind in step with the flag.
///
/// The four tabs answer the four questions in the order they are asked:
/// "what is being routed right now" first, then "who can serve it", "where
/// do callers dial", and "which members fail over to which".
class AiPage extends StatefulWidget {
  /// Builds the surface over [runtime].
  const AiPage({
    super.key,
    required this.runtime,
    required this.seams,
    this.configLoader,
  });

  /// The AI stack this page edits.
  final AiRuntime runtime;

  /// Platform facts — only the clipboard is needed, to copy the endpoint
  /// and token a local tool asks for.
  final PlatformSeams seams;

  /// Where the configuration comes from; defaults to [AiRuntime.load].
  /// Injectable so a widget test can answer from memory instead of real
  /// file IO, which the fake-async test clock cannot advance.
  final Future<AiConfig> Function()? configLoader;

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  AiConfig? _config;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final config = await (widget.configLoader ?? widget.runtime.load)();
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
    await widget.runtime.save(next);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = _config;
    if (config == null) {
      return Center(
        child: _failure == null
            ? const CircularProgressIndicator()
            : HintText('${l10n.aiLoadFailed}: $_failure'),
      );
    }
    // Routing first: "what is being asked right now" is the question the
    // other three tabs configure the answer to, and it is also the only tab
    // with something live to show — a fresh install lands on an idle canvas
    // rather than an empty form.
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: l10n.aiRoutingTitle),
                Tab(text: l10n.aiSectionProviders),
                Tab(text: l10n.aiNavGateway),
                Tab(text: l10n.aiSectionGroups),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                // Full height, no card: the canvas wants every pixel it can
                // get, and the status line sits on its bottom edge.
                _routingPane(),
                _providersPane(l10n, config),
                _gatewayPane(l10n, config),
                _groupsPane(l10n, config),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The routing pane is just the view — it owns its own status line and
  /// needs no scrolling chrome of its own.
  Widget _routingPane() =>
      AiRoutingView(runtime: widget.runtime, configLoader: widget.configLoader);

  Widget _providersPane(AppLocalizations l10n, AiConfig config) {
    return ListView(
      padding: WeChat.pagePadding,
      children: [
        SectionHeader(
          title: l10n.aiSectionProviders,
          trailing: TextButton.icon(
            onPressed: () =>
                unawaited(guarded(context, () => _addProvider(config))),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.aiAddProvider),
          ),
        ),
        // One card per provider: rows inside a shared card bleed into each
        // other, and a provider is a thing you act on as a unit — enable,
        // edit, delete — so it gets its own boundary.
        for (final provider in config.providers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: _ProviderTile(
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
                onEdit: () =>
                    unawaited(guarded(context, () => _editProvider(provider))),
              ),
            ),
          ),
        const SizedBox(height: WeChat.sectionGap),
        HintText(l10n.aiPageHint),
      ],
    );
  }

  Widget _gatewayPane(AppLocalizations l10n, AiConfig config) {
    return ListView(
      padding: WeChat.pagePadding,
      children: [
        SectionHeader(title: l10n.aiGatewayTitle),
        const SizedBox(height: WeChat.sectionGap),
        _GatewayCard(
          config: config,
          gateway: widget.runtime.gateway,
          runtime: widget.runtime,
          onChanged: (gateway) => _save(config.copyWith(gateway: gateway)),
          onCopy: (text) => unawaited(_copy(text)),
        ),
      ],
    );
  }

  Widget _groupsPane(AppLocalizations l10n, AiConfig config) {
    return ListView(
      padding: WeChat.pagePadding,
      children: [
        SectionHeader(
          title: l10n.aiSectionGroups,
          trailing: TextButton.icon(
            onPressed: () => unawaited(_editGroup(null)),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.aiAddGroup),
          ),
        ),
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
              ],
            ),
          ),
        ),
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
              child: _PresetOption(preset: preset),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('custom'),
            child: Row(
              children: [
                const _OptionIcon(icon: Icons.tune),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(context).aiProviderCustom),
              ],
            ),
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
    // The draft is *not* saved here: persisting on selection meant a user
    // who picked a preset and then cancelled still owned a provider they
    // never confirmed. `_saveProvider` appends on save, so the editor can
    // open on a provider the document does not contain yet.
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
    // Delete only makes sense for a provider the document already holds —
    // a fresh draft has nothing to remove, and offering the button would
    // write a no-op save.
    final persisted =
        _config?.providers.any((p) => p.id == provider.id) ?? false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ProviderEditorDialog(
        runtime: widget.runtime,
        provider: provider,
        onSave: _saveProvider,
        onDelete: persisted ? () => _deleteProvider(provider) : null,
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
        onDelete: group == null ? null : () => _deleteGroup(group),
      ),
    );
    if (saved == true) await _reload();
  }

  /// Removes a routing group. Members pointing at it are left alone — a
  /// `group/<id>` reference inside another group simply stops resolving,
  /// which the router already reports as an honest error rather than a
  /// crash.
  Future<void> _deleteGroup(AiRoutingGroup group) async {
    final config = _config;
    if (config == null) return;
    await _save(
      config.copyWith(
        routingGroups: [
          for (final g in config.routingGroups)
            if (g.id != group.id) g,
        ],
      ),
    );
  }
}

/// The gateway card: the switch, and — while it listens — the two values a
/// local tool needs, each one copyable.
class _GatewayCard extends StatelessWidget {
  const _GatewayCard({
    required this.config,
    required this.gateway,
    required this.runtime,
    required this.onChanged,
    required this.onCopy,
  });

  final AiConfig config;

  /// The bound server, or null while the flag is off or the bind failed —
  /// the card shows "configured but not listening" from that alone.
  final AiGateway? gateway;
  final AiRuntime runtime;
  final ValueChanged<AiGatewayConfig> onChanged;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gatewayConfig = config.gateway;
    final enabled = gatewayConfig.enabled;
    final endpoint = gateway?.endpoint;
    final port = gateway?.actualPort;
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
                AiGatewayConfig(
                  enabled: value,
                  port: gatewayConfig.port,
                  scope: gatewayConfig.scope,
                ),
              ),
              title: Text(l10n.aiGatewayTitle),
              subtitle: Text(enabled ? l10n.aiGatewayOn : l10n.aiGatewayOff),
            ),
            if (enabled) ...[
              const SizedBox(height: 8),
              Text(
                l10n.aiGatewayScope,
                style: TextStyle(
                  fontSize: WeChat.fontSizePreview,
                  color: WeChatColors.of(context).secondaryText,
                ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<AiGatewayScope>(
                segments: [
                  ButtonSegment(
                    value: AiGatewayScope.loopback,
                    label: Text(l10n.aiGatewayScopeLoopback),
                  ),
                  ButtonSegment(
                    value: AiGatewayScope.lan,
                    label: Text(l10n.aiGatewayScopeLan),
                  ),
                ],
                selected: {gatewayConfig.scope},
                onSelectionChanged: (selection) => onChanged(
                  AiGatewayConfig(
                    enabled: enabled,
                    port: gatewayConfig.port,
                    scope: selection.first,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _CopyableField(
                label: l10n.aiGatewayEndpoint,
                value: endpoint ?? l10n.aiGatewayNotListening,
                enabled: endpoint != null,
                onCopy: onCopy,
              ),
              // Under LAN scope the same port answers on every interface;
              // loopback alone would hide the addresses peers actually use.
              if (gatewayConfig.scope == AiGatewayScope.lan && port != null)
                for (final address in gateway?.lanAddresses ?? const [])
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _CopyableField(
                      label: l10n.aiGatewayLanEndpoint,
                      value: 'http://$address:$port/v1',
                      onCopy: onCopy,
                    ),
                  ),
              const SizedBox(height: 8),
              _GatewayKeysSection(runtime: runtime, onCopy: onCopy),
              const SizedBox(height: 8),
              HintText(
                endpoint == null
                    ? l10n.aiGatewayNotListeningHint
                    : gatewayConfig.scope == AiGatewayScope.lan
                    ? l10n.aiGatewayLanHint
                    : l10n.aiGatewayHint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The gateway keyring: one row per client key — name, masked secret with
/// an eye toggle, copy and delete — plus the request count and token spend
/// the request log attributes to it. "Add gateway key" opens an inline row
/// rather than a dialog: two fields and two buttons are cheaper as a row
/// than as a modal.
class _GatewayKeysSection extends StatefulWidget {
  const _GatewayKeysSection({required this.runtime, required this.onCopy});

  final AiRuntime runtime;
  final ValueChanged<String> onCopy;

  @override
  State<_GatewayKeysSection> createState() => _GatewayKeysSectionState();
}

class _GatewayKeysSectionState extends State<_GatewayKeysSection> {
  List<AiGatewayKey> _keys = const [];
  final Map<String, int> _requests = {};
  final Map<String, int> _tokens = {};
  bool _adding = false;
  final _name = TextEditingController();
  final _secret = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _name.dispose();
    _secret.dispose();
    super.dispose();
  }

  /// Keys and per-key usage come from two files; both are tiny, so this is
  /// two reads, not a query.
  Future<void> _reload() async {
    final keys = await widget.runtime.keys.load();
    final records = await widget.runtime.requestLog.load();
    final requests = <String, int>{};
    final tokens = <String, int>{};
    for (final record in records) {
      // Rows written before keys existed belong to the migrated default.
      final name = record.key ?? 'default';
      requests[name] = (requests[name] ?? 0) + 1;
      tokens[name] = (tokens[name] ?? 0) + (record.totalTokens ?? 0);
    }
    if (mounted) {
      setState(() {
        _keys = keys;
        _requests
          ..clear()
          ..addAll(requests);
        _tokens
          ..clear()
          ..addAll(tokens);
      });
    }
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) return;
    var secret = _secret.text.trim();
    if (secret.isEmpty) secret = AiGatewayKeyStore.generateSecret();
    if (_keys.any((k) => k.name == name || k.secret == secret)) {
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay != null) {
        unawaited(TopToast.showIn(overlay, l10n.aiGatewayKeyDuplicate));
      }
      return;
    }
    await widget.runtime.keys.save([
      ..._keys,
      AiGatewayKey(name: name, secret: secret, createdAt: DateTime.now()),
    ]);
    _name.clear();
    _secret.clear();
    setState(() => _adding = false);
    await _reload();
  }

  /// The last key cannot go — a gateway with no credential refuses every
  /// caller, which is a locked door with no key under the mat.
  Future<void> _remove(AiGatewayKey key) async {
    if (_keys.length <= 1) return;
    await widget.runtime.keys.save([
      for (final k in _keys)
        if (k.name != key.name || k.secret != key.secret) k,
    ]);
    await _reload();
  }

  String _usageText(String name) {
    final l10n = AppLocalizations.of(context);
    final requests = _requests[name] ?? 0;
    final tokens = _tokens[name] ?? 0;
    return l10n.aiGatewayKeyUsage(
      requests,
      tokens >= 1000 ? '${(tokens / 1000).toStringAsFixed(1)}k' : '$tokens',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.aiGatewayKeys,
          style: TextStyle(
            fontSize: WeChat.fontSizePreview,
            color: colors.secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        for (final key in _keys)
          _GatewayKeyTile(
            name: key.name,
            secret: key.secret,
            usage: _usageText(key.name),
            canDelete: _keys.length > 1,
            onCopy: widget.onCopy,
            onDelete: () => unawaited(_remove(key)),
          ),
        if (_adding)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    hintText: l10n.aiGatewayKeyNameHint,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _secret,
                  decoration: InputDecoration(
                    hintText: l10n.aiGatewayKeySecretHint,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _adding = false),
                      child: Text(l10n.aiGatewayKeyCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => unawaited(_create()),
                      child: Text(l10n.aiGatewayKeyCreate),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          TextButton.icon(
            onPressed: () => setState(() => _adding = true),
            icon: const Icon(Icons.add, size: 18),
            label: Text(l10n.aiGatewayKeyAdd),
          ),
      ],
    );
  }
}

/// One key row: name and usage on the left, masked secret with an eye
/// toggle, copy and delete on the right.
class _GatewayKeyTile extends StatefulWidget {
  const _GatewayKeyTile({
    required this.name,
    required this.secret,
    required this.usage,
    required this.canDelete,
    required this.onCopy,
    required this.onDelete,
  });

  final String name;
  final String secret;
  final String usage;
  final bool canDelete;
  final ValueChanged<String> onCopy;
  final VoidCallback onDelete;

  @override
  State<_GatewayKeyTile> createState() => _GatewayKeyTileState();
}

class _GatewayKeyTileState extends State<_GatewayKeyTile> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: WeChat.fontSizePreview,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _revealed ? widget.secret : '•' * 16,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: colors.secondaryText),
                ),
                Text(
                  widget.usage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: colors.secondaryText),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _revealed
                ? l10n.aiGatewayKeyHide
                : l10n.aiGatewayKeyReveal,
            onPressed: () => setState(() => _revealed = !_revealed),
            icon: Icon(
              _revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
            ),
          ),
          IconButton(
            tooltip: l10n.copySelection,
            onPressed: () => widget.onCopy(widget.secret),
            icon: const Icon(Icons.copy_outlined, size: 18),
          ),
          IconButton(
            tooltip: l10n.deleteMessage,
            onPressed: widget.canDelete ? widget.onDelete : null,
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    );
  }
}

/// A read-only value with a copy button — the endpoints are facts to hand
/// to another program, not preferences to edit.
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
    final colors = WeChatColors.of(context);
    final enabledModels = provider.models.where((m) => m.enabled).length;
    // A disabled provider fades rather than disappearing: the row still
    // explains itself, it just stops competing for attention.
    return Opacity(
      opacity: provider.enabled ? 1 : 0.55,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.brandSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.dns_outlined, size: 20, color: colors.brand),
        ),
        title: Text(
          provider.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
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
      ),
    );
  }

  String _kindLabel(AppLocalizations l10n, AiProviderKind kind) =>
      switch (kind) {
        AiProviderKind.preset => l10n.aiKindPreset,
        AiProviderKind.builtin => l10n.aiKindBuiltin,
        AiProviderKind.custom => l10n.aiKindCustom,
        AiProviderKind.local => l10n.aiKindLocal,
      };
}

/// One row of the add-provider dialog: the vendor's bundled brand mark
/// ahead of its label.
class _PresetOption extends StatelessWidget {
  const _PresetOption({required this.preset});

  final AiProviderPreset preset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _OptionIcon(asset: preset.iconAsset),
        const SizedBox(width: 12),
        Text(preset.label),
      ],
    );
  }
}

/// The leading mark of a picker row: a bundled brand SVG when the preset
/// ships one, tinted to the theme's icon color, or a Material glyph for
/// entries without a mark (the custom endpoint).
class _OptionIcon extends StatelessWidget {
  const _OptionIcon({this.asset, this.icon});

  final String? asset;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    final asset = this.asset;
    if (asset != null) {
      return SvgPicture.asset(
        asset,
        width: 22,
        height: 22,
        colorFilter: ColorFilter.mode(colors.secondaryText, BlendMode.srcIn),
      );
    }
    return Icon(
      icon ?? Icons.dns_outlined,
      size: 22,
      color: colors.secondaryText,
    );
  }
}

/// The provider editor: identity, key, one base-URL row per protocol, and
/// the model catalogue with per-model enable switches and a fetch button.
class _ProviderEditorDialog extends StatefulWidget {
  const _ProviderEditorDialog({
    required this.runtime,
    required this.provider,
    required this.onSave,
    this.onDelete,
  });

  final AiRuntime runtime;
  final AiProvider provider;
  final Future<void> Function(AiProvider next) onSave;

  /// Null while the provider is still an unsaved draft — there is nothing
  /// persisted to delete.
  final Future<void> Function()? onDelete;

  @override
  State<_ProviderEditorDialog> createState() => _ProviderEditorDialogState();
}

class _ProviderEditorDialogState extends State<_ProviderEditorDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _name;
  late final TextEditingController _apiKey;
  late final Map<AiProtocol, TextEditingController> _endpoints;
  late final TabController _tab;
  late AiProvider _draft;
  bool _busy = false;
  int _shownIndex = 0;

  @override
  void initState() {
    super.initState();
    _draft = widget.provider;
    // A draft opens unnamed — its provider.name is only the preset's
    // suggestion, shown as the field's hint until the user types one.
    _name = TextEditingController(
      text: widget.onDelete == null ? '' : widget.provider.name,
    );
    _apiKey = TextEditingController(text: widget.provider.apiKey);
    _endpoints = {
      for (final protocol in AiProtocol.values)
        protocol: TextEditingController(
          text: widget.provider.endpoints[protocol] ?? '',
        ),
    };
    // The shared fetch/test buttons act on whichever tab is showing, so the
    // build has to hear about tab switches — not just field edits.
    _tab = TabController(length: AiProtocol.values.length, vsync: this)
      ..addListener(() {
        if (mounted && _tab.index != _shownIndex) {
          setState(() => _shownIndex = _tab.index);
        }
      });
  }

  @override
  void dispose() {
    _name.dispose();
    _apiKey.dispose();
    _tab.dispose();
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
    // Same overlay capture as [_copy]: the dialog may be gone by the time a
    // failed save reports back, and the toast still has to land somewhere.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    setState(() => _busy = true);
    try {
      await widget.onSave(_collect());
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      // A failed save must say so — silently re-enabling the button would
      // read as "saved" to a user who never saw the error.
      if (mounted) {
        setState(() => _busy = false);
        if (overlay != null) {
          unawaited(TopToast.showIn(overlay, '$error'));
        }
      }
    }
  }

  /// Delete is destructive — the provider's key and every group member
  /// pointing at it go with it — so it asks first, the same courtesy
  /// deleting a conversation gets.
  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.aiDeleteProviderTitle),
        content: Text(l10n.aiDeleteProviderBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteMessage),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await guarded(context, () async {
      await onDelete();
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  /// Feedback goes to a [TopToast], not an inline note: a note appearing or
  /// disappearing inside the dialog resizes it mid-gesture, which reads as
  /// the window jittering.
  Future<void> _fetchModels() async {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    setState(() => _busy = true);
    try {
      // Fetch against the *draft's* endpoints, not the persisted ones: the
      // user may have just corrected a URL and expects the fetch to use it.
      final protocol = AiProtocol.values[_shownIndex];
      final catalog = await widget.runtime.router.fetchModelCatalog(
        _collect(),
        protocol,
      );
      if (!mounted) return;
      // Built-in providers are free-tier by definition: an endpoint that
      // confirms a model is paid never reaches the draft. Unknown pricing
      // stays — Zen's Anthropic-shaped listing carries none.
      final entries = _draft.kind == AiProviderKind.builtin
          ? [
              for (final m in catalog)
                if (m.isFree != false) m,
            ]
          : catalog;
      final merged = [for (final m in _draft.models) m];
      final byKey = {
        for (var i = 0; i < merged.length; i++)
          '${merged[i].protocol.name}/${merged[i].id}': i,
      };
      var added = 0;
      for (final entry in entries) {
        final key = '${protocol.name}/${entry.id}';
        final at = byKey[key];
        if (at != null) {
          // A refetch refreshes the catalogue metadata but never the
          // user's enable choice.
          final current = merged[at];
          merged[at] = AiProviderModel(
            id: current.id,
            protocol: current.protocol,
            enabled: current.enabled,
            label: entry.label ?? current.label,
            contextTokens: entry.contextTokens ?? current.contextTokens,
            isFree: entry.isFree ?? current.isFree,
          );
          continue;
        }
        merged.add(
          AiProviderModel(
            id: entry.id,
            protocol: protocol,
            label: entry.label,
            contextTokens: entry.contextTokens,
            isFree: entry.isFree,
          ),
        );
        added++;
      }
      setState(() => _draft = _draft.copyWith(models: merged));
      final l10n = AppLocalizations.of(context);
      if (overlay != null) {
        unawaited(
          TopToast.showIn(
            overlay,
            entries.isEmpty
                ? (catalog.isEmpty ? l10n.aiFetchEmpty : l10n.aiFetchNoFree)
                : l10n.aiFetchAdded(added),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted && overlay != null) {
        unawaited(TopToast.showIn(overlay, '$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Same probe as [_fetchModels] but reports instead of merging: the point
  /// is "does this URL + key + protocol answer", not the catalogue.
  Future<void> _testConnection() async {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    setState(() => _busy = true);
    try {
      final ids = await widget.runtime.router.fetchModels(
        _collect(),
        AiProtocol.values[_shownIndex],
      );
      if (!mounted) return;
      if (overlay != null) {
        unawaited(
          TopToast.showIn(
            overlay,
            AppLocalizations.of(context).aiConnectionOk(ids.length),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted && overlay != null) {
        unawaited(TopToast.showIn(overlay, '$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One protocol's tab content: just its base-URL field. The fetch/test
  /// actions live once below the tab bar and act on the visible tab.
  Widget _endpointField(AppLocalizations l10n, AiProtocol protocol) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: _endpoints[protocol],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: l10n.aiEndpointHint,
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return AlertDialog(
      title: Text(l10n.aiEditProvider),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.aiProviderName,
                  // A draft starts unnamed: the preset's label is a
                  // suggestion, not an answer — the user names it.
                  hintText: widget.onDelete == null
                      ? widget.provider.name
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              // One protocol per tab: four stacked URL rows read as a form
              // to fill completely, when in practice a provider usually
              // speaks one. Each tab keeps its own field, so filling a
              // second protocol later costs nothing.
              TabBar(
                controller: _tab,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final protocol in AiProtocol.values)
                    Tab(text: _protocolLabel(l10n, protocol)),
                ],
              ),
              SizedBox(
                height: 76,
                child: TabBarView(
                  controller: _tab,
                  children: [
                    for (final protocol in AiProtocol.values)
                      _endpointField(l10n, protocol),
                  ],
                ),
              ),
              // A local model (Ollama, LM Studio) has no credential, so the
              // key field would only invite a paste that goes nowhere.
              if (_draft.kind != AiProviderKind.local) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKey,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.aiProviderApiKey,
                    helperText: l10n.aiProviderApiKeyHint,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // One pair of actions for the whole tab strip: they probe the
              // protocol whose tab is showing, so repeating them per tab
              // would only duplicate identical buttons.
              Builder(
                builder: (context) {
                  final active = AiProtocol.values[_shownIndex];
                  final hasUrl = _endpoints[active]!.text.trim().isNotEmpty;
                  return Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _busy || !hasUrl
                            ? null
                            : () => unawaited(_fetchModels()),
                        icon: const Icon(
                          Icons.cloud_download_outlined,
                          size: 18,
                        ),
                        label: Text(l10n.aiFetchModels),
                      ),
                      TextButton.icon(
                        onPressed: _busy || !hasUrl
                            ? null
                            : () => unawaited(_testConnection()),
                        icon: const Icon(Icons.wifi_tethering, size: 18),
                        label: Text(l10n.aiTestConnection),
                      ),
                    ],
                  );
                },
              ),
              if (_draft.models.isNotEmpty) ...[
                Text(
                  l10n.aiProviderModels,
                  style: TextStyle(
                    fontSize: WeChat.fontSizePreview,
                    color: colors.secondaryText,
                  ),
                ),
                const SizedBox(height: 8),
                // Capsules, not rows: a catalogue can run to hundreds of
                // models, and a wrap lets the eye scan names and badges
                // instead of scrolling a switch column.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final model in _draft.models)
                      _ModelCapsule(
                        model: model,
                        protocolLabel: _protocolLabel(l10n, model.protocol),
                        onTap: () => setState(() {
                          _draft = _draft.copyWith(
                            models: [
                              for (final m in _draft.models)
                                identical(m, model)
                                    ? m.copyWith(enabled: !m.enabled)
                                    : m,
                            ],
                          );
                        }),
                      ),
                  ],
                ),
              ],
              if (widget.onDelete != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => unawaited(_confirmDelete()),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(l10n.deleteMessage),
                  ),
                ),
              ],
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
          onPressed: _busy || _name.text.trim().isEmpty
              ? null
              : () => unawaited(_persist()),
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

/// One model as a capsule: name plus whatever badges the catalogue knew —
/// a green 免费 tag and the context window. Tapping toggles [enabled]; the
/// capsule *is* the switch, so selected state is drawn, not toggled.
class _ModelCapsule extends StatelessWidget {
  const _ModelCapsule({
    required this.model,
    required this.protocolLabel,
    required this.onTap,
  });

  final AiProviderModel model;
  final String protocolLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    final selected = model.enabled;
    final ink = selected ? colors.brand : colors.bubbleText;
    return Tooltip(
      message: '${model.id} · $protocolLabel',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? colors.brand : colors.divider,
              width: selected ? 1.5 : 1,
            ),
            color: selected ? colors.brandSoft : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 14, color: colors.brand),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  model.label ?? model.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: ink,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (model.isFree == true) ...[
                const SizedBox(width: 6),
                _ModelTag(
                  text: l10n.aiModelFree,
                  color: const Color(0xFF1E9E50),
                  background: colors.brandSoft,
                ),
              ],
              if (model.contextTokens != null) ...[
                const SizedBox(width: 6),
                _ModelTag(
                  text: _formatContext(model.contextTokens!),
                  color: colors.secondaryText,
                  background: colors.surfaceSunken,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// `1000000` → `1.0M`, `256000` → `256K`, small values stay raw — the
  /// tag is a scan aid, not an exact figure.
  static String _formatContext(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    }
    if (tokens >= 1000) return '${(tokens / 1000).round()}K';
    return '$tokens';
  }
}

/// The little badge inside a [_ModelCapsule]: tinted text on a tinted
/// plate, small enough to read as metadata rather than content.
class _ModelTag extends StatelessWidget {
  const _ModelTag({
    required this.text,
    required this.color,
    required this.background,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color, height: 1.4),
      ),
    );
  }
}

/// The routing-group editor: a name, and an ordered member list — order *is*
/// the failover order, so members can be moved up and down, not just added
/// and removed.
class _GroupEditorDialog extends StatefulWidget {
  const _GroupEditorDialog({
    required this.config,
    required this.group,
    required this.onSave,
    this.onDelete,
  });

  final AiConfig config;
  final AiRoutingGroup? group;
  final Future<void> Function(AiRoutingGroup next) onSave;

  /// Removes the group outright; null while creating a new one.
  final Future<void> Function()? onDelete;

  @override
  State<_GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends State<_GroupEditorDialog> {
  late final TextEditingController _name;
  late List<String> _members;
  bool _busy = false;
  String? _note;

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
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _note = '$error';
        });
      }
    }
  }

  /// Same courtesy as the provider delete: groups vanish from `/v1/models`
  /// the moment they are gone, so the button asks first.
  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.aiDeleteGroupTitle),
        content: Text(l10n.aiDeleteGroupBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteMessage),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await guarded(context, () async {
      await onDelete();
      if (mounted) Navigator.of(context).pop(true);
    });
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
              if (_note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: HintText(_note!),
                ),
              if (widget.onDelete != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => unawaited(_confirmDelete()),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(l10n.deleteMessage),
                  ),
                ),
              ],
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

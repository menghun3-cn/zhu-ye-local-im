import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../l10n/generated/app_localizations.dart';
import '../wechat/theme.dart';
import '../widgets.dart';

/// Troubleshooting page for network diagnostics and common solutions.
///
/// Every diagnostic reports a real answer: the port check reads the ports the
/// controller actually bound, the interface checks enumerate the machine's
/// adapters, and the firewall check asks Windows Firewall through PowerShell —
/// with the "open the ports" button behind it on Windows, where adding a rule
/// needs the UAC consent the button exists to collect.
class TroubleshootingPage extends StatefulWidget {
  const TroubleshootingPage({super.key});

  @override
  State<TroubleshootingPage> createState() => _TroubleshootingPageState();
}

class _TroubleshootingPageState extends State<TroubleshootingPage> {
  LocalTransferController? _controller;

  /// Null while the interface enumeration is still running.
  List<NetworkInterface>? _interfaces;
  List<String>? _tunnelNames;
  FirewallReport? _firewall;

  bool _openingFirewall = false;
  bool _checking = false;
  FirewallOpenResult? _firewallNotice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = ControllerScope.of(context);
    unawaited(_runChecks());
  }

  Future<void> _runChecks() async {
    // The probe can take a moment — the firewall query enumerates every
    // inbound allow rule — so the button that started it has to say so,
    // or a re-check reads as a dead click.
    if (mounted) setState(() => _checking = true);
    try {
      final platform = _controller!.self.platform;
      final interfaces = await usableInterfaces();
      final tunnels = await suspectedTunnelInterfaces();
      final firewall = await probeFirewall(
        platform: platform,
        programPath: Platform.resolvedExecutable,
      );
      if (!mounted) return;
      setState(() {
        _interfaces = interfaces;
        _tunnelNames = tunnels;
        _firewall = firewall;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openFirewall() async {
    final platform = _controller!.self.platform;
    setState(() {
      _openingFirewall = true;
      _firewallNotice = null;
    });
    final result = await openFirewallPorts(
      platform: platform,
      programPath: Platform.resolvedExecutable,
    );
    // Whether the rules went in or not, what is on the page has to be asked
    // again: a success means the probe should now read "open", and a cancel
    // means nothing changed but the status line still deserves a refresh.
    await _runChecks();
    if (!mounted) return;
    setState(() {
      _openingFirewall = false;
      _firewallNotice = result == FirewallOpenResult.unsupported
          ? null
          : result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller ?? ControllerScope.of(context);

    return ListView(
      padding: WeChat.pagePadding,
      children: [
        SectionHeader(title: l10n.troubleshootingTitle),
        _buildDiagnosticsSection(context, l10n, controller),
        const SizedBox(height: WeChat.sectionGap),
        _buildSolutionsSection(context, l10n),
      ],
    );
  }

  Widget _buildDiagnosticsSection(
    BuildContext context,
    AppLocalizations l10n,
    LocalTransferController controller,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(WeChat.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.troubleshootingDiagnostics,
                    style: TextStyle(
                      fontSize: WeChat.fontSizePreview,
                      fontWeight: FontWeight.w600,
                      color: WeChatColors.of(context).bubbleText,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _checking ? null : _runChecks,
                  child: _checking
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 6),
                            Text(l10n.troubleshootingChecking),
                          ],
                        )
                      : Text(l10n.troubleshootingRecheck),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _DiagnosticItem(
              icon: Icons.wifi,
              title: l10n.troubleshootingNetworkCheck,
              description: l10n.troubleshootingNetworkCheckDesc,
              level: _networkLevel(l10n),
              detail: _networkDetail(l10n),
            ),
            const SizedBox(height: 8),
            _DiagnosticItem(
              icon: Icons.security,
              title: l10n.troubleshootingFirewallCheck,
              description: l10n.troubleshootingFirewallCheckDesc,
              level: _firewallLevel(),
              detail: _firewallDetail(l10n),
            ),
            const SizedBox(height: 8),
            _DiagnosticItem(
              icon: Icons.portable_wifi_off,
              title: l10n.troubleshootingPortCheck,
              description: l10n.troubleshootingPortCheckDesc,
              level: _portLevel(),
              detail: _portDetail(l10n, controller),
              trailing: controller.self.platform == DevicePlatform.windows
                  ? _buildFirewallActions(context, l10n)
                  : null,
            ),
            const SizedBox(height: 8),
            _DiagnosticItem(
              icon: Icons.vpn_lock,
              title: l10n.troubleshootingVpnCheck,
              description: l10n.troubleshootingVpnCheckDesc,
              level: _vpnLevel(),
              detail: _vpnDetail(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFirewallActions(BuildContext context, AppLocalizations l10n) {
    final colors = WeChatColors.of(context);
    // The button exists for one situation: the probe found inbound ports with
    // no covering allow rule. While the ports are open — or the question could
    // not be answered — there is nothing for it to do, so it stays greyed out
    // rather than offering an action that would change nothing.
    final blocked = _firewall?.state == FirewallState.blocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Tooltip(
          message: blocked ? '' : l10n.troubleshootingFirewallNotNeeded,
          child: FilledButton.tonalIcon(
            onPressed: _openingFirewall || !blocked ? null : _openFirewall,
            // The theme pins the filled style to the brand colour for *every*
            // state, so a disabled button would still look pressable. Only the
            // disabled colours are overridden here; enabled keeps the theme.
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? colors.surfaceSunken
                    : null,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? colors.disabledText
                    : null,
              ),
            ),
            icon: const Icon(Icons.lock_open, size: 18),
            label: Text(
              _openingFirewall
                  ? l10n.troubleshootingOpeningFirewall
                  : l10n.troubleshootingOpenFirewallPorts,
            ),
          ),
        ),
        if (_firewallNotice != null) ...[
          const SizedBox(height: 6),
          Text(
            switch (_firewallNotice!) {
              FirewallOpenResult.opened => l10n.troubleshootingFirewallOpened,
              FirewallOpenResult.cancelled =>
                l10n.troubleshootingFirewallCancelled,
              _ => l10n.troubleshootingFirewallFailed,
            },
            style: TextStyle(
              fontSize: WeChat.fontSizeMeta,
              color: _firewallNotice == FirewallOpenResult.failed
                  ? colors.danger
                  : colors.secondaryText,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSolutionsSection(BuildContext context, AppLocalizations l10n) {
    final colors = WeChatColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(WeChat.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.troubleshootingSolutions,
              style: TextStyle(
                fontSize: WeChat.fontSizePreview,
                fontWeight: FontWeight.w600,
                color: colors.bubbleText,
              ),
            ),
            const SizedBox(height: 12),
            _SolutionItem(
              icon: Icons.edit_location_alt,
              title: l10n.troubleshootingManualIp,
              description: l10n.troubleshootingManualIpDesc,
            ),
            const SizedBox(height: 8),
            _SolutionItem(
              icon: Icons.security,
              title: l10n.troubleshootingFirewall,
              description: l10n.troubleshootingFirewallDesc,
            ),
            const SizedBox(height: 8),
            _SolutionItem(
              icon: Icons.restart_alt,
              title: l10n.troubleshootingRestart,
              description: l10n.troubleshootingRestartDesc,
            ),
          ],
        ),
      ),
    );
  }

  CheckStatus _networkLevel(AppLocalizations l10n) {
    final interfaces = _interfaces;
    if (interfaces == null) return CheckStatus.checking;
    return interfaces.isEmpty ? CheckStatus.error : CheckStatus.ok;
  }

  String _networkDetail(AppLocalizations l10n) {
    final interfaces = _interfaces;
    if (interfaces == null) return l10n.troubleshootingChecking;
    return interfaces.isEmpty
        ? l10n.troubleshootingNetworkNone
        : l10n.troubleshootingNetworkOk(interfaces.length);
  }

  CheckStatus _firewallLevel() {
    final report = _firewall;
    if (report == null) return CheckStatus.checking;
    return switch (report.state) {
      FirewallState.open => CheckStatus.ok,
      FirewallState.blocked => CheckStatus.error,
      FirewallState.unknown => CheckStatus.unknown,
      FirewallState.unsupported => CheckStatus.unsupported,
    };
  }

  String _firewallDetail(AppLocalizations l10n) {
    final report = _firewall;
    if (report == null) return l10n.troubleshootingChecking;
    return switch (report.state) {
      FirewallState.open => l10n.troubleshootingFirewallOpen,
      FirewallState.blocked => l10n.troubleshootingFirewallBlocked(
        report.missing.join(', '),
      ),
      FirewallState.unknown => l10n.troubleshootingFirewallUnknown,
      FirewallState.unsupported => l10n.troubleshootingFirewallUnsupported,
    };
  }

  CheckStatus _portLevel() {
    final controller = _controller;
    if (controller == null) return CheckStatus.checking;
    final session = sessionPortLevel(controller.listenPort);
    final pairing = pairingPortLevel(controller.pairingPort);
    if (session == CheckStatus.error || pairing == CheckStatus.error) {
      return CheckStatus.error;
    }
    if (session == CheckStatus.warning || pairing == CheckStatus.warning) {
      return CheckStatus.warning;
    }
    return CheckStatus.ok;
  }

  String _portDetail(
    AppLocalizations l10n,
    LocalTransferController controller,
  ) {
    String label(int? port) => port?.toString() ?? '—';
    final detail = l10n.troubleshootingPortListening(
      label(controller.listenPort),
      label(controller.pairingPort),
      '$discoveryPort',
    );
    final fallback =
        (controller.listenPort != null &&
            controller.listenPort != defaultSessionPort) ||
        (controller.pairingPort != null &&
            controller.pairingPort != defaultPairingPort);
    return fallback
        ? '$detail — ${l10n.troubleshootingPortFallbackNote}'
        : detail;
  }

  CheckStatus _vpnLevel() {
    final names = _tunnelNames;
    if (names == null) return CheckStatus.checking;
    return names.isEmpty ? CheckStatus.ok : CheckStatus.warning;
  }

  String _vpnDetail(AppLocalizations l10n) {
    final names = _tunnelNames;
    if (names == null) return l10n.troubleshootingChecking;
    return names.isEmpty
        ? l10n.troubleshootingVpnNone
        : l10n.troubleshootingVpnFound(names.join(', '));
  }
}

class _DiagnosticItem extends StatelessWidget {
  const _DiagnosticItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.level,
    required this.detail,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final CheckStatus level;
  final String detail;

  /// An action offered beside the finding — today only the port check carries
  /// one, the firewall button that exists for exactly the state it reports.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colors.secondaryText),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: WeChat.fontSizeMeta,
                  fontWeight: FontWeight.w500,
                  color: colors.bubbleText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: WeChat.fontSizeMeta,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _levelLabel(l10n),
                style: TextStyle(
                  fontSize: WeChat.fontSizeMeta,
                  fontWeight: FontWeight.w600,
                  color: _levelColor(colors),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  fontSize: WeChat.fontSizeMeta,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }

  String _levelLabel(AppLocalizations l10n) => switch (level) {
    CheckStatus.ok => l10n.troubleshootingStatusOk,
    CheckStatus.warning => l10n.troubleshootingStatusWarning,
    CheckStatus.error => l10n.troubleshootingStatusError,
    CheckStatus.unsupported => l10n.troubleshootingStatusUnsupported,
    CheckStatus.unknown || CheckStatus.checking => l10n.troubleshootingChecking,
  };

  Color _levelColor(WeChatColors colors) => switch (level) {
    CheckStatus.ok => Colors.green,
    CheckStatus.warning => Colors.orange,
    CheckStatus.error => colors.danger,
    CheckStatus.unknown ||
    CheckStatus.unsupported ||
    CheckStatus.checking => colors.secondaryText,
  };
}

class _SolutionItem extends StatelessWidget {
  const _SolutionItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colors.secondaryText),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: WeChat.fontSizeMeta,
                  fontWeight: FontWeight.w500,
                  color: colors.bubbleText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: WeChat.fontSizeMeta,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

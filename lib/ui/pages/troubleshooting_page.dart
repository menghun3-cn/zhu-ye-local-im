import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../controller_scope.dart';
import '../l10n/generated/app_localizations.dart';
import '../wechat/theme.dart';
import '../widgets.dart';

/// Troubleshooting page for network diagnostics and common solutions.
class TroubleshootingPage extends StatelessWidget {
  const TroubleshootingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);

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
    final colors = WeChatColors.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(WeChat.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.troubleshootingDiagnostics,
              style: TextStyle(
                fontSize: WeChat.fontSizePreview,
                fontWeight: FontWeight.w600,
                color: colors.bubbleText,
              ),
            ),
            const SizedBox(height: 12),
            _DiagnosticItem(
              icon: Icons.wifi,
              title: l10n.troubleshootingNetworkCheck,
              description: l10n.troubleshootingNetworkCheckDesc,
              status: _checkNetworkStatus(controller),
            ),
            const SizedBox(height: 8),
            _DiagnosticItem(
              icon: Icons.security,
              title: l10n.troubleshootingFirewallCheck,
              description: l10n.troubleshootingFirewallCheckDesc,
              status: _checkFirewallStatus(),
            ),
            const SizedBox(height: 8),
            _DiagnosticItem(
              icon: Icons.portable_wifi_off,
              title: l10n.troubleshootingPortCheck,
              description: l10n.troubleshootingPortCheckDesc,
              status: _checkPortStatus(),
            ),
            const SizedBox(height: 8),
            _DiagnosticItem(
              icon: Icons.vpn_lock,
              title: l10n.troubleshootingVpnCheck,
              description: l10n.troubleshootingVpnCheckDesc,
              status: _checkVpnStatus(),
            ),
          ],
        ),
      ),
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

  String _checkNetworkStatus(LocalTransferController controller) {
    // Basic network check - would need actual network APIs
    return 'unknown';
  }

  String _checkFirewallStatus() {
    // Firewall check - platform specific
    return 'unknown';
  }

  String _checkPortStatus() {
    // Port check - would need to check if ports are available
    return 'unknown';
  }

  String _checkVpnStatus() {
    // VPN check - would need to detect VPN interfaces
    return 'unknown';
  }
}

class _DiagnosticItem extends StatelessWidget {
  const _DiagnosticItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;

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
              const SizedBox(height: 4),
              Text(
                status,
                style: TextStyle(
                  fontSize: WeChat.fontSizeMeta,
                  color: _getStatusColor(status, colors),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status, WeChatColors colors) {
    switch (status) {
      case 'ok':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'error':
        return Colors.red;
      default:
        return colors.secondaryText;
    }
  }
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

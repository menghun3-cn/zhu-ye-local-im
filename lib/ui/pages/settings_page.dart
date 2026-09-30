import 'package:flutter/material.dart';

import '../controller_scope.dart';
import '../dialogs.dart';
import '../l10n/generated/app_localizations.dart';
import '../seams.dart';
import '../widgets.dart';

/// What this Device is, where it keeps things, and what has gone wrong.
class SettingsPage extends StatelessWidget {
  /// Builds the Settings surface over the platform facts in [seams].
  const SettingsPage({super.key, required this.seams});

  /// Where this Device's profile lives, and where files land by default.
  final PlatformSeams seams;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = ControllerScope.of(context);
    final self = controller.self;
    final port = controller.listenPort;
    final notices = controller.notices;
    final profilePath = seams.profilePath;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionHeader(title: l10n.settingsThisDevice),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FactLine(l10n.factAlias, self.alias),
                // The whole Fingerprint, selectable: it is the one thing a
                // user can read out loud to tell two Devices apart, and the
                // short form is for lists, not for this.
                FactLine(l10n.factFingerprint, self.fingerprint.hex),
                FactLine(l10n.factPlatform, self.platform.displayName),
                FactLine(
                  l10n.factOwnerGroup,
                  l10n.groupDevices(self.groupLength),
                ),
                FactLine(
                  l10n.factSessions,
                  l10n.sessionsOpen(self.openSessions),
                ),
                FactLine(
                  l10n.factListening,
                  port == null ? l10n.notAcceptingSessions : l10n.onPort(port),
                ),
                FactLine(
                  l10n.factPairingRequests,
                  controller.isAcceptingPairings
                      ? l10n.pairingListening
                      : l10n.pairingNotListening,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => showRenameDialog(context, controller),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(l10n.renameThisDevice),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SectionHeader(title: l10n.settingsWhereThingsGo),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FactLine(
                  l10n.factIdentity,
                  profilePath ?? l10n.notStoredOnThisDevice,
                ),
                if (profilePath == null) HintText(l10n.noIdentityHint),
                FactLine(
                  l10n.factReceivedFiles,
                  seams.defaultIncomingDirectory ?? l10n.noDefaultFolder,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SectionHeader(title: l10n.settingsNotices),
        if (notices.isEmpty)
          HintText(l10n.nothingWentWrong)
        else
          Card(
            child: Column(
              children: [
                // Newest first, and bounded: this is a window on what went
                // wrong, not a log file to scroll.
                for (final notice in notices.reversed.take(20))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.info_outline, size: 18),
                    title: Text(notice),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Text(
          l10n.settingsAbout,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

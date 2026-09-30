import 'package:flutter/material.dart';

import '../controller_scope.dart';
import '../dialogs.dart';
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
    final theme = Theme.of(context);
    final controller = ControllerScope.of(context);
    final self = controller.self;
    final port = controller.listenPort;
    final notices = controller.notices;
    final profilePath = seams.profilePath;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionHeader(title: 'This Device'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FactLine('Alias', self.alias),
                // The whole Fingerprint, selectable: it is the one thing a
                // user can read out loud to tell two Devices apart, and the
                // short form is for lists, not for this.
                FactLine('Fingerprint', self.fingerprint.hex),
                FactLine('Platform', self.platform.displayName),
                FactLine('Owner Group', '${self.groupLength} Device(s)'),
                FactLine('Sessions', '${self.openSessions} open'),
                FactLine(
                  'Listening',
                  port == null ? 'not accepting Sessions' : 'on port $port',
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => showRenameDialog(context, controller),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Rename this Device'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Where things go'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FactLine(
                  'Identity',
                  profilePath ?? 'not stored on this Device',
                ),
                if (profilePath == null)
                  const HintText(
                    'This Device has nowhere to keep its identity, so it runs '
                    'in memory: it works, and it has to be paired again after '
                    'every restart.',
                  ),
                FactLine(
                  'Received files',
                  seams.defaultIncomingDirectory ?? 'no default folder',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Notices'),
        if (notices.isEmpty)
          const HintText('Nothing has gone wrong.')
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
          'Local Transfer moves text, files and clipboard entries between your '
          'own Devices over the local network. There is no server, no account '
          'and no cloud: everything above stays inside this network.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

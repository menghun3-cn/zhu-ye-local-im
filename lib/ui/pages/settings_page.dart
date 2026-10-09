import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../controller_scope.dart';
import '../dialogs.dart';
import '../l10n/generated/app_localizations.dart';
import '../seams.dart';
import '../wechat/theme.dart';
import '../widgets.dart';

/// Asks where received files should land, and remembers the answer.
///
/// [askForDirectory] rather than the folder chooser directly, so the user gets
/// both roads: the field they can type into and the platform's own dialog
/// behind a button. That dialog is the same one the accept flow opens, which is
/// the point — one folder is chosen the same way whether it is being set up in
/// advance or answered at the moment a file arrives.
Future<void> _chooseFolder(
  BuildContext context,
  LocalTransferController controller,
  String? platformDefault,
) async {
  final l10n = AppLocalizations.of(context);
  final chosen = await askForDirectory(
    context,
    title: l10n.chooseFolderTitle,
    initial: controller.incomingDirectory ?? platformDefault ?? '',
    confirmLabel: l10n.save,
  );
  // Null means the user backed out, which must not clear a folder they already
  // have: only a confirmed answer is a decision.
  if (chosen == null) return;
  await controller.setIncomingDirectory(chosen);
}

/// What this Device is, where it keeps things, and what has gone wrong.
class SettingsPage extends StatelessWidget {
  /// Builds the Settings surface over the platform facts in [seams].
  const SettingsPage({super.key, required this.seams});

  /// Where this Device's profile lives, and where files land by default.
  final PlatformSeams seams;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    final self = controller.self;
    final port = controller.listenPort;
    final notices = controller.notices;
    final profilePath = seams.profilePath;

    return ListView(
      padding: WeChat.pagePadding,
      children: [
        SectionHeader(title: l10n.settingsThisDevice),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(WeChat.cardPadding),
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
        const SizedBox(height: WeChat.sectionGap),
        SectionHeader(title: l10n.settingsWhereThingsGo),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(WeChat.cardPadding),
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
                  // What will actually be offered: the user's choice, or the
                  // platform's own answer, or the fact that there is neither.
                  controller.incomingDirectory ??
                      seams.defaultIncomingDirectory ??
                      l10n.noDefaultFolder,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: HintText(
                    controller.incomingDirectory == null
                        ? l10n.incomingFolderUnset
                        : l10n.incomingFolderHint,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(
                    _chooseFolder(
                      context,
                      controller,
                      seams.defaultIncomingDirectory,
                    ),
                  ),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text(l10n.changeIncomingFolder),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: WeChat.sectionGap),
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
      ],
    );
  }
}

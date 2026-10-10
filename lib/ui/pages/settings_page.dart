import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../controller_scope.dart';
import '../dialogs.dart';
import '../l10n/generated/app_localizations.dart';
import '../pickers.dart';
import '../seams.dart';
import '../wechat/theme.dart';
import '../widgets.dart';

/// Where received files land, as something the user can type into.
///
/// A field on the page rather than a fact line with a button beside it: the
/// two roads to one value should not look like two different kinds of thing.
/// The user may know the path and want to paste it, or want the platform's own
/// chooser — so the value is a field, and the folder button lives inside it.
///
/// Saving happens on Enter and on leaving the field. There is deliberately no
/// Save button: a settings field that has to be confirmed is a field nobody
/// trusts to have taken, and the only thing that ever needs saying out loud is
/// that the typed text has *not* been taken yet.
class _IncomingFolderField extends StatefulWidget {
  const _IncomingFolderField({
    required this.controller,
    required this.platformDefault,
  });

  /// The controller the folder is read from and written to.
  final LocalTransferController controller;

  /// What the platform suggests, offered while the user has chosen nothing.
  final String? platformDefault;

  @override
  State<_IncomingFolderField> createState() => _IncomingFolderFieldState();
}

class _IncomingFolderFieldState extends State<_IncomingFolderField> {
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The user's choice if there is one, otherwise what the platform would
    // offer anyway: an empty box would make the user type a path they cannot
    // see, and this field is meant to be *edited*, not composed from nothing.
    _text = TextEditingController(
      text: widget.controller.incomingDirectory ?? widget.platformDefault ?? '',
    );
    // Leaving the field is a decision, the same as pressing Enter. Without it a
    // typed path would sit in the box looking saved, which is the one way this
    // design could lie.
    _focus.addListener(() {
      if (!_focus.hasFocus) unawaited(_commit());
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  /// What the controller is holding, or null when nothing has been chosen.
  ///
  /// The platform default is *shown* while nothing has been chosen, because it
  /// is where a file would land — but it is not what is stored: "the user
  /// picked this" and "this is what the platform suggests" are different facts,
  /// and only the first one is a decision.
  String? get _chosen => widget.controller.incomingDirectory;

  /// Whether the box shows something that has not been taken yet.
  bool get _unsaved => _text.text.trim() != (_chosen ?? '');

  /// Hands what is in the box to the controller.
  ///
  /// An emptied box means "no folder of my own" — the null the controller reads
  /// as "ask me each time" — rather than an empty path, which would name a
  /// destination nothing can be written to.
  Future<void> _commit() async {
    final typed = _text.text.trim();
    if (typed == (_chosen ?? '')) return;
    await widget.controller.setIncomingDirectory(typed.isEmpty ? null : typed);
    if (!mounted) return;
    setState(() {});
  }

  /// Opens the platform's own folder chooser and takes its answer.
  ///
  /// The picker seam rather than [askForDirectory]: there is nothing left to
  /// confirm in a dialog, because the field the answer lands in is already on
  /// screen and already editable.
  Future<void> _browse() async {
    final chosen = await PickerResolution.picker.directory();
    if (chosen == null) return;
    await widget.controller.setIncomingDirectory(chosen);
    if (!mounted) return;
    setState(() => _text.text = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chosen = _chosen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.factReceivedFiles,
          style: const TextStyle(
            fontSize: WeChat.fontSizePreview,
            color: WeChat.secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _text,
          focusNode: _focus,
          style: const TextStyle(fontSize: WeChat.fontSizeInput),
          onSubmitted: (_) => unawaited(_commit()),
          // Any keystroke may be the one that makes the box unsaved, so the
          // line under it has to be redrawn as the user types.
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: WeChat.surfaceSunken,
            hintText: l10n.noDefaultFolder,
            suffixIcon: IconButton(
              tooltip: l10n.changeIncomingFolder,
              onPressed: () => unawaited(_browse()),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WeChat.controlRadius),
              borderSide: const BorderSide(color: WeChat.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WeChat.controlRadius),
              borderSide: const BorderSide(color: WeChat.brandStrong),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: HintText(
            _unsaved
                ? l10n.folderNotSaved
                : chosen == null
                ? l10n.incomingFolderUnset
                : l10n.incomingFolderHint,
          ),
        ),
      ],
    );
  }
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
                const SizedBox(height: 8),
                _IncomingFolderField(
                  controller: controller,
                  platformDefault: seams.defaultIncomingDirectory,
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

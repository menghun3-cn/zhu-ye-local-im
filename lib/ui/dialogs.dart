import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'feedback.dart';
import 'l10n/generated/app_localizations.dart';
import 'pickers.dart';

/// The dialogs the surfaces open.
///
/// Each one is a step of a flow that talks to a peer — receiving a connection,
/// comparing six digits, typing an address — so each is a `StatefulWidget` with
/// its own error line rather than a `showDialog` with a closure: a flow that
/// waits for another Device to answer has to show what it is waiting for, and
/// where the answer went wrong, in the dialog itself.

/// Asks for a new Alias and applies it.
Future<void> showRenameDialog(
  BuildContext context,
  LocalTransferController controller,
) => showDialog<void>(
  context: context,
  builder: (_) => _RenameDialog(controller: controller),
);

/// Asks for the address of a Device Discovery could not find.
Future<void> showManualAddressDialog(
  BuildContext context,
  LocalTransferController controller,
) => showDialog<void>(
  context: context,
  builder: (_) => _ManualAddressDialog(controller: controller),
);

/// Asks for the path of a file to send to [name], the Device at [to].
///
/// An address rather than a [PeerView] because a conversation is opened with a
/// Fingerprint and outlives the peer list: a Device that is still connected but
/// no longer being announced is something a user can send to, and the dialog
/// has no business refusing on the grounds that a list somewhere forgot it.
Future<void> showSendFileDialog(
  BuildContext context,
  LocalTransferController controller, {
  required Fingerprint to,
  required String name,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SendFileDialog(controller: controller, to: to, name: name),
);

/// Asks where a Transfer should land.
///
/// Returns the path, or null when the user backed out. The default comes from
/// the platform — Downloads on Windows, the app's own directory on Android —
/// and is editable, because a Device that only ever wrote to one folder would
/// be a Device that cannot file anything.
Future<String?> askForDirectory(
  BuildContext context, {
  required String title,
  String? initial,
  String? confirmLabel,
}) => showDialog<String>(
  context: context,
  builder: (_) => _DirectoryDialog(
    title: title,
    initial: initial ?? '',
    // Resolved inside the dialog rather than defaulted here: a default argument
    // cannot be a lookup, and the string has to come from the language on
    // screen.
    confirmLabel: confirmLabel,
  ),
);

// -------------------------------------------------------------------- pieces

/// A failure, where the flow happened.
///
/// [failure] is either an exception the layers below raised — described at
/// render time, so the sentence is in the language the window is showing — or a
/// sentence this dialog made up about its own fields, which is text already.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.failure);

  final Object? failure;

  @override
  Widget build(BuildContext context) {
    final failure = this.failure;
    if (failure == null) return const SizedBox.shrink();
    final message = failure is String
        ? failure
        : describeFailure(failure, AppLocalizations.of(context));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ rename

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.controller});

  final LocalTransferController controller;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _alias = TextEditingController(
    text: widget.controller.self.alias,
  );
  Object? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.controller.rename(_alias.text);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.renameThisDevice),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _alias,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.factAlias,
              helperText: l10n.aliasHelper,
            ),
            onSubmitted: (_) {
              if (!_busy) unawaited(_save());
            },
          ),
          _ErrorLine(_failure),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_save()),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------- manual address

class _ManualAddressDialog extends StatefulWidget {
  const _ManualAddressDialog({required this.controller});

  final LocalTransferController controller;

  @override
  State<_ManualAddressDialog> createState() => _ManualAddressDialogState();
}

class _ManualAddressDialogState extends State<_ManualAddressDialog> {
  final TextEditingController _address = TextEditingController();
  late final TextEditingController _port = TextEditingController(
    text: '$defaultSessionPort',
  );
  Object? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _address.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final port = int.tryParse(_port.text.trim());
    if (port == null) {
      setState(() => _failure = AppLocalizations.of(context).portIsANumber);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.controller.connectTo(
        address: _address.text.trim(),
        port: port,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.manualAddressTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _address,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.fieldAddress,
              helperText: l10n.addressHelper,
            ),
          ),
          TextField(
            controller: _port,
            decoration: InputDecoration(labelText: l10n.fieldPort),
            keyboardType: TextInputType.number,
            onSubmitted: (_) {
              if (!_busy) unawaited(_connect());
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(l10n.manualAddressNote),
          ),
          _ErrorLine(_failure),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_connect()),
          child: Text(l10n.connect),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ sending

/// Asks for the path of a file, then offers it to [to].
///
/// A path rather than a picker: this build ships no plugins, and a native file
/// dialog per platform is a different piece of work — so the field says so
/// instead of looking like a Browse button that does nothing.
class _SendFileDialog extends StatefulWidget {
  const _SendFileDialog({
    required this.controller,
    required this.to,
    required this.name,
  });

  final LocalTransferController controller;

  /// The Device the file is for.
  final Fingerprint to;

  /// What to call that Device in the title.
  final String name;

  @override
  State<_SendFileDialog> createState() => _SendFileDialogState();
}

class _SendFileDialogState extends State<_SendFileDialog> {
  final TextEditingController _path = TextEditingController();
  Object? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final path = _path.text.trim();
    final file = File(path);
    if (path.isEmpty || !file.existsSync()) {
      setState(() => _failure = l10n.noSuchFile(path));
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.controller.sendFile(file, to: widget.to);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.sendFileTitle(widget.name)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _path,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.fieldPath,
              helperText: l10n.pathHelper,
            ),
            onSubmitted: (_) {
              if (!_busy) unawaited(_send());
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            // Said plainly because the alternative — an empty field with no
            // explanation — reads as a broken Browse button.
            child: Text(l10n.noFileBrowserNote),
          ),
          _ErrorLine(_failure),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_send()),
          child: Text(l10n.send),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- destination

class _DirectoryDialog extends StatefulWidget {
  const _DirectoryDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String initial;

  /// What the confirm button says, or null to use the standard wording.
  final String? confirmLabel;

  @override
  State<_DirectoryDialog> createState() => _DirectoryDialogState();
}

class _DirectoryDialogState extends State<_DirectoryDialog> {
  late final TextEditingController _path = TextEditingController(
    text: widget.initial,
  );
  Object? _failure;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  /// Opens the platform's own folder chooser and puts what it returned in the
  /// field.
  ///
  /// The field stays editable: the chooser cannot reach a network share the
  /// user has not mounted, and a destination that could only be set by
  /// clicking would be one that cannot be set at all for those. So this is an
  /// addition to typing, not a replacement for it.
  Future<void> _browse() async {
    final chosen = await PickerResolution.picker.directory();
    if (!mounted || chosen == null) return;
    _path.text = chosen;
  }

  void _accept() {
    final path = _path.text.trim();
    if (path.isEmpty) {
      setState(() => _failure = AppLocalizations.of(context).folderRequired);
      return;
    }
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _path,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.fieldFolder,
              helperText: l10n.folderHelper,
            ),
            onSubmitted: (_) => _accept(),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(_browse()),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: Text(l10n.browseFolder),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l10n.folderNote),
          ),
          _ErrorLine(_failure),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _accept,
          child: Text(widget.confirmLabel ?? l10n.acceptIntoFolder),
        ),
      ],
    );
  }
}

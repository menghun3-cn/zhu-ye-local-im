import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'feedback.dart';
import 'l10n/generated/app_localizations.dart';

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

/// Opens an open Pairing and waits for another Device to connect to it.
Future<void> showReceiveDialog(
  BuildContext context,
  LocalTransferController controller,
) => showDialog<void>(
  context: context,
  // Not dismissible by tapping outside: withdrawing the invitation by
  // accident mid-Pairing is not a "cancel" a user means.
  barrierDismissible: false,
  builder: (_) => _ReceiveDialog(controller: controller),
);

/// Pairs with a discovered [peer] that is receiving, without typing a code.
Future<void> showPairWithPeerDialog(
  BuildContext context,
  LocalTransferController controller,
  PeerView peer,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PairWithPeerDialog(controller: controller, peer: peer),
);

/// Asks for the address of a Device Discovery could not find.
Future<void> showManualAddressDialog(
  BuildContext context,
  LocalTransferController controller,
) => showDialog<void>(
  context: context,
  builder: (_) => _ManualAddressDialog(controller: controller),
);

/// Asks for text to send to [peer].
Future<void> showSendTextDialog(
  BuildContext context,
  LocalTransferController controller,
  PeerView peer,
) => showDialog<void>(
  context: context,
  builder: (_) => _SendTextDialog(controller: controller, peer: peer),
);

/// Asks for the path of a file to send to [peer].
Future<void> showSendFileDialog(
  BuildContext context,
  LocalTransferController controller,
  PeerView peer,
) => showDialog<void>(
  context: context,
  builder: (_) => _SendFileDialog(controller: controller, peer: peer),
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

/// A code or six digits, big enough to read across a desk.
class _BigCode extends StatelessWidget {
  const _BigCode({required this.value, this.caption});

  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = this.caption;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText(
          value,
          style: theme.textTheme.displaySmall?.copyWith(letterSpacing: 4),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              caption,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

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

/// The six digits both screens have to be showing.
///
/// The step exists because the handshake alone proves only that both sides used
/// the same secret — not that no third Device is in the middle. Reading digits
/// aloud is the only check that does.
class _Confirmation extends StatelessWidget {
  const _Confirmation({
    required this.attempt,
    required this.busy,
    required this.onConfirm,
  });

  final PairingAttempt attempt;
  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final peer = attempt.peer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BigCode(value: attempt.sas, caption: l10n.compareDigits(peer.alias)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : onConfirm,
          icon: const Icon(Icons.check),
          label: Text(l10n.theyMatch),
        ),
      ],
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

// ------------------------------------------------------------------ receive

/// The receiving side of the click-to-pair flow: this Device waits, the user
/// of the other Device taps its name in a list.
class _ReceiveDialog extends StatefulWidget {
  const _ReceiveDialog({required this.controller});

  final LocalTransferController controller;

  @override
  State<_ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<_ReceiveDialog> {
  PairingInvitation? _invitation;
  PairingAttempt? _attempt;
  Object? _failure;
  bool _busy = false;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    // Closing the dialog withdraws the invitation: a listener still open
    // after the window is gone would admit a Device nobody is watching.
    if (!_confirmed) {
      unawaited(_attempt?.cancel());
      unawaited(_invitation?.cancel());
    }
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final invitation = await widget.controller.inviteOpen();
      if (!mounted) {
        unawaited(invitation.cancel());
        return;
      }
      setState(() => _invitation = invitation);
      // This is the step that waits: it completes when a Device connects, not
      // when the user does anything.
      final attempt = await invitation.attempt;
      if (!mounted) {
        unawaited(attempt.cancel());
        return;
      }
      setState(() => _attempt = attempt);
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _confirm() async {
    final attempt = _attempt;
    if (attempt == null) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await attempt.confirm();
      _confirmed = true;
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
    final invitation = _invitation;
    final attempt = _attempt;
    return AlertDialog(
      title: Text(l10n.receiveAConnection),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (invitation == null && _failure == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(),
            ),
          if (invitation != null && attempt == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l10n.receiveWaiting),
            ),
          if (attempt != null)
            _Confirmation(
              attempt: attempt,
              busy: _busy,
              onConfirm: () => unawaited(_confirm()),
            ),
          _ErrorLine(_failure),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(attempt == null ? l10n.cancel : l10n.cancelThisPairing),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- pair by click

/// The initiating side of the click-to-pair flow: dial a Device the user
/// picked from the discovered list, then confirm the digits.
class _PairWithPeerDialog extends StatefulWidget {
  const _PairWithPeerDialog({required this.controller, required this.peer});

  final LocalTransferController controller;
  final PeerView peer;

  @override
  State<_PairWithPeerDialog> createState() => _PairWithPeerDialogState();
}

class _PairWithPeerDialogState extends State<_PairWithPeerDialog> {
  PairingAttempt? _attempt;
  Object? _failure;
  bool _busy = false;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_join());
  }

  @override
  void dispose() {
    if (!_confirmed) unawaited(_attempt?.cancel());
    super.dispose();
  }

  Future<void> _join() async {
    final address = widget.peer.address;
    if (address == null) {
      // The same sentence the app layer's refusal carries, because it is the
      // same fact: nothing here knows where that Device is.
      setState(
        () =>
            _failure = AppLocalizations.of(context)
                .refusalPeerAddressUnknown(widget.peer.displayName),
      );
      return;
    }
    try {
      final attempt = await widget.controller.joinOpen(host: address);
      if (!mounted) {
        unawaited(attempt.cancel());
        return;
      }
      setState(() => _attempt = attempt);
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _confirm() async {
    final attempt = _attempt;
    if (attempt == null) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await attempt.confirm();
      _confirmed = true;
      // The Session is what the user is here for, so it is opened now, while
      // the Pairing that allows it is the thing on screen. A Session that
      // fails to follow is a tap away on the peer card, and reporting it here
      // would read as the Pairing having failed when it has not.
      try {
        await widget.controller.connectAfterPairing(attempt.peer.fingerprint);
      } on Object {
        // Deliberately swallowed; see above.
      }
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
    final attempt = _attempt;
    return AlertDialog(
      title: Text(l10n.connectToPeerTitle(widget.peer.displayName)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attempt == null && _failure == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(l10n.reachingOtherDevice),
                ],
              ),
            ),
          if (attempt != null)
            _Confirmation(
              attempt: attempt,
              busy: _busy,
              onConfirm: () => unawaited(_confirm()),
            ),
          _ErrorLine(_failure),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(attempt == null ? l10n.cancel : l10n.cancelThisPairing),
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

class _SendTextDialog extends StatefulWidget {
  const _SendTextDialog({required this.controller, required this.peer});

  final LocalTransferController controller;
  final PeerView peer;

  @override
  State<_SendTextDialog> createState() => _SendTextDialogState();
}

class _SendTextDialogState extends State<_SendTextDialog> {
  final TextEditingController _text = TextEditingController();
  Object? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.controller.sendText(_text.text, to: widget.peer.fingerprint);
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
      title: Text(l10n.sendTextTitle(widget.peer.displayName)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            maxLines: 6,
            minLines: 3,
            decoration: InputDecoration(
              labelText: l10n.fieldText,
              helperText: l10n.textHelper,
            ),
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

class _SendFileDialog extends StatefulWidget {
  const _SendFileDialog({required this.controller, required this.peer});

  final LocalTransferController controller;
  final PeerView peer;

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
      await widget.controller.sendFile(file, to: widget.peer.fingerprint);
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
      title: Text(l10n.sendFileTitle(widget.peer.displayName)),
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
          Padding(
            padding: const EdgeInsets.only(top: 12),
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

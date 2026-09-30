import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'feedback.dart';

/// The dialogs the surfaces open.
///
/// Each one is a step of a flow that talks to a peer — showing a Pairing code,
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
  String confirmLabel = 'Accept into this folder',
}) => showDialog<String>(
  context: context,
  builder: (_) => _DirectoryDialog(
    title: title,
    initial: initial ?? '',
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
class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return const SizedBox.shrink();
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
/// The step exists because the code alone proves only that both sides used the
/// same code — not that no third Device is in the middle. Reading digits aloud
/// is the only check that does.
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
    final peer = attempt.peer;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BigCode(
          value: attempt.sas,
          caption:
              'Compare these digits with ${peer.alias}. '
              'If the two screens disagree, cancel.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : onConfirm,
          icon: const Icon(Icons.check),
          label: const Text('They match'),
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
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.rename(_alias.text);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeFailure(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename this Device'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _alias,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Alias',
              helperText: 'What other Devices show for this one',
            ),
            onSubmitted: (_) {
              if (!_busy) unawaited(_save());
            },
          ),
          _ErrorLine(_error),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_save()),
          child: const Text('Save'),
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
  String? _error;
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
      if (mounted) setState(() => _error = describeFailure(error));
    }
  }

  Future<void> _confirm() async {
    final attempt = _attempt;
    if (attempt == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await attempt.confirm();
      _confirmed = true;
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeFailure(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitation = _invitation;
    final attempt = _attempt;
    return AlertDialog(
      title: const Text('Receive a connection'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (invitation == null && _error == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(),
            ),
          if (invitation != null && attempt == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Waiting for a Device to connect. On the other Device, tap '
                'Pair beside this one. Both screens will then show the same '
                'six digits to compare.',
              ),
            ),
          if (attempt != null)
            _Confirmation(
              attempt: attempt,
              busy: _busy,
              onConfirm: () => unawaited(_confirm()),
            ),
          _ErrorLine(_error),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(attempt == null ? 'Cancel' : 'Cancel this Pairing'),
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
  String? _error;
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
      setState(
        () => _error =
            'Nothing is known about where ${widget.peer.displayName} is. '
            'Wait until this Device has discovered it, then try again.',
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
      if (mounted) setState(() => _error = describeFailure(error));
    }
  }

  Future<void> _confirm() async {
    final attempt = _attempt;
    if (attempt == null) return;
    setState(() {
      _busy = true;
      _error = null;
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
          _error = describeFailure(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final attempt = _attempt;
    return AlertDialog(
      title: Text('Connect to ${widget.peer.displayName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attempt == null && _error == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Reaching the other Device…'),
                ],
              ),
            ),
          if (attempt != null)
            _Confirmation(
              attempt: attempt,
              busy: _busy,
              onConfirm: () => unawaited(_confirm()),
            ),
          _ErrorLine(_error),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(attempt == null ? 'Cancel' : 'Cancel this Pairing'),
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
  String? _error;
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
      setState(() => _error = 'A port is a number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
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
          _error = describeFailure(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reach a Device by address'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _address,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Address',
              helperText: 'For a Device Discovery cannot find',
            ),
          ),
          TextField(
            controller: _port,
            decoration: const InputDecoration(labelText: 'Port'),
            keyboardType: TextInputType.number,
            onSubmitted: (_) {
              if (!_busy) unawaited(_connect());
            },
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Nothing is known about this Device beforehand, so the Session '
              'is what proves it belongs in your Owner Group. A Device in a '
              'different group is refused.',
            ),
          ),
          _ErrorLine(_error),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_connect()),
          child: const Text('Connect'),
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
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.sendText(_text.text, to: widget.peer.fingerprint);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeFailure(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Send text to ${widget.peer.displayName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            maxLines: 6,
            minLines: 3,
            decoration: const InputDecoration(
              labelText: 'Text',
              helperText: 'It arrives as a Transfer the Device has to accept',
            ),
          ),
          _ErrorLine(_error),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_send()),
          child: const Text('Send'),
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
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final path = _path.text.trim();
    final file = File(path);
    if (path.isEmpty || !file.existsSync()) {
      setState(() => _error = 'There is no file at "$path".');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.sendFile(file, to: widget.peer.fingerprint);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeFailure(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Send a file to ${widget.peer.displayName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _path,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Path',
              helperText: 'Copy a path, or type one',
            ),
            onSubmitted: (_) {
              if (!_busy) unawaited(_send());
            },
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              // Said plainly because the alternative — an empty field with no
              // explanation — reads as a broken Browse button.
              'This build has no file browser: it ships no plugins, and a '
              'native dialog for each platform is its own change. A path is '
              'what it takes for now.',
            ),
          ),
          _ErrorLine(_error),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_send()),
          child: const Text('Send'),
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
  final String confirmLabel;

  @override
  State<_DirectoryDialog> createState() => _DirectoryDialogState();
}

class _DirectoryDialogState extends State<_DirectoryDialog> {
  late final TextEditingController _path = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  void _accept() {
    final path = _path.text.trim();
    if (path.isEmpty) {
      setState(
        () => _error =
            'A folder is needed: a name from the peer must '
            'not be allowed to choose one.',
      );
      return;
    }
    Navigator.of(context).pop(path);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _path,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Folder',
              helperText: 'Created if it does not exist',
            ),
            onSubmitted: (_) => _accept(),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'A name that arrives with the Transfer is untrusted: it can '
              'name a file inside this folder and nothing else.',
            ),
          ),
          _ErrorLine(_error),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _accept, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

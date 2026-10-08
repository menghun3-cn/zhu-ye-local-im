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

/// Asks whether the Device that dialled this one may pair with it.
///
/// Raised by the application rather than by a button, and that is the point:
/// anything on the link may dial this Device, so the dialog *is* the admission
/// step. Closing it without answering refuses the request — a Device nobody is
/// looking at is not a Device that said yes.
Future<void> showPairingRequestDialog(
  BuildContext context,
  LocalTransferController controller,
  PairingRequest request,
) => showDialog<void>(
  context: context,
  builder: (_) =>
      _PairingRequestDialog(controller: controller, request: request),
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

// --------------------------------------------------------- pairing requests

/// Who dials when both Devices tap Connect at the same time.
///
/// When both sides start at once, each one finds the other already knocking and
/// the two Pairings that follow are mirror images. Left alone that is fine —
/// the handshake is symmetric and both halves complete — but it leaves *two*
/// things expecting to dial, and a Session dialled from both ends at once is a
/// Session each end refuses as a second one: the Pairing works and there is
/// still nobody to talk to.
///
/// So the side that would otherwise be second is told to open the Session and
/// the other to wait for it. The choice is made on the two Fingerprints, which
/// are known before either side is asked anything, so both Devices work it out
/// from the same pair of facts and reach opposite answers.
///
/// This is deliberately only consulted by the *answering* side. The side whose
/// user pressed Pair dialled the Pairing link in the first place and always
/// opens the Session, so the ordinary flow — one Device asks, the other
/// answers — has exactly one dialler no matter which Fingerprint sorts first.
/// The rule bites only where there would otherwise be two: two people tapping
/// Connect at the same moment, so that the answering side here is answering a
/// request while its own request is out. Then one of them must stand down, and
/// the Fingerprints are the only thing both sides can agree on.
///
/// Getting this wrong is silent and asymmetric: a rule the *presser* also
/// consults leaves the ordinary flow with no dialler at all whenever the
/// presser sorts higher, and nothing happens for twenty seconds.
bool _dialsFirst(Fingerprint self, Fingerprint peer) =>
    self.hex.compareTo(peer.hex) < 0;

/// The answering side of the click-to-pair flow: a Device dialled this one and
/// is waiting to hear whether it may pair.
///
/// One question, and the answer is the whole decision. The name above is the
/// caller's own claim, so what this window asks is whether a person wants to
/// let this Device into their group; saying yes pairs the two and nothing else
/// is asked afterwards.
class _PairingRequestDialog extends StatefulWidget {
  const _PairingRequestDialog({
    required this.controller,
    required this.request,
  });

  /// Needed for two things the request alone cannot do: reading this Device's
  /// own Fingerprint, which decides which side opens the Session, and opening
  /// that Session at all.
  final LocalTransferController controller;

  final PairingRequest request;

  @override
  State<_PairingRequestDialog> createState() => _PairingRequestDialogState();
}

class _PairingRequestDialogState extends State<_PairingRequestDialog> {
  PairingAttempt? _attempt;
  Object? _failure;
  bool _busy = false;
  bool _settled = false;

  @override
  void dispose() {
    // However this window goes away, nobody is left waiting behind it: a
    // request left unanswered keeps the other Device on a spinner, and an
    // attempt left open keeps the next caller out. Refusing an admitted request
    // is a no-op and cancelling its attempt is the real abandonment, so both
    // are issued rather than tracking which one applies.
    if (!_settled) {
      unawaited(widget.request.refuse());
      final attempt = _attempt;
      if (attempt != null) unawaited(attempt.cancel());
    }
    super.dispose();
  }

  /// Lets the caller in, and finishes the Pairing.
  ///
  /// One tap is the whole decision: the handshake still derives its short
  /// authentication string and both Devices still confirm over it — that is
  /// what stops a half-paired state where one side believes in a group the
  /// other knows nothing about — but nobody is asked to read six digits off a
  /// screen, so the two confirmations happen back to back here.
  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final PairingAttempt attempt;
    try {
      attempt = await widget.request.admit();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error;
        });
      }
      return;
    }
    if (!mounted) {
      unawaited(attempt.cancel());
      return;
    }
    _attempt = attempt;
    try {
      await attempt.confirm();
      _settled = true;
      // Usually this side opens nothing: the Device that dialled the Pairing
      // asked for it and opens the Session itself, and a Session dialled from
      // both ends at once is one each end refuses as a second one.
      //
      // The exception is the pair of people who tapped Connect on each other at
      // the same moment. Then this side is answering a request while its own
      // request is out, both sides would dial, and one has to stand down — so
      // the tie-break is consulted, from the two Fingerprints, and the same
      // answer comes out on both Devices. See [_dialsFirst].
      final peerFingerprint = attempt.peer.fingerprint;
      if (_dialsFirst(widget.controller.self.fingerprint, peerFingerprint)) {
        try {
          await widget.controller.connectAfterPairing(peerFingerprint);
        } on Object {
          // Deliberately swallowed: the Pairing itself succeeded, and reporting
          // a Session failure here would read as the Pairing having failed. A
          // Session that did not come up leaves the row offering Connect.
        }
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

  Future<void> _refuse() async {
    setState(() => _busy = true);
    _settled = true;
    await widget.request.refuse();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final caller = widget.request.caller;
    // A Device that answered Discovery without announcing a name looks like an
    // empty Alias here. Its address is a better answer than a placeholder: it
    // came off the transport rather than out of the caller's mouth, so it is
    // the one thing on this window nobody chose, and it is the thing a user
    // needs to work out which machine is asking. A nameless stranger and a
    // second nameless stranger are told apart by it and by nothing else.
    final name = caller.alias.isNotEmpty
        ? caller.alias
        : widget.request.callerAddress ?? l10n.pairingRequestUnnamed;
    return AlertDialog(
      title: Text(l10n.pairingRequestTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.pairingRequestFrom(name)),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              l10n.pairingRequestClaimHint,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(l10n.pairingCompleting),
                ],
              ),
            ),
          _ErrorLine(_failure),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => unawaited(_refuse()),
          child: Text(l10n.refuse),
        ),
        FilledButton(
          onPressed: _busy ? null : () => unawaited(_accept()),
          child: Text(l10n.acceptPairing),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- pair by click

/// The initiating side of the click-to-pair flow: dial a Device the user
/// picked from the discovered list, and wait for its user to let this one in.
///
/// The window is a progress report rather than a question. Everything the user
/// had to decide they decided by tapping Pair; the only thing left is the other
/// Device's answer, and this side finishes on its own as soon as it arrives.
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
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_join());
  }

  @override
  void dispose() {
    // Closing the window while the other user is still deciding leaves the
    // dial running — there is no handle to call it off — but nothing is
    // written on either side: this Device never confirms, so the peer's own
    // confirmation times out and its half of the Pairing is abandoned. The
    // attempt is cancelled the moment it turns up, which closes the link
    // immediately rather than waiting for that timeout.
    if (!_settled) unawaited(_attempt?.cancel());
    super.dispose();
  }

  /// Dials, then finishes the Pairing without asking for anything.
  ///
  /// Nothing else is left for the user to do: the other Device's user is the
  /// one with a question on screen, and this side confirms as soon as that
  /// question is answered, because waiting for a second tap on a comparison
  /// nobody needs would be a step that only exists to be clicked through.
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
    final PairingAttempt attempt;
    try {
      attempt = await widget.controller.pairWith(host: address);
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
      return;
    }
    if (!mounted) {
      unawaited(attempt.cancel());
      return;
    }
    _attempt = attempt;
    try {
      await attempt.confirm();
      _settled = true;
      final peerFingerprint = attempt.peer.fingerprint;
      // The Session is what the user is here for, so it is opened now, while
      // the Pairing that allows it is the thing on screen. This side asked for
      // the Pairing, so this side opens the Session — unconditionally, because
      // it is the only side that knows a Session is wanted at all, and because
      // [connectAfterPairing] retries through the window where the peer has not
      // re-announced the port yet. The two people who tap Connect at the same
      // moment are the one case with two diallers; there the answering side
      // stands down instead, which is what [_dialsFirst] is for.
      try {
        await widget.controller.connectAfterPairing(peerFingerprint);
      } on Object {
        // Deliberately swallowed: the Session is a tap away on the row the user
        // pressed, and reporting it here would read as the Pairing having
        // failed when it has not.
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.connectToPeerTitle(widget.peer.displayName)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_failure == null)
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
          _ErrorLine(_failure),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
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

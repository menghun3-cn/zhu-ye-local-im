import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../conversation_view.dart';
import '../dialogs.dart';
import '../feedback.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../widgets.dart';

/// Every conversation this Device has, beside the one being read.
///
/// Arranged the way a messenger is — a list on the left, the conversation on
/// the right — rather than as a table of Devices you have to open something
/// from first. That is the point of the surface: a Session coming up *is* a
/// conversation starting, so a Device that connects appears here on its own,
/// with nothing to press.
///
/// And a Device that has merely been *found* appears here too, with the one
/// button that starts a conversation on its row. Connecting a Device is not a
/// thing done to a Device; it is the first line of a conversation, so the whole
/// gesture lives on this surface and the Devices surface is left to describe
/// what is on the network.
///
/// Who is in the list is deliberately not just "who is connected". A
/// conversation outlives its Session — the messages are still there after the
/// link drops, and a list that emptied itself the moment a Device went quiet
/// would hide the thing the user came to read. So a peer shows up if it has
/// something to show and stays as long as it does: connected now, or holding
/// history, or holding an offer nobody has answered yet.
class ConversationsPage extends StatefulWidget {
  /// Shows every conversation, opening with [requestedPeer] selected if given.
  const ConversationsPage({
    super.key,
    this.defaultIncomingDirectory,
    this.requestedPeer,
  });

  /// Where a file received here lands when the user has not said otherwise.
  final String? defaultIncomingDirectory;

  /// A conversation to open when the user arrives from somewhere else.
  ///
  /// The shell sets this when the Devices surface asks for a conversation — the
  /// whole point being that connecting and talking are one action — and clears
  /// it once it has been honoured, so that coming back here later opens with
  /// whatever the user last picked rather than with a stale instruction.
  final Fingerprint? requestedPeer;

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  /// The peer being read, by Fingerprint hex. Null until one is picked.
  ///
  /// Held as a hex string rather than a [Fingerprint] so that a peer that
  /// leaves the list and comes back keeps its selection: the row was rebuilt,
  /// the identity did not change.
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.requestedPeer?.hex;
  }

  @override
  void didUpdateWidget(ConversationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new request wins over whatever was selected: it is the user having just
    // asked for a particular conversation, which is not something a previous
    // selection may outvote. A cleared one is not a request to close anything.
    final requested = widget.requestedPeer;
    if (requested != null && requested != oldWidget.requestedPeer) {
      setState(() => _selected = requested.hex);
    }
  }

  /// A conversation worth a row.
  ///
  /// The pair of a peer and what makes it listable — kept together because the
  /// list is sorted by name, and a name comes from the peer while the reason
  /// comes from the history.
  List<_Conversation> _conversationsOf(LocalTransferController controller) {
    // Peers are the spine, not the transfers: a peer that is connected but has
    // never exchanged anything still belongs here, because the first thing a
    // user does with a live Session is type into it.
    //
    // Every peer Discovery knows about is listed, connected or not. A Device
    // that has been found but not dialled is a conversation the user has not
    // started yet, and the row carries the Connect button that starts it — so
    // this list is where a Device first appears, and the Devices surface is
    // where the things that are not conversations live. A peer with neither an
    // address nor a port is still listed: it has been heard, and a row saying
    // "not accepting Sessions" with no button on it is the honest reading of
    // what was heard.
    final entries = <_Conversation>[];
    for (final peer in controller.peers) {
      final history = controller.transfers
          .where(
            (view) =>
                view.peer == peer.fingerprint &&
                view.kind != PayloadKind.clipboard,
          )
          .toList();
      final waiting = history.where((view) => view.needsDecision).isNotEmpty;
      entries.add(
        _Conversation(peer: peer, history: history, waiting: waiting),
      );
    }
    entries.sort((a, b) {
      // Connected first, then whoever is waiting on an answer, then by name:
      // the two things a user acts on lead, and the rest is alphabetical.
      if (a.peer.isConnected != b.peer.isConnected) {
        return a.peer.isConnected ? -1 : 1;
      }
      if (a.waiting != b.waiting) return a.waiting ? -1 : 1;
      return a.peer.displayName.toLowerCase().compareTo(
        b.peer.displayName.toLowerCase(),
      );
    });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    final conversations = _conversationsOf(controller);

    // A selection that is no longer in the list is dropped rather than kept as
    // a dangling pane: showing a conversation the list no longer offers would
    // leave the header unable to say what it is.
    _Conversation? selected;
    for (final entry in conversations) {
      if (entry.peer.fingerprint.hex == _selected) {
        selected = entry;
        break;
      }
    }

    final wide = MediaQuery.sizeOf(context).width >= 720;

    if (conversations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: HintText(l10n.conversationListEmpty),
      );
    }

    // Narrow windows get the list and then the conversation, one at a time:
    // two panes at 400 logical pixels each would leave neither readable.
    if (!wide) {
      final current = selected;
      if (current == null) {
        return _list(context, l10n, conversations, selected: null);
      }
      return Column(
        children: [
          _PaneHeader(
            title: current.peer.displayName,
            subtitle: _subtitleFor(current.peer, l10n),
            onBack: () => setState(() => _selected = null),
            offline: !current.peer.isConnected,
          ),
          Expanded(
            child: ConversationView(
              key: ValueKey(current.peer.fingerprint.hex),
              peer: current.peer.fingerprint,
              defaultIncomingDirectory: widget.defaultIncomingDirectory,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 300,
          child: _list(context, l10n, conversations, selected: selected),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: HintText(l10n.conversationPickOne),
                )
              : ConversationView(
                  // Keyed by peer so switching conversations rebuilds the
                  // composer and the scroll position rather than carrying the
                  // previous one's over.
                  key: ValueKey(selected.peer.fingerprint.hex),
                  peer: selected.peer.fingerprint,
                  defaultIncomingDirectory: widget.defaultIncomingDirectory,
                  header: _PaneHeader(
                    title: selected.peer.displayName,
                    // The address, and — when the Session has gone — that it
                    // has. A conversation outlives its Session, so this is the
                    // only place that says whether typing here would reach
                    // anybody, and a pane that looked the same either way would
                    // be inviting a message into a void.
                    subtitle: _subtitleFor(selected.peer, l10n),
                    offline: !selected.peer.isConnected,
                  ),
                ),
        ),
      ],
    );
  }

  /// What the pane header says under the name.
  ///
  /// The address, always: it is the answer to "which machine is this". Then,
  /// only when the Session has gone, that it has gone — because a conversation
  /// outlives its Session, and a header that looked identical either way would
  /// be inviting a message into a void.
  String _subtitleFor(PeerView peer, AppLocalizations l10n) {
    final address = describePeerAddress(peer, l10n);
    if (peer.isConnected) return address;
    return '$address · ${l10n.conversationDisconnected}';
  }

  /// The list of conversations, with [selected] marked when it is present.
  Widget _list(
    BuildContext context,
    AppLocalizations l10n,
    List<_Conversation> conversations, {
    required _Conversation? selected,
  }) {
    return ListView.builder(
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final entry = conversations[index];
        return _ConversationTile(
          entry: entry,
          l10n: l10n,
          selected:
              entry.peer.fingerprint.hex == selected?.peer.fingerprint.hex,
          controller: ControllerScope.of(context),
          onTap: () => setState(() => _selected = entry.peer.fingerprint.hex),
        );
      },
    );
  }
}

/// One peer, and the reason it has a row.
class _Conversation {
  const _Conversation({
    required this.peer,
    required this.history,
    required this.waiting,
  });

  /// The Device on the other end.
  final PeerView peer;

  /// Everything exchanged with it, newest first, clipboard aside.
  final List<TransferView> history;

  /// Whether something from this peer is waiting on an answer.
  final bool waiting;

  /// The last thing said, for the one-line summary a row shows.
  TransferView? get latest => history.isEmpty ? null : history.first;

  /// Whether this is a conversation the user could open right now.
  ///
  /// A Session is what makes a conversation a place to type; without one there
  /// is nothing on the other pane but the history, and the row's job is to
  /// offer the button that opens it.
  bool get isLive => peer.isConnected;
}

/// A row in the conversation list: who it is, where it got to, and what can be
/// done with it.
///
/// This row carries the whole of connecting. A found Device appears here before
/// anybody has done anything about it, and the one button that matters is on
/// the row: Connect when there is an address to dial and a group to dial into,
/// Pair when the Device is not in the group yet — pairing is how a Device gets
/// in — and nothing when there is neither, because a button that can only fail
/// is worse than no button.
///
/// The facts are read the same way the Devices card reads them, so the two
/// surfaces cannot disagree about what a row is offering.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.entry,
    required this.l10n,
    required this.selected,
    required this.controller,
    required this.onTap,
  });

  final _Conversation entry;
  final AppLocalizations l10n;
  final bool selected;

  /// Used to dial, and to open the pairing window. The tile is the only place a
  /// Session is started from, so it needs the controller and not just the view.
  final LocalTransferController controller;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peer = entry.peer;
    final latest = entry.latest;
    // Dialling needs both an address to dial and a peer in the group: a Device
    // from somebody else's group would fail the handshake, so offering the
    // button would be offering a failure. Pairing needs only an address — the
    // whole point of it is to bring a Device that is not in the group in.
    final canConnect = peer.isDiallable && peer.isInGroup;
    final canPair = !peer.isInGroup && peer.address != null;
    return ListTile(
      selected: selected,
      onTap: onTap,
      leading: CircleAvatar(child: Icon(iconForConversation())),
      // The name and the address, which is what a conversation is called here:
      // a name can be claimed by anyone, the address is where it actually is.
      title: Text(peer.displayName, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        describePeerAddress(peer, l10n),
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: _trailing(context, peer, latest, canConnect, canPair),
      isThreeLine: false,
    );
  }

  /// What sits at the end of the row: the action when there is one to take, and
  /// otherwise how the last exchange went.
  ///
  /// A connected peer has no reconnect button — the Session is up, and pressing
  /// again would be refused as a second one — so the row falls back to the last
  /// Transfer's state, which is what a messenger puts there.
  Widget? _trailing(
    BuildContext context,
    PeerView peer,
    TransferView? latest,
    bool canConnect,
    bool canPair,
  ) {
    if (!peer.isConnected && (canConnect || canPair)) {
      return Tooltip(
        message: canConnect
            ? l10n.openSession
            : canPair
            ? l10n.pairWithThisDevice
            : '',
        child: canConnect
            ? FilledButton.tonal(
                onPressed: () => guarded(context, () => _connect(context)),
                child: Text(l10n.connect),
              )
            : TextButton(
                onPressed: () =>
                    showPairWithPeerDialog(context, controller, peer),
                child: Text(l10n.pair),
              ),
      );
    }
    if (entry.waiting) {
      return Badge(
        label: const Icon(Icons.download, size: 12),
        backgroundColor: Theme.of(context).colorScheme.error,
        child: const SizedBox(width: 24),
      );
    }
    if (latest == null) {
      // Nothing to report and nothing to press: a found Device this one is
      // already in a group with but cannot reach says as much as it can.
      return peer.isConnected
          ? null
          : Text(
              peer.isDiallable
                  ? l10n.nothingKnownAboutPeer
                  : l10n.nothingToDialYet,
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            );
    }
    return Text(
      labelForState(latest.state, l10n),
      style: Theme.of(context).textTheme.labelSmall,
    );
  }

  /// Opens a Session. The conversation is already selected here, because this
  /// row only ever appears in the list the user is looking at.
  ///
  /// A dial that fails throws through [guarded], which reports it, and nothing
  /// moves: the row stays where it was, still offering the same button.
  Future<void> _connect(BuildContext context) async {
    await controller.connect(entry.peer.fingerprint);
  }
}

/// The strip above a conversation in the shell, standing in for an [AppBar].
class _PaneHeader extends StatelessWidget {
  const _PaneHeader({
    required this.title,
    this.subtitle,
    this.onBack,
    this.offline = false,
  });

  final String title;
  final String? subtitle;

  /// Shown as a leading back button on a narrow window, where the list and the
  /// conversation are the same screen.
  final VoidCallback? onBack;

  /// Whether to mark the peer as unreachable. Drawn as a muted icon beside the
  /// name rather than as colour alone, so that it reads without colour vision.
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(
          children: [
            if (onBack != null)
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (offline) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.link_off,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

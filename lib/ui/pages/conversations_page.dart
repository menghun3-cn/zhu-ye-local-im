import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../conversation_view.dart';
import '../dialogs.dart';
import '../feedback.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../wechat/bubble.dart';
import '../wechat/theme.dart';
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
        Container(
          width: WeChat.conversationListWidth,
          color: WeChat.sidebarBackground,
          child: _list(context, l10n, conversations, selected: selected),
        ),
        const VerticalDivider(width: 1, color: WeChat.divider),
        Expanded(
          child: selected == null
              // The pane a conversation would open into, so it wears the
              // conversation's own white rather than the page's grey.
              ? ColoredBox(
                  color: WeChat.conversationBackground,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: HintText(l10n.conversationPickOne),
                  ),
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
    final peer = entry.peer;
    final latest = entry.latest;
    // Dialling needs both an address to dial and a peer in the group: a Device
    // from somebody else's group would fail the handshake, so offering the
    // button would be offering a failure. Pairing needs only an address — the
    // whole point of it is to bring a Device that is not in the group in.
    final canConnect = peer.isDiallable && peer.isInGroup;
    final canPair = !peer.isInGroup && peer.address != null;
    // The top-right corner is the clock, where the desktop client puts it: the
    // time the last thing was said, or — for a conversation nobody has said
    // anything in yet — when the Device was last heard from.
    final stamp = _stampFor(peer, latest);
    // Under it, the one thing there is to press, or else how the last exchange
    // went. Never both: a row holds two lines and no more, and two answers to
    // "what is this conversation doing" would neither fit nor agree.
    final lower =
        _actionFor(context, peer, canConnect, canPair) ??
        _summary(context, peer, latest);

    return ConversationRow(
      selected: selected,
      onTap: onTap,
      // The name is handed down so a test can name one row and reach only it.
      // Without it a finder for "Connect" would match every row on the list,
      // and the harness that drives these surfaces has to be able to say *which*
      // conversation it means.
      peer: peer.displayName,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WeChat.conversationRowPadding,
          vertical: WeChat.conversationRowVPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // The one Device drawn from something other than the first letter
            // of its name: a Device named by its address carries its last octet
            // in the circle, because `1` is what every address starts with.
            Avatar(
              name: peer.displayName,
              seed: peer.fingerprint.hex,
              label: peer.avatarLabel,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    peer.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: WeChat.fontSizeTitle,
                      color: WeChat.bubbleText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _previewFor(peer, latest),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: WeChat.fontSizePreview,
                      color: WeChat.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Bounded, because the fallback summary is a whole sentence
            // ("Not accepting Sessions", or the address) and an unbounded one
            // in a fixed-width row overflows instead of ellipsising. A third
            // of the row is enough for a clock or a state word and leaves
            // the name the room it needs.
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: WeChat.conversationListWidth * 0.42,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (stamp != null)
                    Text(
                      stamp,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: WeChat.fontSizeMeta,
                        color: WeChat.secondaryText,
                      ),
                    ),
                  if (lower != null) ...[
                    if (stamp != null) const SizedBox(height: 2),
                    lower,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The time in a row's top-right corner.
  ///
  /// The last thing said, when anything has been said; otherwise when the
  /// Device was last heard from, so that a conversation that has been picked
  /// but not yet held still carries a time rather than a blank corner.
  ///
  /// Relative ("3 分钟前") rather than a clock face, because that is what every
  /// other surface in this application says about time, and a list that
  /// switched to `14:07` here would be the one place a user has to decode.
  String? _stampFor(PeerView peer, TransferView? latest) {
    final when = latest?.at ?? peer.lastSeen;
    if (when == null) return null;
    return describeLastSeen(when, l10n);
  }

  /// What the row says under the name: the last thing said, or where the peer
  /// is reachable.
  ///
  /// A conversation with no history still needs a second line — a row of one
  /// line is a different height from its neighbours and the list looks broken —
  /// so it falls back to the address, which is also the answer to "which
  /// machine is this".
  String _previewFor(PeerView peer, TransferView? latest) {
    final last = latest;
    if (last == null) return describePeerAddress(peer, l10n);
    final text = last.text;
    if (last.kind == PayloadKind.text && text != null && text.isNotEmpty) {
      // A newline in a preview would make the row taller than its neighbours.
      return text.replaceAll(RegExp(r'\s+'), ' ');
    }
    if (last.kind == PayloadKind.image) {
      return last.names.isEmpty
          ? l10n.kindImages
          : '[${l10n.kindImages}] ${last.names.first}';
    }
    if (last.names.isNotEmpty) return last.names.first;
    return labelForKind(last.kind, l10n);
  }

  /// The row's action button, when it has one.
  ///
  /// A connected peer has no reconnect button — the Session is up, and pressing
  /// again would be refused as a second one.
  Widget? _actionFor(
    BuildContext context,
    PeerView peer,
    bool canConnect,
    bool canPair,
  ) {
    if (peer.isConnected || !(canConnect || canPair)) return null;
    return Tooltip(
      message: canConnect ? l10n.openSession : l10n.pairWithThisDevice,
      child: canConnect
          ? _RowAction(
              label: l10n.connect,
              primary: true,
              onPressed: () => guarded(context, () => _connect(context)),
            )
          : _RowAction(
              label: l10n.pair,
              primary: false,
              onPressed: () =>
                  showPairWithPeerDialog(context, controller, peer),
            ),
    );
  }

  /// What sits at the end of the row when there is nothing to press: how the
  /// last exchange went, or a badge when something is waiting to be let in.
  Widget? _summary(BuildContext context, PeerView peer, TransferView? latest) {
    if (entry.waiting) {
      return Badge(
        label: const Icon(Icons.download, size: 12),
        backgroundColor: WeChat.danger,
        child: const SizedBox(width: 24),
      );
    }
    if (latest == null) {
      // Nothing to report and nothing to press: a found Device this one is
      // already in a group with but cannot reach says as much as it can.
      if (peer.isConnected) return null;
      return Text(
        peer.isDiallable ? l10n.nothingKnownAboutPeer : l10n.nothingToDialYet,
        style: const TextStyle(
          fontSize: WeChat.fontSizeMeta,
          color: WeChat.secondaryText,
        ),
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
      );
    }
    return Text(
      labelForState(latest.state, l10n),
      style: const TextStyle(
        fontSize: WeChat.fontSizeMeta,
        color: WeChat.secondaryText,
      ),
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

/// A row that answers the mouse the way the desktop client's list does.
///
/// [ListTile] is not used here because its selected and hover colours come from
/// the colour scheme, and the scheme's colours are the seed's, not WeChat's —
/// the whole point of this list is that a hovered row is `#E9E9E9` and a
/// selected one is `#C9C9C9`, both of which the scheme has no slot for.
///
/// Public, and named by [peer], so that the widget tests can find one row and
/// not its neighbours. `find.widgetWithText(ListTile, name)` used to do that
/// job; this is the type that does it now.
class ConversationRow extends StatefulWidget {
  const ConversationRow({
    super.key,
    required this.peer,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  /// What this row is called, for a finder to name it by.
  final String peer;

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends State<ConversationRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colour = widget.selected
        ? WeChat.listSelected
        : _hovered
        ? WeChat.listHover
        : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: colour,
          // The row sizes to its content — the avatar, or the two lines of
          // text beside it, whichever is taller — rather than to a number
          // somebody guessed. A fixed height had to be re-guessed every time a
          // font size moved, and was wrong in between.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.child,
              // The hairline between two conversations. Inset so that it
              // begins at the avatar's left edge rather than at the row's: a
              // full-bleed line would cut the list into blocks, and the
              // WeChat list reads as one surface with its rows merely
              // separated. The row paints it rather than the list, because
              // only the row knows the inset its own padding produced.
              const Padding(
                padding: EdgeInsets.only(left: WeChat.conversationRowPadding),
                child: Divider(height: 1, thickness: 1, color: WeChat.divider),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small entry that starts a conversation, on the row of a Device that is
/// not in one yet.
///
/// A [TextButton] carrying a dot and a word, rather than a filled pill: a
/// filled button is the loudest thing Material draws, and a list of found
/// Devices would be a column of them. The desktop client marks "you can act
/// here" with a spot of colour and a word, which is what this is — the dot is
/// in the brand green for the straightforward action (connect) and grey for
/// the one that needs the peer's consent first (pair).
///
/// Still a [TextButton] and not a hand-rolled `GestureDetector`: a hand-rolled
/// one would look the same and behave worse — no focus ring, no keyboard
/// activation, no `Tooltip` semantics — and the row has to stay reachable
/// without a mouse.
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.label,
    required this.primary,
    required this.onPressed,
  });

  final String label;

  /// Whether this is the straightforward action. Only the colour differs.
  final bool primary;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colour = primary ? WeChat.brand : WeChat.secondaryText;
    final style = ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStatePropertyAll(colour),
      overlayColor: const WidgetStatePropertyAll(WeChat.listHover),
      // Square-ish and small: a row is only two lines tall, and a
      // Material-default button would fill a third of it.
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(WeChat.controlRadius)),
        ),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: WeChat.fontSizeMeta),
      ),
    );
    return TextButton(
      onPressed: onPressed,
      style: style,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
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
    final subtitle = this.subtitle;
    return Material(
      color: WeChat.toolbarBackground,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: WeChat.divider)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(
          children: [
            if (onBack != null)
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                color: WeChat.secondaryText,
                visualDensity: VisualDensity.compact,
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
                          style: const TextStyle(
                            fontSize: WeChat.fontSizeTitle,
                            color: WeChat.bubbleText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (offline) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.link_off,
                          size: 16,
                          color: WeChat.secondaryText,
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: WeChat.fontSizeMeta,
                        color: WeChat.secondaryText,
                      ),
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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../conversation_menu.dart';
import '../controller_scope.dart';
import '../conversation_view.dart';
import '../feedback.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../presence.dart';
import '../wechat/bubble.dart';
import '../wechat/splitter.dart';
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
    this.focusRequest = 0,
    this.isVisible = true,
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

  /// How many times the user has been brought to this surface.
  ///
  /// Counted by the shell, which is the only thing that knows a tab was
  /// pressed. A change in it means the user just asked for this surface, and
  /// the answer to that is a composer ready to type in — the alternative is a
  /// second click on the box for every arrival. A counter rather than a bool
  /// so that arriving twice asks twice.
  final int focusRequest;

  /// Whether this surface is the one the shell is showing.
  ///
  /// The page stays mounted in the shell's `IndexedStack` while another
  /// surface is in front, so its `build` running is not the same thing as
  /// somebody looking at it. Read marks are gated on this: a conversation
  /// that receives a message while the user is elsewhere is still unread,
  /// and the row keeps counting it; coming back to this surface is what
  /// reads it.
  final bool isVisible;

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  final TextEditingController _search = TextEditingController();

  /// The peer being read, by Fingerprint hex. Null until one is picked.
  ///
  /// Held as a hex string rather than a [Fingerprint] so that a peer that
  /// leaves the list and comes back keeps its selection: the row was rebuilt,
  /// the identity did not change.
  String? _selected;

  /// Whether [_selected] is still the "nothing picked yet" state.
  ///
  /// The distinction this exists for: a user who tapped the *first* row's
  /// conversation and a user who has picked nothing at all are different, and
  /// only the second should be handed the remembered conversation. Without it
  /// the remembered peer would be restored on top of every arrival at this
  /// surface, undoing a choice the user made and then navigated away from.
  bool _untouched = true;

  /// Set for one frame when the composer should take focus.
  ///
  /// A flag rather than a direct `FocusNode` held here, because the field
  /// lives inside [ConversationView] — which is keyed by peer and rebuilt
  /// whenever the selection changes — and a node held out here would be the
  /// wrong one the moment the user opened a different conversation. The flag
  /// travels down as `autoFocusComposer`, and the view's composer answers the
  /// false→true edge. It comes back down in a post-frame callback: the edge is
  /// what triggers the request, so a flag left standing would make the *next*
  /// arrival a no-op.
  bool _focusComposer = false;

  /// Peers the user has explicitly deleted from this list.
  ///
  /// Kept as a session-local set: deleting an offline conversation removes
  /// the row, and the row comes back the moment Discovery hears the peer
  /// again or a Session opens. An online or diallable peer stays listed with
  /// its history cleared, because Discovery would place it back anyway.
  final Set<String> _deletedPeers = {};

  /// How wide the conversation list is, in logical pixels.
  ///
  /// The width the user has dragged it to, or [WeChat.conversationListWidth]
  /// until they drag it. Held as a number rather than as a share of the
  /// window, because the list has a width a person can recognise — the same
  /// 300 pixels on every screen — and a share would make the list wider on
  /// a wide screen for no reason the user asked for.
  ///
  /// The *drawn* width is not this number: it is this number after
  /// [_clampedListWidth] has applied the window's own limits. Keeping the
  /// user's choice here and the limits there is what lets a window that
  /// shrinks give the room back without throwing the choice away.
  double _listWidth = WeChat.conversationListWidth;

  @override
  void initState() {
    super.initState();
    _selected = widget.requestedPeer?.hex;
    _untouched = widget.requestedPeer == null;
    // The shell starts on this surface, so the first visible frame can already
    // be an arrival with a remembered conversation in it. The shell counts
    // that arrival; answer it here as well as in [didUpdateWidget], otherwise
    // the default conversation would need a trip to another tab before its
    // composer became ready to type in.
    _focusComposer = widget.isVisible && widget.focusRequest > 0;
  }

  @override
  void didUpdateWidget(ConversationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new request wins over whatever was selected: it is the user having just
    // asked for a particular conversation, which is not something a previous
    // selection may outvote. A cleared one is not a request to close anything.
    final requested = widget.requestedPeer;
    if (requested != null && requested != oldWidget.requestedPeer) {
      setState(() {
        _selected = requested.hex;
        _untouched = false;
      });
    }
    // The user has just been brought here, so the composer takes the caret.
    // Only the *arrival* asks — a controller tick that rebuilds this page
    // while the user reads elsewhere must not pull the caret out of whatever
    // they are doing, which is why this is an edge and not a state.
    if (widget.focusRequest != oldWidget.focusRequest) {
      setState(() => _focusComposer = true);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      // A peer the user explicitly deleted stays out of the list only while
      // it is genuinely gone. Discovery hearing it again is what brings the
      // row back — an address and a Session port are the proof the Device is
      // there, so a deleted row that is merely remembered is hidden, while
      // one that has been re-found is shown.
      if (_deletedPeers.contains(peer.fingerprint.hex) &&
          !peer.isConnected &&
          !peer.isDiallable) {
        continue;
      }

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
    final colors = WeChatColors.of(context);
    final controller = ControllerScope.of(context);
    final conversations = _conversationsOf(controller);

    // What the pane opens with: the conversation the user asked for, or the one
    // they were last in. Arriving at this surface is coming back to a
    // conversation, not to a form — a messenger that showed a blank pane beside
    // a list of your conversations would be making the user pick one they
    // already picked, every single time they came back.
    //
    // The remembered peer is only a *fallback*: once the user has tapped a row
    // or a request has arrived, [_untouched] is false and this stops applying,
    // so a choice made in this sitting is never overwritten by an older one.
    final remembered = _untouched && _selected == null
        ? controller.lastConversation?.hex
        : null;
    final wanted = _selected ?? remembered;

    // A selection that is no longer in the list is dropped rather than kept as
    // a dangling pane: showing a conversation the list no longer offers would
    // leave the header unable to say what it is.
    _Conversation? selected;
    for (final entry in conversations) {
      if (entry.peer.fingerprint.hex == wanted) {
        selected = entry;
        break;
      }
    }
    final current = selected;

    // The arrival's focus request is answered on this frame and taken back on
    // the next: the composer asks for focus on the false→true edge, so the
    // flag has to come down again or the following arrival would find it
    // already true and ask for nothing.
    final focusComposer = _focusComposer;
    if (focusComposer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _focusComposer = false);
      });
    }

    // Whatever conversation is on screen while this surface is the visible
    // one has been read. That covers more than a tap on a row: opening from
    // Devices arrives through [requestedPeer], arriving back through the rail
    // leaves the previous selection in place, and a message that lands while
    // the conversation is already open changes none of the selection state at
    // all. In every one of those cases the user can see the message, so the
    // count has to clear here rather than waiting for another tap on the row.
    //
    // Deferred past the frame because this is `build`, and marking writes to
    // the conversation file. `isVisible` is re-read when the callback runs, so
    // a switch away before it fires does not mark a conversation nobody is
    // looking at.
    if (current != null && widget.isVisible) {
      final peer = current.peer.fingerprint;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isVisible) {
          unawaited(controller.markConversationOpened(peer));
        }
      });
    }

    final wide = MediaQuery.sizeOf(context).width >= 720;

    // Narrow windows get the list and then the conversation, one at a time:
    // two panes at 400 logical pixels each would leave neither readable.
    if (!wide) {
      if (current == null) {
        return _list(context, l10n, conversations, selected: null);
      }
      return Column(
        children: [
          _PaneHeader(
            title: current.peer.displayName,
            subtitle: _subtitleFor(current.peer, l10n),
            peer: current.peer.fingerprint,
            onBack: () => setState(() {
              _selected = null;
              _untouched = false;
            }),
            offline: !current.peer.isConnected,
          ),
          Expanded(
            child: ConversationView(
              key: ValueKey(current.peer.fingerprint.hex),
              peer: current.peer.fingerprint,
              defaultIncomingDirectory: widget.defaultIncomingDirectory,
              autoFocusComposer: focusComposer,
            ),
          ),
        ],
      );
    }

    // The two panes share whatever this surface is given, and the split
    // between them is the user's to make.
    //
    // The width is *measured* rather than derived from the window: this
    // surface does not know how much of the window the shell has already
    // taken for its rail, and subtracting a known constant for it is a
    // guess that a change to the shell would silently invalidate. The
    // [LayoutBuilder] says what the two panes actually have between them,
    // which is the only number the list's bounds are derived from.
    return LayoutBuilder(
      builder: (context, constraints) {
        // The room the list may grow into, before the conversation is
        // squeezed: the width the two panes share, less the splitter between
        // them, less what the conversation needs to keep.
        final room =
            constraints.maxWidth -
            WeChat.splitterWidth -
            WeChat.conversationPaneMinWidth;
        return Row(
          children: [
            Container(
              width: _clampedListWidth(room),
              color: colors.sidebarBackground,
              child: _list(context, l10n, conversations, selected: current),
            ),
            // The line between the panes, which the user drags to move it. It
            // stands where the divider was, and it *is* the divider: what it
            // draws is the same hairline, so a surface that is not being
            // resized looks exactly as it did before the splitter existed.
            PaneSplitter(
              enabled: room > WeChat.conversationListMinWidth,
              onDrag: (delta) => setState(() => _listWidth += delta),
            ),
            Expanded(
              child: current == null
                  // The pane a conversation would open into, so it wears the
                  // conversation's own white rather than the page's grey.
                  ? ColoredBox(
                      color: colors.conversationBackground,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: HintText(l10n.conversationPickOne),
                      ),
                    )
                  : ConversationView(
                      // Keyed by peer so switching conversations rebuilds the
                      // composer and the scroll position rather than carrying
                      // the previous one's over.
                      key: ValueKey(current.peer.fingerprint.hex),
                      peer: current.peer.fingerprint,
                      defaultIncomingDirectory: widget.defaultIncomingDirectory,
                      autoFocusComposer: focusComposer,
                      header: _PaneHeader(
                        title: current.peer.displayName,
                        // The address, and — when the Session has gone — that
                        // it has. A conversation outlives its Session, so this
                        // is the only place that says whether typing here
                        // would reach anybody, and a pane that looked the same
                        // either way would be inviting a message into a void.
                        subtitle: _subtitleFor(current.peer, l10n),
                        peer: current.peer.fingerprint,
                        offline: !current.peer.isConnected,
                      ),
                    ),
            ),
          ],
        );
      },
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
    return '$address · '
        '${peer.isConnecting ? l10n.connectingAutomatically : l10n.conversationDisconnected}';
  }

  /// How wide the list is drawn, once every limit is applied.
  ///
  /// The width the user dragged it to, held to three bounds:
  ///
  /// - the list's own floor ([WeChat.conversationListMinWidth]), because a
  ///   list narrower than that cannot show a name and a preview;
  /// - the list's own ceiling ([WeChat.conversationListMaxWidth]), because
  ///   there is no second thing to put in the space;
  /// - and what the **conversation** still needs, which is the bound that
  ///   matters when the window is small.
  ///
  /// That last one is the one worth arguing for. A list dragged to 480
  /// pixels in an 800-pixel window would leave the conversation 300 pixels
  /// of which the rail has already taken 84 — the messages would be a
  /// two-word column. The conversation is what this surface is *for*, so it
  /// is the list that gives way.
  ///
  /// All three live here and nowhere else. The drag itself does not clamp:
  /// a clamp in the drag handler and a clamp at the draw site are two rules
  /// that can disagree, and a test that breaks one of them would then be
  /// testing the other.
  ///
  /// [room] is what the two panes have between them, less what the
  /// conversation needs to keep — measured by the caller, which is where the
  /// two panes' actual width is known.
  double _clampedListWidth(double room) {
    final ceiling = math.min(WeChat.conversationListMaxWidth, room);
    return _listWidth.clamp(
      WeChat.conversationListMinWidth,
      // A window too narrow to hold the list's floor and the conversation's
      // minimum at once: the floor wins, because the list is the pane the
      // user is looking at and the conversation is already at its minimum.
      ceiling < WeChat.conversationListMinWidth
          ? WeChat.conversationListMinWidth
          : ceiling,
    );
  }

  /// The list of conversations, with [selected] marked when it is present.
  Widget _list(
    BuildContext context,
    AppLocalizations l10n,
    List<_Conversation> conversations, {
    required _Conversation? selected,
  }) {
    final controller = ControllerScope.of(context);
    final query = _search.text.trim();
    final visible = _searchConversations(conversations, query);
    final colors = WeChatColors.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: WeChat.fontSizeInput),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colors.surfaceSunken,
              hintText: l10n.searchConversations,
              prefixIcon: const Icon(Icons.search, size: 19),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.clearSearch,
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(WeChat.controlRadius),
                borderSide: BorderSide(color: colors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(WeChat.controlRadius),
                borderSide: BorderSide(color: colors.brandStrong),
              ),
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: HintText(
                    query.isEmpty
                        ? l10n.conversationListEmpty
                        : l10n.conversationSearchEmpty,
                  ),
                )
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final entry = visible[index];
                    return _ConversationTile(
                      entry: entry,
                      l10n: l10n,
                      selected:
                          entry.peer.fingerprint.hex ==
                          selected?.peer.fingerprint.hex,
                      unread: controller.unreadCount(entry.peer.fingerprint),
                      controller: controller,
                      onContextMenu: (position) => _showConversationMenu(
                        context,
                        entry.peer.fingerprint,
                        position,
                      ),
                      onTap: () => _open(entry.peer.fingerprint),
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<_Conversation> _searchConversations(
    List<_Conversation> conversations,
    String query,
  ) {
    if (query.isEmpty) return conversations;
    final needle = query.toLowerCase();
    final answer = <_Conversation>[];
    for (final entry in conversations) {
      final nameMatches =
          _titleFor(entry.peer).toLowerCase().contains(needle) ||
          entry.peer.displayName.toLowerCase().contains(needle);
      TransferView? matched;
      for (final view in entry.history) {
        final text = view.text?.toLowerCase();
        final named = view.names.any(
          (name) => name.toLowerCase().contains(needle),
        );
        if ((text != null && text.contains(needle)) || named) {
          matched = view;
          break;
        }
      }
      if (!nameMatches && matched == null) continue;
      answer.add(
        _Conversation(
          peer: entry.peer,
          history: entry.history,
          waiting: entry.waiting,
          preview: matched,
        ),
      );
    }
    return answer;
  }

  /// Opens [peer]'s conversation, and records that it has been read.
  ///
  /// The mark is made here rather than from the conversation's own `build`,
  /// because "the user is looking at it" is a fact about this list's selection
  /// and not about the widget below it: a conversation that was rebuilt while
  /// the user was on another surface — which the shell's `IndexedStack` does
  /// every time the controller ticks — is not being read by anybody.
  void _open(Fingerprint peer) {
    setState(() {
      _selected = peer.hex;
      // Picking a row is the user choosing where to type next. The existing
      // auto-focus edge sends the caret to the new composer without making a
      // second click necessary.
      _focusComposer = true;
    });
    unawaited(ControllerScope.of(context).markConversationOpened(peer));
  }

  /// Opens the list's context menu where the pointer or long press started.
  ///
  /// The menu is one step before the destructive action, as it is in the
  /// desktop client: a right-click opens what can be done to the row, and
  /// choosing Delete is what raises the confirmation question.
  Future<void> _showConversationMenu(
    BuildContext context,
    Fingerprint peer,
    Offset position,
  ) async {
    final l10n = AppLocalizations.of(context);
    final overlay = Overlay.of(context).context.findRenderObject();
    final size = overlay is RenderBox
        ? overlay.size
        : MediaQuery.sizeOf(context);
    final chosen = await showMenu<_ConversationListAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        size.width - position.dx,
        size.height - position.dy,
      ),
      items: [
        PopupMenuItem(
          value: _ConversationListAction.delete,
          child: Text(l10n.deleteConversation),
        ),
      ],
    );
    if (chosen != _ConversationListAction.delete || !context.mounted) return;
    await _confirmDeleteConversation(context, peer);
  }

  /// Confirms, then removes every message exchanged with [peer].
  ///
  /// Clipboard entries stay put, exactly as `clearConversation` promises.
  Future<void> _confirmDeleteConversation(
    BuildContext context,
    Fingerprint peer,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteConversationConfirmTitle),
        content: Text(l10n.deleteConversationConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.deleteConversation),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.clearConversation(peer);
      // Deleting means clearing every message exchanged with the peer. An
      // offline peer also drops out of the list, because keeping a row that
      // only history justified would just show an empty conversation. A peer
      // that is online is placed back by Discovery anyway, so its row stays
      // and only its history is cleared; the session-local marker keeps an
      // explicitly deleted peer out until Discovery hears it again.
      var offline = true;
      for (final view in controller.peers) {
        if (view.fingerprint == peer &&
            (view.isConnected || view.isDiallable)) {
          offline = false;
          break;
        }
      }
      if (offline && mounted) {
        setState(() => _deletedPeers.add(peer.hex));
      }
    }
  }
}

/// One peer, and the reason it has a row.
class _Conversation {
  const _Conversation({
    required this.peer,
    required this.history,
    required this.waiting,
    this.preview,
  });

  /// The Device on the other end.
  final PeerView peer;

  /// Everything exchanged with it, newest first, clipboard aside.
  final List<TransferView> history;

  /// Whether something from this peer is waiting on an answer.
  final bool waiting;

  /// The message a search matched, when the row is being drawn for a search.
  final TransferView? preview;

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
/// Discovery establishes group trust and connects automatically. A discovered
/// Device appears here with no admission action; Connect remains only as a
/// retry for a known member that is visibly diallable but not connected.
///
/// The facts are read the same way the Devices card reads them, so the two
/// surfaces cannot disagree about what a row is offering.
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.entry,
    required this.l10n,
    required this.selected,
    required this.unread,
    required this.controller,
    required this.onTap,
    required this.onContextMenu,
  });

  final _Conversation entry;
  final AppLocalizations l10n;
  final bool selected;

  /// How many messages from this peer the user has not read.
  ///
  /// Pushed in rather than read here, so that the count and the row it marks
  /// are decided by one caller and a test can ask for a row with any number on
  /// it without arranging a whole conversation to produce it.
  final int unread;

  /// Used to retry a Session dial. The tile needs the controller rather than
  /// only the view so that retry can call it.
  final LocalTransferController controller;

  final VoidCallback onTap;

  /// Right-tap or long-press on this row: opens its actions at [position].
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    final peer = entry.peer;
    final latest = entry.preview ?? entry.latest;
    final action = _actionFor(peer);
    final presenceLabel = labelForPeerPresence(peer, l10n);
    final presenceColour = peer.presence == PeerPresence.online
        ? colors.brandStrong
        : colors.secondaryText;
    // The top-right corner is the clock, where the desktop client puts it: the
    // time the last thing was said, or — for a conversation nobody has said
    // anything in yet — when the Device was last heard from.
    final stamp = _stampFor(peer, latest);
    // Under it, the one thing there is to press, or else how the last exchange
    // went. Never both: a row holds two lines and no more, and two answers to
    // "what is this conversation doing" would neither fit nor agree.
    final lower =
        _actionButtonFor(context, peer, action) ??
        _summary(context, peer, latest);
    // An unread row is *louder*: the name goes semibold, and the preview steps
    // up from secondary ink to body ink. That is the difference a user reads at
    // a glance — no separate dot or badge is needed, because the row itself is
    // telling, and a badge would be a third thing competing with the clock and
    // the action button already in that corner.
    final loud = unread > 0;
    final previewColour = loud ? colors.bubbleText : colors.secondaryText;

    return ConversationRow(
      selected: selected,
      onTap: onTap,
      onContextMenu: onContextMenu,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _titleFor(peer),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: WeChat.fontSizeTitle,
                            color: colors.bubbleText,
                            fontWeight: loud
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 96),
                        child: Tooltip(
                          message: presenceLabel,
                          child: Text(
                            presenceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: WeChat.railLabelSize,
                              color: presenceColour,
                              fontWeight: peer.presence == PeerPresence.online
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _previewFor(peer, latest, unread),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: WeChat.fontSizePreview,
                      color: previewColour,
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
                      style: TextStyle(
                        fontSize: WeChat.fontSizeMeta,
                        color: colors.secondaryText,
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
    // The presence line already carries last-seen for an offline peer. Keeping
    // it out of the clock column leaves that column meaning one thing: when the
    // last message moved. A connected peer with no history still gets the
    // discovery time, because there is no presence line carrying it.
    final when =
        latest?.at ??
        (peer.presence == PeerPresence.online ? peer.lastSeen : null);
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
  ///
  /// An unread conversation leads with how many are waiting: the count first,
  /// then the same preview every row has. That is what the desktop client does,
  /// and the reason is that the count answers "should I open this" while the
  /// preview answers "what is it about" — and the first question comes first.
  /// The count is a plain bracketed number rather than a red badge, because a
  /// badge belongs on an avatar where it cannot be mistaken for the message's
  /// own first characters; here it shares a line with the text, and the square
  /// brackets are what keep the two apart.
  String _previewFor(PeerView peer, TransferView? latest, int unread) {
    final preview = _summaryOf(peer, latest);
    if (unread <= 0) return preview;
    return '${l10n.conversationUnread(unread)} $preview';
  }

  /// The last thing said, with no unread prefix.
  String _summaryOf(PeerView peer, TransferView? latest) {
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

  /// What the user can do with this peer from its conversation row.
  ///
  /// Discovery establishes membership and opens the Session on its own. A
  /// Connect button remains only as a retry when a known member is visibly
  /// diallable but not connected yet; there is deliberately no Pair or Pair
  /// again action to put the user back into the old admission flow.
  _PeerAction? _actionFor(PeerView peer) {
    if (peer.isConnected) return null;
    if (peer.isInGroup && peer.isDiallable) return _PeerAction.connect;
    return null;
  }

  /// The row's action button, when it has one.
  ///
  /// A connected peer has no reconnect button — the Session is up, and pressing
  /// again would be refused as a second one.
  Widget? _actionButtonFor(
    BuildContext context,
    PeerView peer,
    _PeerAction? action,
  ) {
    if (action == null) return null;
    return Tooltip(
      message: l10n.openSession,
      child: _RowAction(
        label: l10n.connect,
        primary: true,
        onPressed: () => guarded(context, () => _connect(context)),
      ),
    );
  }

  /// What sits at the end of the row when there is nothing to press: how the
  /// last exchange went, or a badge when something is waiting to be let in.
  Widget? _summary(BuildContext context, PeerView peer, TransferView? latest) {
    final colors = WeChatColors.of(context);
    if (entry.waiting) {
      return Badge(
        label: const Icon(Icons.download, size: 12),
        backgroundColor: colors.danger,
        child: const SizedBox(width: 24),
      );
    }
    if (latest == null) {
      // Nothing to report and nothing to press: a found Device this one is
      // already in a group with but cannot reach says as much as it can.
      if (peer.isConnected) return null;
      return Text(
        peer.isConnecting
            ? l10n.connectingAutomatically
            : peer.isDiallable
            ? l10n.autoReconnectPending
            : peer.address == null
            ? l10n.nothingToDialYet
            : l10n.autoConnectingSoon,
        style: TextStyle(
          fontSize: WeChat.fontSizeMeta,
          color: colors.secondaryText,
        ),
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
      );
    }
    return Text(
      labelForState(latest.state, l10n),
      style: TextStyle(
        fontSize: WeChat.fontSizeMeta,
        color: colors.secondaryText,
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

/// The row's primary line.
///
/// The address is the fact that tells two machines apart on the local network.
/// An alias can be duplicated, while a row has only one line for identity. A
/// peer Discovery has not placed yet has no address, so its display name stays
/// as the fallback rather than leaving the row without a title.
String _titleFor(PeerView peer) {
  final address = peer.address;
  return address == null || address.isEmpty ? peer.displayName : address;
}

enum _PeerAction { connect }

enum _ConversationListAction { delete }

/// A row that answers the mouse the way the desktop client's list does.
///
/// [ListTile] is not used here because its selected and hover colours come from
/// the colour scheme, and the scheme's colours are the seed's, not this
/// design's — the whole point of this list is that a hovered row is
/// `listHover` and a selected one is `listSelected` (a soft brand tint), both
/// of which the scheme has no slot for.
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
    this.onContextMenu,
    required this.child,
  });

  /// What this row is called, for a finder to name it by.
  final String peer;

  final bool selected;
  final VoidCallback onTap;

  /// Right-tap or long-press on the row, at the pointer's global position.
  final ValueChanged<Offset>? onContextMenu;
  final Widget child;

  @override
  State<ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends State<ConversationRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    final colour = widget.selected
        ? colors.listSelected
        : _hovered
        ? colors.listHover
        : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapDown: (details) =>
            widget.onContextMenu?.call(details.globalPosition),
        onLongPressStart: (details) =>
            widget.onContextMenu?.call(details.globalPosition),
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
              Padding(
                padding: const EdgeInsets.only(
                  left: WeChat.conversationRowPadding,
                ),
                child: Divider(height: 1, thickness: 1, color: colors.divider),
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
    final colors = WeChatColors.of(context);
    final colour = primary ? colors.brandStrong : colors.secondaryText;
    final style = ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStatePropertyAll(colour),
      overlayColor: WidgetStatePropertyAll(colors.listHover),
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
        TextStyle(
          fontSize: WeChat.fontSizeMeta,
          fontFamily: WeChat.fontFamily,
          fontFamilyFallback: WeChat.fontFamilyFallback,
        ),
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
    this.peer,
    this.onBack,
    this.offline = false,
  });

  final String title;
  final String? subtitle;

  /// The conversation this header belongs to, when there is a menu to offer.
  final Fingerprint? peer;

  /// Shown as a leading back button on a narrow window, where the list and the
  /// conversation are the same screen.
  final VoidCallback? onBack;

  /// Whether to mark the peer as unreachable. Drawn as a muted icon beside the
  /// name rather than as colour alone, so that it reads without colour vision.
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    final subtitle = this.subtitle;
    return Material(
      color: colors.toolbarBackground,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(
          children: [
            if (onBack != null)
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                color: colors.secondaryText,
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
                          style: TextStyle(
                            fontSize: WeChat.fontSizeTitle,
                            color: colors.bubbleText,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (offline) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.link_off,
                          size: 16,
                          color: colors.secondaryText,
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: WeChat.fontSizeMeta,
                        color: colors.secondaryText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (peer != null)
              ConversationMenuButton(
                peer: peer!,
                color: colors.secondaryText,
                iconSize: 20,
              ),
          ],
        ),
      ),
    );
  }
}

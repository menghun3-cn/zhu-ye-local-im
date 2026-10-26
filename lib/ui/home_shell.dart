import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app.dart';
import '../core/core.dart';
import 'controller_scope.dart';
import 'l10n/generated/app_localizations.dart';
import 'nav_rail.dart';
import 'pages/about_page.dart';
import 'pages/clipboard_page.dart';
import 'pages/conversations_page.dart';
import 'pages/devices_page.dart';
import 'pages/settings_page.dart';
import 'pages/transfers_page.dart';
import 'presence.dart';
import 'seams.dart';
import 'update_notice.dart';
import 'wechat/theme.dart';

/// Where the Conversations surface sits, for the one place that has to name it.
///
/// It leads the list: talking to somebody is what the app is for, and the
/// Devices surface is what you visit to set that up, so Devices sits second.
///
/// The shell builds the pages and the destinations from the same ordered list,
/// so every index is already in the same order by construction. Only the
/// indices that machinery has to name get a constant; a full set would be five
/// names kept in step with a list for no gain.
const int _conversationsSurface = 0;

/// Where the Devices surface sits, for the presence summary's press.
const int _devicesSurface = 1;

/// Where the About surface sits, named for the one thing outside the index list
/// that has to know it.
///
/// The rail's update entry brings this surface forward: it has nowhere to *put*
/// an update — no room for a download's progress, for the question before
/// closing, or for the sentence an attempt ends in — and this card has all
/// three. Writing the index once is what keeps the entry and the About
/// destination agreeing; two spellings of it would be two chances for the entry
/// to open a surface that is not the one it thinks it is.
///
/// Named beside [_conversationsSurface] rather than beside it in a list: that
/// one is the leading surface and reads first, this one is an exception and is
/// only written by machinery.
const int _aboutSurface = 5;

/// How many of the six entries hang at the foot of the rail.
///
/// The design splits them the way a desk is split: four places to be (会话 /
/// 设备 / 传输 / 剪贴板), and then, past the space, the two things a user visits
/// to change something (设置 / 关于) — `design-preview/conversation.html` puts a
/// `.rail__spacer` between the two groups. Which entries those are follows from
/// the list's own order, so the only number the code has to write down is how
/// many come at the end.
const int _toolSurfaces = 2;

/// The six surfaces, and the way between them.
///
/// The About surface doubles as where an update is carried out. That is worth
/// stating here rather than leaving it to the About page's own documentation,
/// because it is a fact about the *shell's* indices: the rail's update entry
/// switches to it rather than leaving the application, so pressing that entry
/// moves the same selection a press on the About destination moves. The two are
/// kept in step by [_aboutSurface] being written once, which is the whole of why
/// the constant exists — see its own doc.
class HomeShell extends StatefulWidget {
  /// Shows the surfaces for [seams].
  const HomeShell({super.key, required this.seams, this.update});

  /// The platform facts a page needs but the controller does not carry —
  /// where a Transfer lands by default, and where the profile lives.
  final PlatformSeams seams;

  /// Whether a newer build has been published, when this shell was given
  /// something that knows.
  ///
  /// Held by the application rather than made here, because the question is
  /// asked once per run and this widget is rebuilt every time the controller
  /// reports a change: a notice created here would ask again on each rebuild.
  /// Nullable so that a tree assembled without one — a test that cares about
  /// something else — simply has no update entry, rather than reaching for the
  /// network to draw a rail it is not asking about.
  final UpdateNotice? update;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// The controller this shell is currently drawing.
  LocalTransferController? _controller;

  /// Unread counts change one message at a time, so the shell listens once and
  /// asks the controller for the total rather than maintaining a second count.
  StreamSubscription<void>? _changes;

  /// Native window activation, used to clear the taskbar marker.
  StreamSubscription<bool>? _windowActivity;

  bool _windowActive = true;
  bool _unreadShown = false;

  /// The conversation the user asked for from another surface, if any.
  ///
  /// The Devices surface cannot switch tabs itself — it does not know this
  /// shell exists — so it asks through a callback, and the request lands here
  /// until the Conversations surface has taken it. Connecting to a Device is
  /// the case this exists for: the user asked to talk to somebody, so the tab
  /// changes and that conversation is already open.
  Fingerprint? _requestedConversation;

  /// How many times the user has been brought to the Conversations surface.
  ///
  /// Arriving at a conversation is arriving *to type in it*: the next act is
  /// nearly always a message, and a composer that waits to be clicked first
  /// makes the user pay a click for something they already asked for. The
  /// page owns the field, so the shell cannot focus it — what it can say is
  /// "the user just asked for this surface", which is what this counter
  /// carries. A counter rather than a bool, so that asking twice asks twice:
  /// leaving the surface and coming back is a second arrival, not a repeat
  /// of the first.
  int _conversationArrivals = 0;

  /// How many times the rail's update entry has been pressed.
  ///
  /// The entry is where a user presses "install the newer build", and the
  /// About card is where an install is carried out — see [_aboutSurface]. A
  /// counter rather than a call, because the shell cannot reach into a page
  /// that is built in the `IndexedStack` below: what travels down is the
  /// count, and the card answers the change.
  int _installRequests = 0;

  /// Whether an install is under way and the entry must go quiet.
  ///
  /// The shell cannot see into the About card, so the card reports the phases
  /// that must pin the entry: a check while a download is in flight, all the
  /// way through to the closing hand-over. The one moment it stays false is
  /// between a successful download and the question: the entry is alive there
  /// so that a second press can find the question the first press opened.
  bool _updateLocked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ControllerScope.of(context);
    _controller = controller;
    _changes ??= controller.changes.listen((_) => _syncUnread());
    _windowActivity ??= widget.seams.hostShell.windowActivity.listen(
      _setWindowActive,
    );
    _syncUnread();
  }

  void _setWindowActive(bool active) {
    _windowActive = active;
    _syncUnread();
  }

  /// Mirrors "there is something unread in a window the user is not looking
  /// at" onto the native taskbar icon.
  ///
  /// The native runner also clears the overlay as soon as it sees activation;
  /// this call keeps the Dart-side state in step and clears it on hosts whose
  /// activity stream emits the same fact.
  void _syncUnread() {
    final controller = _controller;
    if (controller == null) return;
    final wanted = !_windowActive && controller.totalUnread > 0;
    if (wanted == _unreadShown) return;
    _unreadShown = wanted;
    unawaited(widget.seams.hostShell.setUnread(wanted));
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    unawaited(_windowActivity?.cancel());
    super.dispose();
  }

  /// Brings the Conversations surface forward, with [peer]'s conversation open.
  ///
  /// Handed to the Devices surface, which is where a user connects to a Device:
  /// having done so, the thing they want is the conversation, and this is what
  /// makes that one action instead of two.
  void _showConversation(Fingerprint peer) {
    setState(() {
      _requestedConversation = peer;
      _index = _conversationsSurface;
      _conversationArrivals++;
    });
  }

  /// Brings surface [index] forward, counting it as an arrival when it is the
  /// Conversations one.
  ///
  /// Both roads into a surface go through here — the rail and the bottom bar
  /// hand their selections to it — so "the user asked for this tab" has one
  /// answer rather than two that could drift apart.
  void _select(int index) {
    setState(() {
      _index = index;
      if (index == _conversationsSurface) _conversationArrivals++;
    });
  }

  /// Brings the About surface forward and asks it to install what was found.
  ///
  /// What the rail's update entry does when it is pressed. It used to leave the
  /// application for a browser, which made a user who had just been told a newer
  /// build exists go and fetch it by hand — the one thing an entry pinned to the
  /// rail should save them. It installs instead: the answer the entry was drawn
  /// from is *already here*, on the notice that found it, and the About card
  /// carries the whole of what an install does.
  ///
  /// The card is where the work happens rather than here, because the rail has
  /// nowhere to put any of it: [WeChat.railWidth] pixels hold neither a
  /// download's progress, nor the question an update asks before it closes this
  /// program, nor the sentence an attempt ends in. So the shell switches to the
  /// one surface that has all three and passes the count down; the card answers
  /// the change, and a press that arrives while one is already under way is
  /// dropped rather than queued — two downloads of one package is one too many.
  void _installUpdate() {
    setState(() {
      _index = _aboutSurface;
      _installRequests++;
    });
  }

  /// Reports that the update a press started has reached [busy].
  ///
  /// [UpdateNotice] is the shell's own channel for the rail; this is the other
  /// direction, from the card the rail hands the work to. A second press must
  /// not be possible while a download or the closing hand-over is running, so
  /// the card tells the rail when it is that busy and when it has stopped.
  /// `busy == false` arrives when the download ended in a failure — at that
  /// point the same button is the retry, exactly as the card's own button is.
  void _setUpdateLocked(bool busy) {
    if (_updateLocked == busy) return;
    setState(() => _updateLocked = busy);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    // A Transfer that is waiting for this Device is the one thing worth
    // interrupting for, so the count rides on the destination itself.
    final waiting = controller.transfers
        .where((transfer) => transfer.needsDecision)
        .length;
    // What the user chose beats what the platform suggests. Resolved here
    // rather than inside each page so that "where do files go" has one answer
    // in the running app: three pages each resolving it their own way is three
    // chances to disagree.
    final incoming =
        controller.incomingDirectory ?? widget.seams.defaultIncomingDirectory;
    final presence = PresenceCounts.of(controller.peers);

    final pages = <Widget>[
      ConversationsPage(
        defaultIncomingDirectory: incoming,
        requestedPeer: _requestedConversation,
        focusRequest: _conversationArrivals,
        isVisible: _index == _conversationsSurface,
      ),
      DevicesPage(
        defaultIncomingDirectory: incoming,
        localAddresses: widget.seams.localAddresses,
        onConversationRequested: _showConversation,
      ),
      TransfersPage(defaultIncomingDirectory: incoming),
      const ClipboardPage(),
      SettingsPage(seams: widget.seams),
      AboutPage(
        offeredUpdate: widget.update?.answer,
        installRequest: _installRequests,
        onUpdateBusyChanged: _setUpdateLocked,
      ),
    ];
    // The six surfaces, in the order both layouts show them. One list rather
    // than one per layout: the rail and the bar are one decision about where to
    // put the same six, and a list each would be two places to forget a seventh.
    //
    // Both surfaces that can raise the question carry the count, because they
    // count one thing: a Transfer waiting on an answer. It is met first in the
    // conversation it arrived in and answered on the Transfers surface.
    final surfaces = <_Surface>[
      _Surface(
        icon: Icons.forum_outlined,
        selectedIcon: Icons.forum,
        label: l10n.tabConversation,
        badge: waiting,
      ),
      _Surface(
        icon: Icons.devices_outlined,
        selectedIcon: Icons.devices,
        label: l10n.tabDevices,
      ),
      _Surface(
        icon: Icons.swap_horiz_outlined,
        selectedIcon: Icons.swap_horiz,
        label: l10n.tabTransfers,
        badge: waiting,
      ),
      _Surface(
        icon: Icons.content_paste_outlined,
        selectedIcon: Icons.content_paste,
        label: l10n.tabClipboard,
      ),
      _Surface(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: l10n.tabSettings,
      ),
      _Surface(
        icon: Icons.info_outline,
        selectedIcon: Icons.info,
        label: l10n.tabAbout,
      ),
    ];

    // Wide windows get a rail, narrow ones a bar. The same six either way.
    final wide = MediaQuery.sizeOf(context).width >= 720;
    // Every surface, kept alive: switching tabs must not restart a page, and a
    // conversation half-typed into one must survive a look at another.
    final content = IndexedStack(index: _index, children: pages);
    final notice = widget.update;

    // The rail, with whatever belongs below its foot.
    Widget railWith(Widget? trailing) => AppNavRail(
      selectedIndex: _index,
      onDestinationSelected: _select,
      destinations: [
        // The rail draws one glyph per entry either way; the filled glyphs are
        // the bar's, which is how Material says "you are here".
        for (final surface in surfaces)
          NavRailDestination(
            icon: surface.icon,
            label: surface.label,
            badge: surface.badge,
          ),
      ],
      pinnedCount: _toolSurfaces,
      status: ConnectionSummary(
        counts: presence,
        compact: true,
        onTap: () => _select(_devicesSurface),
      ),
      trailing: trailing,
    );

    // The update entry, when the notice has one to offer. Nothing while the
    // question is out, and nothing when the answer is "you are up to date": an
    // entry that is always there would be a permanent question mark on a rail
    // whose whole job is to be a map of where things are. Read out here rather
    // than inside the rail's own builder so that "nothing to say" can be no
    // entry at all — the rail's column has a gap between its children, and a
    // zero-height child would still be charged one.
    final rail = notice == null
        ? railWith(null)
        : ListenableBuilder(
            listenable: notice,
            builder: (context, _) {
              final version = notice.version;
              return railWith(
                version == null
                    ? null
                    : _UpdateEntry(
                        version: version,
                        onInstall: _installUpdate,
                        enabled: !_updateLocked,
                      ),
              );
            },
          );

    return Scaffold(
      // No `AppBar` on purpose. The window's own title bar already carries the
      // application's name, and this Device's name is a fact about this Device
      // rather than about the surface being looked at — it belongs on the
      // Devices surface with the rest of what this Device says about itself,
      // not pinned above six pages that have nothing to do with it. What is
      // left is a strip of chrome doing no work, so it goes.
      body: SafeArea(
        // The bottom navigation bar and every composer already account for
        // the bottom inset. The top inset belongs here because the shell has
        // no AppBar to reserve it, including above a conversation's own
        // compact back button on a narrow screen.
        bottom: false,
        child: wide
            ? FocusTraversalGroup(
                // Geometry used to put the rail first because its entries sat
                // above everything in the page. A search field can now start
                // at the top of the content column, so state the order rather
                // than letting a pixel decide which control Tab reaches first.
                policy: OrderedTraversalPolicy(),
                child: Row(
                  children: [
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(1),
                      child: rail,
                    ),
                    VerticalDivider(
                      width: 1,
                      color: WeChatColors.of(context).divider,
                    ),
                    Expanded(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: content,
                      ),
                    ),
                  ],
                ),
              )
            : content,
      ),
      bottomNavigationBar: wide
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The summary's hairline used to ride on its own decoration;
                // now that it is a `TextButton`, the line is the border under
                // the strip, drawn by the chrome so the two stay one decision.
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: WeChatColors.of(context).divider),
                    ),
                  ),
                  child: ConnectionSummary(
                    counts: presence,
                    onTap: () => _select(_devicesSurface),
                  ),
                ),
                NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  destinations: [
                    for (final surface in surfaces)
                      NavigationDestination(
                        icon: _badged(surface.icon, surface.badge),
                        selectedIcon: _badged(
                          surface.selectedIcon,
                          surface.badge,
                        ),
                        label: surface.label,
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// The rail's update entry: one word on the rail, the version on the hover.
///
/// The rail has room for one word, so the version number — which is the whole
/// reason the entry exists rather than a coloured dot — rides on the hover.
/// That the version is the payload and not the label is why the tooltip is
/// [AppLocalizations.aboutUpdateAvailable] rather than a sentence invented
/// here: the About card already says exactly this fact, in exactly this shape,
/// and two spellings of one number is one place for them to drift apart.
///
/// Drawn as a [TextButton] rather than as a [NavRailDestination]:
/// destinations switch the surface below, and this one hands a job to it — see
/// [_HomeShellState._installUpdate], which is what the press does. It wears the
/// same icon the About card's 「检查更新」 button does, so the two read as the
/// same feature, and that icon is already in the shipped bundle's icon subset.
class _UpdateEntry extends StatelessWidget {
  const _UpdateEntry({
    required this.version,
    required this.onInstall,
    required this.enabled,
  });

  /// The newer version, named on the hover.
  final String version;

  /// What pressing it does: start the install.
  ///
  /// Handed in rather than built here, because the shell is what has to bring
  /// the About surface forward — and a widget drawn deep inside a rail has no
  /// way to name the shell's own selection. The entry's job ends at saying
  /// "the user wants it"; where the work happens is the shell's decision.
  final VoidCallback onInstall;

  /// Whether a press can start anything. False while an update is in flight,
  /// so a second press cannot queue a second download.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return Padding(
      // Room to breathe under the last destination: without it the entry sits
      // flush against the bottom edge of the window and reads as a tab that has
      // fallen off the end of the list. Nothing to the left or right, because
      // the rail has already given its whole inside the same margin.
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Tooltip(
        message: l10n.aboutUpdateAvailable(version),
        child: TextButton(
          // Installs rather than opens a browser: the whole point of the entry
          // is that a user who has been told a newer build exists should not
          // then have to go and fetch it by hand. What it does instead is
          // hand the job to the About card, which has the room to show a
          // download's progress, ask the one question before closing, and say
          // how an attempt ended — so the shell switches to it and counts the
          // press.
          onPressed: enabled ? onInstall : null,
          // The colour is named rather than inherited because the rest of the
          // style is: the theme's text-button slot holds this green already, but
          // its shape is a sentence on a padded button, and this entry is a
          // glyph over two characters.
          style: TextButton.styleFrom(
            foregroundColor: colors.brandStrong,
            // As tall as a comfortable target: the width comes from the rail,
            // as it does for every other entry.
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeChat.controlRadius),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // No colour or size of its own on purpose: a `ButtonStyleButton`
              // hands its child an `IconTheme` carrying the foreground colour
              // and the resolved icon size, so the icon is the button's own
              // green in either theme without saying so twice.
              const Icon(Icons.system_update_alt),
              const SizedBox(height: 2),
              Text(
                l10n.railUpdate,
                style: const TextStyle(fontSize: WeChat.fontSizeMeta),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the six surfaces, as both layouts need it.
///
/// Two glyphs and a count rather than either layout's own destination type, so
/// that the order, the words and the counts are written once: the rail takes the
/// outlined glyph, which is the one the design draws, and the bar takes both,
/// because filling the current tab's glyph is how Material says where a reader
/// is. Nothing here is a widget — a caller turns these into whichever
/// destination type it hands its own component.
class _Surface {
  const _Surface({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge = 0,
  });

  /// The glyph when this surface is not the one on screen.
  final IconData icon;

  /// The glyph when it is. Unused by the rail, which draws [icon] either way.
  final IconData selectedIcon;

  /// The surface's name, on the rail and in the bar.
  final String label;

  /// How many Transfers are waiting for an answer, or zero for none.
  final int badge;
}

/// [icon] with a count riding on it, for the surfaces that can raise one.
///
/// A function rather than a widget class because both of a surface's glyphs take
/// the same count, and neither layout owns the badge: it belongs to the event
/// the count is about, and each surface says how many of them it can show.
Widget _badged(IconData icon, int count) =>
    Badge.count(count: count, isLabelVisible: count > 0, child: Icon(icon));

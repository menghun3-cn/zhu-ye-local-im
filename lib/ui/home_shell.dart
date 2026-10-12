import 'dart:async';

import 'package:flutter/material.dart';

import '../core/core.dart';
import 'controller_scope.dart';
import 'dialogs.dart';
import 'external_links.dart';
import 'l10n/generated/app_localizations.dart';
import 'pages/about_page.dart';
import 'pages/clipboard_page.dart';
import 'pages/conversations_page.dart';
import 'pages/devices_page.dart';
import 'pages/settings_page.dart';
import 'pages/transfers_page.dart';
import 'seams.dart';
import 'update_notice.dart';
import 'wechat/theme.dart';

/// Where the Conversations surface sits, for the one place that has to name it.
///
/// It leads the list: talking to somebody is what the app is for, and the
/// Devices surface is what you visit to set that up, so Devices sits second.
///
/// Only this one index has a name: the shell builds the pages and the
/// destinations from the same ordered list, so every index is already in the
/// same order by construction, and the only place an index is *written* rather
/// than derived is [_HomeShellState._showConversation]. A full set of names
/// would be five constants kept in step with a list for no gain.
const int _conversationsSurface = 0;

/// The six surfaces, and the way between them.
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

  /// The conversation the user asked for from another surface, if any.
  ///
  /// The Devices surface cannot switch tabs itself — it does not know this
  /// shell exists — so it asks through a callback, and the request lands here
  /// until the Conversations surface has taken it. Connecting to a Device is
  /// the case this exists for: the user asked to talk to somebody, so the tab
  /// changes and that conversation is already open.
  Fingerprint? _requestedConversation;

  StreamSubscription<PairingRequest>? _requests;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Wired here rather than in the page that draws the pairing card: a request
    // arrives whoever the user is looking at, and a prompt that only appeared on
    // one of the surfaces would be a prompt that gets missed. The shell is the
    // narrowest thing that is always alive.
    _requests ??= ControllerScope.of(context).pairingRequests
        .listen(_ask, onError: (Object _) {});
  }

  @override
  void dispose() {
    unawaited(_requests?.cancel());
    super.dispose();
  }

  /// Puts one request to the user, and lets the answer travel back.
  ///
  /// Nothing else may happen first: the Device on the other end is blocked on
  /// this dialog, so a request that arrives while there is no window to show it
  /// in is refused rather than dropped — the alternative is a peer waiting for
  /// a question nobody was ever asked.
  Future<void> _ask(PairingRequest request) async {
    if (!mounted) {
      await request.refuse();
      return;
    }
    // The controller travels with the question because the answer may have to
    // open a Session: which side does that, when both sides asked at once, is
    // decided from the two Fingerprints, and this is the side that knows one
    // of them.
    await showPairingRequestDialog(
      context,
      ControllerScope.of(context),
      request,
    );
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
    });
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

    final pages = <Widget>[
      ConversationsPage(
        defaultIncomingDirectory: incoming,
        requestedPeer: _requestedConversation,
      ),
      DevicesPage(
        defaultIncomingDirectory: incoming,
        onConversationRequested: _showConversation,
      ),
      TransfersPage(defaultIncomingDirectory: incoming),
      const ClipboardPage(),
      SettingsPage(seams: widget.seams),
      const AboutPage(),
    ];
    final destinations = <NavigationDestination>[
      NavigationDestination(
        // The same badge as Transfers, because it counts the same thing: a
        // Transfer waiting on an answer is the one event worth interrupting
        // for, and it now has two places it can be answered from.
        icon: Badge.count(
          count: waiting,
          isLabelVisible: waiting > 0,
          child: const Icon(Icons.forum_outlined),
        ),
        selectedIcon: Badge.count(
          count: waiting,
          isLabelVisible: waiting > 0,
          child: const Icon(Icons.forum),
        ),
        label: l10n.tabConversation,
      ),
      NavigationDestination(
        icon: const Icon(Icons.devices_outlined),
        selectedIcon: const Icon(Icons.devices),
        label: l10n.tabDevices,
      ),
      NavigationDestination(
        icon: Badge.count(
          count: waiting,
          isLabelVisible: waiting > 0,
          child: const Icon(Icons.swap_horiz_outlined),
        ),
        selectedIcon: Badge.count(
          count: waiting,
          isLabelVisible: waiting > 0,
          child: const Icon(Icons.swap_horiz),
        ),
        label: l10n.tabTransfers,
      ),
      NavigationDestination(
        icon: const Icon(Icons.content_paste_outlined),
        selectedIcon: const Icon(Icons.content_paste),
        label: l10n.tabClipboard,
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: l10n.tabSettings,
      ),
      NavigationDestination(
        icon: const Icon(Icons.info_outline),
        selectedIcon: const Icon(Icons.info),
        label: l10n.tabAbout,
      ),
    ];

    // Wide windows get a rail, narrow ones a bar. The same destinations
    // either way: this is one layout decision, not two screens.
    final wide = MediaQuery.sizeOf(context).width >= 720;
    // Every surface, kept alive: switching tabs must not restart a page, and a
    // conversation half-typed into one must survive a look at another.
    final content = IndexedStack(index: _index, children: pages);
    final notice = widget.update;

    return Scaffold(
      // No `AppBar` on purpose. The window's own title bar already carries the
      // application's name, and this Device's name is a fact about this Device
      // rather than about the surface being looked at — it belongs on the
      // Devices surface with the rest of what this Device says about itself,
      // not pinned above six pages that have nothing to do with it. What is
      // left is a strip of chrome doing no work, so it goes.
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (index) =>
                      setState(() => _index = index),
                  labelType: NavigationRailLabelType.all,
                  // The update entry is pinned rather than listed with the six.
                  // It is not a surface: pressing it leaves the application for
                  // a browser. A destination in the middle of the list would also
                  // make every tab below it move the day a seventh surface
                  // arrives, and the tabs are what a user has learned by
                  // position.
                  trailingAtBottom: true,
                  trailing: notice == null
                      ? null
                      : ListenableBuilder(
                          listenable: notice,
                          builder: (context, _) {
                            final version = notice.version;
                            final url = notice.url;
                            // Nothing to say while the question is out, and
                            // nothing to say when the answer is "you are up to
                            // date": an entry that is always there would be a
                            // permanent question mark on a rail whose whole job
                            // is to be a map of where things are.
                            if (version == null || url == null) {
                              return const SizedBox.shrink();
                            }
                            return _UpdateEntry(version: version, url: url);
                          },
                        ),
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: destination.icon,
                        selectedIcon: destination.selectedIcon,
                        label: Text(destination.label),
                      ),
                  ],
                ),
                VerticalDivider(
                  width: 1,
                  color: WeChatColors.of(context).divider,
                ),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (index) => setState(() => _index = index),
              destinations: destinations,
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
/// Drawn as a [TextButton] rather than as a [NavigationRailDestination]:
/// destinations switch the surface below, and this one leaves the application
/// for a browser. It wears the same icon the About card's 「检查更新」 button
/// does, so the two read as the same feature, and that icon is already in the
/// shipped bundle's icon subset.
class _UpdateEntry extends StatelessWidget {
  const _UpdateEntry({required this.version, required this.url});

  /// The newer version, named on the hover.
  final String version;

  /// Where pressing it goes.
  final String url;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return Padding(
      // Room to breathe under the last destination: without it the entry sits
      // flush against the bottom edge of the window and reads as a tab that has
      // fallen off the end of the list.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Tooltip(
        message: l10n.aboutUpdateAvailable(version),
        child: TextButton(
          onPressed: () => unawaited(LinkResolution.opener.open(url)),
          // The colours are named rather than inherited: the rail's own theme
          // styles destinations, and a `TextButton` inside one has no style of
          // its own to fall back on — it would come out in the theme's default
          // primary, which is not this design's green.
          style: TextButton.styleFrom(
            foregroundColor: colors.brandStrong,
            // Wide enough to be a comfortable target, narrow enough to fit
            // inside a 72px rail: the label below is two characters.
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

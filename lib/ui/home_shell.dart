import 'dart:async';

import 'package:flutter/material.dart';

import '../core/core.dart';
import 'controller_scope.dart';
import 'dialogs.dart';
import 'l10n/generated/app_localizations.dart';
import 'labels.dart';
import 'pages/clipboard_page.dart';
import 'pages/conversations_page.dart';
import 'pages/devices_page.dart';
import 'pages/settings_page.dart';
import 'pages/transfers_page.dart';
import 'seams.dart';

/// Where the Conversations surface sits, for the one place that has to name it.
///
/// Only this one index has a name: the shell builds the pages and the
/// destinations from the same ordered list, so every index is already in the
/// same order by construction, and the only place an index is *written* rather
/// than derived is [_HomeShellState._showConversation]. A full set of names
/// would be five constants kept in step with a list for no gain.
const int _conversationsSurface = 1;

/// The five surfaces, and the way between them.
class HomeShell extends StatefulWidget {
  /// Shows the surfaces for [seams].
  const HomeShell({super.key, required this.seams});

  /// The platform facts a page needs but the controller does not carry —
  /// where a Transfer lands by default, and where the profile lives.
  final PlatformSeams seams;

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
    await showPairingRequestDialog(context, request);
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
    final self = controller.self;
    // A Transfer that is waiting for this Device is the one thing worth
    // interrupting for, so the count rides on the destination itself.
    final waiting = controller.transfers
        .where((transfer) => transfer.needsDecision)
        .length;

    final pages = <Widget>[
      DevicesPage(
        defaultIncomingDirectory: widget.seams.defaultIncomingDirectory,
        onConversationRequested: _showConversation,
      ),
      ConversationsPage(
        defaultIncomingDirectory: widget.seams.defaultIncomingDirectory,
        requestedPeer: _requestedConversation,
      ),
      TransfersPage(
        defaultIncomingDirectory: widget.seams.defaultIncomingDirectory,
      ),
      const ClipboardPage(),
      SettingsPage(seams: widget.seams),
    ];
    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.devices_outlined),
        selectedIcon: const Icon(Icons.devices),
        label: l10n.tabDevices,
      ),
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
    ];

    // Wide windows get a rail, narrow ones a bar. The same destinations
    // either way: this is one layout decision, not two screens.
    final wide = MediaQuery.sizeOf(context).width >= 720;
    // Every surface, kept alive: switching tabs must not restart a page, and a
    // conversation half-typed into one must survive a look at another.
    final content = IndexedStack(index: _index, children: pages);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(iconForPlatform(self.platform), size: 18),
                const SizedBox(width: 8),
                Text(self.alias),
                if (!self.isPaired) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: l10n.notPairedYet,
                    child: const Icon(Icons.link_off, size: 18),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (index) =>
                      setState(() => _index = index),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: destination.icon,
                        selectedIcon: destination.selectedIcon,
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
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

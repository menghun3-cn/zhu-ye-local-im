import 'package:flutter/material.dart';

import 'controller_scope.dart';
import 'labels.dart';
import 'pages/clipboard_page.dart';
import 'pages/devices_page.dart';
import 'pages/settings_page.dart';
import 'pages/transfers_page.dart';
import 'seams.dart';

/// The four surfaces, and the way between them.
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

  @override
  Widget build(BuildContext context) {
    final controller = ControllerScope.of(context);
    final self = controller.self;
    // A Transfer that is waiting for this Device is the one thing worth
    // interrupting for, so the count rides on the destination itself.
    final waiting = controller.transfers
        .where((transfer) => transfer.needsDecision)
        .length;

    final pages = <Widget>[
      const DevicesPage(),
      TransfersPage(
        defaultIncomingDirectory: widget.seams.defaultIncomingDirectory,
      ),
      const ClipboardPage(),
      SettingsPage(seams: widget.seams),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.devices_outlined),
        selectedIcon: Icon(Icons.devices),
        label: 'Devices',
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
        label: 'Transfers',
      ),
      const NavigationDestination(
        icon: Icon(Icons.content_paste_outlined),
        selectedIcon: Icon(Icons.content_paste),
        label: 'Clipboard',
      ),
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Settings',
      ),
    ];

    // Wide windows get a rail, narrow ones a bar. The same four destinations
    // either way: this is one layout decision, not two screens.
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final content = IndexedStack(index: _index, children: pages);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Transfer'),
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
                  const Tooltip(
                    message: 'Not paired with any Device yet',
                    child: Icon(Icons.link_off, size: 18),
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

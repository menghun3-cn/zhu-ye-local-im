import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../l10n/generated/app_localizations.dart';
import '../seams.dart';
import '../update_notice.dart';
import '../wechat/theme.dart';
import '../widgets.dart';
import 'about_page.dart';
import 'clipboard_page.dart';
import 'devices_page.dart';
import 'settings_page.dart';

/// One card in the "My" page, representing a low-frequency surface.
///
/// Each card shows the surface's icon, title, a short summary of the most
/// useful information, and a button to open the full surface.
class _MyCard extends StatelessWidget {
  const _MyCard({
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WeChat.controlRadius),
        child: Padding(
          padding: const EdgeInsets.all(WeChat.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 24, color: colors.bubbleText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: WeChat.fontSizePreview,
                        fontWeight: FontWeight.w600,
                        color: colors.bubbleText,
                      ),
                    ),
                  ),
                  TextButton(onPressed: onTap, child: Text(l10n.myViewDetails)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                summary,
                style: TextStyle(
                  fontSize: WeChat.fontSizeMeta,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "My" page, aggregating low-frequency surfaces.
///
/// This page shows four cards, each pointing to one of the four low-frequency
/// pages: Devices, Clipboard, Settings, and About. Each card displays a short
/// summary of the most useful information from that surface, and a button to
/// open the full surface as a new route.
class MyPage extends StatefulWidget {
  const MyPage({
    super.key,
    required this.seams,
    this.update,
    this.installRequest = 0,
    this.onUpdateBusyChanged,
  });

  /// The platform facts a page needs but the controller does not carry.
  final PlatformSeams seams;

  /// Whether a newer build has been published, when this page was given
  /// something that knows.
  final UpdateNotice? update;

  /// How many times the user has asked for the newer build to be installed.
  ///
  /// Counted by the shell, which is the only thing that knows the rail's
  /// update entry was pressed. A change in it is that press arriving: the
  /// rail has no room for a download's progress, the question before closing
  /// or the sentence an attempt ends in, and the About card has all three — so
  /// the entry hands the work here rather than duplicating it in a 72-pixel strip.
  final int installRequest;

  /// What the shell's rail entry should hear about the phases of an update.
  ///
  /// The rail has no room for a download's progress, so the one thing it needs
  /// from the card is whether its own entry may be pressed: while a download or
  /// the closing hand-over is in flight a second press must not be possible.
  final ValueChanged<bool>? onUpdateBusyChanged;

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  /// Whether an update is in flight.
  ///
  /// Held here rather than in the notice the rail reads: the rail's entry is
  /// about *asking*, and an update is something a person pressed a button on
  /// the About card to start. This page passes the state to the About card.
  bool _updateLocked = false;

  /// Tells the rail whether an update is in flight, when there is a rail.
  void _reportBusy(bool busy) => widget.onUpdateBusyChanged?.call(busy);

  /// Reports that the update a press started has reached [busy].
  ///
  /// This is called by the About card, which is where the actual work happens.
  void _setUpdateLocked(bool busy) {
    if (_updateLocked == busy) return;
    setState(() => _updateLocked = busy);
    _reportBusy(busy);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    final incoming =
        controller.incomingDirectory ?? widget.seams.defaultIncomingDirectory;

    return ListView(
      padding: WeChat.pagePadding,
      children: [
        SectionHeader(title: l10n.myPageTitle),
        _MyCard(
          icon: Icons.devices_outlined,
          title: l10n.myCardDevices,
          summary: l10n.myCardDevicesSummary(controller.peers.length),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text(l10n.tabDevices)),
                body: DevicesPage(
                  defaultIncomingDirectory: incoming,
                  localAddresses: widget.seams.localAddresses,
                  onConversationRequested: (_) {},
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: WeChat.sectionGap),
        _MyCard(
          icon: Icons.content_paste_outlined,
          title: l10n.myCardClipboard,
          summary: controller.clipboardMode == ClipboardMode.off
              ? l10n.myCardClipboardSummaryDisabled
              : l10n.myCardClipboardSummary,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text(l10n.tabClipboard)),
                body: const ClipboardPage(),
              ),
            ),
          ),
        ),
        const SizedBox(height: WeChat.sectionGap),
        _MyCard(
          icon: Icons.settings_outlined,
          title: l10n.myCardSettings,
          summary: controller.incomingDirectory == null
              ? l10n.myCardSettingsSummaryUnset
              : l10n.myCardSettingsSummary,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text(l10n.tabSettings)),
                body: SettingsPage(seams: widget.seams),
              ),
            ),
          ),
        ),
        const SizedBox(height: WeChat.sectionGap),
        _MyCard(
          icon: Icons.info_outline,
          title: l10n.myCardAbout,
          summary: _aboutSummary(widget.update, l10n),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text(l10n.tabAbout)),
                body: AboutPage(
                  offeredUpdate: widget.update?.answer,
                  installRequest: widget.installRequest,
                  onUpdateBusyChanged: _setUpdateLocked,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _aboutSummary(UpdateNotice? update, AppLocalizations l10n) {
    if (update == null) return l10n.myCardAboutSummary(appVersion);
    final version = update.version;
    if (version == null) return l10n.myCardAboutSummary(appVersion);
    return l10n.myCardAboutSummaryUpdate(version);
  }
}

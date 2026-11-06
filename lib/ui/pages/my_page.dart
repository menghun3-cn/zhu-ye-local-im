import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../l10n/generated/app_localizations.dart';
import '../seams.dart';
import '../update_notice.dart';
import '../update_session.dart';
import '../wechat/theme.dart';
import '../widgets.dart';
import 'about_page.dart';
import 'clipboard_page.dart';
import 'devices_page.dart';
import 'screenshot_page.dart';
import 'settings_page.dart';
import 'share_by_link_page.dart';
import 'troubleshooting_page.dart';

/// Which sub-page is shown.
enum _SubPage {
  devices,
  clipboard,
  screenshot,
  settings,
  troubleshooting,
  shareByLink,
  about,
}

/// The header shown above each sub-page, with a back button.
class _SubPageHeader extends StatelessWidget {
  const _SubPageHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.pageBackground,
        border: Border(bottom: BorderSide(color: colors.divider, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
            tooltip: 'Back',
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.bubbleText,
            ),
          ),
        ],
      ),
    );
  }
}

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
    this.installSession,
    this.openAboutRequests = 0,
    this.onUpdateBusyChanged,
  });

  /// The platform facts a page needs but the controller does not carry.
  final PlatformSeams seams;

  /// Whether a newer build has been published, when this page was given
  /// something that knows.
  final UpdateNotice? update;

  /// The update the shell is carrying out, when there is one.
  ///
  /// Handed to the About card, which is where an install's progress, its
  /// question and its failure are shown. The session outlives this page — it
  /// is owned by the shell — so a download that is under way when the user
  /// backs out to the card list is still there when they return.
  final UpdateInstallSession? installSession;

  /// How many times the rail's update entry has asked for the About card.
  ///
  /// The session owns the install itself — the press reaches it directly — so
  /// all this page owes a request is the sub-page the card lives on: a press
  /// that landed on the card list would have started a download the user
  /// cannot see. A counter rather than a flag, so that every press is a
  /// request even when the card was already open.
  final int openAboutRequests;

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
  /// Which sub-page is currently shown, or null for the card list.
  _SubPage? _currentSubPage;

  /// Tells the rail whether the About card's own check is in flight.
  void _reportBusy(bool busy) => widget.onUpdateBusyChanged?.call(busy);

  /// Reports that the About card's own check has reached [busy].
  ///
  /// This is called by the About card. The install's phases are not reported
  /// here — the shell hears those from the session directly, which is what
  /// lets the download survive this page never being built at all.
  void _setUpdateLocked(bool busy) => _reportBusy(busy);

  @override
  void didUpdateWidget(MyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openAboutRequests == oldWidget.openAboutRequests) return;
    // The press that started the install wants the card that shows it: the
    // download's progress, the question before closing, the failure sentence.
    _currentSubPage = _SubPage.about;
  }

  /// Opens a sub-page.
  void _openSubPage(_SubPage page) {
    setState(() => _currentSubPage = page);
  }

  /// Closes the current sub-page and returns to the card list.
  void _closeSubPage() {
    setState(() => _currentSubPage = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    final incoming =
        controller.incomingDirectory ?? widget.seams.defaultIncomingDirectory;

    // If a sub-page is open, show it with a back button
    if (_currentSubPage != null) {
      return _buildSubPage(context, l10n, controller, incoming);
    }

    // Otherwise show the card list
    return ListView(
      padding: WeChat.pagePadding,
      children: [
        SectionHeader(title: l10n.myPageTitle),
        _MyCard(
          icon: Icons.devices_outlined,
          title: l10n.myCardDevices,
          summary: l10n.myCardDevicesSummary(controller.peers.length),
          onTap: () => _openSubPage(_SubPage.devices),
        ),
        const SizedBox(height: WeChat.sectionGap),
        _MyCard(
          icon: Icons.content_paste_outlined,
          title: l10n.myCardClipboard,
          summary: controller.clipboardMode == ClipboardMode.off
              ? l10n.myCardClipboardSummaryDisabled
              : l10n.myCardClipboardSummary,
          onTap: () => _openSubPage(_SubPage.clipboard),
        ),
        // The screenshot card exists only where the feature can run: the
        // capture overlay, the pins and the global hotkey are all Windows
        // machinery, and a card on Android would lead to a page that can do
        // nothing.
        if (widget.seams.platform == DevicePlatform.windows) ...[
          const SizedBox(height: WeChat.sectionGap),
          _MyCard(
            icon: Icons.screenshot_monitor_outlined,
            title: l10n.myCardScreenshot,
            summary: controller.screenshotEnabled
                ? l10n.myCardScreenshotSummaryEnabled
                : l10n.myCardScreenshotSummaryDisabled,
            onTap: () => _openSubPage(_SubPage.screenshot),
          ),
        ],
        const SizedBox(height: WeChat.sectionGap),
        _MyCard(
          icon: Icons.settings_outlined,
          title: l10n.myCardSettings,
          // The folder that would actually be used, not only the one the user
          // typed: the platform default is a real destination too, so "unset"
          // is honest only when neither exists.
          summary: incoming == null
              ? l10n.myCardSettingsSummaryUnset
              : l10n.myCardSettingsSummary,
          onTap: () => _openSubPage(_SubPage.settings),
        ),
        const SizedBox(height: WeChat.sectionGap),
        _MyCard(
          icon: Icons.healing_outlined,
          title: l10n.myCardTroubleshooting,
          summary: l10n.myCardTroubleshootingSummary,
          onTap: () => _openSubPage(_SubPage.troubleshooting),
        ),
        const SizedBox(height: WeChat.sectionGap),
        _MyCard(
          icon: Icons.link,
          title: l10n.myCardShareByLink,
          summary: l10n.myCardShareByLinkSummary,
          onTap: () => _openSubPage(_SubPage.shareByLink),
        ),
        const SizedBox(height: WeChat.sectionGap),
        _MyCard(
          icon: Icons.announcement,
          title: l10n.myCardAbout,
          summary: _aboutSummary(widget.update, l10n),
          onTap: () => _openSubPage(_SubPage.about),
        ),
      ],
    );
  }

  /// Builds the content for the currently selected sub-page.
  Widget _buildSubPage(
    BuildContext context,
    AppLocalizations l10n,
    LocalTransferController controller,
    String? incoming,
  ) {
    final page = switch (_currentSubPage) {
      _SubPage.devices => Column(
        children: [
          _SubPageHeader(title: l10n.tabDevices, onBack: _closeSubPage),
          Expanded(
            child: DevicesPage(
              defaultIncomingDirectory: incoming,
              localAddresses: widget.seams.localAddresses,
              onConversationRequested: (_) {},
            ),
          ),
        ],
      ),
      _SubPage.clipboard => Column(
        children: [
          _SubPageHeader(title: l10n.tabClipboard, onBack: _closeSubPage),
          const Expanded(child: ClipboardPage()),
        ],
      ),
      _SubPage.screenshot => Column(
        children: [
          _SubPageHeader(title: l10n.myCardScreenshot, onBack: _closeSubPage),
          const Expanded(child: ScreenshotPage()),
        ],
      ),
      _SubPage.settings => Column(
        children: [
          _SubPageHeader(title: l10n.tabSettings, onBack: _closeSubPage),
          Expanded(child: SettingsPage(seams: widget.seams)),
        ],
      ),
      _SubPage.troubleshooting => Column(
        children: [
          _SubPageHeader(
            title: l10n.troubleshootingTitle,
            onBack: _closeSubPage,
          ),
          const Expanded(child: TroubleshootingPage()),
        ],
      ),
      _SubPage.shareByLink => Column(
        children: [
          _SubPageHeader(title: l10n.myCardShareByLink, onBack: _closeSubPage),
          const Expanded(child: ShareByLinkPage()),
        ],
      ),
      _SubPage.about => Column(
        children: [
          _SubPageHeader(title: l10n.tabAbout, onBack: _closeSubPage),
          Expanded(
            child: AboutPage(
              session: widget.installSession,
              onUpdateBusyChanged: _setUpdateLocked,
            ),
          ),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
    return page;
  }

  String _aboutSummary(UpdateNotice? update, AppLocalizations l10n) {
    if (update == null) return l10n.myCardAboutSummary(appVersion);
    final version = update.version;
    if (version == null) return l10n.myCardAboutSummary(appVersion);
    return l10n.myCardAboutSummaryUpdate(version);
  }
}

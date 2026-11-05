import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../l10n/generated/app_localizations.dart';
import '../seams.dart';
import '../update_check.dart';
import '../update_notice.dart';
import '../wechat/theme.dart';
import '../widgets.dart';
import 'about_page.dart';
import 'clipboard_page.dart';
import 'devices_page.dart';
import 'settings_page.dart';

/// Which sub-page is shown.
enum _SubPage { devices, clipboard, settings, about }

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
  /// Which sub-page is currently shown, or null for the card list.
  _SubPage? _currentSubPage;

  /// The install request the About card has not acknowledged yet, or null.
  ///
  /// The shell counts rail presses; this page is the one thing alive between
  /// them and the card — the card itself only exists while its sub-page is
  /// open, so a press that arrives with the card list showing would otherwise
  /// meet nothing and be lost. Held here until [AboutPage.onInstallRequestHandled]
  /// reports the card has the job, including the case where the card is only
  /// opened afterwards: a nonzero value handed down is by definition a request
  /// still waiting to be answered.
  int? _pendingInstallRequest;

  @override
  void didUpdateWidget(MyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.installRequest == oldWidget.installRequest) return;
    _pendingInstallRequest = widget.installRequest;
  }

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
        const SizedBox(height: WeChat.sectionGap),
        _MyCard(
          icon: Icons.settings_outlined,
          title: l10n.myCardSettings,
          summary: controller.incomingDirectory == null
              ? l10n.myCardSettingsSummaryUnset
              : l10n.myCardSettingsSummary,
          onTap: () => _openSubPage(_SubPage.settings),
        ),
        const SizedBox(height: WeChat.sectionGap),
        // The About card is the one whose summary can change without anything
        // on this page happening: the notice answers once as the application
        // comes up, and again on the interval the profile names. Listening here
        // is what keeps 「有新版本」 from waiting for an unrelated rebuild.
        widget.update == null
            ? _aboutCard(null, l10n)
            : ListenableBuilder(
                listenable: widget.update!,
                builder: (context, _) => _aboutCard(widget.update, l10n),
              ),
      ],
    );
  }

  /// The About card, summarising [update] — the notice, or null for none.
  Widget _aboutCard(UpdateNotice? update, AppLocalizations l10n) => _MyCard(
    icon: Icons.announcement,
    title: l10n.myCardAbout,
    summary: _aboutSummary(update, l10n),
    onTap: () => _openSubPage(_SubPage.about),
  );

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
      _SubPage.settings => Column(
        children: [
          _SubPageHeader(title: l10n.tabSettings, onBack: _closeSubPage),
          Expanded(child: SettingsPage(seams: widget.seams)),
        ],
      ),
      _SubPage.about => Column(
        children: [
          _SubPageHeader(title: l10n.tabAbout, onBack: _closeSubPage),
          Expanded(child: _aboutPage()),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
    return page;
  }

  /// The About card, rebuilt when the notice's answer changes.
  ///
  /// The page mirrors [UpdateNotice.answer] — see `AboutPage.offeredUpdate` —
  /// so it has to be handed each new answer as it lands, not only the one that
  /// happened to be there when the sub-page opened. Without the listener a
  /// check that finishes while the page is open would leave the card showing
  /// 「检查更新」 over an answer the rail is already acting on.
  Widget _aboutPage() {
    final update = widget.update;
    if (update == null) return _aboutPageWith(null);
    return ListenableBuilder(
      listenable: update,
      builder: (context, _) => _aboutPageWith(update.answer),
    );
  }

  /// The About page itself, showing [offered] as the application's answer.
  ///
  /// [installRequest] is nonzero only while a rail press is still waiting for
  /// the card to answer it — see [_pendingInstallRequest] — so a card mounted
  /// for the first time can tell a request that is still owed from one that
  /// was already carried out by a card that has since gone away.
  Widget _aboutPageWith(UpdateCheck? offered) => AboutPage(
    offeredUpdate: offered,
    installRequest: _pendingInstallRequest ?? 0,
    onInstallRequestHandled: (request) {
      if (_pendingInstallRequest == request) {
        setState(() => _pendingInstallRequest = null);
      }
    },
    onUpdateBusyChanged: _setUpdateLocked,
  );

  String _aboutSummary(UpdateNotice? update, AppLocalizations l10n) {
    if (update == null) return l10n.myCardAboutSummary(appVersion);
    final version = update.version;
    if (version == null) return l10n.myCardAboutSummary(appVersion);
    return l10n.myCardAboutSummaryUpdate(version);
  }
}

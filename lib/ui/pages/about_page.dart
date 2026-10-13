import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../external_links.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../update_check.dart';
import '../update_install.dart';
import '../update_notes.dart';
import '../wechat/theme.dart';
import '../widgets.dart';

/// What this build is, and how to get a newer one.
///
/// A surface of its own rather than a section of Settings: it is the one page
/// whose content is about the *program* rather than about this Device or this
/// network.
///
/// Nothing here is asked when the page is opened, and the difference that makes
/// is a narrower one than it used to be. The application asks GitHub once as it
/// comes up — see `UpdateNotice`, and this card's own description, which names
/// that as the one exception to staying inside the local network — and this
/// button is how a user asks again on demand, without restarting the app to find
/// out. What the page must not do is ask on *arrival*: that would turn one
/// deliberate request per run into one per visit, and a visit is not something a
/// person thinks of as reaching outwards.
///
/// The page also offers to install what the question turns up — see
/// `update_install.dart` for what that does to the folder this build runs from,
/// and note that the offer is left out entirely on a platform that cannot:
/// a button that could only ever fail is worse than no button.
class AboutPage extends StatefulWidget {
  /// Shows what this build is.
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// The last answer, or null while none has been asked for.
  UpdateCheck? _answer;

  /// Whether a question is out. The button is inert while it is, because a
  /// second press would only ask the same thing again.
  bool _asking = false;

  /// What an update is doing, or null when none is.
  ///
  /// Held here rather than in the notice the rail reads: the rail's entry is
  /// about *asking*, and an update is something a person pressed a button on
  /// this card to start. Switching surfaces and coming back leaves it where it
  /// was — the shell keeps every page alive — which is what a user who started
  /// a download and went to look at something else will expect to find.
  UpdateInstallProgress? _progress;

  /// Why an update this run did not happen, or null.
  UpdateInstallFailure? _failure;

  /// Why the last hand-over this app ever attempted did not finish, or null.
  ///
  /// Read once, as the page is built for the first time, and consumed by that
  /// read: on the run *after* a failed hand-over there is no other trace of it
  /// — the build that failed was the new one, and what it left behind is a
  /// window that came and went.
  UpdateInstallFailure? _leftOver;

  @override
  void initState() {
    super.initState();
    _leftOver = UpdateInstallResolution.installer.previousFailure();
  }

  /// Whether an update is in flight.
  bool get _busy => _progress != null;

  /// Whether this build can replace itself.
  bool get _canInstall => UpdateInstallResolution.installer.supported;

  /// Asks GitHub again, because somebody pressed the button that says so.
  Future<void> _check() async {
    setState(() => _asking = true);
    // The checker never throws — every failure is an [UpdateOutcome] — so there
    // is nothing to guard here but the widget's own lifetime.
    final answer = await UpdateResolution.checker.latest();
    if (!mounted) return;
    setState(() {
      _answer = answer;
      _asking = false;
    });
  }

  /// Downloads the newer build, checks it, and hands this folder over to it.
  ///
  /// On success this does not come back: the installer ends the process, because
  /// the files it replaces are open until it does. What the page shows after
  /// that call is therefore the last thing the old build draws, which is the
  /// whole reason the hand-over is announced on screen before it is started.
  Future<void> _install() async {
    final answer = _answer;
    if (answer == null || answer.outcome != UpdateOutcome.available) return;
    setState(() {
      _failure = null;
      _leftOver = null;
      _progress = const UpdateInstallProgress(UpdateInstallStage.downloading);
    });
    final result = await UpdateInstallResolution.installer.install(
      answer,
      onProgress: (progress) {
        if (mounted) setState(() => _progress = progress);
      },
    );
    if (!mounted) return;
    if (result.handedOver) {
      // A hand-over does not return, so this is a stand-in answering. Leaving
      // the last progress on screen is the honest rendering of "the process
      // this is running in is about to end".
      return;
    }
    setState(() {
      _failure = result.failure;
      _progress = null;
    });
  }

  /// What an update that is under way is doing, as a sentence.
  ///
  /// Null for the two stages that are not "under way" — nothing is in flight
  /// and something failed — because those are not progress: the first has
  /// nothing to say and the second says [UpdateInstallFailure]'s own sentence.
  String? _progressSentence(
    UpdateInstallProgress progress,
    AppLocalizations l10n,
  ) {
    switch (progress.stage) {
      case UpdateInstallStage.downloading:
        // The byte counts are the existing pair from the Transfers surface,
        // joined rather than baked into one string: a download whose length is
        // not known yet says only which of the two things is happening.
        return [
          l10n.aboutUpdateDownloading,
          if (progress.total > 0)
            l10n.bytesOf(
              formatBytes(progress.received),
              formatBytes(progress.total),
            ),
        ].join(' · ');
      case UpdateInstallStage.verifying:
        return l10n.aboutUpdateVerifying;
      case UpdateInstallStage.staging:
        return l10n.aboutUpdateStaging;
      case UpdateInstallStage.handingOver:
        return l10n.aboutUpdateHandingOver;
      case UpdateInstallStage.idle:
      case UpdateInstallStage.failed:
        return null;
    }
  }

  /// Where a newer build can be fetched, when one has been found.
  String? get _downloadUrl {
    final answer = _answer;
    if (answer == null || answer.outcome != UpdateOutcome.available) {
      return null;
    }
    return answer.url ?? updateReleasesPage;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = WeChatColors.of(context);
    final answer = _answer;
    final url = _downloadUrl;
    // Empty for the three outcomes that carry no release, which is what makes
    // the panel below appear exactly when there is a better version to describe
    // — `UpdateCheck.notes` is filled by `parseRelease` for that case alone.
    final notes = readUpdateNotes(answer?.notes);
    final progress = _progress;
    final failure = _failure;
    final leftOver = _leftOver;
    final canInstall =
        _canInstall && answer?.outcome == UpdateOutcome.available;
    final progressSentence = progress == null
        ? null
        : _progressSentence(progress, l10n);

    return ListView(
      padding: WeChat.pagePadding,
      children: [
        SectionHeader(title: l10n.tabAbout),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(WeChat.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(l10n.appTitle, style: theme.textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Text(
                      l10n.aboutVersion(appVersion),
                      style: TextStyle(
                        fontSize: WeChat.fontSizeMeta,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(l10n.aboutDescription),
                const Divider(height: 24),
                // A row that wraps, because the three buttons together are
                // wider than a narrow window: on a squeezed card an overflow
                // stripe is what a `Row` would draw, and a button nobody can
                // reach is worse than one that moved to the next line.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // The one action on this card a user reaches for, so it
                    // wears the filled style every other primary action in this
                    // application wears — 检查更新 is a *button*, not a link,
                    // and a flat green word was the odd one out beside the
                    // Connect and Send buttons elsewhere.
                    FilledButton.icon(
                      onPressed: _asking || _busy
                          ? null
                          : () => unawaited(_check()),
                      icon: const Icon(Icons.system_update_alt, size: 18),
                      label: Text(
                        _asking
                            ? l10n.aboutChecking
                            : l10n.aboutCheckForUpdates,
                      ),
                    ),
                    // The one-click way, on a platform whose packaging this
                    // build knows how to replace. Absent rather than disabled
                    // elsewhere: an inert button explains nothing.
                    if (canInstall)
                      FilledButton.icon(
                        onPressed: _busy ? null : () => unawaited(_install()),
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: Text(l10n.aboutUpdateInstall),
                      ),
                    // Opens a page rather than doing something in this window,
                    // so it stays the quiet style: the filled button above is
                    // what a user should press.
                    if (url != null)
                      TextButton.icon(
                        onPressed: () =>
                            unawaited(LinkResolution.opener.open(url)),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(l10n.aboutOpenDownload),
                      ),
                  ],
                ),
                if (answer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      describeUpdateCheck(answer, l10n),
                      style: TextStyle(
                        fontSize: WeChat.fontSizePreview,
                        color: answer.outcome == UpdateOutcome.available
                            ? colors.brand
                            : colors.secondaryText,
                      ),
                    ),
                  ),
                // What the newer build says it changes, under the version it
                // is. The version alone answers "is there something to fetch";
                // this is what answers "do I want it", which is the question a
                // user actually has in front of a button that will replace the
                // program they are running.
                if (notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _UpdateNotes(
                      notes: notes,
                      title: l10n.aboutUpdateNotes,
                    ),
                  ),
                if (progress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(value: progress.fraction),
                        if (progressSentence != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            progressSentence,
                            style: TextStyle(
                              fontSize: WeChat.fontSizeMeta,
                              color: colors.secondaryText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (failure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      describeUpdateInstallFailure(failure, l10n),
                      style: TextStyle(
                        fontSize: WeChat.fontSizePreview,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                // What a hand-over that never finished left behind, said once:
                // the read consumed it. Without this line the only trace of it
                // would be a window that came and went.
                if (failure == null && leftOver != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      describeUpdateInstallFailure(leftOver, l10n),
                      style: TextStyle(
                        fontSize: WeChat.fontSizePreview,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                // The address stays on screen even when the browser could not
                // be opened — a machine with no default handler is exactly the
                // machine that has to have somewhere to copy it from.
                if (url != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      url,
                      style: TextStyle(
                        fontSize: WeChat.fontSizeMeta,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                HintText(
                  canInstall
                      ? l10n.aboutUpdateInstallHint
                      : l10n.aboutHowToUpgrade,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// What the newer build says it changes.
///
/// A panel of its own rather than more lines of the sentence above it, because
/// the two are different kinds of thing: that sentence is this application
/// reporting what it found, and this is the release's own notes — a quotation,
/// in the release's words. The sunken fill is the one this design gives an
/// inset panel, which is also what keeps a long changelog from reading as part
/// of the card's own text.
///
/// The lines arrive already classified — see `update_notes.dart` — and the only
/// decisions taken here are the ones about drawing: a section of the notes is
/// bold and set off by a little space above it, an item is a bullet with its
/// text hanging beside it rather than under it, and anything else is prose.
class _UpdateNotes extends StatelessWidget {
  /// Draws [notes], under a [title] that says what they are.
  const _UpdateNotes({required this.notes, required this.title});

  /// The release's lines, in the order it wrote them.
  final List<UpdateNote> notes;

  /// What to call them: the section is labelled, because a quotation with no
  /// attribution on a card that is otherwise this app's own voice would read as
  /// something this app is claiming about itself.
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(WeChat.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: WeChat.fontSizeMeta,
              color: colors.secondaryText,
            ),
          ),
          for (var index = 0; index < notes.length; index++)
            _line(context, notes[index], first: index == 0),
        ],
      ),
    );
  }

  /// Draws one line of the notes, [first] being the one at the top.
  Widget _line(BuildContext context, UpdateNote note, {required bool first}) {
    final colors = WeChatColors.of(context);
    final panelTop = !first && note.kind == UpdateNoteKind.heading ? 8.0 : 2.0;
    switch (note.kind) {
      case UpdateNoteKind.heading:
        // The release's own section title — 新增, 修复 — so it is set apart by
        // weight rather than by size: a size smaller than the items it labels
        // would read as a footnote, and a larger one would compete with the
        // version line above the panel.
        return Padding(
          padding: EdgeInsets.only(top: panelTop),
          child: Text(
            note.text,
            style: TextStyle(
              fontSize: WeChat.fontSizePreview,
              fontWeight: FontWeight.w600,
              height: WeChat.lineHeightBody,
              color: colors.bubbleText,
            ),
          ),
        );
      case UpdateNoteKind.item:
        // The bullet hangs beside the text rather than in front of it: a
        // wrapped item that started its second line under the bullet instead of
        // under the first word would read as a sub-item of itself.
        return Padding(
          padding: EdgeInsets.only(top: panelTop),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '·',
                style: TextStyle(
                  fontSize: WeChat.fontSizePreview,
                  height: WeChat.lineHeightBody,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: _prose(context, note.text)),
            ],
          ),
        );
      case UpdateNoteKind.text:
        return Padding(
          padding: EdgeInsets.only(top: panelTop),
          child: _prose(context, note.text),
        );
    }
  }

  /// A line of the notes that is neither a section nor an item.
  Widget _prose(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: WeChat.fontSizePreview,
      height: WeChat.lineHeightBody,
      color: WeChatColors.of(context).bubbleText,
    ),
  );
}

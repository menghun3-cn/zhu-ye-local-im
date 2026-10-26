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
/// a button that could only ever fail is worse than no button. Installing is
/// two steps with a question between them: everything that can be done while
/// this build still runs happens without a word, and the step that ends the
/// process asks first — [_ConfirmUpdateDialog] — because the last thing this
/// build does before its window goes away is close itself on purpose.
class AboutPage extends StatefulWidget {
  /// Shows what this build is, installing [offeredUpdate] when asked to.
  const AboutPage({
    super.key,
    this.offeredUpdate,
    this.installRequest = 0,
    this.onUpdateBusyChanged,
  });

  /// What the application's own update check found, when it was asked at all.
  ///
  /// Handed down by the shell from the notice it already holds — see
  /// `UpdateNotice`, which is asked once as the application comes up — so that
  /// the rail's update entry can start an install on a card that has not been
  /// opened and asked first. It is *not* shown for that reason alone: the
  /// answer is adopted only when a request arrives, which is what keeps this
  /// card saying nothing until somebody asks it something.
  final UpdateCheck? offeredUpdate;

  /// How many times the user has asked for the newer build to be installed.
  ///
  /// Counted by the shell, which is the only thing that knows the rail's
  /// update entry was pressed. A change in it is that press arriving: the
  /// rail has no room for a download's progress, the question before closing
  /// or the sentence an attempt ends in, and this card has all three — so the
  /// entry hands the work here rather than duplicating it in a 72-pixel strip.
  ///
  /// A counter rather than a pending flag, so that two presses are two
  /// installs and a rebuild in between is not one.
  final int installRequest;

  /// What the shell's rail entry should hear about the phases of an update.
  ///
  /// The rail has no room for a download's progress, so the one thing it needs
  /// from the card is whether its own entry may be pressed: while a download or
  /// the closing hand-over is in flight a second press must not be possible.
  final ValueChanged<bool>? onUpdateBusyChanged;

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

  /// What has been fetched and checked, waiting for the word that puts it in
  /// place, or null.
  ///
  /// Kept rather than thrown away when the question is answered no: the package
  /// is already in the update folder, so offering it again costs nothing and
  /// fetching it again would cost twenty megabytes for nothing.
  PreparedUpdate? _prepared;

  @override
  void initState() {
    super.initState();
    _leftOver = UpdateInstallResolution.installer.previousFailure();
  }

  /// Tells the rail whether an update is in flight, when there is a rail.
  void _reportBusy(bool busy) => widget.onUpdateBusyChanged?.call(busy);

  @override
  void didUpdateWidget(AboutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The rail's entry was pressed. The answer it was drawn from is adopted
    // first: the card may never have been asked, and an install needs a
    // version to fetch.
    final installRequest = widget.installRequest;
    if (installRequest == oldWidget.installRequest) return;
    // While a download is in flight or the page is asking GitHub, a second
    // press is only the same request again, so it is dropped rather than
    // queued twice. Once the package is ready, `_busy` is null again and a
    // later press is what is behind the currently open question — it has to
    // reach this same dialog, not become a second install.
    if (_asking || (_busy && _prepared == null)) return;
    unawaited(_install(offered: widget.offeredUpdate ?? _answer));
  }

  /// Whether an update is in flight.
  bool get _busy => _progress != null;

  /// Whether this build can replace itself.
  bool get _canInstall => UpdateInstallResolution.installer.supported;

  /// Asks GitHub again, because somebody pressed the button that says so.
  Future<void> _check() async {
    setState(() => _asking = true);
    _reportBusy(true);
    // The checker never throws — every failure is an [UpdateOutcome] — so there
    // is nothing to guard here but the widget's own lifetime.
    final answer = await UpdateResolution.checker.latest();
    if (!mounted) return;
    setState(() {
      _answer = answer;
      _asking = false;
      // A fresh question invalidates anything a previous one readied: the
      // version it named may not be the one on offer now, and a package for a
      // version nobody asked about is litter with a download in it.
      _prepared = null;
    });
    _reportBusy(false);
  }

  /// Downloads the newer build, checks it, and hands this folder over to it.
  ///
  /// In two steps with a question between them. The first is everything that
  /// can be done while this build still runs — fetching, checking, unpacking —
  /// and it answers with what is ready or why nothing is. What is left ends the
  /// process, because the files it replaces are open until it does, so the user
  /// is asked before anything closes: on success this does not come back, and
  /// what the page shows after that call is the last thing the old build draws.
  ///
  /// [offered] is the answer to install when the caller has one this page was
  /// never asked for — the rail's update entry, pressing straight through to
  /// here from the application's own check. It defaults to what this card last
  /// asked, which is the road this page's own button takes. Either way the
  /// answer is adopted as this page's own, so the card describes the update it
  /// is carrying out rather than staying silent about one that is under way.
  ///
  /// The rail is told about the phases out of band — after the build phase a
  /// press-pushed `didUpdateWidget` is in, the parent shell must not be marked
  /// dirty from inside it. The enter/exit edges of the update are reported by
  /// the async work itself, so whichever press opened them lands with the
  /// frame.
  Future<void> _install({UpdateCheck? offered}) async {
    // The button is disabled as soon as the first progress state lands. Guard
    // the method itself as well so two entry points in one frame cannot start
    // two downloads before that disabled frame is drawn.
    if (_busy) return;
    final answer = offered ?? _answer;
    if (answer == null || answer.outcome != UpdateOutcome.available) return;
    final installer = UpdateInstallResolution.installer;
    final restarts = installer.restartsApplication;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportBusy(true));
    setState(() => _answer = answer);
    var prepared = _prepared;
    if (prepared == null) {
      setState(() {
        _failure = null;
        _leftOver = null;
        _progress = const UpdateInstallProgress(UpdateInstallStage.downloading);
      });
      final staged = await installer.prepare(
        answer,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      prepared = staged.prepared;
      if (prepared == null) {
        setState(() {
          _failure = staged.failure;
          _progress = null;
        });
        _reportBusy(false);
        return;
      }
      setState(() {
        _prepared = prepared;
        // Nothing is in flight any more: what is left is a question, and a
        // progress bar over a question is a claim about work that is not
        // happening.
        _progress = null;
      });
    }
    // The question. Everything the update still has to do ends this process,
    // and the user is the one who has to say so — the package is already in
    // place, so answering no costs nothing and changes nothing.
    final closing = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmUpdateDialog(
        version: answer.version ?? '',
        restartsApplication: restarts,
      ),
    );
    if (!mounted) return;
    if (closing != true) {
      setState(() => _progress = null);
      _reportBusy(false);
      return;
    }
    setState(() {
      // The question is past: what is left closes this program, so the buttons
      // that opened the question have nothing left to say.
      _progress = UpdateInstallProgress(
        restarts
            ? UpdateInstallStage.handingOver
            : UpdateInstallStage.installing,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportBusy(true));
    try {
      await installer.apply(
        prepared,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
    } on UpdateInstallException catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error.failure;
        _progress = null;
      });
      _reportBusy(false);
      return;
    } on Object {
      if (!mounted) return;
      setState(() {
        _failure = UpdateInstallFailure.installer;
        _progress = null;
      });
      _reportBusy(false);
      return;
    }
    if (!mounted) return;
    if (!restarts) {
      // Android returns as soon as the system installer has been opened. The
      // APK stays on disk so cancelling there and pressing again costs no new
      // download.
      setState(() => _progress = null);
    }
    // A scripted installer returns without ending the process; the real one
    // never reaches here. Unlock only so a test that walks through the whole
    // flow does not leave the rail pinned behind it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportBusy(false));
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
      case UpdateInstallStage.installing:
        return l10n.aboutUpdateInstalling;
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
    final prepared = _prepared;
    final installer = UpdateInstallResolution.installer;
    final restarts = installer.restartsApplication;
    final canInstall =
        _canInstall && answer?.outcome == UpdateOutcome.available;
    final installHint = restarts
        ? l10n.aboutUpdateInstallHint
        : l10n.aboutUpdateInstallHintAndroid;
    final readyText = restarts
        ? l10n.aboutUpdateReady
        : l10n.aboutUpdateReadyAndroid;
    final manualHint = _canInstall && !restarts
        ? l10n.aboutHowToUpgradeAndroid
        : l10n.aboutHowToUpgrade;
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
                // A row that wraps, because the primary action and the
                // secondary link are wider than a narrow window: on a squeezed
                // card an overflow stripe is what a `Row` would draw, and a
                // button nobody can reach is worse than one on the next line.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // One primary action changes role with the answer: ask for
                    // an update, then install the one that was found. Keeping
                    // both actions visible would make the user choose between
                    // two steps the card already knows how to order.
                    FilledButton.icon(
                      onPressed: _asking || _busy
                          ? null
                          : canInstall
                          ? () => unawaited(_install())
                          : () => unawaited(_check()),
                      icon: const Icon(Icons.system_update_alt, size: 18),
                      label: Text(
                        _asking
                            ? l10n.aboutChecking
                            : canInstall
                            ? l10n.aboutUpdate
                            : l10n.aboutCheckForUpdates,
                      ),
                    ),
                    // Opens a page rather than doing something in this window,
                    // so it stays the quiet style: the filled button above is
                    // what a user should press.
                    if (url != null)
                      TextButton.icon(
                        onPressed: _asking || _busy
                            ? null
                            : () => unawaited(LinkResolution.opener.open(url)),
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
                // What a fetched package is waiting for. Not a progress line —
                // nothing is in flight — and not a failure either: answering no
                // to the question left the package exactly where it was.
                if (prepared != null && failure == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      readyText,
                      style: TextStyle(
                        fontSize: WeChat.fontSizePreview,
                        color: colors.brand,
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
                HintText(canInstall ? installHint : manualHint),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The question an update asks before anything closes.
///
/// A dialog of its own rather than a line on the card: what it is asking about
/// is the window going away, and a question that shared a surface with the
/// progress it follows would read as one more status line. Answering no is the
/// quiet option and also the safe one — the package stays in the update folder
/// and the application carries on exactly as it was.
class _ConfirmUpdateDialog extends StatelessWidget {
  /// Asks about installing [version].
  const _ConfirmUpdateDialog({
    required this.version,
    required this.restartsApplication,
  });

  /// The version that has been fetched and checked.
  final String version;

  /// Whether confirming closes this process and starts it again.
  final bool restartsApplication;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        restartsApplication
            ? l10n.aboutUpdateConfirmTitle
            : l10n.aboutUpdateConfirmTitleAndroid,
      ),
      content: Text(
        restartsApplication
            ? l10n.aboutUpdateConfirmBody(version)
            : l10n.aboutUpdateConfirmBodyAndroid(version),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            restartsApplication
                ? l10n.aboutUpdateConfirmApply
                : l10n.aboutUpdateConfirmApplyAndroid,
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../external_links.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../update_check.dart';
import '../update_install.dart';
import '../update_notes.dart';
import '../update_session.dart';
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
  /// Shows what this build is, installing through [session] when asked to.
  const AboutPage({super.key, this.session, this.onUpdateBusyChanged});

  /// The update the shell is carrying out, when there is one.
  ///
  /// The download, its progress, the package waiting for the question and the
  /// sentence a failure arrives as all live in the session rather than here,
  /// because this page is not always built: My shows it only while its
  /// sub-page is open, and a download owned by a page that can go away is a
  /// download that goes away with it. A session handed in is the shell's and
  /// outlives this page; one made here is this page's own, for a tree that
  /// has no shell above it — a test, mostly.
  final UpdateInstallSession? session;

  /// What the shell's rail entry should hear about the phases of an update.
  ///
  /// The rail has no room for a download's progress, so the one thing it needs
  /// from the card is whether its own entry may be pressed while the card's
  /// own *check* is out — the install's phases are heard from the session
  /// itself, which is why they are not reported through here any more.
  final ValueChanged<bool>? onUpdateBusyChanged;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// The session this page reports, handed in or made for this page alone.
  late final UpdateInstallSession _session;

  /// Whether [_session] was made here and is this state's to dispose.
  bool _ownsSession = false;

  /// The last answer this card asked for, or null while none has been.
  ///
  /// The session keeps its own answer — the one an install was started
  /// for — and it is the one the card describes while there is one; this is
  /// the fallback for the ordinary "check for updates" road.
  UpdateCheck? _answer;

  /// Whether a question is out. The button is inert while it is, because a
  /// second press would only ask the same thing again.
  bool _asking = false;

  /// Why the last hand-over this app ever attempted did not finish, or null.
  ///
  /// Read once, as the page is built for the first time, and consumed by that
  /// read: on the run *after* a failed hand-over there is no other trace of it
  /// — the build that failed was the new one, and what it left behind is a
  /// window that came and went.
  UpdateInstallFailure? _leftOver;

  /// The prepared update the question has already been asked about, or null.
  ///
  /// A package that appears is followed by the question once — the way it
  /// always was — unless it is one a restart found on disk, which is offered
  /// rather than announced. Answering no keeps the package, and the press
  /// that asks again is a new [UpdateInstallSession.confirmRequests] count,
  /// not this field changing.
  PreparedUpdate? _askedPrepared;

  /// The session's [UpdateInstallSession.confirmRequests] this page has
  /// already answered, so a request made while the page was not built is not
  /// replayed on every visit — only a press that arrives while it is.
  int _seenConfirmRequests = 0;

  @override
  void initState() {
    super.initState();
    final handed = widget.session;
    _session = handed ?? UpdateInstallSession();
    _ownsSession = handed == null;
    _leftOver = UpdateInstallResolution.installer.previousFailure();
    _seenConfirmRequests = _session.confirmRequests;
    _session.addListener(_onSession);
    // The session may already hold an answer from before this page existed —
    // a download that finished while the user was on another surface, or a
    // package a restart found. The question it leads to needs a frame first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSession());
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    if (_ownsSession) _session.dispose();
    super.dispose();
  }

  /// Tells the rail whether the card's own check is in flight.
  void _reportBusy(bool busy) => widget.onUpdateBusyChanged?.call(busy);

  /// Whether this build can replace itself.
  bool get _canInstall => UpdateInstallResolution.installer.supported;

  /// Reacts to whatever the session now holds.
  ///
  /// The session's fields are the card's fields, so the first thing every
  /// change gets is a rebuild. Two things are not drawing and follow it: a
  /// prepared update that has not been asked about — which is followed by the
  /// question, the way it always was, unless a restart found it on disk and
  /// it is only offered — and a request for the question counted while this
  /// page was not built, which is answered the moment it is. The leftover
  /// hand-over sentence is also retired here: once an update is under way or
  /// has ended, it is a report about a run that is no longer this one.
  void _onSession() {
    if (!mounted) return;
    setState(() {
      if (_leftOver != null &&
          (_session.progress != null ||
              _session.prepared != null ||
              _session.failure != null)) {
        _leftOver = null;
      }
    });
    final prepared = _session.prepared;
    if (prepared != null && prepared != _askedPrepared) {
      _askedPrepared = prepared;
      if (!_session.preparedIsRestore) _askToApply();
      return;
    }
    if (_session.confirmRequests != _seenConfirmRequests) {
      _seenConfirmRequests = _session.confirmRequests;
      if (_session.prepared != null) _askToApply();
    }
  }

  /// Puts the question an update asks before anything closes.
  ///
  /// A dialog of its own rather than a line on the card: what it is asking
  /// about is the window going away, and a question that shared a surface
  /// with the progress it follows would read as one more status line.
  /// Answering no is the quiet option and also the safe one — the package
  /// stays in the update folder and the application carries on exactly as it
  /// was.
  Future<void> _askToApply() async {
    final prepared = _session.prepared;
    if (prepared == null || !mounted) return;
    final restarts = UpdateInstallResolution.installer.restartsApplication;
    final closing = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmUpdateDialog(
        version: _session.answer?.version ?? '',
        restartsApplication: restarts,
      ),
    );
    if (!mounted || closing != true) return;
    await _session.apply(prepared);
  }

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
    });
    // A fresh question invalidates anything a previous one readied: the
    // version it named may not be the one on offer now, and a package for a
    // version nobody asked about is litter with a download in it.
    _session.reset();
    _reportBusy(false);
  }

  /// Whether an install or its download is in flight.
  ///
  /// The session's own busy edge: while a package is merely *waiting* for the
  /// question nothing is running, and the button stays live — pressing it is
  /// how the question is asked again, which is what answering no leaves
  /// behind.
  bool get _installing => _session.busy;

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
      case UpdateInstallStage.idle:
      case UpdateInstallStage.failed:
        return null;
      case UpdateInstallStage.installing:
        return l10n.aboutUpdateInstalling;
    }
  }

  /// Where a newer build can be fetched, when one has been found.
  String? get _downloadUrl {
    final answer = _session.answer ?? _answer;
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
    // The session's answer is the one an install was started for — adopted
    // from the rail's entry or this card's own press — and it is the one the
    // card describes while there is one. The card's own last check is the
    // fallback for the ordinary road.
    final answer = _session.answer ?? _answer;
    final url = _downloadUrl;
    // Empty for the three outcomes that carry no release, which is what makes
    // the panel below appear exactly when there is a better version to describe
    // — `UpdateCheck.notes` is filled by `parseRelease` for that case alone.
    final notes = readUpdateNotes(answer?.notes);
    final progress = _session.progress;
    final failure = _session.failure;
    final leftOver = _leftOver;
    final prepared = _session.prepared;
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
                      onPressed: _asking || _installing
                          ? null
                          : canInstall
                          ? () => unawaited(_session.install(answer!))
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
                        onPressed: _asking || _installing
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

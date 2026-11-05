import 'package:flutter/foundation.dart';

import 'update_check.dart';
import 'update_install.dart';

/// One update, from "there is a newer build" to "it is in place".
///
/// The work an install is — fetching the package, checking it, unpacking it,
/// and the hand-over that ends this process — used to live in the About
/// page's state, which meant it lived exactly as long as the page did: backing
/// out of the sub-page dropped the answer the download had produced, and a
/// second press while the first was still running could put two fetches on
/// the same partial file. This session is the owner instead, and it is owned
/// by the shell, which is the one widget that outlives every page: a download
/// that is under way when the user looks at something else is still under way
/// when they come back, and a package that finished fetching while they were
/// away is still ready to install.
///
/// It is also where a *finished* download is found again after a restart. The
/// package stays in the update folder between runs — see
/// `update_install.dart` — so [restore] asks the installer whether the file
/// the answer names is already there, whole and matching the checksum the
/// release published, and only then runs the same [UpdateInstaller.prepare]
/// a fresh install would: the digest check makes that a local verify and
/// unpack rather than a download. A package that is not there is not fetched
/// — restoring must never be the thing that starts a download nobody asked
/// for.
///
/// The question before the process ends is still the page's: this session
/// reports [prepared] and counts [confirmRequests], and the About card turns
/// either into the dialog — see `about_page.dart`.
class UpdateInstallSession extends ChangeNotifier {
  /// Starts idle: no answer adopted, nothing in flight, nothing ready.
  UpdateInstallSession();

  /// The answer the work in flight — or waiting — is for.
  UpdateCheck? _answer;

  /// What the installer last reported, or null when nothing is in flight.
  UpdateInstallProgress? _progress;

  /// Why the last attempt ended without anything ready, or null.
  UpdateInstallFailure? _failure;

  /// What is fetched, checked and staged, waiting for the word that puts it
  /// in place — or null.
  PreparedUpdate? _prepared;

  /// Whether [_prepared] came from [restore] rather than from a press.
  ///
  /// The difference is what the page does with it: a prepared update that a
  /// download just produced is followed by the question straight away, the
  /// way it always was, while one a restart found on disk is only *offered* —
  /// the user opening the About page is not a request to close the app, so
  /// the card shows it ready and waits for the press that means it.
  bool _preparedIsRestore = false;

  /// The prepare call in flight, so a second request joins it rather than
  /// starting a second fetch of the same package.
  Future<void>? _inFlight;

  /// How many times somebody has asked for the question to be put again.
  ///
  /// Counted rather than called, because the surface that can draw the
  /// question — the About card — may not be built when the request arrives:
  /// the rail's entry can be pressed from any surface. A change in the count
  /// is a request; the card answers the change the way it answers
  /// `installRequest` used to travel.
  int _confirmRequests = 0;

  /// The version [restore] has already looked for on disk, or null.
  ///
  /// Once per version per run: a package that is not there stays not there
  /// until a press fetches it, and re-asking the disk on every rebuild would
  /// be a digest check per frame.
  String? _restoreLookedFor;

  /// Whether [dispose] has run. A prepare still in flight when the shell goes
  /// away finishes into fields nobody reads, and a notification nobody is
  /// listening for is only noise — or an assertion, in a debug build.
  bool _disposed = false;

  /// The answer the work is for, or null while none has been asked for.
  UpdateCheck? get answer => _answer;

  /// What the update is doing, or null when nothing is.
  UpdateInstallProgress? get progress => _progress;

  /// Why the last attempt failed, or null.
  UpdateInstallFailure? get failure => _failure;

  /// What is ready to put in place, or null.
  PreparedUpdate? get prepared => _prepared;

  /// Whether [prepared] was found on disk rather than just fetched.
  bool get preparedIsRestore => _preparedIsRestore;

  /// How many times the question has been asked for again.
  int get confirmRequests => _confirmRequests;

  /// Whether work is in flight: a fetch, a check, an unpack, a hand-over.
  ///
  /// False while a prepared update waits for the question — nothing is
  /// running then, and the entry that started it stays pressable so a second
  /// press can be the answer "ask me again" rather than "start over".
  bool get busy => _progress != null;

  /// Whether this build can replace itself at all.
  bool get supported => UpdateInstallResolution.installer.supported;

  /// Whether applying an update ends this process and starts it again.
  bool get restartsApplication =>
      UpdateInstallResolution.installer.restartsApplication;

  /// Fetches, checks and stages [answer] — everything that can be done while
  /// this build still runs — unless it is already under way or already done.
  ///
  /// The entry point for "install this": the About card's button and the
  /// rail's entry both land here. When a prepared update for the same version
  /// is already waiting, the press is not a second download — it is a request
  /// for the question, counted in [confirmRequests] for whichever surface is
  /// showing.
  Future<void> install(UpdateCheck answer) async {
    if (answer.outcome != UpdateOutcome.available) return;
    _useAnswer(answer);
    if (busy) return;
    if (_prepared != null) {
      _confirmRequests++;
      _notify();
      return;
    }
    await _prepare(answer, restored: false);
  }

  /// Looks for a download [answer] already finished on an earlier run, and
  /// stages it when it is there.
  ///
  /// The package a completed fetch leaves in the update folder is the whole
  /// point of that folder keeping it — see `update_install.dart` — so a
  /// restart finds it by asking the installer, which knows both where the
  /// file lives and which shape of copy this is. Nothing is fetched here:
  /// when the file is not there, or is not what the release published, this
  /// answers without touching the network, and the next press downloads as
  /// it always did.
  Future<void> restore(UpdateCheck answer) async {
    if (answer.outcome != UpdateOutcome.available) return;
    if (busy || _prepared != null) return;
    if (_restoreLookedFor == answer.version) return;
    _restoreLookedFor = answer.version;
    _useAnswer(answer);
    final bool fetched;
    try {
      fetched = await UpdateInstallResolution.installer.hasFetchedPackage(
        answer,
      );
    } on Object {
      return;
    }
    // The wait above is long enough for a press to have started the real
    // thing: joining that is correct, starting a second prepare is not.
    if (!fetched || busy || _prepared != null) return;
    await _prepare(answer, restored: true);
  }

  /// Forgets the answer and whatever it readied, when nothing is in flight.
  ///
  /// What a fresh question from the About card amounts to: the version it
  /// names may not be the one a previous answer readied, and a package for a
  /// version nobody asked about is litter with a download in it.
  void reset() {
    if (busy) return;
    _answer = null;
    _progress = null;
    _failure = null;
    _prepared = null;
    _preparedIsRestore = false;
    _notify();
  }

  /// Puts [prepared] in place — the step that ends this process on the
  /// platforms that replace themselves.
  ///
  /// What the page calls once the question has been answered yes. Progress
  /// and failure land in the same fields a prepare reports them in, because
  /// to a surface watching they are the same update getting closer or
  /// further away.
  Future<void> apply(PreparedUpdate prepared) async {
    if (busy) return;
    final installer = UpdateInstallResolution.installer;
    _failure = null;
    try {
      await installer.apply(
        prepared,
        onProgress: (progress) {
          _progress = progress;
          _notify();
        },
      );
    } on UpdateInstallException catch (error) {
      _failure = error.failure;
      _progress = null;
      _notify();
      return;
    } on Object {
      _failure = UpdateInstallFailure.installer;
      _progress = null;
      _notify();
      return;
    }
    if (!installer.restartsApplication) {
      // Android returns as soon as the system installer has been opened. The
      // package stays on disk so cancelling there and pressing again costs no
      // new download — which is what the ready line on the card says.
      _progress = null;
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Tells the listeners, unless the session is already gone.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Adopts [answer] as the one the session works for.
  ///
  /// A different version drops what an earlier answer readied — the package
  /// for it is litter the next prepare's own housekeeping takes away. While
  /// work is in flight nothing is dropped: the fetch already running is for
  /// the version it was started with, and its answer is discarded on arrival
  /// rather than here, so the bytes it leaves are still the resume point a
  /// retry starts from.
  void _useAnswer(UpdateCheck answer) {
    final same = _answer?.version == answer.version;
    _answer = answer;
    if (same || busy) return;
    _prepared = null;
    _preparedIsRestore = false;
    _failure = null;
    _progress = null;
  }

  /// Runs [UpdateInstaller.prepare] once for [check], however many callers
  /// arrive while it is running.
  Future<void> _prepare(UpdateCheck check, {required bool restored}) {
    final running = _inFlight;
    if (running != null) return running;
    _failure = null;
    _progress = const UpdateInstallProgress(UpdateInstallStage.downloading);
    final installer = UpdateInstallResolution.installer;
    late final Future<void> future;
    future = () async {
      UpdatePrepareResult result;
      try {
        result = await installer.prepare(
          check,
          onProgress: (progress) {
            // Progress for a version this session has moved on from is not
            // this update's progress.
            if (_answer?.version == check.version) {
              _progress = progress;
              _notify();
            }
          },
        );
      } on Object {
        // The interface answers with a result rather than throwing; a
        // stand-in that breaks that contract still gets the same sentence a
        // fetch that did not arrive gets.
        result = const UpdatePrepareResult.failed(
          UpdateInstallFailure.download,
        );
      }
      _inFlight = null;
      if (_answer?.version != check.version) {
        // Superseded while it ran: its prepared update is for a version
        // nobody is looking at any more.
        _progress = null;
      } else if (result.prepared != null) {
        _prepared = result.prepared;
        _preparedIsRestore = restored;
        _progress = null;
      } else {
        _failure = result.failure;
        _progress = null;
      }
      _notify();
    }();
    _inFlight = future;
    _notify();
    return future;
  }
}

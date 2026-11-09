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
/// There is no question before the process ends: the press that asked for the
/// update is the answer to it. A prepare that finishes — fetched, checked and
/// staged — is applied straight away, and a press that finds a package already
/// waiting applies that rather than downloading again. The one exception is
/// [restore]: a package a restart found on disk is only *offered*, because
/// opening the About page is not a request to close the app.
class UpdateInstallSession extends ChangeNotifier {
  /// Starts idle: no answer adopted, nothing in flight, nothing ready.
  UpdateInstallSession();

  /// The answer the work in flight — or waiting — is for.
  UpdateCheck? _answer;

  /// What the installer last reported, or null when nothing is in flight.
  UpdateInstallProgress? _progress;

  /// Why the last attempt ended without anything ready, or null.
  UpdateInstallFailure? _failure;

  /// What is fetched, checked and staged, waiting to be put in place — or
  /// null.
  ///
  /// A package reached this way without [restore] is applied the moment it
  /// lands, so in practice it is only ever set for a restored package — the
  /// one case where "found on disk" is not "just asked for".
  PreparedUpdate? _prepared;

  /// The prepare call in flight, so a second request joins it rather than
  /// starting a second fetch of the same package.
  Future<void>? _inFlight;

  /// Whether [apply] is running: the hand-over that ends this process.
  ///
  /// Tracked beside [_progress] rather than as a stage of it, because the
  /// hand-over reports no progress of its own on the platforms that replace
  /// themselves — and a [UpdateInstallStage] that drew a bar for it would be
  /// a bar for a process that is already on its way out.
  bool _applying = false;

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

  /// Whether work is in flight: a fetch, a check, an unpack, a hand-over.
  ///
  /// False while a prepared update waits to be applied — nothing is running
  /// then, and the entry that started it stays pressable so a second press is
  /// the apply rather than a second download.
  bool get busy => _progress != null || _applying;

  /// Whether this build can replace itself at all.
  bool get supported => UpdateInstallResolution.installer.supported;

  /// Whether applying an update ends this process and starts it again.
  bool get restartsApplication =>
      UpdateInstallResolution.installer.restartsApplication;

  /// Fetches, checks and stages [answer] — everything that can be done while
  /// this build still runs — unless it is already under way or already done,
  /// and then puts it in place: the press that asked for the update is the
  /// consent the hand-over needs, so a finished prepare is applied without a
  /// second question.
  ///
  /// The entry point for "install this": the About card's button and the
  /// rail's entry both land here. When a prepared update for the same version
  /// is already waiting — one [restore] found on disk — the press is not a
  /// second download: it is the apply.
  Future<void> install(UpdateCheck answer) async {
    if (answer.outcome != UpdateOutcome.available) return;
    _useAnswer(answer);
    if (busy) return;
    final ready = _prepared;
    if (ready != null) {
      await apply(ready);
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
    _notify();
  }

  /// Puts [prepared] in place — the step that ends this process on the
  /// platforms that replace themselves.
  ///
  /// What [install] calls once there is nothing left to fetch: a prepare that
  /// just finished calls it itself, and a press on a package [restore] found
  /// waiting calls it through [install]. Progress and failure land in the
  /// same fields a prepare reports them in, because to a surface watching they
  /// are the same update getting closer or further away.
  Future<void> apply(PreparedUpdate prepared) async {
    if (busy) return;
    final installer = UpdateInstallResolution.installer;
    _applying = true;
    _failure = null;
    _notify();
    try {
      await installer.apply(
        prepared,
        onProgress: (progress) {
          _progress = progress;
          _notify();
        },
      );
    } on UpdateInstallException catch (error) {
      _applying = false;
      _failure = error.failure;
      _progress = null;
      _notify();
      return;
    } on Object {
      _applying = false;
      _failure = UpdateInstallFailure.installer;
      _progress = null;
      _notify();
      return;
    }
    _applying = false;
    // Android returns as soon as the system installer has been opened. The
    // package stays on disk so cancelling there and pressing again costs no
    // new download — which is what the ready line on the card says. On the
    // platforms that replace themselves this line is never reached: the
    // process is already gone.
    _progress = null;
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
        _progress = null;
        _notify();
        if (!restored) {
          // Everything that could be done while this build ran has been, so
          // the hand-over follows without a second question — the press that
          // started the download already answered it. A restored package is
          // the exception: finding one on disk is not a request to close the
          // app, so it waits for the press that means it.
          await apply(result.prepared!);
        }
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

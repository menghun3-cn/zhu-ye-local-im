import 'package:flutter/foundation.dart';

import 'update_check.dart';

/// Whether a newer build has been published, asked once per run.
///
/// The rail's update entry has to know the answer *before* anybody opens the
/// About surface, so the question is asked once as the application comes up and
/// the answer is kept here until the process ends. This is the one place in the
/// product that talks to anything outside the local network nobody having asked
/// it to at that moment, and it is the deliberate exception the About text
/// names: a build that never looked could only ever tell a user about an upgrade
/// they had already thought to go looking for.
///
/// ## Why it is not part of the controller
///
/// [LocalTransferController] is the one object a screen talks to, and this
/// deliberately is not in it. The controller's job is Devices, Sessions and
/// Transfers, and the interface it would need — an [UpdateChecker] — lives in
/// this layer: `lib/app` may not import Flutter, and it may not reach upwards
/// into `lib/ui` either. What the two share is a lifetime, not a subject.
///
/// ## Asked through the shared seam
///
/// [UpdateResolution.checker], which is the same checker the About surface
/// reads, rather than one of its own. Two ways to ask would be two things for a
/// test to stand in for, and two answers that could disagree with each other on
/// one screen.
class UpdateNotice extends ChangeNotifier {
  /// Starts with no answer. Call [check] to ask for one.
  UpdateNotice();

  UpdateCheck? _answer;

  /// The last answer, or null while none has arrived.
  ///
  /// Every outcome is kept, not only the interesting one: a caller that wants
  /// to say "the question could not be asked" needs the difference between that
  /// and "nothing has been asked yet", and `null` versus an outcome is how the
  /// two are told apart.
  UpdateCheck? get answer => _answer;

  /// The version to upgrade to, or null when there is nothing newer to fetch.
  String? get version =>
      _answer?.outcome == UpdateOutcome.available ? _answer?.version : null;

  /// Whether there is something newer to fetch.
  bool get hasUpdate => version != null;

  /// Where to fetch it.
  ///
  /// The release the answer came from when it named one, and the download page
  /// otherwise — the same fallback the About surface makes, and for the same
  /// reason: an answer whose `html_url` was missing still leaves a browser able
  /// to open the page a person would have gone to by hand.
  String? get url => hasUpdate ? (_answer?.url ?? updateReleasesPage) : null;

  /// Asks once.
  ///
  /// Safe to call un-awaited from `initState`, which is the one call site: the
  /// interface promises an outcome rather than an exception for every way the
  /// question can fail, and the real checker keeps that promise. The catch is
  /// here for the call site rather than for the checker — nobody is waiting on
  /// this future, so a double that broke the contract would surface as an
  /// unhandled error rather than as the "could not ask" state that already
  /// exists.
  Future<void> check() async {
    UpdateCheck answer;
    try {
      answer = await UpdateResolution.checker.latest();
    } on Object {
      answer = UpdateCheck.unreachable;
    }
    _answer = answer;
    notifyListeners();
  }
}

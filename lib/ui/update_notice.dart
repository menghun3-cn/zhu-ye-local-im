import 'package:flutter/foundation.dart';

import 'update_check.dart';

/// Whether a newer build has been published, asked once per run.
///
/// The rail's update entry has to know the answer *before* anybody opens the
/// About surface, so the question is asked once as the application comes up and
/// the answer is kept here until the process ends. This is the one place in the
/// product that talks to anything outside the local network without somebody
/// having asked it to at that moment, and it is the deliberate exception the
/// About text names: a build that never looked could only ever tell a user about
/// an upgrade they had already thought to go looking for.
///
/// ## Why it is not part of the controller
///
/// `LocalTransferController` is the one object a screen talks to, and this
/// deliberately is not in it. The controller's job is Devices, Sessions and
/// Transfers; the interface this needs — an [UpdateChecker] — lives in this
/// layer, and `lib/app` may neither import Flutter nor reach upwards into
/// `lib/ui`. What the controller and this notice share is a lifetime, not a
/// subject.
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

  /// The whole answer, or null while none has arrived.
  ///
  /// Every outcome is kept rather than only the interesting one, and this is
  /// what tells the four of them apart: [version] and [url] both collapse
  /// "nothing published", "the question could not be asked" and "this build is
  /// the latest" into a single null, because the rail does the same thing with
  /// all three. Anything that needs to say *which* one happened reads it here.
  UpdateCheck? get answer => _answer;

  /// The version to upgrade to, or null when there is nothing to offer.
  String? get version =>
      _answer?.outcome == UpdateOutcome.available ? _answer?.version : null;

  /// Where to fetch [version], or null when there is nothing to offer.
  ///
  /// The release the answer came from when it named one, and the download page
  /// otherwise — the same fallback the About surface makes, and for the same
  /// reason: an answer whose `html_url` was missing still leaves a browser able
  /// to open the page a person would have gone to by hand.
  String? get url =>
      version == null ? null : (_answer?.url ?? updateReleasesPage);

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

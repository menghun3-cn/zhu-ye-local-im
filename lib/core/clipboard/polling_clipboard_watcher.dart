import 'dart:async';

/// Turns "read a value and see whether it changed" into a change stream.
///
/// Windows is the one v1 platform with a real clipboard-change notification —
/// `AddClipboardFormatListener` on a message-only window — and this app cannot
/// open one while it ships no plugins. So the app polls, and this is the poll
/// loop, with the read injected. Every decision in it — what gets reported,
/// what does not, when it stops, what happens to a failed read — is a decision
/// worth testing, and none of them need a clipboard to test.
///
/// [changes] is single-subscription, as the platform notification it stands in
/// for is, and each read of the getter hands out a **new** stream with its own
/// loop. That matters because switching clipboard sync off and on again
/// cancels one subscription and takes out another, which a reused single
/// subscription controller would refuse with "Stream has already been
/// listened to".
final class PollingClipboardWatcher {
  /// Watches whatever [read] returns, every [interval].
  ///
  /// [read] returns null when there is nothing to report: no text on the
  /// clipboard, or a platform that will not say at this moment — which is how
  /// Android answers whenever its window is not focused. Null is never a
  /// change, and it does not start the watcher either: the baseline is the
  /// first value the platform will actually show, because that value is the
  /// one that must not be reported. Reporting it would mirror whatever was
  /// copied before clipboard sync was switched on.
  PollingClipboardWatcher({
    required Future<String?> Function() read,
    this.interval = const Duration(milliseconds: 700),
  }) : // A named parameter cannot be a private field, so the read is assigned
       // here; the lint that asks for an initializing formal cannot be
       // satisfied when the field is private and the parameter is named.
       // ignore: prefer_initializing_formals
       _read = read;

  final Future<String?> Function() _read;

  /// How often the value is read: the reporting latency, and the cost.
  final Duration interval;

  /// Fires whenever the watched value changes, with its new value.
  Stream<String> get changes {
    late final StreamController<String> controller;
    Timer? timer;
    // The baseline. Seeded by the first successful read rather than by a
    // literal, because "the clipboard is empty" and "nothing has been read
    // yet" are different states: the first reports a later copy, the second
    // must not report the content that was already there.
    var primed = false;
    var last = '';
    var reading = false;
    // Whether the failure that is currently happening has already been
    // reported. False to begin with, and cleared again by every read that
    // works, so a failure after a healthy stretch is news a second time.
    var failureReported = false;

    Future<void> tick() async {
      if (reading || controller.isClosed) return;
      reading = true;
      final String? value;
      try {
        value = await _read();
        failureReported = false;
      } on Object catch (error) {
        // A clipboard that refuses to be read is worth reporting once, not
        // once per interval: nothing about polling makes the next attempt any
        // likelier to succeed, and a notice per tick is a log nobody reads.
        if (!failureReported) {
          failureReported = true;
          if (!controller.isClosed) controller.addError(error);
        }
        return;
      } finally {
        reading = false;
      }
      if (value == null) return;
      if (!primed) {
        primed = true;
        last = value;
        return;
      }
      if (value == last) return;
      last = value;
      if (!controller.isClosed) controller.add(value);
    }

    controller = StreamController<String>(
      onListen: () {
        // The baseline is taken straight away rather than one interval in, so
        // a copy made right after syncing is switched on is still a change
        // rather than part of what was already there.
        unawaited(tick());
        timer = Timer.periodic(interval, (_) => unawaited(tick()));
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
        unawaited(controller.close());
      },
    );
    return controller.stream;
  }
}

import 'dart:async';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

/// A clipboard-shaped value a test drives by hand.
///
/// It is deliberately not a [SystemClipboard]: the poll loop takes a read
/// function and nothing else, and keeping the fake at that width is what lets
/// these cases be about the loop rather than about a clipboard.
final class FakeReader {
  String? text;
  Object? failure;
  int reads = 0;

  Future<String?> read() async {
    reads += 1;
    final failure = this.failure;
    if (failure != null) throw failure;
    return text;
  }
}

/// A short interval, so a case is milliseconds rather than seconds.
const Duration tick = Duration(milliseconds: 10);

void main() {
  test('reports a change, and not the value it started on', () async {
    final reader = FakeReader()..text = 'already there';
    final watcher = PollingClipboardWatcher(read: reader.read, interval: tick);

    final seen = <String>[];
    final subscription = watcher.changes.listen(seen.add);
    addTearDown(subscription.cancel);

    // Long enough for several polls of the unchanged value.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(
      seen,
      isEmpty,
      reason: 'content already on the clipboard is the baseline, not a change',
    );

    reader.text = 'copied now';
    await until(
      () => seen.isNotEmpty,
      description: 'the change to be reported',
    );
    expect(seen, ['copied now']);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(seen, [
      'copied now',
    ], reason: 'an unchanged value must not be reported over and over');
  });

  test('a read that cannot see the clipboard is not a change', () async {
    // What Android answers whenever its window is not focused.
    final reader = FakeReader();
    final watcher = PollingClipboardWatcher(read: reader.read, interval: tick);

    final seen = <String>[];
    final subscription = watcher.changes.listen(seen.add);
    addTearDown(subscription.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(seen, isEmpty);

    reader.text = 'the first thing this Device can see';
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      seen,
      isEmpty,
      reason: 'the first readable value is the baseline, not a change',
    );

    reader.text = 'copied after that';
    await until(() => seen.isNotEmpty, description: 'the later change');
    expect(seen, ['copied after that']);
  });

  test('stops polling when the subscription is cancelled', () async {
    final reader = FakeReader()..text = 'one';
    final watcher = PollingClipboardWatcher(read: reader.read, interval: tick);

    final subscription = watcher.changes.listen((_) {});
    await until(() => reader.reads > 1, description: 'polling to start');
    await subscription.cancel();

    // Settle whatever tick was already in flight, then watch for a stall.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final settled = reader.reads;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(
      reader.reads,
      settled,
      reason: 'a cancelled watcher must not keep reading the clipboard',
    );
  });

  test('hands out a fresh loop when it is watched again', () async {
    // Switching clipboard sync off and on again cancels one subscription and
    // takes out another: a reused single-subscription controller would refuse
    // that outright.
    final reader = FakeReader()..text = 'before';
    final watcher = PollingClipboardWatcher(read: reader.read, interval: tick);

    final first = <String>[];
    final firstSubscription = watcher.changes.listen(first.add);
    await until(() => reader.reads > 1, description: 'the first loop to start');
    await firstSubscription.cancel();

    final second = <String>[];
    final secondSubscription = watcher.changes.listen(second.add);
    addTearDown(secondSubscription.cancel);

    reader.text = 'after';
    await until(
      () => second.isNotEmpty,
      description: 'the second loop to work',
    );
    expect(second, ['after']);
    expect(first, isEmpty, reason: 'the cancelled loop must stay silent');
  });

  test(
    'reports a failed read once, and again after a read that worked',
    () async {
      final reader = FakeReader()
        ..failure = const FormatException('no clipboard');
      final watcher = PollingClipboardWatcher(
        read: reader.read,
        interval: tick,
      );

      final errors = <Object>[];
      final subscription = watcher.changes.listen((_) {}, onError: errors.add);
      addTearDown(subscription.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        errors,
        hasLength(1),
        reason: 'nothing about polling makes the next attempt likelier to work',
      );

      reader.failure = null;
      reader.text = 'working again';
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(reader.reads > 1, isTrue);

      reader.failure = const FormatException('gone again');
      await until(() => errors.length == 2, description: 'the second failure');
    },
  );
}

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  final alice = testDevice('alice').fingerprint;
  final capturedAt = DateTime.utc(2026, 9, 29, 12);

  ClipboardEntry sample() => ClipboardEntry(
    entryId: 'e1',
    origin: alice,
    text: 'a one-time code',
    capturedAt: capturedAt,
  );

  group('a clipboard entry', () {
    test('round-trips through the wire', () {
      final entry = sample();
      expect(ClipboardEntry.fromMessage(entry.toMessage()), entry);
    });

    test('compares by every field', () {
      final entry = sample();
      expect(entry, sample());
      expect(entry.hashCode, sample().hashCode);
      expect(
        entry,
        isNot(
          ClipboardEntry(
            entryId: 'e2',
            origin: alice,
            text: entry.text,
            capturedAt: capturedAt,
          ),
        ),
      );
    });

    test('knows when it holds nothing', () {
      expect(sample().isEmpty, isFalse);
      expect(
        ClipboardEntry(
          entryId: 'e0',
          origin: alice,
          text: '',
          capturedAt: capturedAt,
        ).isEmpty,
        isTrue,
      );
    });

    test('never prints its content', () {
      final printed = sample().toString();
      expect(printed, isNot(contains('one-time')));
      expect(printed, contains('15 chars'));
      expect(printed, contains(alice.short()));
    });
  });
}

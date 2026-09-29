import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';
import 'support.dart';

/// Sends one item and hands back the offer that went out.
Future<({FakeChannel channel, TransferEngine engine, OutgoingTransfer sent})>
sendOneItem(int size) async {
  final channel = FakeChannel();
  final engine = channel.engineWith();
  final sent = await engine.sendFiles([
    OutgoingItem(
      name: 'item.bin',
      source: MemoryByteSource(List<int>.generate(size, (i) => i % 256)),
    ),
  ]);
  return (channel: channel, engine: engine, sent: sent);
}

void main() {
  group('sending', () {
    test('the offer goes out before the send call returns', () async {
      final link = await sendOneItem(3);
      final offer = link.channel.sent.single;
      expect(offer, isA<OfferMessage>());
      final described = offer as OfferMessage;
      expect(described.transferId, link.sent.id);
      expect(described.kind, PayloadKind.file);
      expect(described.items.single.name, 'item.bin');
      expect(described.items.single.size, 3);
      // The digest is a promise about bytes that have not moved yet, so it has
      // to be in the offer rather than in anything that follows it.
      expect(described.items.single.digest, sha256Hex([0, 1, 2]));
      expect(link.sent.state, TransferState.awaitingDecision);
      expect(link.channel.sentChunks, isEmpty);

      await link.engine.close();
      await link.channel.close();
    });

    test('resumes from the offset the receiver already holds', () async {
      const size = 200000;
      const resumeFrom = 70000;
      final link = await sendOneItem(size);
      final offer = link.channel.sentOf<OfferMessage>()!;
      final item = offer.items.single;

      link.channel.deliver(
        AcceptMessage(
          transferId: offer.transferId,
          acceptedItemIds: [item.id],
          resumeOffsets: {item.id: resumeFrom},
        ),
      );
      await until(
        () => link.sent.state == TransferState.verifying,
        description: '发送完毕',
      );

      // The first slice starts where the receiver says it got to, and the
      // slices run contiguous to the end without repeating the prefix.
      expect(link.channel.sentChunks, isNotEmpty);
      expect(link.channel.sentChunks.first.offset, resumeFrom);
      expect(link.channel.sentChunks.first.data.first, resumeFrom % 256);
      var next = resumeFrom;
      for (final chunk in link.channel.sentChunks) {
        expect(chunk.itemId, item.id);
        expect(chunk.offset, next);
        next += chunk.data.length;
      }
      expect(next, size);

      // Bytes already at the far end count as transferred, so both ends report
      // the same numbers for the same payload.
      expect(link.sent.transferredBytes, size);
      expect(link.sent.progress.fraction, 1);

      link.channel.deliver(
        VerifiedMessage(
          transferId: offer.transferId,
          digests: {item.id: item.digest!},
        ),
      );
      expect(await link.sent.outcome, isA<TransferCompleted>());

      await link.engine.close();
      await link.channel.close();
    });

    test(
      'an acceptance naming an item the offer does not have fails the send',
      () async {
        final link = await sendOneItem(4);
        final offer = link.channel.sentOf<OfferMessage>()!;

        link.channel.deliver(
          AcceptMessage(
            transferId: offer.transferId,
            acceptedItemIds: const ['invented'],
          ),
        );

        final outcome = await link.sent.outcome;
        expect(outcome, isA<TransferFailed>());
        expect((outcome as TransferFailed).detail, contains('invented'));
        expect(link.channel.sentChunks, isEmpty);

        await link.engine.close();
        await link.channel.close();
      },
    );

    test('a resume offset past the end of an item fails the send', () async {
      final link = await sendOneItem(4);
      final offer = link.channel.sentOf<OfferMessage>()!;
      final item = offer.items.single;

      link.channel.deliver(
        AcceptMessage(
          transferId: offer.transferId,
          acceptedItemIds: [item.id],
          resumeOffsets: {item.id: 9999},
        ),
      );

      final outcome = await link.sent.outcome;
      expect(outcome, isA<TransferFailed>());
      expect((outcome as TransferFailed).detail, contains('9999'));
      expect(link.channel.sentChunks, isEmpty);

      await link.engine.close();
      await link.channel.close();
    });

    test(
      'a resume offset for an item that was not accepted fails the send',
      () async {
        final channel = FakeChannel();
        final engine = channel.engineWith();
        final sent = await engine.sendFiles([
          OutgoingItem(name: 'a.bin', source: MemoryByteSource([1, 2, 3])),
          OutgoingItem(name: 'b.bin', source: MemoryByteSource([4, 5, 6])),
        ]);
        final offer = channel.sentOf<OfferMessage>()!;

        channel.deliver(
          AcceptMessage(
            transferId: offer.transferId,
            acceptedItemIds: [offer.items.first.id],
            resumeOffsets: {offer.items.last.id: 2},
          ),
        );

        final outcome = await sent.outcome;
        expect(outcome, isA<TransferFailed>());
        expect((outcome as TransferFailed).detail, contains('did not accept'));

        await engine.close();
        await channel.close();
      },
    );

    test('an acceptance that takes nothing is a refusal', () async {
      final link = await sendOneItem(4);
      final offer = link.channel.sentOf<OfferMessage>()!;

      link.channel.deliver(
        AcceptMessage(transferId: offer.transferId, acceptedItemIds: const []),
      );

      final outcome = await link.sent.outcome;
      expect(outcome, isA<TransferRejected>());
      expect((outcome as TransferRejected).reason, RejectionReason.declined);

      await link.engine.close();
      await link.channel.close();
    });

    test('a confirmation whose digest differs fails the send', () async {
      final link = await sendOneItem(8);
      final offer = link.channel.sentOf<OfferMessage>()!;
      final item = offer.items.single;

      link.channel.deliver(
        AcceptMessage(transferId: offer.transferId, acceptedItemIds: [item.id]),
      );
      await until(
        () => link.sent.state == TransferState.verifying,
        description: '发送完毕',
      );

      final elsewhere = sha256Hex(List<int>.filled(8, 9));
      link.channel.deliver(
        VerifiedMessage(
          transferId: offer.transferId,
          digests: {item.id: elsewhere},
        ),
      );

      final outcome = await link.sent.outcome;
      expect(outcome, isA<TransferFailed>());
      final failure = outcome as TransferFailed;
      expect(failure.reason, RejectionReason.corrupt);
      expect(failure.itemId, item.id);
      // Both hashes are in the detail: which one is "right" is exactly the
      // question, so neither may be dropped from the explanation.
      expect(failure.detail, contains(elsewhere));
      expect(failure.detail, contains(item.digest!));

      await link.engine.close();
      await link.channel.close();
    });

    test('a confirmation that omits an accepted item fails the send', () async {
      final link = await sendOneItem(8);
      final offer = link.channel.sentOf<OfferMessage>()!;

      link.channel.deliver(
        AcceptMessage(
          transferId: offer.transferId,
          acceptedItemIds: [offer.items.single.id],
        ),
      );
      await until(
        () => link.sent.state == TransferState.verifying,
        description: '发送完毕',
      );

      link.channel.deliver(
        VerifiedMessage(transferId: offer.transferId, digests: const {}),
      );

      final outcome = await link.sent.outcome;
      expect(outcome, isA<TransferFailed>());
      expect((outcome as TransferFailed).reason, RejectionReason.corrupt);
      expect(outcome.detail, contains('did not report a digest'));

      await link.engine.close();
      await link.channel.close();
    });

    test('a failure from the receiver keeps its reason and item', () async {
      final link = await sendOneItem(8);
      final offer = link.channel.sentOf<OfferMessage>()!;
      final item = offer.items.single;

      link.channel.deliver(
        AcceptMessage(transferId: offer.transferId, acceptedItemIds: [item.id]),
      );
      await until(
        () => link.sent.state == TransferState.verifying,
        description: '发送完毕',
      );

      link.channel.deliver(
        FailedMessage(
          transferId: offer.transferId,
          reason: RejectionReason.ioError,
          itemId: item.id,
        ),
      );

      final outcome = await link.sent.outcome;
      expect(outcome, isA<TransferFailed>());
      final failure = outcome as TransferFailed;
      expect(failure.reason, RejectionReason.ioError);
      expect(failure.itemId, item.id);

      await link.engine.close();
      await link.channel.close();
    });

    test('cancelling tells the peer and ends the transfer', () async {
      final link = await sendOneItem(8);

      await link.sent.cancel(RejectionReason.declined);

      expect(link.channel.sentOf<CancelMessage>(), isNotNull);
      expect(
        link.channel.sentOf<CancelMessage>()!.reason,
        RejectionReason.declined,
      );
      final outcome = await link.sent.outcome;
      expect(outcome, isA<TransferCancelled>());
      expect((outcome as TransferCancelled).byPeer, isFalse);

      await link.engine.close();
      await link.channel.close();
    });

    test('an empty file offer is a programming error', () async {
      final channel = FakeChannel();
      final engine = channel.engineWith();
      await expectLater(
        engine.sendFiles(const []),
        throwsA(isA<ArgumentError>()),
      );
      await engine.close();
      await channel.close();
    });
  });
}

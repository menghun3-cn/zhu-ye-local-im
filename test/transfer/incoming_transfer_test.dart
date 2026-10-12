import 'dart:async';
import 'dart:typed_data';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A receiver holding one unanswered Offer.
final class PendingOffer {
  PendingOffer(this.channel, this.engine, this.transfer);

  final FakeChannel channel;
  final TransferEngine engine;
  final IncomingTransfer transfer;

  /// The item the offer described.
  PayloadItem get item => transfer.items.single;

  Future<void> dispose() async {
    await engine.close();
    await channel.close();
  }
}

/// Delivers a file Offer for [bytes] and waits for the engine to hand it over.
Future<PendingOffer> deliverFileOffer(List<int> bytes) async {
  final channel = FakeChannel();
  final engine = channel.engineWith();
  final arrived = Completer<IncomingTransfer>();
  engine.incoming.listen(arrived.complete);
  channel.deliver(
    OfferMessage(
      transferId: 't-1',
      kind: PayloadKind.file,
      items: [
        PayloadItem(
          id: 'i0',
          name: 'item.bin',
          size: bytes.length,
          digest: sha256Hex(bytes),
        ),
      ],
    ),
  );
  return PendingOffer(channel, engine, await arrived.future);
}

void main() {
  group('an incoming offer', () {
    test('is inert until somebody answers it', () async {
      final pending = await deliverFileOffer(const [1, 2, 3, 4]);

      expect(pending.transfer.state, TransferState.awaitingDecision);
      expect(pending.transfer.isDecidable, isTrue);
      expect(pending.transfer.transferredBytes, 0);
      expect(pending.transfer.totalBytes, 4);
      // Nothing has been sent back, and nothing has been written anywhere:
      // the sender learns nothing until a decision is made.
      expect(pending.channel.sent, isEmpty);
      expect(pending.transfer.sinks, isEmpty);

      await pending.dispose();
    });

    test('reports what is already held as a resume offset', () async {
      final payload = List<int>.generate(200000, (index) => index % 256);
      final pending = await deliverFileOffer(payload);
      const alreadyHeld = 70000;

      final sink = MemoryPayloadSink();
      await sink.write(0, payload.sublist(0, alreadyHeld));
      await pending.transfer.accept(itemIds: const ['i0'], sinks: {'i0': sink});

      final accept = pending.channel.sentOf<AcceptMessage>()!;
      expect(accept.acceptedItemIds, ['i0']);
      expect(accept.resumeOffsets, {'i0': alreadyHeld});
      expect(pending.transfer.state, TransferState.transferring);
      // The bytes already on disk count as progress, so a resumed transfer does
      // not restart its progress bar.
      expect(pending.transfer.transferredBytes, alreadyHeld);

      pending.channel.deliverChunk(
        ChunkFrame(
          transferId: 't-1',
          itemId: 'i0',
          offset: alreadyHeld,
          data: Uint8List.fromList(payload.sublist(alreadyHeld)),
        ),
      );
      pending.channel.deliver(CompleteMessage(transferId: 't-1'));

      final outcome = await pending.transfer.outcome;
      expect(outcome, isA<TransferCompleted>());
      expect(sink.bytes, payload);
      expect(pending.transfer.transferredBytes, payload.length);
      expect(pending.transfer.progress.fraction, 1);
      expect(
        pending.channel.sentOf<VerifiedMessage>()!.digests['i0'],
        sha256Hex(payload),
      );

      await pending.dispose();
    });

    test(
      'a slice that does not continue the item fails the transfer',
      () async {
        final pending = await deliverFileOffer(const [1, 2, 3, 4, 5]);
        await pending.transfer.accept(
          itemIds: const ['i0'],
          sinks: {'i0': MemoryPayloadSink()},
        );

        pending.channel.deliverChunk(
          ChunkFrame(
            transferId: 't-1',
            itemId: 'i0',
            offset: 2,
            data: Uint8List.fromList(const [9]),
          ),
        );

        final outcome = await pending.transfer.outcome;
        expect(outcome, isA<TransferFailed>());
        final failure = outcome as TransferFailed;
        expect(failure.reason, RejectionReason.corrupt);
        expect(failure.itemId, 'i0');
        // The sender is told, so it can stop rather than stream into the void.
        expect(
          pending.channel.sentOf<FailedMessage>()!.reason,
          RejectionReason.corrupt,
        );

        await pending.dispose();
      },
    );

    test('a slice past the declared size fails the transfer', () async {
      final pending = await deliverFileOffer(const [1, 2, 3, 4, 5]);
      await pending.transfer.accept(
        itemIds: const ['i0'],
        sinks: {'i0': MemoryPayloadSink()},
      );

      pending.channel.deliverChunk(
        ChunkFrame(
          transferId: 't-1',
          itemId: 'i0',
          offset: 0,
          data: Uint8List.fromList(const [1, 2, 3, 4, 5, 6]),
        ),
      );

      final outcome = await pending.transfer.outcome;
      expect(outcome, isA<TransferFailed>());
      expect((outcome as TransferFailed).detail, contains('past the 5 bytes'));

      await pending.dispose();
    });

    test('an item that arrives short fails the transfer', () async {
      final pending = await deliverFileOffer(const [1, 2, 3, 4, 5]);
      final sink = MemoryPayloadSink();
      await pending.transfer.accept(itemIds: const ['i0'], sinks: {'i0': sink});

      pending.channel.deliverChunk(
        ChunkFrame(
          transferId: 't-1',
          itemId: 'i0',
          offset: 0,
          data: Uint8List.fromList(const [1, 2, 3]),
        ),
      );
      pending.channel.deliver(CompleteMessage(transferId: 't-1'));

      final outcome = await pending.transfer.outcome;
      expect(outcome, isA<TransferFailed>());
      final failure = outcome as TransferFailed;
      expect(failure.reason, RejectionReason.corrupt);
      expect(failure.detail, contains('received 3 of the 5'));

      await pending.dispose();
    });

    test('bytes that hash to something else fail the transfer', () async {
      final pending = await deliverFileOffer(const [1, 2, 3, 4, 5]);

      await pending.transfer.accept(
        itemIds: const ['i0'],
        sinks: {'i0': MemoryPayloadSink()},
      );
      pending.channel.deliverChunk(
        ChunkFrame(
          transferId: 't-1',
          itemId: 'i0',
          offset: 0,
          data: Uint8List.fromList(const [9, 9, 9, 9, 9]),
        ),
      );
      pending.channel.deliver(CompleteMessage(transferId: 't-1'));

      final outcome = await pending.transfer.outcome;
      expect(outcome, isA<TransferFailed>());
      final failure = outcome as TransferFailed;
      expect(failure.reason, RejectionReason.corrupt);
      // The digest the offer promised is still in the explanation: that is what
      // tells a reader whether the bytes or the promise were wrong.
      expect(failure.detail, contains(sha256Hex(const [1, 2, 3, 4, 5])));

      await pending.dispose();
    });

    test(
      'a slice for an item that was not accepted fails the transfer',
      () async {
        final channel = FakeChannel();
        final engine = channel.engineWith();
        final arrived = Completer<IncomingTransfer>();
        engine.incoming.listen(arrived.complete);
        channel.deliver(
          OfferMessage(
            transferId: 't-2',
            kind: PayloadKind.file,
            items: [
              PayloadItem(id: 'i0', name: 'a', size: 1, digest: sha256Hex([1])),
              PayloadItem(id: 'i1', name: 'b', size: 1, digest: sha256Hex([2])),
            ],
          ),
        );
        final transfer = await arrived.future;
        final sink = MemoryPayloadSink();
        await transfer.accept(itemIds: const ['i0'], sinks: {'i0': sink});

        channel.deliverChunk(
          ChunkFrame(
            transferId: 't-2',
            itemId: 'i1',
            offset: 0,
            data: Uint8List.fromList(const [2]),
          ),
        );

        final outcome = await transfer.outcome;
        expect(outcome, isA<TransferFailed>());
        expect((outcome as TransferFailed).detail, contains('not accepted'));

        await engine.close();
        await channel.close();
      },
    );

    test('a slice before the offer is answered fails the transfer', () async {
      final pending = await deliverFileOffer(const [1, 2]);

      pending.channel.deliverChunk(
        ChunkFrame(
          transferId: 't-1',
          itemId: 'i0',
          offset: 0,
          data: Uint8List.fromList(const [1, 2]),
        ),
      );

      final outcome = await pending.transfer.outcome;
      expect(outcome, isA<TransferFailed>());
      expect(
        (outcome as TransferFailed).detail,
        contains('before the offer was answered'),
      );

      await pending.dispose();
    });

    test('a cancel from the sender ends the receive', () async {
      final pending = await deliverFileOffer(const [1, 2]);

      pending.channel.deliver(
        CancelMessage(transferId: 't-1', reason: RejectionReason.declined),
      );

      final outcome = await pending.transfer.outcome;
      expect(outcome, isA<TransferCancelled>());
      expect((outcome as TransferCancelled).byPeer, isTrue);

      await pending.dispose();
    });

    test('rejecting tells the sender why', () async {
      final pending = await deliverFileOffer(const [1, 2]);

      await pending.transfer.reject(RejectionReason.refused);

      final reject = pending.channel.sentOf<RejectMessage>()!;
      expect(reject.reason, RejectionReason.refused);
      final outcome = await pending.transfer.outcome;
      expect(outcome, isA<TransferRejected>());
      expect((outcome as TransferRejected).reason, RejectionReason.refused);

      await pending.dispose();
    });

    test('answering twice is a programming error', () async {
      final pending = await deliverFileOffer(const [1, 2]);
      await pending.transfer.accept(
        itemIds: const ['i0'],
        sinks: {'i0': MemoryPayloadSink()},
      );

      await expectLater(pending.transfer.reject(), throwsA(isA<StateError>()));
      await pending.dispose();
    });
  });

  group('accepting', () {
    test('refuses a streamed item that was given no sink', () async {
      final pending = await deliverFileOffer(const [1, 2]);

      await expectLater(
        pending.transfer.accept(itemIds: const ['i0']),
        throwsA(isA<ArgumentError>()),
      );
      expect(pending.transfer.isDecidable, isTrue);
      expect(pending.channel.sent, isEmpty);

      await pending.dispose();
    });

    test(
      'refuses an empty acceptance, which is what refusing looks like',
      () async {
        final pending = await deliverFileOffer(const [1, 2]);

        await expectLater(
          pending.transfer.accept(itemIds: const []),
          throwsA(isA<ArgumentError>()),
        );
        expect(pending.transfer.isDecidable, isTrue);

        await pending.dispose();
      },
    );

    test('refuses an item the offer does not name', () async {
      final pending = await deliverFileOffer(const [1, 2]);

      await expectLater(
        pending.transfer.accept(
          itemIds: const ['invented'],
          sinks: {'invented': MemoryPayloadSink()},
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(pending.transfer.isDecidable, isTrue);

      await pending.dispose();
    });

    test('refuses a sink for a body that travels inside the offer', () async {
      final channel = FakeChannel();
      final engine = channel.engineWith();
      final arrived = Completer<IncomingTransfer>();
      engine.incoming.listen(arrived.complete);
      channel.deliver(
        OfferMessage(
          transferId: 't-3',
          kind: PayloadKind.text,
          items: [PayloadItem(id: 'text', name: 'text', size: 2)],
          text: 'hi',
        ),
      );
      final transfer = await arrived.future;

      await expectLater(
        transfer.accept(
          itemIds: const ['text'],
          sinks: {'text': MemoryPayloadSink()},
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Without a sink it is accepted, and completes on the sender's word
      // because the body was already authenticated by the record layer.
      await transfer.accept(itemIds: const ['text']);
      expect(transfer.transferredBytes, 2);
      channel.deliver(CompleteMessage(transferId: 't-3'));
      expect(await transfer.outcome, isA<TransferCompleted>());
      expect(transfer.text, 'hi');

      await engine.close();
      await channel.close();
    });

    test(
      'refuses a sink that already holds more than the item declares',
      () async {
        final pending = await deliverFileOffer(const [1, 2]);
        final sink = MemoryPayloadSink();
        await sink.write(0, const [1, 2, 3]);

        await expectLater(
          pending.transfer.accept(itemIds: const ['i0'], sinks: {'i0': sink}),
          throwsA(isA<ArgumentError>()),
        );

        await pending.dispose();
      },
    );
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';
import 'support.dart';

void main() {
  group('over a real session', () {
    test('a text payload arrives whole and both ends agree', () async {
      final peers = await connectedPeers();
      final receiver = peers.receiverAtBob();
      const body = '竹叶 reading list: 局域网传输';

      final sent = await peers.alice.engine.sendText(body);
      final outcome = await sent.outcome;

      expect(outcome, isA<TransferCompleted>());
      await receiver.answered(1);
      final receipt = receiver.receipts.single;
      expect(receipt.inlineText, body);
      expect(receipt.transfer.kind, PayloadKind.text);
      expect(await receipt.transfer.outcome, isA<TransferCompleted>());

      // A body that travelled inside the Offer is delivered the moment it is
      // accepted, so a text transfer is never partly done.
      expect(sent.transferredBytes, utf8.encode(body).length);
      expect(sent.progress.fraction, 1);
      expect(sent.state, TransferState.completed);

      await peers.close();
    });

    test('clipboard content keeps its own payload kind', () async {
      final peers = await connectedPeers();
      final receiver = peers.receiverAtBob();

      final sent = await peers.alice.engine.sendClipboard('copied on alice');
      expect(await sent.outcome, isA<TransferCompleted>());
      await receiver.answered(1);

      expect(receiver.receipts.single.transfer.kind, PayloadKind.clipboard);
      expect(receiver.receipts.single.inlineText, 'copied on alice');

      await peers.close();
    });

    test('several files travel as one transfer and stay apart', () async {
      final peers = await connectedPeers();
      final receiver = peers.receiverAtBob();
      final photo = Uint8List.fromList(
        List<int>.generate(200000, (index) => (index * 7) % 256),
      );

      final sent = await peers.alice.engine.sendFiles([
        OutgoingItem(
          name: 'notes.txt',
          source: MemoryByteSource(utf8.encode('first item')),
        ),
        OutgoingItem(name: 'photo.bin', source: MemoryByteSource(photo)),
        OutgoingItem(name: 'empty.bin', source: MemoryByteSource(const [])),
      ]);
      final outcome = await sent.outcome;
      await receiver.answered(1);
      final receipt = receiver.receipts.single;

      expect(outcome, isA<TransferCompleted>());
      // One digest per item, including the empty one.
      expect((outcome as TransferCompleted).digests, hasLength(3));
      expect(receipt.transfer.items.map((item) => item.name), [
        'notes.txt',
        'photo.bin',
        'empty.bin',
      ]);
      expect(receipt.textOf('i0'), 'first item');
      expect(receipt.bytesOf('i1'), photo);
      expect(receipt.bytesOf('i2'), isEmpty);
      // 200000 bytes is four chunks, so the slices of three items were routed
      // by item id rather than by the order they happened to arrive in.
      expect(sent.transferredBytes, sent.totalBytes);
      expect(sent.totalBytes, 10 + 200000);

      await peers.close();
    });

    test('a refusal ends the send as rejected', () async {
      final peers = await connectedPeers();
      peers.receiverAtBob().refuseWith = RejectionReason.declined;

      final sent = await peers.alice.engine.sendText('not wanted');
      final outcome = await sent.outcome;

      expect(outcome, isA<TransferRejected>());
      expect((outcome as TransferRejected).reason, RejectionReason.declined);
      expect(sent.state, TransferState.rejected);

      await peers.close();
    });

    test(
      'an offer over the limits is refused before the app is asked',
      () async {
        final peers = await connectedPeers(
          limits: const TransferLimits(maxItemBytes: 1024),
        );
        final receiver = peers.receiverAtBob();

        final sent = await peers.alice.engine.sendFiles([
          OutgoingItem(
            name: 'too-big.bin',
            source: MemoryByteSource(List<int>.filled(4096, 7)),
          ),
        ]);
        final outcome = await sent.outcome;

        expect(outcome, isA<TransferRejected>());
        expect((outcome as TransferRejected).reason, RejectionReason.refused);
        // The receiver was never handed a Transfer to answer, because there was
        // nothing sensible for it to be asked.
        expect(receiver.offers, isEmpty);
        expect(peers.bob.engine.pending, isEmpty);

        await peers.close();
      },
    );

    test('an offer nobody answers ends rather than waiting forever', () async {
      final peers = await connectedPeers(
        limits: const TransferLimits(
          acceptanceTimeout: Duration(milliseconds: 80),
        ),
      );

      final sent = await peers.alice.engine.sendText('anyone there?');
      final outcome = await sent.outcome;

      expect(outcome, isA<TransferFailed>());
      // No wire reason applies to a wait this Device gave up on itself.
      expect((outcome as TransferFailed).reason, isNull);
      expect(outcome.detail, contains('did not answer'));

      await peers.close();
    });

    test('a session that dies takes its transfers with it', () async {
      final peers = await connectedPeers();
      final sent = await peers.alice.engine.sendText('in flight');

      await peers.bob.link.close();
      final outcome = await sent.outcome;

      expect(outcome, isA<TransferFailed>());
      expect((outcome as TransferFailed).reason, isNull);

      await peers.close();
    });

    test('an offer waits for a listener instead of being dropped', () async {
      final peers = await connectedPeers();

      final sent = await peers.alice.engine.sendText('sent before anyone read');
      await until(
        () => peers.bob.engine.pending.length == 1,
        description: 'Offer 到达接收端',
      );

      // Subscribe only now: an Offer that arrived before the app was ready must
      // still be there to answer.
      final receiver = peers.receiverAtBob();
      await receiver.answered(1);

      expect(receiver.receipts.single.inlineText, 'sent before anyone read');
      expect(await sent.outcome, isA<TransferCompleted>());

      await peers.close();
    });

    test(
      'a cancel from the receiver ends the send as cancelled by peer',
      () async {
        final peers = await connectedPeers();
        final arrived = Completer<IncomingTransfer>();
        peers.bob.engine.incoming.listen(arrived.complete);

        final sent = await peers.alice.engine.sendText('stop');
        final incoming = await arrived.future;
        await incoming.cancel();

        final outcome = await sent.outcome;
        expect(outcome, isA<TransferCancelled>());
        expect((outcome as TransferCancelled).byPeer, isTrue);
        expect(incoming.state, TransferState.cancelled);

        await peers.close();
      },
    );

    test('a cancel from the sender ends the receive too', () async {
      final peers = await connectedPeers();
      final arrived = Completer<IncomingTransfer>();
      peers.bob.engine.incoming.listen(arrived.complete);

      final sent = await peers.alice.engine.sendText('never mind');
      final incoming = await arrived.future;
      await sent.cancel(RejectionReason.declined);

      expect(await sent.outcome, isA<TransferCancelled>());
      expect((await sent.outcome as TransferCancelled).byPeer, isFalse);
      final outcome = await incoming.outcome;
      expect(outcome, isA<TransferCancelled>());
      expect((outcome as TransferCancelled).byPeer, isTrue);

      await peers.close();
    });

    test('closing the engine fails what it was running', () async {
      final peers = await connectedPeers();
      final sent = await peers.alice.engine.sendText('still going');

      await peers.alice.engine.close();
      final outcome = await sent.outcome;

      expect(outcome, isA<TransferFailed>());
      expect((outcome as TransferFailed).detail, contains('closed'));
      expect(peers.alice.engine.isClosed, isTrue);

      await peers.close();
    });
  });

  group('routing', () {
    test(
      'a message for a transfer the session is not running is not fatal',
      () async {
        final channel = FakeChannel();
        final engine = channel.engineWith();

        channel.deliver(
          AcceptMessage(transferId: 'ghost', acceptedItemIds: const ['i0']),
        );
        channel.deliver(
          RejectMessage(transferId: 'ghost', reason: RejectionReason.declined),
        );
        channel.deliver(CompleteMessage(transferId: 'ghost'));
        channel.deliver(
          VerifiedMessage(transferId: 'ghost', digests: const {}),
        );
        channel.deliver(
          FailedMessage(transferId: 'ghost', reason: RejectionReason.corrupt),
        );
        channel.deliver(
          CancelMessage(transferId: 'ghost', reason: RejectionReason.declined),
        );

        await until(() => channel.notices.length == 6, description: '六条未匹配消息');
        expect(channel.notices, everyElement(contains('ghost')));
        expect(channel.sent, isEmpty);
        expect(engine.outgoing, isEmpty);
        expect(engine.pending, isEmpty);
        expect(engine.isClosed, isFalse);

        await engine.close();
        await channel.close();
      },
    );

    test('an offer reusing a transfer id is refused', () async {
      final channel = FakeChannel();
      final engine = channel.engineWith();
      engine.incoming.listen((_) {});
      final offer = OfferMessage(
        transferId: 'reused',
        kind: PayloadKind.text,
        items: [PayloadItem(id: 'text', name: 'text', size: 2)],
        text: 'hi',
      );

      channel.deliver(offer);
      channel.deliver(offer);

      await until(
        () => channel.sent.whereType<RejectMessage>().isNotEmpty,
        description: '拒绝重复 id',
      );
      expect(channel.sent, hasLength(1));
      expect(channel.sentOf<RejectMessage>()!.reason, RejectionReason.refused);
      expect(channel.notices.single, contains('reusing'));

      await engine.close();
      await channel.close();
    });

    test('messages that are not the transfer layer\'s are ignored', () async {
      final channel = FakeChannel();
      final engine = channel.engineWith();

      channel.deliver(
        ClipboardMessage(
          entryId: 'entry',
          originFingerprint: Fingerprint.ofPublicKey(utf8.encode('origin')),
          text: 'mirrored',
          capturedAt: DateTime.utc(2026, 9, 29),
        ),
      );
      channel.deliver(const ErrorMessage(code: 'x', message: 'y'));
      channel.deliver(
        CancelMessage(transferId: 'ghost', reason: RejectionReason.declined),
      );

      await until(() => channel.notices.length == 1, description: 'notices');
      // Only the cancel produced a notice: the clipboard message belongs to
      // the mirroring layer, which has its own listener.
      expect(channel.notices.single, contains('ghost'));

      await engine.close();
      await channel.close();
    });
  });
}

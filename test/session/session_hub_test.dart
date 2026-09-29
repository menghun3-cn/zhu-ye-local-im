import 'dart:typed_data';

import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../clipboard/support.dart';
import '../support/harness.dart';
import '../transfer/support.dart';
import 'support.dart';

void main() {
  group('a Session split by a hub', () {
    test('still runs a text Transfer over the transfer view', () async {
      final pair = await connectedHubs();
      final alice = pair.engineAtAlice();
      final bob = pair.engineAtBob();
      final receiver = MemoryReceiver(
        Peer(pair.bobDevice, pair.bobHub.link, bob),
      );

      await alice.sendText('hello over a hub');
      await receiver.answered(1);

      expect(receiver.receipts.single.transfer.text, 'hello over a hub');
      await pair.close();
    });

    test('still streams bulk payload over the transfer view', () async {
      final pair = await connectedHubs();
      final alice = pair.engineAtAlice();
      final bob = pair.engineAtBob();
      final receiver = MemoryReceiver(
        Peer(pair.bobDevice, pair.bobHub.link, bob),
      );

      // Three chunks' worth, so the chunk pass-through is actually exercised.
      final bytes = Uint8List.fromList(
        List<int>.generate(transferChunkBytes * 3 + 7, (index) => index % 251),
      );
      await alice.sendFiles([
        OutgoingItem(name: 'blob.bin', source: MemoryByteSource(bytes)),
      ]);
      await receiver.answered(1);

      expect(receiver.receipts.single.bytesOf('i0'), bytes);
      await pair.close();
    });

    test('routes a clipboard entry to the clipboard view alone', () async {
      final pair = await connectedHubs();
      final transferMessages = <WireMessage>[];
      final entries = <ClipboardMessage>[];
      pair.bobHub.transfers.messages.listen(transferMessages.add);
      pair.bobHub.clipboard.entries.listen(entries.add);

      await pair.aliceHub.clipboard.send(
        testEntry(pair.aliceDevice, 'copied on alice').toMessage(),
      );
      await until(() => entries.length == 1, description: '一个剪贴板条目');

      expect(entries.single.text, 'copied on alice');
      expect(transferMessages, isEmpty);
      await pair.close();
    });

    test(
      'routes a transfer control message to the transfer view alone',
      () async {
        final pair = await connectedHubs();
        final transferMessages = <WireMessage>[];
        final entries = <ClipboardMessage>[];
        pair.bobHub.transfers.messages.listen(transferMessages.add);
        pair.bobHub.clipboard.entries.listen(entries.add);

        await pair.aliceHub.transfers.send(
          CancelMessage(transferId: 't1', reason: RejectionReason.declined),
        );
        await until(() => transferMessages.length == 1, description: '一条控制消息');

        expect(transferMessages.single, isA<CancelMessage>());
        expect(entries, isEmpty);
        await pair.close();
      },
    );

    test('keeps the handshake out of both views', () async {
      final pair = await connectedHubs();
      final transferMessages = <WireMessage>[];
      final entries = <ClipboardMessage>[];
      pair.bobHub.transfers.messages.listen(transferMessages.add);
      pair.bobHub.clipboard.entries.listen(entries.add);

      await pair.aliceHub.clipboard.send(
        testEntry(pair.aliceDevice, 'anything').toMessage(),
      );
      await until(() => entries.length == 1, description: '一个剪贴板条目');

      // The hello and helloAck pair was consumed by the handshake before the
      // hub existed, so the only thing that reached the transfer view is
      // nothing at all.
      expect(transferMessages, isEmpty);
      expect(entries.single.originFingerprint, pair.aliceDevice.fingerprint);
      await pair.close();
    });

    test('reports the fingerprint the peer announced', () async {
      final pair = await connectedHubs();
      expect(pair.aliceHub.peer, pair.bobDevice.fingerprint);
      expect(pair.bobHub.peer, pair.aliceDevice.fingerprint);
      await pair.close();
    });

    test('tears the Session down on close, once', () async {
      final pair = await connectedHubs();
      await pair.aliceHub.close();
      await pair.aliceHub.close();
      expect(pair.aliceHub.isClosed, isTrue);
      expect(pair.aliceHub.link.isClosed, isTrue);
      await pair.bobHub.close();
    });

    test('ends the other side when one hub closes', () async {
      final pair = await connectedHubs();
      await pair.aliceHub.close();
      await until(() => pair.bobHub.isClosed, description: '对端 hub 关闭');
      await pair.bobHub.close();
    });
  });

  group('a hub and its two views', () {
    test('carries both conversations over one Session at once', () async {
      final pair = await connectedHubs();
      final alice = pair.engineAtAlice();
      final bob = pair.engineAtBob();
      final receiver = MemoryReceiver(
        Peer(pair.bobDevice, pair.bobHub.link, bob),
      );
      final entries = <ClipboardMessage>[];
      pair.bobHub.clipboard.entries.listen(entries.add);

      await alice.sendText('a file and a clipboard entry');
      await pair.aliceHub.clipboard.send(
        testEntry(pair.aliceDevice, 'copied on alice').toMessage(),
      );

      await receiver.answered(1);
      await until(() => entries.length == 1, description: '一个剪贴板条目');
      expect(
        receiver.receipts.single.transfer.text,
        'a file and a clipboard entry',
      );
      expect(entries.single.text, 'copied on alice');
      await pair.close();
    });
  });
}

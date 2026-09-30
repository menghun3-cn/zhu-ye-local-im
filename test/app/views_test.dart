import 'dart:io';

import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('formatBytes', () {
    test('writes bytes, and the units above them', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(999), '999 B');
      expect(formatBytes(1024), '1.0 KiB');
      expect(formatBytes(1536), '1.5 KiB');
      expect(formatBytes(200 * 1024), '200 KiB');
      expect(formatBytes(1024 * 1024), '1.0 MiB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GiB');
    });

    test('stops at the largest unit it knows', () {
      // Beyond TiB the number keeps growing rather than inventing a unit.
      expect(formatBytes(5 * 1024 * 1024 * 1024 * 1024), '5.0 TiB');
      expect(formatBytes(9000 * 1024 * 1024 * 1024 * 1024), '9000 TiB');
    });
  });

  group('TransferView', () {
    TransferView view({required int moved, required int total}) => TransferView(
      id: '1',
      direction: TransferDirection.incoming,
      kind: PayloadKind.file,
      peer: Fingerprint.ofPublicKey(const [1, 2, 3]),
      state: TransferState.transferring,
      transferredBytes: moved,
      totalBytes: total,
      names: const ['a.bin'],
      offer: null,
    );

    test('reports progress as a fraction a progress bar can take', () {
      expect(view(moved: 0, total: 0).fraction, 0);
      expect(view(moved: 0, total: 100).fraction, 0);
      expect(view(moved: 50, total: 100).fraction, 0.5);
      expect(view(moved: 100, total: 100).fraction, 1);
      expect(
        view(moved: 120, total: 100).fraction,
        1,
        reason: 'a bar cannot be over-full, and counters can lag a settle',
      );
    });

    test('needs a decision only while an offer is unanswered', () {
      expect(view(moved: 0, total: 10).needsDecision, isFalse);
    });
  });

  group('PeerView', () {
    PeerView view({String? address, int? port, String? alias}) => PeerView(
      fingerprint: Fingerprint.ofPublicKey(const [4, 5, 6]),
      alias: alias,
      platform: DevicePlatform.windows,
      address: address,
      sessionPort: port,
      isConnected: false,
      isInGroup: true,
      isFavorite: false,
      lastSeen: null,
    );

    test('is diallable only with both an address and a port', () {
      expect(view(address: '10.0.0.2', port: 53000).isDiallable, isTrue);
      expect(view(address: '10.0.0.2').isDiallable, isFalse);
      expect(view(port: 53000).isDiallable, isFalse);
      expect(view().isDiallable, isFalse);
    });

    test('falls back to the Fingerprint when no Alias was ever announced', () {
      final peer = view();
      expect(peer.alias, isNull);
      expect(peer.displayName, peer.shortFingerprint);
      expect(peer.displayName, isNot(isEmpty));
      expect(view(alias: 'Bob').displayName, 'Bob');
    });
  });

  group('incomingPathFor', () {
    test('keeps a received file inside the chosen directory', () {
      final directory = Directory.systemTemp.createTempSync('local-transfer-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = incomingPathFor(directory, '../../escape.txt');
      expect(path.parent.path, directory.path);
      expect(path.existsSync(), isFalse);
    });
  });
}

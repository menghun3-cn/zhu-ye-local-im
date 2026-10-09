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
      at: DateTime.utc(2026, 10, 9, 12),
      state: TransferState.transferring,
      transferredBytes: moved,
      totalBytes: total,
      names: const ['a.bin'],
      text: null,
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

    test('prefers the Alias over everything, because it is the only name', () {
      expect(view(alias: 'Bob').displayName, 'Bob');
      expect(view(alias: 'Bob', address: '10.0.0.2').displayName, 'Bob');
      expect(
        view(alias: 'Bob', address: '10.0.0.2', port: 53000).displayName,
        'Bob',
      );
      expect(view(alias: 'Bob').hasRealAlias, isTrue);
    });

    test('treats the placeholder name as no name at all', () {
      // A Device that announced nothing arrives as `fallbackAlias`, not as
      // null: the wire substitutes it, so "no name" has to be recognised as
      // that literal string or a nameless peer would be labelled "Unnamed
      // device" on every screen — which is not a name, it is the absence of
      // one wearing a name's clothes.
      final peer = view(alias: DeviceDescriptor.fallbackAlias);
      expect(peer.alias, DeviceDescriptor.fallbackAlias);
      expect(peer.hasRealAlias, isFalse);
      expect(peer.displayName, isNot(DeviceDescriptor.fallbackAlias));
      expect(peer.displayName, peer.shortFingerprint);
    });

    test('falls back to the Fingerprint when no Alias was announced', () {
      // The address is a fact about *where* a Device is, not who it is: two
      // Devices that both announce nothing are told apart by the Fingerprint
      // they proved they hold, and the address is shown beside it in every row
      // anyway. Ordering the fallback the other way round would put a value
      // nobody chose where a name belongs.
      final peer = view(address: '10.0.0.2', port: 53000);
      expect(peer.alias, isNull);
      expect(peer.hasRealAlias, isFalse);
      expect(peer.displayName, peer.shortFingerprint);
      expect(
        view(address: '10.0.0.7', port: 53000).displayName,
        peer.displayName,
        reason: 'the same Device, seen at a second address',
      );
    });

    test('names a peer the same way whether or not it has an address', () {
      // There is nothing to dial in the second case, but "who" does not depend
      // on "where": a peer seen through Discovery and never connected to is
      // still the same Device, and it reads the same.
      final unreachable = view(address: '10.0.0.2');
      expect(unreachable.isDiallable, isFalse);
      expect(unreachable.displayName, unreachable.shortFingerprint);
      expect(
        view().displayName,
        unreachable.displayName,
        reason: 'the Fingerprint does not come from the address',
      );
    });

    test('has something to show even with neither a name nor an address', () {
      final peer = view();
      expect(peer.alias, isNull);
      expect(peer.address, isNull);
      expect(peer.displayName, peer.shortFingerprint);
      expect(peer.displayName, isNot(isEmpty));
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

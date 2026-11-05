import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('TailscaleDirectory.parseStatus', () {
    test('reads peer Tailscale IPv4 addresses, online only', () {
      final body = '''
      {
        "Self": {"TailscaleIPs": ["100.64.0.1"]},
        "Peer": {
          "nodekey:a": {
            "Online": true,
            "TailscaleIPs": ["100.64.0.2", "fd7a:115c:a1e0::2"]
          },
          "nodekey:b": {
            "Online": false,
            "TailscaleIPs": ["100.64.0.3"]
          },
          "nodekey:c": {
            "TailscaleIPs": ["100.64.0.4", "100.64.0.4"]
          }
        }
      }
      ''';

      final addresses = TailscaleDirectory.parseStatus(body);

      // Self is never a target; offline peers are skipped; IPv6 and
      // duplicates are dropped.
      expect(addresses.map((a) => a.address), ['100.64.0.2', '100.64.0.4']);
    });

    test('malformed input yields an empty list, not a throw', () {
      for (final body in [
        '',
        'not json',
        '[]',
        '{}',
        '{"Peer": "nope"}',
        '{"Peer": {"k": "nope"}}',
      ]) {
        expect(TailscaleDirectory.parseStatus(body), isEmpty);
      }
    });
  });

  group('TailscaleDirectory.peers', () {
    test(
      'fetches once and serves the cache until the interval passes',
      () async {
        var now = DateTime(2026, 11, 5, 12);
        var fetches = 0;
        final directory = TailscaleDirectory(
          fetch: (url) async {
            fetches++;
            expect(url.path, TailscaleDirectory.statusPath);
            return '{"Peer": {"k": {"Online": true, '
                '"TailscaleIPs": ["100.64.0.2"]}}}';
          },
          clock: () => now,
        );

        expect((await directory.peers()).single.address, '100.64.0.2');
        await directory.peers();
        expect(fetches, 1, reason: 'the second call is served from cache');

        now = now.add(const Duration(seconds: 31));
        await directory.peers();
        expect(fetches, 2, reason: 'the interval passing asks again');
      },
    );

    test('a failed fetch keeps the last answer and does not hammer', () async {
      var now = DateTime(2026, 11, 5, 12);
      var fetches = 0;
      final directory = TailscaleDirectory(
        fetch: (url) async {
          fetches++;
          return fetches == 1
              ? '{"Peer": {"k": {"TailscaleIPs": ["100.64.0.2"]}}}'
              : null;
        },
        clock: () => now,
      );

      expect((await directory.peers()).single.address, '100.64.0.2');

      now = now.add(const Duration(seconds: 31));
      // The daemon went away: the old answer stays rather than emptying.
      expect((await directory.peers()).single.address, '100.64.0.2');

      now = now.add(const Duration(seconds: 31));
      await directory.peers();
      expect(fetches, 3);
      expect(
        (await directory.peers()).single.address,
        '100.64.0.2',
        reason: 'a directory that cannot be read is not an empty one',
      );
    });
  });
}

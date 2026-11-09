import 'package:local_transfer/core/link_transfer/share_address.dart';
import 'package:test/test.dart';

void main() {
  ShareAddressCandidate candidate(String address, {String? interface}) =>
      ShareAddressCandidate(address: address, interfaceName: interface);

  group('chooseShareAddress', () {
    test('returns null when there is no usable IPv4 candidate', () {
      expect(chooseShareAddress(candidates: const []), isNull);
      expect(
        chooseShareAddress(
          candidates: [
            candidate('::1'),
            candidate('169.254.1.1'),
            candidate('127.0.0.1'),
            candidate('not-an-ip'),
          ],
        ),
        isNull,
      );
    });

    test('picks the LAN address when a peer was heard on the LAN', () {
      // The reported bug: the VPN adapter enumerated first used to win.
      expect(
        chooseShareAddress(
          candidates: [
            candidate('100.64.0.1', interface: 'Tailscale'),
            candidate('192.168.1.10', interface: 'Wi-Fi'),
            candidate('172.20.0.1', interface: 'vEthernet (WSL)'),
          ],
          peerAddresses: ['192.168.1.55'],
        ),
        '192.168.1.10',
      );
    });

    test(
      'picks the tailnet address when the peer was heard on the tailnet',
      () {
        expect(
          chooseShareAddress(
            candidates: [
              candidate('192.168.1.10', interface: 'Wi-Fi'),
              candidate('100.64.0.1', interface: 'Tailscale'),
            ],
            // Tailnet peers share only the 100.64.0.0/10 prefix with the local
            // address, which is still far more than the LAN address shares.
            peerAddresses: ['100.101.7.9'],
          ),
          '100.64.0.1',
        );
      },
    );

    test('breaks a peer-match tie deterministically', () {
      expect(
        chooseShareAddress(
          candidates: [
            candidate('10.0.0.5', interface: 'Ethernet'),
            candidate('192.168.1.10', interface: 'Wi-Fi'),
          ],
          peerAddresses: ['10.0.0.9', '192.168.1.99'],
        ),
        // Both match their own subnet equally; equal scores fall back to the
        // ranking, where the lower address wins.
        '10.0.0.5',
      );
    });

    test('ignores peer hints that share no first octet', () {
      expect(
        chooseShareAddress(
          candidates: [
            candidate('192.168.1.10', interface: 'vEthernet (WSL)'),
            candidate('192.168.1.20', interface: 'Wi-Fi'),
          ],
          peerAddresses: ['8.8.8.8', 'not-an-ip', '::1'],
        ),
        // No peer match: the physical interface wins the fallback ranking.
        '192.168.1.20',
      );
    });

    test('falls back to preferring physical private interfaces', () {
      expect(
        chooseShareAddress(
          candidates: [
            candidate('100.64.0.1', interface: 'Tailscale'),
            candidate('172.20.10.1', interface: 'vEthernet (WSL)'),
            candidate('192.168.1.10', interface: 'Wi-Fi'),
          ],
        ),
        '192.168.1.10',
      );
    });

    test('still answers when only a VPN address exists', () {
      expect(
        chooseShareAddress(
          candidates: [candidate('100.64.0.1', interface: 'Tailscale')],
        ),
        '100.64.0.1',
      );
    });

    test('is deterministic when candidates tie on every rank', () {
      final first = chooseShareAddress(
        candidates: [
          candidate('192.168.1.10', interface: 'Wi-Fi'),
          candidate('192.168.1.20', interface: 'Ethernet'),
        ],
      );
      final second = chooseShareAddress(
        candidates: [
          candidate('192.168.1.20', interface: 'Ethernet'),
          candidate('192.168.1.10', interface: 'Wi-Fi'),
        ],
      );
      expect(first, second);
      expect(first, '192.168.1.10');
    });
  });
}

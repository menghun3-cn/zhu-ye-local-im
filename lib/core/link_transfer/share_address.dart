import 'dart:io';

/// One local IPv4 address a share link could name, plus the interface it
/// sits on.
///
/// The interface name is a hint, not a fact: virtual adapters — VPNs, WSL,
/// Hyper-V, Docker — enumerate exactly like physical ones, and the name is
/// the only thing `dart:io` offers that tells them apart.
final class ShareAddressCandidate {
  const ShareAddressCandidate({required this.address, this.interfaceName});

  /// The dotted-quad address, as the OS reports it.
  final String address;

  /// The interface's name as the OS reports it, when known.
  final String? interfaceName;
}

/// Interface names that mark an adapter as virtual or otherwise not the
/// link a LAN peer would arrive on: VPN tunnels, hypervisor switches,
/// containers, and cellular data.
final RegExp _virtualInterfaceName = RegExp(
  r'vethernet|hyper-?v|vmware|virtualbox|vbox|docker|wsl|vpn|'
  r'tailscale|wireguard|openvpn|zerotier|tap|tun|ppp|loopback|'
  r'bluetooth|isatap|teredo|rmnet|ccmni|wwan|pdp',
  caseSensitive: false,
);

/// Picks the local address a share link should name.
///
/// [peerAddresses] are the addresses Devices were recently heard at, on
/// whichever link carried them — LAN broadcast or a VPN directory. When
/// several local interfaces exist, the address sharing the longest prefix
/// with a peer's is the one a recipient on that link can actually reach:
/// that is what makes the router-LAN case and the Tailscale case both work,
/// because the peer's own address says which network the link belongs to.
///
/// With no useful peer hint the pick falls back to ranking: link-local is
/// never usable, RFC1918 private ranges beat carrier-grade NAT and other
/// globals, and virtual-looking interfaces lose to physical ones — the
/// first-enumerated-address rule this replaces kept landing on VPN and
/// hypervisor adapters.
///
/// Returns null when no usable IPv4 candidate exists; the caller decides
/// what "no address" means for its link.
String? chooseShareAddress({
  required List<ShareAddressCandidate> candidates,
  List<String> peerAddresses = const [],
}) {
  final usable = <_Candidate>[];
  for (final candidate in candidates) {
    final bits = _parseIpv4(candidate.address);
    // Loopback and link-local are unreachable from another Device, so they
    // are not candidates at all rather than merely low-ranked ones.
    if (bits == null || _isLoopback(bits) || _isLinkLocal(bits)) continue;
    usable.add(_Candidate(candidate: candidate, bits: bits));
  }
  if (usable.isEmpty) return null;

  final peers = <int>[];
  for (final raw in peerAddresses) {
    final bits = _parseIpv4(raw);
    if (bits != null) peers.add(bits);
  }

  if (peers.isNotEmpty) {
    _Candidate? best;
    var bestScore = 0;
    for (final candidate in usable) {
      var score = 0;
      for (final peer in peers) {
        final shared = _commonPrefixBits(candidate.bits, peer);
        if (shared > score) score = shared;
      }
      // Below a whole first octet the "match" is coincidence, not a shared
      // link: unrelated networks can still agree on scattered leading bits.
      if (score < 8) continue;
      if (best == null ||
          score > bestScore ||
          (score == bestScore &&
              _compareRank(candidate.rankKey, best.rankKey) < 0)) {
        best = candidate;
        bestScore = score;
      }
    }
    if (best != null) return best.candidate.address;
  }

  usable.sort((a, b) => _compareRank(a.rankKey, b.rankKey));
  return usable.first.candidate.address;
}

final class _Candidate {
  _Candidate({required this.candidate, required this.bits})
    : rankKey = _rankKey(candidate, bits);

  final ShareAddressCandidate candidate;
  final int bits;
  final List<Comparable<Object>> rankKey;
}

/// The fallback ordering: virtual-looking interfaces last, then address
/// class (private, then carrier-grade NAT, then everything else), then the
/// address itself so the pick never depends on enumeration order.
List<Comparable<Object>> _rankKey(ShareAddressCandidate candidate, int bits) =>
    [
      _virtualInterfaceName.hasMatch(candidate.interfaceName ?? '') ? 1 : 0,
      _addressClass(bits),
      candidate.address,
    ];

/// How well [address] serves as a share-link target by its range alone:
/// RFC1918 private first, carrier-grade NAT (the Tailscale range) next,
/// everything else last.
int _addressClass(int bits) {
  if (_isPrivate(bits)) return 0;
  if (_isCarrierGradeNat(bits)) return 1;
  return 2;
}

int _compareRank(List<Comparable<Object>> a, List<Comparable<Object>> b) {
  for (var i = 0; i < a.length; i++) {
    final order = a[i].compareTo(b[i]);
    if (order != 0) return order;
  }
  return 0;
}

/// The address as a 32-bit integer, or null when it is not IPv4.
int? _parseIpv4(String raw) {
  final address = InternetAddress.tryParse(raw);
  if (address == null || address.type != InternetAddressType.IPv4) return null;
  var value = 0;
  for (final part in address.address.split('.')) {
    value = (value << 8) | int.parse(part);
  }
  return value;
}

/// How many leading bits two IPv4 addresses share.
int _commonPrefixBits(int a, int b) {
  if (a == b) return 32;
  return 32 - (a ^ b).bitLength;
}

bool _isLoopback(int bits) => (bits >> 24) == 127;

bool _isLinkLocal(int bits) => (bits & 0xFFFF0000) == 0xA9FE0000;

bool _isPrivate(int bits) =>
    (bits >> 24) == 10 ||
    (bits & 0xFFF00000) == 0xAC100000 ||
    (bits & 0xFFFF0000) == 0xC0A80000;

/// 100.64.0.0/10 — the carrier-grade NAT range Tailscale assigns from.
bool _isCarrierGradeNat(int bits) => (bits & 0xFFC00000) == 0x64400000;

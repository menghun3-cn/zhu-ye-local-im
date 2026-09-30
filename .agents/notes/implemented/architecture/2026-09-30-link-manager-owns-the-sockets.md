# Agent Note: A LinkManager owns the sockets and hands out Sessions

Status: implemented

English | [中文](2026-09-30-link-manager-owns-the-sockets.zh.md)

## Problem

Everything below the socket existed and nothing above it did. [Discovery](../../architecture/2026-09-29-lan-discovery-by-broadcast.md)
produced a `DiscoveredPeer` carrying an address and a listening port;
[SecureLink](../../architecture/2026-09-29-core-wire-protocol-and-secure-session.md)
turned a `ByteTransport` into an authenticated Session; the transfer engine
and the clipboard mirror each wanted a Session and never a socket. Between
those two halves there was no object at all: nothing bound a listening port,
nothing dialed, nothing decided what happens when the same peer connects
twice, and nothing told anybody a Session had gone away. An app layer would
have had to implement all of that itself, and the second implementation would
have disagreed with the first.

## Decision

`LinkManager` is the only object that touches a socket.

- **`serve(port)`** binds `0.0.0.0` (default port 47655, or 0 for any free
  port) and turns each accepted connection into a Session as the responder.
  **`connect(host, port)`** dials and establishes as the initiator. Both
  return a `ManagedSession`, and both report failures as
  `HandshakeException` — a refused dial, a dead host, a timeout, a peer that
  is not the pinned Device, and a peer that does not hold the Pairing Secret
  are one error type to a caller.
- **A `ManagedSession` is a `SessionHub` plus its role and address.** The hub,
  not the raw `SecureLink`, is what the manager hands out, because a Session
  carries the transfer conversation and the clipboard conversation at once and
  the hub is the single object allowed to read the link's stream.
- **One Session per peer.** A second connection from a peer already held is
  closed with a `HandshakeException`; the existing Session is untouched.
  Replacing would tear down in-flight Transfers whenever a peer redialed, and
  would let any holder of the Pairing Secret displace a Session at will.
- **A Device never talks to itself.** A Session whose peer claims this
  Device's own Fingerprint is refused. A loopback connection read back is the
  ordinary case; accepting it would let a Device send itself Transfers that
  look like a peer's.
- **`expectedFingerprint` pins the peer.** The handshake proves a peer holds
  the Pairing Secret, never that it is a particular Device. A caller that
  decided who it is dialing passes the Fingerprint and gets a refusal, with no
  Session ever registered on its side, rather than a stranger's Session.
- **Events, not callbacks.** `events` is a broadcast stream of
  `SessionEstablished`, `SessionLost` and `SessionRefused`. An app layer
  rebuilding a device list and a clipboard mirror switching itself on both
  watch the same events, and neither owns the manager.
- **Trust is not decided here.** Holding the Pairing Secret is the entire
  admission test. Owner Group membership, Favorites and per-Transfer
  confirmation all live above this seam, which is what keeps "may receive my
  files" and "may read my clipboard" separable.

## Alternatives considered

**Let the app layer own the `ServerSocket` and call `SecureLink.establish`
itself.** Rejected: every rule above — one Session per peer, self-refusal,
pinning, teardown reporting — would then have to be re-implemented by each
consumer, and the rules exist precisely because they are easy to get subtly
wrong. Putting them in a tested object makes them once, not per consumer.

**One Session per *connection* rather than per peer, replacing on conflict.**
Rejected: a peer that redials — after a network blip, or because its own UI
reconnected — would silently kill whatever Transfer was in flight, and a peer
that can displace a Session at will is a peer that can interrupt another
Device's work.

**Have the manager own a `TransferEngine` and a clipboard mirror per
Session.** Rejected for this increment: the engine needs a payload sink and
limits chosen by the app (where do received files go?), and the mirror needs a
`SystemClipboard`. Both are app-layer policy. The manager hands out the hub
and says nothing about what runs on it.

**Resolve the Pairing Secret per peer, after the handshake identifies it.**
Rejected, and structurally impossible: the secret is what authenticates the
handshake, so it cannot be chosen after the peer is known. One secret per
manager, overridden per `connect` call for the Pairing flow, is the honest
shape.

## Consequences

- An app layer can be written against `LinkManager` alone: discover, connect,
  hold `ManagedSession`s, close. Nothing above it needs a `Socket`.
- `serve` binds all interfaces. That is what makes a Device reachable on a
  LAN, and it means anything on the same link can *attempt* a handshake; what
  stops it is the Pairing Secret, not the bind address.
- Session teardown is now observable from both ends, because transport
  completion is derived from the read side — see
  [peer teardown and secret confirmation](../../bug-fix/2026-09-30-peer-teardown-and-secret-confirmation.md),
  which this increment had to fix to make `SessionLost` true.
- A refused connection is reported as an event but is not retried. Automatic
  redial policy belongs to the app layer, which knows whether the user asked
  for it.
- `lib/core/` still has no Flutter dependency: the manager is exercised by
  `dart test` over real loopback sockets, including a transfer carried end to
  end through a managed Session.

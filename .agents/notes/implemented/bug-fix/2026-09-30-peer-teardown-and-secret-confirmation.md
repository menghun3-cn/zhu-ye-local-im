# Agent Note: A peer's disappearance is read, and the Pairing Secret is confirmed

Status: implemented

English | [中文](2026-09-30-peer-teardown-and-secret-confirmation.zh.md)

## Problem

Building [the LinkManager](../../architecture/2026-09-30-link-manager-owns-the-sockets.md)
required two things the layers below it did not actually provide, and the
tests written for the manager found both:

**1. A Session never learned that its peer had gone.** `SocketByteTransport`
completed its `done` future from `Socket.done`. Measured on this platform,
that future never completes when the *peer* closes the connection: it only
ever completes for a socket this side closed. A probe (a server that accepts a
connection, a client that calls `destroy()`, timestamps on every observable
event) showed the read side reporting `onDone` in about 1ms while `done`
stayed pending for the full two-second window — and reporting nothing at all
when nobody was reading the socket. So `SessionLost` could not fire, and a
Device would keep showing a peer it could no longer reach.

**2. A Session could be established with a peer that did not hold the Pairing
Secret.** The handshake exchanged `hello` and `helloAck`, derived keys from
the X25519 exchange and the secret, and returned. Nothing in it *checked* that
both sides derived the same keys: with two different secrets, both peers
returned a `SecureLink` and the mismatch surfaced later, as a decryption
failure on the first real message. A caller that treats "a Session was
established" as a fact — which the transfer engine, the clipboard mirror and
the LinkManager all do — was relying on something nobody had verified.

## Decision

**Transport completion is derived from the read side.** `SocketByteTransport`
completes `done` when the incoming stream ends or errors, with `close()` and
`Socket.done` kept as additional completion paths. The consequence is
documented where it matters: dart:io reports nothing on a socket nobody reads,
so a transport with no reader cannot notice a peer leaving. Every consumer in
this codebase reads — the frame decoder subscribes as soon as a Session exists
— so nothing depends on the unread case.

**The handshake confirms the secret before returning a link.** After deriving
the keys, each side sends one `SessionConfirmMessage`, sealed with the keys
the handshake derived, and requires the peer's in return. The message carries
nothing: its authentication tag is the whole payload, so a peer holding a
different secret cannot produce one that decrypts. The confirmation is read
through the same frame iterator the pump will later use — safe because the
pump only starts when somebody subscribes, which cannot happen before
`establish` returns — and it is consumed by the handshake, so no consumer
above ever sees one. A side that finds the peer's confirmation unreadable
closes the transport immediately rather than waiting out its timeout: the peer
has no reason to keep waiting for a Session that will never work.

The wire protocol version stays at 1. Nothing has been released, so there is
no deployed build to interoperate with; the confirmation is part of v1's
handshake as shipped.

## Alternatives considered

**Keep the late failure and document it.** Rejected: "a Session exists" is the
contract the entire layer above is written against. A Session that is
established and then cannot carry a single message is a lie that turns every
caller into a special case, and the failure would arrive as a decrypt error on
some unrelated Transfer rather than at the moment of connecting.

**Give the confirmation a payload — a version tag, or the sender's
Fingerprint.** Rejected: the tag would have to be verified against something,
and the Fingerprint is already carried, unauthenticated, in the handshake
where it is explicitly a claim. A confirmation that carries nothing has
exactly one meaning and no parsing surface.

**Confirm on one side only.** Rejected: then only the responder learns the
secret is wrong while the initiator gets a Session that dies on first use —
half the problem, kept.

**Use a dedicated frame type for the confirmation instead of a wire message.**
Rejected: both peers would need to agree on a second framing vocabulary for
one frame that carries no data, and every frame type added there is a new
thing a hostile peer can send.

**Poll the socket, or send periodic keepalives, to detect a peer's
disappearance.** Rejected: it costs traffic and time to answer a question TCP
already answers. The read side knows the moment the peer goes away; the bug
was that the signal was being read from the wrong place.

## Consequences

- `SessionLost` fires promptly and reliably in both directions, including when
  a peer's process is killed rather than closing cleanly.
- A wrong Pairing Secret fails in the handshake, with an error naming the
  secret, on both sides. Two existing tests that pinned the old behaviour —
  "a peer that does not know the pairing secret cannot be understood" and "a
  different pairing secret derives a different short string" — were replaced
  by ones that pin the new behaviour, because the old behaviour no longer
  exists to test.
- The handshake costs one extra round trip: two sealed records, one in each
  direction. For a connection that will carry a file, that is noise.
- A caller can now distinguish "the peer's secret differs" from "the peer
  vanished" only by the message text; both are `HandshakeException`. That is
  deliberate — a peer that cannot authenticate and a peer that is not there
  are the same answer to "can I talk to it".

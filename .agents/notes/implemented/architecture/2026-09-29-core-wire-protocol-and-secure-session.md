# Agent Note: The wire protocol and the authenticated secure session

Status: implemented

English | [中文](2026-09-29-core-wire-protocol-and-secure-session.zh.md)

## Problem

Two Devices on a LAN have to exchange text, files and clipboard Mirrors with no
server, no account and no cloud. That leaves two things the platform does not
hand over for free: a way to frame messages over a byte stream, and a Session
that is both confidential and authenticated — because a LAN is hostile, and any
host that can reach the listen port can open a TCP connection and start
talking.

Authentication is the awkward part. With no server there is no certificate
authority to sign a device certificate, and with no account there is nothing to
anchor trust in. The only thing two Devices can share before they meet is the
Pairing Secret established out of band — a QR code or a short code with a SAS
comparison (see
[owner-identity-gates-clipboard](2026-09-29-owner-identity-gates-clipboard.md)).
The Session has to be authenticated by that secret and by nothing else, and it
has to run on the pure-Dart VM so the same code serves Windows and Android with
no native crypto.

## Decision

The project ships its own framing layer and its own handshake over `dart:io`
sockets, in `lib/core/`:

- `protocol/frame.dart` — the wire framing.
- `protocol/messages.dart` — the control vocabulary.
- `transport/byte_transport.dart` — the only thing the layers above know about
  the network.
- `identity/` — Device, Fingerprint and Pairing Secret.
- `security/hkdf.dart`, `security/secure_link.dart` — key derivation and the
  Session.

## The frame layer

Every frame is `u32 length | u8 kind | payload`, with `length` counting the kind
byte plus the payload so a reader always knows how many further bytes to wait
for. Three kinds exist: `control` (`0x01`, a UTF-8 JSON object), `chunk`
(`0x02`, a transfer id, a `u64` offset and raw bytes) and `sealed` (`0x03`, a
12-byte nonce followed by ciphertext and its 16-byte Poly1305 tag).

The length prefix is attacker-controlled, so a frame is rejected above
`maxFrameBytes` (16 MiB) on both encode and decode — without that ceiling nine
bytes on the wire could ask the decoder to allocate 4 GiB. The decoder is
incremental and compacts lazily, because TCP delivers byte ranges rather than
messages and a stream of small frames must not memmove its live tail on every
frame. A stream that ends mid-frame raises `ProtocolException` rather than
looking like a clean end of conversation.

Sealing sits *above* framing rather than below it: a `sealed` frame's plaintext
is the complete encoding of exactly one inner frame. One decoder therefore
serves both the plaintext handshake and the encrypted session, and there is no
point mid-stream where a half-consumed read buffer has to be handed between
layers.

## The handshake

The handshake is X25519 plus HKDF-SHA256 plus ChaCha20-Poly1305, with the
Pairing Secret mixed in as pre-shared key material:

1. Each side generates an ephemeral X25519 key pair and a 32-byte nonce, and
   sends a `hello` (or `helloAck`) carrying its Device descriptor, its ephemeral
   public key, its nonce and `wireProtocolVersion` (1).
2. A peer that claims this Device's own Fingerprint, or speaks another protocol
   version, is rejected before any key derivation happens.
3. `ikm = X25519 shared secret ‖ Pairing Secret`; `salt = initiatorNonce ‖
   responderNonce`, ordered by role rather than by arrival so both sides build
   the same salt regardless of who spoke first.
4. `HKDF-Extract` produces the PRK; two `HKDF-Expand` calls under the labels
   `i2r` and `r2i` produce two 32-byte directional keys. Each direction has its
   own key, so a record can never be reflected back at its sender.
5. Records are sealed with ChaCha20-Poly1305 under the AAD
   `local-transfer/v1 record`.

The label `local-transfer/v1` is mixed into every derivation as domain
separation: a protocol change alters the derivation, so an old build and a new
one derive different keys instead of silently interoperating with different
meanings.

The same PRK yields a six-digit short authentication string — four bytes of
`HKDF-Expand` under the label `sas`, taken modulo one million — that both
Devices display. Completing the handshake proves the peer knows the Pairing
Secret; it does **not** prove *which* Device is on the other end, because any
Device holding the same secret authenticates identically. The SAS is what closes
that gap: the user compares it out of band, and a mismatched peer is
disconnected.

Every way the handshake can fail — a timeout, a peer that hung up, a transport
that died mid-exchange — surfaces as `HandshakeException`, so a caller decides
"no Session was established" on one error type rather than having to tell a
socket error from a protocol error.

## The transport seam

`ByteTransport` (`incoming`, `add`, `done`, `close`) is the only thing the
layers above know about the network. `SocketByteTransport` wraps a TCP socket
and `destroy()`s rather than closing gracefully on teardown, so an abandoned
Session never waits for a FIN the peer may not send. `MemoryTransportPair` joins
two transports in-process, which lets the full handshake and session be
exercised over a real socket and purely in memory with no code path difference.

## Alternatives considered

**TLS via `dart:io`'s `SecureSocket`.** Would give a vetted record layer for
free. Rejected: TLS authenticates with certificates, and there is no CA and no
account here. Anchoring trust in the Pairing Secret would mean either running a
private CA and shipping a client certificate to every Device, or using a PSK
cipher suite `dart:io` does not expose — and TLS still cannot derive the SAS
without an extra in-band exchange that the record layer exists to protect.

**The Noise protocol framework.** A well-reviewed framework whose `XXpsk3`-shaped
handshake matches this threat model closely. Rejected: no maintained Dart
implementation exists, so adopting it would mean porting it; the subset actually
needed here — one X25519 exchange, one HKDF, one AEAD — is smaller than the port
would be.

**Plaintext with a separate HMAC per message.** Smaller and easier to review.
Rejected: no confidentiality, and it hand-rolls an encrypt-then-MAC composition
that an AEAD already standardises.

**`libsodium` or another native crypto over FFI.** Rejected: adds a native
dependency and a per-platform build step to a pure-Dart codebase, for primitives
`package:cryptography` already provides in Dart.

**Take HKDF from a dependency.** Rejected: key derivation is the one place a
silent change fails quietly — it would produce keys the other side simply cannot
match rather than raising — so the derivation is owned here and pinned by this
repository's own tests against RFC 5869's published vectors.

## Consequences

- The Session is authenticated by the Pairing Secret alone, with no PKI, no
  per-device certificate and no account, which is what the no-server constraint
  requires.
- The protocol is now this project's to version and keep compatible.
  `wireProtocolVersion` and the `local-transfer/v1` label make a future change
  detectable instead of silently mismatched, but there is deliberately no
  negotiation: version 1 and version 2 will simply not interoperate.
- Crypto risk is now this repository's. Mitigations: only vetted primitives
  (`package:cryptography` for X25519 and ChaCha20-Poly1305, `package:crypto` for
  HMAC-SHA256), a hand-rolled HKDF pinned by RFC vectors, one directional key
  and a fresh nonce per record, and a `sealed` record whose plaintext is exactly
  one inner frame so nothing can be smuggled past the layer that inspects
  frames.
- `test/security/secure_link_test.dart` pins the security-relevant behaviour
  over both the in-memory pair and a real loopback socket: a completed
  handshake, a matching SAS, rejection of a wrong secret, rejection of a
  tampered record, refusal of an unsealed frame after the handshake, a version
  mismatch, a self-fingerprint peer, a peer that hangs up mid-handshake, and a
  1 MiB payload reassembled across many socket reads.
- The clipboard Mirror and the transfer engine are not built yet. They are the
  next increments and are expected to consume this layer unchanged.

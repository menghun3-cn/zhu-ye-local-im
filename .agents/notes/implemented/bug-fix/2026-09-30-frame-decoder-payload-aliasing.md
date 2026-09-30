# Agent Note: A decoded frame owns its bytes, not the decoder's buffer

Status: implemented

English | [中文](2026-09-30-frame-decoder-payload-aliasing.zh.md)

## Problem

[`FrameDecoder`](../../../../lib/core/protocol/frame.dart) reassembles every
frame in one growable buffer that it reuses for the life of a connection, and
`next()` handed out payloads that were *views* into that buffer
(`Uint8List.sublistView`). The buffer is not append-only: once a frame is long
enough, `_compact()` shifts the live tail down over the bytes that frame just
came from. A frame that still referenced those bytes therefore had its own
payload rewritten underneath it.

The damage was not theoretical, because the transfer path sends 512 KiB per
chunk and one real socket read routinely delivers a whole record *plus the
first bytes of the next one*. A single `add()` puts both in the buffer, and the
first `next()` then decodes the large record, advances the cursor past it, and
— with the following frame's opening bytes already sitting there — runs the
compaction that moves them to offset 0. That is exactly where the record's
nonce and the head of its ciphertext live. The record came back with a
different nonce, failed ChaCha20-Poly1305 authentication, and took the pump
down with it.

It presented as flakiness rather than as a bug: whether a large record shared a
read with the next frame depends on socket timing, so
`test/security/secure_link_test.dart`'s "over a real socket handshake, control
message and bulk bytes all arrive" passed on some runs and failed on others.
Running that case alone gave one failure and then one pass — intermittency on a
test whose subject is a real socket is what pointed at the decoder instead of
at the test.

## Decision

**`next()` copies a frame's payload out of the read buffer.** A returned frame
owns its bytes, so the decoder may grow, append to, and compact that buffer
freely afterwards: nothing it has already handed out points into it. The decode
helpers still build their fields as views — `ChunkFrame.data`,
`SealedFrame.nonce`, `SealedFrame.cipherText` — but into the owned payload,
which is never written again.

The invariant is stated on `FrameDecoder` itself, so whoever adds the next frame
kind has one rule to satisfy rather than a per-helper convention to
reconstruct.

Nothing on the wire changes and the protocol version stays at 1.

## Testing

Two cases in `test/protocol/frame_test.dart`'s "decoder buffer reuse" group
decode a 512 KiB frame with the following frame's first bytes already buffered,
one sealed and one chunk. With the copy in place they pass; removing it makes
the sealed case report a nonce of `{"t":"after"` — the following frame's bytes
— so the regression names the corruption instead of surfacing several layers up
as an authentication error that reads like a wrong Pairing Secret.

## Alternatives considered

**Make `_compact()` allocate a fresh buffer instead of memmoving in place.**
Rejected: it does not close the hole by itself. The `_start == _end` path also
resets the cursor to zero without moving anything, and the next `add()` then
writes at offset 0 — over the bytes of the frame just handed out. Closing both
paths means allocating a buffer every time the buffer drains, which is the most
common case in a request/response protocol, to avoid a copy that only matters
for bulk frames.

**Copy only where a frame keeps a view — `ChunkFrame.data`,
`SealedFrame.nonce`, `SealedFrame.cipherText` — and leave `next()` alone.**
Rejected: it leaves "does this frame own its bytes" as a property each decode
helper has to be audited for, and a helper that starts retaining a view keeps
compiling. Its only saving is one copy per control message, tens of bytes,
since chunk and sealed frames pay a single copy either way.

**Have callers copy what they need before advancing the decoder.** Rejected:
the rule a caller could follow would be wrong. The corruption happens *inside*
the `next()` that returns the frame, not on some later call, so no caller
discipline avoids it — the frame is already damaged when it arrives.

**Document the aliasing as a known constraint.** Rejected for the same reason:
a constraint that cannot be honoured is a bug with a comment on it. It would
also have to reach through `SecureLink`, whose pump holds a frame across the
`await` that decrypts it, and through every future consumer that touches a
chunk's bytes before the decoder is advanced again.

## Consequences

- Frames are durable. No part of the framing layer has a hidden "valid until"
  window, and the class no longer depends on callers consuming each frame
  promptly — a property no consumer could have been relied on to keep.
- The decode path performs one memcpy per frame that did not happen before. For
  a bulk record that is the same order as the copy `SecureLink` already makes
  when it assembles a record's ciphertext and tag for sending; for a control
  message it is tens of bytes.
- The `secure_link_test` case that exposed this stops being intermittent. It
  was recorded as flaky, which is the failure mode that hides this whole class
  of defect: the code was wrong on every run, and only sometimes observably.

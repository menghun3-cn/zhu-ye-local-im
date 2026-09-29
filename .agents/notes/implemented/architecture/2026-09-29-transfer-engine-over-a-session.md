# Agent Note: Offer, stream, verify — and make an interrupted transfer resumable

Status: implemented

English | [中文](2026-09-29-transfer-engine-over-a-session.zh.md)

## Problem

A handshake proves the peer knows the Pairing Secret and gives both Devices a
private channel. It says nothing about whether the bytes that travel over that
channel arrive, arrive whole, or arrive as the bytes that were meant. A Session
is a pipe; a transfer is a promise, and something has to keep it.

The promise has a specific shape in this product. A user drops five files on a
Device name, or copies text and expects it to appear on the other machine. On
the receiving side, a stranger on the same Wi-Fi can *offer* things, and a
receiver that starts writing before its owner has agreed has been made to fill
its disk by somebody it has never met. On the sending side, "sent" is not
"arrived": the sender has no more evidence the file is intact on the far end
than a handshake can give it.

Two platform facts make this concrete rather than theoretical. Android gets a
foreground service with a six-hour `dataSync` budget, so an interrupted transfer
is a normal event rather than a rare one
(see `docs/android-background-constraints.md`). And a socket write is not a
promise: `Socket.add` returns before anything has left the machine, so the only
evidence a payload arrived is the receiver saying so.

## Decision

Transfers live in `lib/core/transfer/`, over a Session, in three phases:

1. **Offer.** The sender declares what it wants to send — kind, items, sizes, and
   a SHA-256 per item — and nothing moves.
2. **Answer.** The receiver names the items it will take, and how many bytes of
   each it already holds. Anything it omits is refused.
3. **Stream and verify.** The sender streams the accepted items as slices, says
   `complete`, and the receiver replies with what it hash-verified. Only then is
   the transfer over.

- `transfer.dart` — the shared vocabulary: `TransferState`, `TransferProgress`,
  the sealed `TransferOutcome` family, and the base `Transfer`.
- `byte_source.dart` / `payload_sink.dart` — the two storage seams, each with an
  in-memory and a file implementation.
- `outgoing_transfer.dart` / `incoming_transfer.dart` — the two state machines.
- `transfer_channel.dart` — the seam over a Session, so a state machine can be
  driven without a socket or a handshake.
- `transfer_engine.dart` — the router: one engine per Session, one worker, and
  the limits.
- `transfer_limits.dart` — what a Device refuses before anyone is asked.

### The digest is a promise made before the bytes

An Offer carries each item's SHA-256, computed by reading the item through
*before* proposing it. The receiver hashes what it actually wrote and reports
its own digests back, and the sender compares. Both ends hash independently, and
neither end's number is taken on trust by the other.

This is an integrity check, not a security boundary. A third party cannot alter
bytes in flight — ChaCha20-Poly1305 already covers that. What the digest catches
is everything else: a file that was edited between the Offer and the read, a
source that ended early, a sink that wrote to the wrong offset, a full disk, and
a peer whose implementation is simply broken. Those are the failures that
actually happen, and none of them are visible from the record layer.

### Resume is reported from the sink, not from the caller

`IncomingTransfer.accept` takes sinks and derives the resume offsets from
`PayloadSink.bytesWritten`. There is deliberately no separate `resumeOffsets`
parameter: the sink *is* the thing that knows how many bytes are on disk, and a
second number passed in beside it is a second truth that can disagree with the
first. Handing over the partial file kept from an interrupted attempt is the
whole resume API.

A digested prefix is not a loophole. The sink hashes adopted bytes along with
the ones it receives — by reading the prefix through once when it opens — so the
final digest covers the whole item. A receiver cannot claim to hold a prefix
that is not part of the item, and if the file was replaced between attempts the
check fails at the end rather than producing a silently spliced file.

### Frames are routed in arrival order, one at a time

`complete` means "every byte of every item is on the wire", so it may only be
handled once the slices before it have actually been *written*. The Session
hands control messages and payload slices to two separate streams, so the engine
funnels both into a single queue drained one task at a time.

This is not tidiness. Two concurrent loops reading the two streams let a
`complete` overtake a slice still being written to disk — the chunk's `onData`
starts first, then awaits a file write, and the message's `onData` runs during
that gap. The receiver then sees a short item, fails a transfer whose bytes had
all arrived, and the sender gets a `corrupt` report for a file that is fine. The
in-memory sink happens to write synchronously and hides this; a file sink does
not, which is how the test suite caught it.

The cost is that one slow write delays an unrelated message on the same Session.
A Session carries one conversation between two Devices, so that is cheaper than
the alternative.

### Limits are enforced before the app is asked

`TransferLimits.violationOf` runs on every Offer. An Offer that names no items,
too many items, an item bigger than `maxItemBytes`, more in total than
`maxTotalBytes`, a reused or empty item id, a malformed digest, or a text body
whose declared size is not its length, is refused with `refused` and never
reaches the app. An Offer is the peer's claim, so the checks are on the claim.

The shape rules are strict on purpose. A file item must carry a digest — without
one the receiver has nothing to check against, and the copy would carry no
guarantee at all. A text or clipboard Offer must name exactly one item whose
size is the body's UTF-8 length, because that body travels in the Offer and its
size is a fact both ends can compute rather than a negotiation.

The two timeouts are the sender's only, and they are implemented without timers
in the receiver. A sender that hears nothing must stop waiting eventually; a
receiver that is mid-write has a transfer its user can cancel, and timing it out
would turn a slow link into a failed transfer for no reason.

### The engine routes, it does not decide

`TransferEngine` refuses what the limits forbid and hands everything else to
whoever is listening on `incoming`. Whether an Offer is welcome is the app's
call — a question that needs a user, a destination directory, and possibly a
prompt. A message naming a transfer the engine is not running is noted through
`onNotice` and dropped: a stale or hostile id must not be able to take the
engine down, but a bug on this side must not be silent either.

## Finding: a closed Session could crash its own pump

Writing the "a session that dies takes its transfers with it" test exposed a
defect in the previous increment. `SecureLink.close()` finishes both stream
controllers *before* closing the transport, so frames already queued behind the
teardown were still delivered to a finished controller. The resulting
`StateError` was then caught by the pump's own error handler, which tried to
report it on the same closed controller — and that second, unhandled throw is
what escaped.

`_runPump` now checks `_closed` both before delivering and again after
decrypting, and the error path returns quietly once the link is closed. A link
torn down on purpose has nothing to report.

## Alternatives considered

**Stream the bytes and skip the Offer.** The sender just starts writing, as a
socket would. Rejected: the receiver would have to accept whatever arrives
before it can decline, the sender cannot say how much is coming, and a receiver
whose disk is full finds out after the bytes are already on the wire. The
round trip is what lets the receiving user be asked at all.

**Send the digest after the bytes, as a check of what arrived.** Rejected: an
attacker or a broken peer could compute the digest of whatever it did send, so
the check would only prove internal consistency. A promise has to precede the
thing it is about, or it is not a promise.

**Check the size instead of a digest.** Catches truncation, not corruption or
substitution — a single flipped bit inside the payload passes. Rejected: it
costs one hash and buys a materially weaker guarantee.

**Let the sender track resume offsets.** The sender keeps a ledger of what it
believes the receiver has, and resumes from there. Rejected: only the receiver
knows what is actually on its disk. A sender-side ledger is a second truth that
goes stale exactly when it matters — after a crash, a kill, or a failed write.

**Trust the receiver's verification alone.** The receiver hashes and says
"fine", and the sender believes it. Rejected: if the receiver is the side that
is wrong, its complaint is useless, and a buggy receiver reporting success would
be indistinguishable from a good one. Both ends hash, and the two answers are
compared.

**One Offer per item.** A five-file drop becomes five transfers. Rejected
because it moves a problem upward: five decisions for one gesture, five partial
outcomes to present, and a grouping the UI would have to invent that the wire
format already has.

**Sequence numbers instead of byte offsets.** Rejected: an offset is
self-describing and is what makes a stream resumable after an interruption. A
sequence number needs a persisted map of what each number meant, which is
precisely the state that does not survive the crash the mechanism exists to
recover from.

**Carry small payloads inside the Offer.** Tempting, since text already does.
Rejected for files: an Offer is a control frame, bounded by `maxFrameBytes`,
decoded as one JSON object and held in memory whole. Routing bulk through it
would cap every transfer at 16 MiB and base64 the bytes on the way.

**Write to a temporary file and rename on completion.** Not rejected —
deferred. It is the right way to avoid leaving a half-file under the final name,
and it belongs to whoever creates the sink, because renaming is a filesystem
decision and the sink deliberately knows nothing about final names. Recorded
under Consequences so the gap is visible rather than assumed.

## Consequences

- **There is no socket backpressure.** The sender awaits each encryption, which
  yields, but `ByteTransport.add` never blocks, so a fast source and a slow link
  can queue the in-flight remainder in memory. `maxTotalBytes` bounds it — at
  8 GiB per Offer, a bound that is real but not small. Closing it properly means
  a credit-based flow control window, which is a wire change.
- **A transfer does not survive a process restart.** The engine's state is in
  memory, so an interrupted transfer is failed, not parked. The *bytes* survive:
  a file sink leaves the partial file, and a new transfer against it resumes
  from where it stopped. Nothing re-drives that automatically, and on Android
  that automatic re-drive is what the six-hour foreground-service budget is for.
- **Sinks write in place**, so an interrupted transfer leaves a partial file at
  its final path. Reference-counting and renaming are the caller's job.
- **Nothing creates an engine yet.** The Windows and Android layers that would
  open a listening socket, run the handshake, and build a `SecureLinkChannel`
  are not written, so this increment is reachable from tests and from a headless
  harness, not from the app.
- **`transferChunkBytes` is a protocol constant**, not a tuning knob: 64 KiB
  keeps a slice far below the frame ceiling while keeping framing and AEAD
  overhead under a tenth of a percent. Changing it changes the wire, so a
  version of this that negotiated a window would have to version it.
- **A Transfer is one-directional and one-shot.** There is no restart, no
  renegotiation, and no way to add an item to a Transfer already running. A new
  Transfer is how anything else is expressed, and transfer ids are random so two
  Devices starting at once cannot collide.

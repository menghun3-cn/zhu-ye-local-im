# Agent Note: Clipboard Mirroring inside an Owner Group

Status: implemented

English | [中文](2026-09-29-clipboard-mirroring-within-an-owner-group.zh.md)

## Problem

Transfers work. The clipboard does not, and it is the harder half of the
product.

Three things go wrong at once when a Device starts mirroring its clipboard.

**It loops.** A applies a value from B. Its clipboard changes. The platform
reports that change, so A captures it and sends it to B. B applies it, its
clipboard changes, and the two Devices bounce one value between them for as long
as they are both running. Nothing about a Session prevents this; the loop is
made of two correctly behaving peers.

**The Session is the wrong size of trust.** A handshake proves the peer knows
the Pairing Secret, and the Secret is what decides who can connect. But a Secret
is a string that can be copied, and "this Device may receive my files" is not
"this Device may read every password I copy". Exchanging clipboard content over
any authenticated Session would silently grant the second when the user only
intended the first. This is the decision recorded in
[Owner identity layer gates clipboard mirroring](2026-09-29-owner-identity-gates-clipboard.md);
this note is what implements it.

**Platforms disagree with each other and with themselves.** Reading the
clipboard and writing it have different rules, and the direction matters:
Android can write a clipboard in the background but may only read one while its
window is focused (`docs/platform-clipboard-constraints.md`). A UI that offers
one "sync clipboard" switch therefore promises something half the platforms
cannot deliver.

There is also a plumbing problem that has to be solved before any of the above
can be expressed. `SecureLink.messages` is a single-subscription stream and the
transfer engine already reads it. A second listener does not receive a copy of
the frames; it silently takes every one of them. So there is currently no way
for a second conversation to exist on a Session at all.

## Decision

Four pieces, in `lib/core/`, each the precondition of the next.

### One Session, split by a hub

`session/session_hub.dart` introduces `SessionHub`: it takes the single
subscription on a `SecureLink`, and hands out two views over it.

- `hub.transfers` is a `TransferChannel` for the `TransferEngine`, whose
  contract is unchanged.
- `hub.clipboard` is a `ClipboardChannel` for the mirror.

The hub sorts and does not interpret: a `ClipboardMessage` goes to the clipboard
view, `hello` and `helloAck` are dropped because the handshake is history by the
time a hub exists, and everything else goes to the transfer view, where the
engine already decides what to do with a type it does not route.

Payload slices are passed through rather than intercepted. The engine is their
only consumer, so a second controller in the path would copy nothing and add a
buffer somebody has to drain.

### The Owner Group is the gate

`identity/owner_group.dart` adds `OwnerGroup`: the set of member Fingerprints,
always including this Device's own. Membership is per Device rather than per
person, because Pairing admits one Device at a time and because a Fingerprint is
something a Device can prove it holds.

An entry is captured only for peers in the group, and applied only when it came
from a member. This is the boundary the previous note argued for, made
mechanical: there is no code path that mirrors to or from a Device outside the
group, so no configuration mistake can widen the trust.

The model is here; the flow is not. How a Device joins a group — a scanned QR
code, a typed code with short-authentication-string comparison, and the storage
that survives a restart — is a separate increment.

### Mirroring is a conversation, not a Transfer

Clipboard content that a person deliberately sends is a `PayloadKind.clipboard`
Transfer: it gets an offer, an answer, a digest and a receipt. Mirroring is not
that. It is defined by needing *no* user action, it is one direction at a time,
and it has nothing to verify — so it travels as a single `ClipboardMessage`.

That message carries two fields a Transfer Offer does not, and both are load
bearing:

- `origin`, the Device the value was copied on. This is what stops the loop: a
  Device that sees its own content returning drops it without a word instead of
  applying it and bouncing it back.
- `entryId`, so a Device can recognise a duplicate of an entry it has already
  handled — which happens whenever a Session is retried or a peer is buggy.

### The mirror

`clipboard/clipboard_mirror.dart` is the service, over two seams:
`SystemClipboard` (read, write, watch) and `ClipboardChannel` (send, receive). A
`ClipboardEntry` is the value with its tag, and it never prints its text: a
clipboard routinely holds passwords and one-time codes, so its `toString` gives
an id, an origin and a length.

One mirror covers every peer rather than one mirror per peer, because echo
suppression, duplicate detection and ordering are properties of the *clipboard*,
not of a Session.

### The origin tag is the loop fix, and it is guarded in one direction

An incoming entry must be tagged with the peer it arrived from. A peer that
relays somebody else's content under a new tag would put into the group a value
that never belonged to it, and the tag is the only thing that would have said so.
An entry tagged with *this* Device, arriving over the wire, is dropped first and
silently — that is the routine echo case, and logging it would fill a log with
the normal path.

### Capability is enforced, not displayed

`ClipboardCapability` already travels in every `hello`. The mirror enforces it:
a platform whose `canOriginate` is false is never watched for changes at all —
not watched and then discarded, which on Android would be a permission prompt
for a read that the platform will refuse — and a platform whose `canApply` is
false refuses to write and reports why, rather than appearing to work.

### Ordering is compared per origin only

Each incoming entry carries the `capturedAt` the capturing Device stamped on it.
A mirror keeps the newest timestamp it has taken *from each origin* and drops
anything not newer. Timestamps from different Devices are never compared:
clocks are not synchronised, so the comparison would be meaningless, and within
one origin the same Device's clock is the only ordering information available.

### Three modes, one switch

`ClipboardMode` is `off`, `stage` or `mirror`. `off` captures nothing and does
not watch the clipboard; `stage` captures as `mirror` does but holds an incoming
entry until the user accepts it; `mirror` applies with no user action. Capture is
on in the last two because the mode describes how this Device *treats* the
clipboard, and a user thinks of clipboard sync as one setting.

## Alternatives considered

**Give `TransferEngine` a callback for messages it does not route.** The
smallest change, and it needs no new type: the engine is already the sole reader
of `messages`, so it can simply hand on what it does not handle. Rejected
because it makes the engine the Session's dispatcher — a job it does not have —
and every future conversation would grow the engine's API by one callback. The
hub keeps the engine's contract exactly as it was.

**Let the mirror read `SecureLink.messages` directly.** Not a choice: the stream
is single-subscription and the engine reads it first, so the mirror would take
every frame and the engine would silently starve.

**Buffer clipboard changes while Mirroring is off, and replay them on.** Would
make switching the mode on look like it recovered the copies made while it was
off. Rejected because it imitates a bug rather than the platform: a watcher that
is not running does not observe anything, and a queue that replays stale copies
into an Owner Group is a worse failure than a dropped one. It is also why
`MemorySystemClipboard` uses a broadcast controller — a buffering one would have
hidden exactly this.

**One mirror per peer.** Would let each Session own its own state and be easier
to reason about in isolation. Rejected because the state is not per Session: the
two-Device loop is a property of two clipboards, and a per-peer mirror would
have to detect it across peers or not at all.

**Suppress our own echo by comparing the value's text.** This is what the mirror
does, as a bounded queue of the last 16 applied values. The alternative — an id
registry only — cannot work, because the platform reports a *change* with text
and no id, so text is the only thing there is to match on. The cost is recorded
under Consequences.

**Tag entries with the Owner's key pair rather than the Device Fingerprint.**
Would make "same Owner" the tag and remove the need for a membership set.
Rejected because a Fingerprint is what identifies a Device everywhere else in
this codebase, and Pairing admits Devices one at a time — an Owner key would
have to be introduced, distributed and rotated where a Fingerprint is already
derived and already travels.

**Accept an entry tagged with any member of the group, whatever Session it
arrived on.** More permissive, and it would let a well-behaved peer relay.
Rejected: it is precisely the smuggling route. A Device inside the group could
relay content it received from outside it, relabelled, and nothing downstream
could tell.

**Order entries by `capturedAt` across all origins.** Would settle ties between
two Devices that copy at nearly the same moment. Rejected: Device clocks are not
synchronised, so cross-origin comparison is noise with a plausible look.

**A single `mirroring` boolean instead of three modes.** Simpler to persist and
to render. Rejected because `Stage` is a real expectation — the glossary defines
it — and a boolean cannot express "send what I copy, but ask me before replacing
what I have".

**Use `PayloadKind.clipboard` Transfers for mirroring too.** Would give every
mirrored entry an accept/verify round trip and a receipt. Rejected because a
Transfer's centre is a user decision — the whole point of the offer/answer phase
is that the receiver is asked — and Mirroring is defined as needing no user
action. Making the receiver auto-answer would leave the mechanism intact and its
meaning gone.

## Consequences

- **Nothing creates a hub from a socket.** The platform layers that would accept
  a connection, run the handshake, and build a `SessionHub` are not written, so
  this increment is reachable from tests and from a headless harness, not from
  the app. The same is true of `SystemClipboard`: the seam has an in-memory
  implementation and no platform one.
- **Mirroring has no delivery confirmation.** It is fire-and-forget, so an entry
  dropped by a dead Session is lost with no retry and no report. For a mirrored
  copy that is the right trade — the value is on the originating clipboard
  either way — but it is a guarantee this path does not have.
- **Echo suppression can swallow a genuine re-copy.** The last 16 applied values
  are remembered by text; copying one of them again inside that window is not
  re-mirrored. It is benign rather than correct: the group already holds that
  exact value, so nothing observable is lost. The window is a bound, not a
  correctness argument.
- **A duplicate is remembered for 256 entries and a staged entry held for 8.**
  Beyond those bounds the oldest is forgotten, so a sufficiently delayed
  duplicate of a very old entry would be applied a second time.
- **A Device that pairs later receives nothing.** There is no history to send:
  the previous clipboard is the platform's state, not this product's, and no
  copy that predates the Session is replayed.
- **Two mechanisms now carry clipboard content.** Mirroring uses
  `ClipboardMessage`; a deliberate send uses a `PayloadKind.clipboard` Transfer.
  They have genuinely different guarantees, but the Transfer path has no caller
  and the boundary between them exists only in this note and in a doc comment.
  A later increment should either give it a caller or remove it.
- **Found while writing this: `SecureLink.isClosed` is false after the peer
  hangs up.** `_runPump` closes both controllers when the frame stream ends but
  never sets `_closed`, which only `close()` does — so the field's own doc
  comment, "True once this link is closed, from either side", is not true of the
  far side. Worse, `_seal` only checks `_closed`, so a send after the peer has
  gone raises a transport error instead of failing cleanly. The hub sidesteps
  the confusion by deriving its own closure from its streams, but the mismatch
  is real, pre-existing, and not fixed here: separating "the streams ended" from
  "close() was called" needs a second flag, because making `_closed` true would
  turn a later `close()` into a no-op and leak the transport.

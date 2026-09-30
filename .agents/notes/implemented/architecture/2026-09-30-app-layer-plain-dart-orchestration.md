# Agent Note: The application is a plain-Dart layer, not a widget tree

Status: implemented

English | [中文](2026-09-30-app-layer-plain-dart-orchestration.zh.md)

## Problem

Every layer that makes the product work existed — [Discovery](../../architecture/2026-09-29-lan-discovery-by-broadcast.md),
[identity](../../architecture/2026-09-30-owner-identity-key-pair-and-device-profile.md),
[Pairing](../../architecture/2026-09-30-pairing-by-typed-code.md),
[Sessions](../../architecture/2026-09-30-link-manager-owns-the-sockets.md),
[Transfers](../../architecture/2026-09-29-transfer-engine-over-a-session.md) and
[clipboard mirroring](../../architecture/2026-09-29-clipboard-mirroring-within-an-owner-group.md)
— and nothing composed them. `lib/main.dart` was a placeholder screen reading
"No devices discovered yet", and the only code that had ever wired two layers
together was the test suite, each test wiring its own subset.

That left two things missing, and the second is the one that mattered:

1. **No runnable flow.** A user could not discover a Device, pair with one,
   send anything, or turn clipboard sync on. No order of the existing pieces
   produced a working product.
2. **Nowhere for the composition decisions to live.** When does a Device start
   accepting Sessions? Which Session does a send go to? Is an incoming offer
   answered automatically? Where does a received file land? Every one of those
   is a decision rather than plumbing, and with no layer to hold them each would
   have been made by whichever screen needed it first, at the one place where it
   is hardest to test.

The development machine settled which layer had to come first. `flutter test`
cannot start here at all: the runner reports `Unable to connect to
flutter_tester process: Invalid WebSocket upgrade request`, because the
zero-trust client on this host strips the hop-by-hop headers a loopback
WebSocket upgrade needs — the finding recorded in
[the dart-test gate note](../testing/2026-09-29-dart-test-as-the-core-gate.md).
A first step shaped like a screen would therefore have been a step nobody could
verify on this machine.

## Decision

**`lib/app` is a new layer between `lib/core` and the widget tree, and it is
plain Dart.** `LocalTransferController` owns the `DiscoveryService`, the
`PairingService`, the `LinkManager`, one `TransferEngine` per Session, and the
`ClipboardMirror`, and answers the questions a user interface asks: what this
Device says about itself ([SelfView](../../../../lib/app/views.dart)), which
Devices are around ([PeerView](../../../../lib/app/views.dart)), what is
transferring ([TransferView](../../../../lib/app/views.dart)), and the methods
that start each flow.

The claim is enforced rather than asserted:
`test/app/plain_dart_test.dart` walks every `.dart` file under `lib/core` and
`lib/app` and fails if any of them imports `package:flutter`. It also fails if
it scanned fewer than twenty files, so a moved or mis-rooted glob cannot make it
pass for the wrong reason.

**The platform seams are injected, never created.** The controller takes a
`ProfileStore`, a `BeaconTransport` and a `SystemClipboard`. The app passes the
real ones; a test passes in-memory ones and runs two complete Devices in one
process over real `ServerSocket`s. There is no branch between the two.

Policies the layer holds, in the order a Device meets them:

- **A Device serves only once it holds a group secret.** With no secret there is
  nobody it could authenticate, so it binds no port and announces none — an
  unpaired Device is visible and not diallable. Pairing is what makes it
  reachable, not starting the app.
- **One `TransferEngine` per Session**, created when the Session is established
  and closed when it is lost, with the clipboard mirror attached to the same
  Session at the same moment.
- **The application never answers an offer.** An incoming Transfer appears on
  `incoming` and in `transfers` with `offer` set; only `acceptInto` or `reject`,
  called by the user, settles it.
- **A received file's name is untrusted input.** `sanitiseIncomingName` strips
  every separator and everything Windows would refuse,
  `incomingPathFor` numbers around a name already in use rather than
  overwriting it, and the only invariant that matters — the path stays inside
  the chosen directory — is asserted directly.
- **A send is addressed or refused, never guessed.** With exactly one Session
  open, sending needs no peer; with several, the caller is told to name one.
- **A profile change rebuilds the session layer.** Pairing and renaming both
  change what this Device announces, and what a peer pins includes the
  descriptor it announced, so a new name means a new `LinkManager` and fresh
  Sessions. The group secret is untouched, so no re-pairing follows a rename.

## Alternatives considered

**Build the screens first, and let each screen compose the layers.** Rejected:
the composition is precisely where the decisions are, so this puts every one of
them where it cannot be tested — and on this machine a widget test cannot run at
all, so the result would have been unverifiable as well as duplicated. Three
screens would each have needed their own answer to "which Session is this
going to".

**Put the controller in `lib/core`.** Rejected: `lib/core`'s rule is that it is
the part of the product that does not depend on Flutter, and that rule stays
true either way — but core's vocabulary is bytes, Sessions and Owners, and
"which peer did the user pick" is not a protocol fact. Keeping `lib/app`
separate keeps that seam honest instead of diluting it.

**Have the controller create the `LinkManager` eagerly, with a random
placeholder secret while unpaired.** Rejected: it would bind and announce a
listen port, so an unpaired Device would appear diallable and every dial to it
would fail the handshake. A peer list that offers connections which cannot work
is worse than one that shows the Device is not accepting any.

**Answer offers from a Favorite without asking.** Rejected for now, though the
profile already has the concept and `DeviceProfile.canMirrorTo` says a Favorite
is meant to skip the per-Transfer confirmation. Accepting a file needs somewhere
to put it, and there is no download directory in this layer — inventing one
silently, from a peer-supplied name, is the wrong way to earn that permission.
The Favorite grant is in the profile and unused, which is a deliberate debt.

**Let the widget tree own the controller's streams directly** — one stream per
field, subscribed by whichever widget wants it. Rejected: a coarse "something
moved" tick that rebuilds once per change is less work at the call site and
cannot race, and the views are cheap value objects that a widget can diff.

## Consequences

- The whole application can be driven, and accepted, headlessly:
  `test/app/app_controller_test.dart` runs 15 cases over real loopback TCP —
  pairing two Devices with a typed code, both users confirming, discovery
  placing them, a Session, a text Transfer settling on both sides, a 200 KiB
  file arriving byte for byte across several chunks, a refused offer reported to
  its sender, and the clipboard travelling in `mirror`, waiting in `stage`, and
  doing nothing in `off`. `test/app` totals 28 cases; the suite went from 313 to
  341.
- Reading `Transfer.updates` per Transfer is what makes progress visible; each
  subscription is cancelled when its Transfer settles, so a long-lived app does
  not accumulate one per transfer.
- Two run-time failures this layer met are worth naming, because neither is a
  compile error. A stream's `onError` has to accept an `Object`, so passing a
  `void Function(String)` throws only when an error actually arrives. And
  `Fingerprint`/`Descriptor` comparisons are by value only where those types say
  so, which is why the layer compares keys it builds itself.
- Renaming costs every open Session. That is the honest consequence of what a
  peer pins, not an oversight, and it is the reason the alias is not editable
  from inside a Session in the UI.
- No widgets ship in this change: `lib/main.dart` still starts into the
  placeholder screen. The layer a screen needs is now there, and the screen is
  the next change.

# Agent Note: Connecting is done in the conversation list

Status: implemented

English | [中文](2026-10-08-connect-from-the-conversation-list.zh.md)

## Problem

Three things were wrong with the way a conversation begins, and they were the
same thing seen from three angles.

**Connect lived on the wrong surface.** The Devices surface carried a Connect
button on every peer card, and pressing it dialled and then jumped the user to
the Conversations surface with the thread open. So the gesture started on one
surface and finished on another, and the surface it started on is the one that
is *about* hardware — addresses, ports, last-seen times, the local Device's own
Fingerprint. A user who wanted to talk to somebody had to go to an inventory
first. The Devices surface also has one peer card per Device and each of them
carried one button, which meant "where do I connect from" had as many answers as
there were Devices.

**A found Device was invisible until it was connected.** The conversation list
kept a peer when it was connected *or* had history:

```dart
if (!peer.isConnected && history.isEmpty) continue;
```

That is the right rule for "what have I got to read", and the wrong rule for
"who can I talk to". A Device that Discovery had placed — address, port, group,
all known — did not appear in the conversation list at all, because nobody had
dialled it yet. The list that exists to hold conversations was missing exactly
the entry a new user was looking for.

**The conversation list had no icon of its own, and led the tab bar nowhere.**
The row was drawn with the peer's platform icon, which in a list of
conversations reads as "which app is this" — a question nobody is asking, and
one the Devices surface already answers. And Conversations sat second behind
Devices, so the surface the user lives in was behind the surface they visit once.

Finally, there was a case nobody had handled: **both sides tapping Connect at
the same moment**. `PairingService.receive` binds `anyIPv4`, so two simultaneous
dials do meet, and the handshake after the opening exchange is symmetric, so
both halves complete. What did *not* happen was a Session. Each side expected to
be the dialler and expected to refuse the other's attempt as a second one — the
answering side said so in a comment:

```dart
// No Session is opened from this side: the Device that dialled opens it,
// and a Session dialled from both ends at once would have each end refuse
// the other's as a second one.
```

Both users tapped Connect, the Pairing succeeded, and neither could type. The
rule that avoided the double dial was correct about the hazard and wrong about
what to do with it.

## Decision

### The conversation list is where a Device is connected from

`ConversationsPage` lists **every peer Discovery knows about**, connected or
not. A Device that has been found is a conversation the user has not started
yet, so the row that lists it carries the button that starts it:

- **Connect** when `peer.isDiallable && peer.isInGroup` — there is an address to
  dial and a group to dial into.
- **Pair** when `!peer.isInGroup && peer.address != null` — pairing is how a
  Device gets into the group, so it is the action that comes first.
- **Nothing** when there is neither: a peer with no port is a peer that is not
  accepting Sessions at all, and a button that can only fail is worse than no
  button.

Those two predicates are copied verbatim from `_PeerCard`, deliberately: the
guard is a fact about the peer and not about a surface, and the two surfaces
reading it the same way is what keeps them from disagreeing.

`_PeerCard` loses the button and the dial. `_ConversationTile` gains both, and
`_connect` there is one line — `controller.connect(peer.fingerprint)` — because
the conversation is already selected: the row only ever appears in the list the
user is looking at. The dial goes through `guarded`, as before, so a failure is
reported and nothing moves.

### Conversations leads, Devices follows

`_conversationsSurface` is `0`, `pages` and `destinations` are reordered in the
same edit, and the five constants in `test_flutter/support/ui_harness.dart`
swap. The two lists in `home_shell.dart` are index-aligned by construction, so
they move together or not at all.

### A conversation row is drawn as a conversation

`iconForConversation()` in `lib/ui/labels.dart` returns `Icons.forum_outlined` —
the same icon the destination carries. The peer's platform is still a fact, and
is still on the peer's card and in the app bar.

### Simultaneous Connect ends in a Session, by a rule both sides can compute

`_dialsFirst(self, peer)` compares the two Fingerprints:

```dart
bool _dialsFirst(Fingerprint self, Fingerprint peer) =>
    self.hex.compareTo(peer.hex) < 0;
```

The rule is consulted by the **answering** side only — `_PairingRequestDialog._accept`
— and it is there that the tie-break decides. The side whose user pressed Pair
(`_PairWithPeerDialog._join`) opens the Session unconditionally: it dialled the
Pairing link in the first place, so it is the only side that knows a Session is
wanted, and `connectAfterPairing`'s 24-attempt, 250-millisecond retry loop is
already behind it. `showPairingRequestDialog` therefore takes the controller as
well as the request — the window needs this Device's own Fingerprint to compute
the tie-break, and needs somewhere to dial from if it wins.

**Applying the rule to both sides instead is wrong, and was wrong here first.**
It looks symmetrical and it is not: in an ordinary Pairing the two sides are in
different code paths, so if the presser's Fingerprint happens to sort higher,
*two* "no"s are computed — the presser defers to the answerer and the answerer
defers to the presser — and nobody dials at all. Nothing errors; the Pairing
completes and the Session simply never arrives, which is a twenty-second timeout
and a row still offering Connect. The asymmetry is not a wart: it is the fact
that makes the ordinary flow have exactly one dialler, and the tie-break's only
job is to break the race where both sides genuinely are pressers.

## Alternatives considered

**Keep Connect on the Devices card and add a second button to the conversation
list.** Rejected: two places that both mean "connect", with two predicates that
would drift, and a user who reads the Devices page as the answer to a question
it no longer answers.

**Make the Devices row dial on tap instead of carrying a button.** Rejected: it
is the same surface doing the same job, and it makes the row ambiguous — the row
of a connected Device already means "open the conversation", and one row cannot
mean dial when it is down and open when it is up without a user learning a state
machine.

**Only list found Devices that are in the group, so the row always has a
button.** Rejected: a peer outside the group is exactly the one a new user wants
to see, since pairing it is the next thing they must do. Hiding it would send
them to the Devices page to find out it exists.

**List a found Device but leave out the Pair action, on the grounds that pairing
is a Devices-page concern.** Rejected: pairing presents a window on the *other*
device, so it is an interaction between two people and belongs where the two
people are talking. And the Devices surface keeps the pairing card — the switch
that says whether this Device answers at all — so the standing half stays there.

**Break the simultaneous-Connect tie by who dialled the Pairing.** Rejected:
that is the asymmetry the old code relied on, and it is the one fact the two
sides do not agree about. It describes the race as "one side dialled" when the
defining feature of the race is that both did.

**Let the two simultaneous dials collide and have one side retry after the
refusal.** Rejected: the refusal arrives as `AppRefusal.sessionAlreadyOpen` on
the side that lost, but "lost" is not derivable there — both sides would retry,
both would be refused again, and the retry would need its own tie-break. Paying
for one comparison with a retry loop that needs the same comparison is worse
than paying for the comparison.

**Open the Session from both sides and let `connect`'s existing
`sessionAlreadyOpen` refusal sort it out.** Rejected: the refusal is what
prevents the Session, not what resolves the race. `connect` throws on the second
dial rather than adopting the first, so both ends would end up with the other's
refusal and neither with a Session.

**Put the tie-break in the pairing layer, where the two roles are already
distinguished.** Rejected: by the point the roles exist, the race has already
been lost — `PairingService.receive` has already accepted the second inbound
request as its one request, and both sides are `initiator` in their own view.
The decision has to be made from a fact both sides hold at the start, which is
why it is the Fingerprints.

## Consequences

- A Device this app has found appears in the conversation list on its own,
  before anybody has dialled it, with Connect (or Pair) on its row. That is the
  "一开始扫描到则在对话列表里面显示" behaviour, and it is one code change: the
  `continue` in `_conversationsOf` is gone.
- `conversationListEmpty` and `conversationPickOne` no longer tell the user to
  go to the Devices surface, because there is nothing there that is not here.
  Both languages were updated in the same change.
- The Devices surface is now read-only with respect to Sessions: it describes
  peers and offers `openConversation` on a connected one. `_PeerCard` no longer
  takes a `LocalTransferController`, which is the type signature saying it has
  no actions left.
- `test_flutter/support/ui_harness.dart` gained `conversationListed` and
  `conversationConnectable`, and `openConversation` now taps the conversation
  list rather than the Devices card. `conversationOffered` stays as the
  Devices-surface signal, and the e2e file-move flow goes through the list.
- Simultaneous Connect now ends in a Session. The behaviour is not covered by a
  test: driving two windows to tap two buttons in the same frame is not
  something `pumpUntil` can express, and the parts that are testable — that
  `_dialsFirst` is antisymmetric, that each side dials exactly once — are
  already implied by the single-dial paths that are covered. This is a named
  coverage gap rather than an oversight.
- `_PairingRequestDialog` now dials, so `showPairingRequestDialog` takes the
  controller. A caller with a request but no controller can no longer show the
  window, which is correct: that combination could not complete a Pairing the
  user had just approved.
- The first version of this change consulted the tie-break on both sides and
  broke pairing entirely, in a way no static check could see: `flutter analyze`
  was clean, `dart test` passed 390, and seven widget tests failed with
  twenty-second timeouts. The failure was order-dependent — which tests failed
  changed between runs — because it depended on which Fingerprint happened to
  sort first. What caught it was running `flutter test test_flutter` against a
  stashed baseline: the same suite passed 40/40 on the clean tree, which
  turned "some tests are flaky" into "this change is wrong".
- Reordering the destinations moved the surface a window *opens* on, and the
  `IndexedStack` keeps the others offstage, which `find` skips by default. Every
  assertion against the old first surface therefore started failing with "found
  0 widgets" — not because the widget was gone but because it was no longer
  built on top. Four tests in the Devices group and one harness helper
  (`pairThroughWindows`, which tapped Pair on the Devices card) had to be taught
  to open the tab they meant. The general rule this establishes: **a test that
  reads a surface has to open it**, which every group except the Devices one
  already did.
- A dial that a *tap* starts cannot be asserted in `testWidgets`. `connectDevices`
  works because it drives `controller.connect` inside `tester.runAsync`, which
  hands the socket work the real event loop. A tap runs on the widget test's own
  zone, so the futures it starts never resume inside the test body, and the
  Session simply never appears — with no error anywhere, which is what made it
  look like a product bug. The Connect-on-a-row test therefore asserts the
  wiring (the row offers one action, aimed at this peer, whose view is diallable)
  and leaves the socket to `connectDevices` and the two-window e2e test. This is
  a named coverage gap, not an oversight.

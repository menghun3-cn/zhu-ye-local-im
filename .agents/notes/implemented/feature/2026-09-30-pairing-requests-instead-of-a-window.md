# Agent Note: Answering Pairing requests permanently, instead of inside a window

Status: implemented

English | [中文](2026-09-30-pairing-requests-instead-of-a-window.zh.md)

## Problem

[Pairing by clicking](2026-09-30-click-to-pair-no-more-typing.md) shipped with a
step that the user of the *other* Device could neither see nor perform: the
answering side had to tap **Receive a connection** and leave that window open
while the caller tapped Pair. The listener's lifetime was the window's
lifetime, and three things were wrong with that.

It asked the wrong person to prepare. The Device that had to be got ready was
the one being paired *with* — the desktop on the desk, the machine that is
already set up and whose user is probably not looking at it. Nothing on the
caller's screen said a window had to be open over there, so a caller that dialled
a Device nobody had prepared got `Connection timed out`, which reads as a broken
network rather than as an unopened window.

It could not add a third Device. One window meant one Pairing. Adding a third
Device to a group required the *already paired* Device's user to go back and
open the window again — which contradicts what a group is: a set of Devices you
can send to, without doing anything to any of them first.

And it reported itself badly. An unpaired Device that nobody had opened a window
on showed "Listening: not accepting connections" — reported as a fact about the
Device, which a user reasonably reads as "pairing is broken here" even though it
is only "we have not started yet".

The reason the window existed was real, and worth stating before replacing it.
An open Pairing runs its handshake on `PairingSecret.openPairing()`, which is a
**published constant**. Any Device on the link can therefore complete that
handshake. The window bounded that exposure in time: while it was open, any
Device could dial; when it closed, nobody could. So the window was not the check
that admitted the caller — the user's answer to the question is — it was the
thing that limited *when* a stranger could try.

## Decision

Answering Pairing requests is a permanent listener, and what bounds it is a
per-caller question rather than a clock.

* `PairingService.receive({port})` binds the well-known pairing port and keeps
  answering until `stopReceiving()`. `invite()` — the typed-code path — refuses
  to run while the listener is up: both want the same port, and a caller that
  arrives on a request listener has shown no code to check it against.
* A caller is answered in two stages, and the order is the whole decision. The
  handshake completes first, because the name to put on the question travels in
  it; then a `PairingRequest` is emitted. **Everything that matters waits for
  `PairingRequest.admit()`**: the admission exchange, the six digits, and the
  group secret the answering Device would otherwise hand over. A caller that has
  not been allowed through has a link and nothing else. That is what replaces
  the window — the exposure is now bounded per caller by a human answer, instead
  of by a clock.
* The wait is bounded anyway. `requestTimeout` (two minutes) refuses a request
  nobody answers, because the caller is *waiting*: a Device nobody is sitting at
  should stop collecting diallers rather than hold them on a spinner until the
  process dies.
* One at a time. A second caller arriving while the first is on screen is
  refused, not queued: two Pairings in flight would both commit to the same
  profile, and the rosters they wrote would each be missing the other's Device.
  A queue of prompts nobody asked for is worse than an honest refusal.
* The listener outlives the Pairing. Answering one request leaves it up, so the
  next Device is answered on the same listener — which is what "add another
  Device" has to mean.
* Half-open connections are bounded (`_Receiving.maxHandshakes`, 8). A listener
  that is always open is reachable by anything on the link, and every half-open
  dialler costs a task that waits out `handshakeTimeout`, which a hostile Device
  can open faster than it expires. The ninth simultaneous caller is dropped,
  which no honest pair of users is.
* A request with nobody to ask is refused on the spot (`!requests.hasListener`).
  There is no screen for it to appear on, and the alternative is a peer waiting
  for a question that was never asked.
* `DeviceProfile.acceptsPairingRequests` (default true) is the user's intent and
  is persisted, so a Device that was told not to answer does not quietly start
  answering after a restart. `AppController._syncPairingListener` makes the
  listener match it, and failing to bind is *reported* rather than raised: the
  usual cause is a second copy of the app on one host, and that user can still
  dial out. The Devices page shows it as a switch whose **subtitle reports the
  listener rather than the preference** — the two can disagree, and a switch
  promising something that is not happening would be the lie.
* The interface answers and the app layer never does. `AppController` forwards
  `pairingRequests`, `HomeShell` subscribes to it (the narrowest widget that is
  always alive, so a request is not missed because the user was on another
  surface), and `showPairingRequestDialog` asks the two questions in order:
  continue or refuse, then the six digits. A controller that answered on the
  user's behalf would make a permanent listener unsafe, so the type is named for
  what it is — a question with a caller attached, not an event.
* The dial that never lands is now reported as what it is. `PairingException`
  carries `unreachable`, and the UI answers it with a sentence that names what
  to check — the other program running, both machines on one network, incoming
  TCP 47656 allowed through its firewall — instead of leaving the user with the
  operating system's `Connection timed out`. This was the other half of the same
  report, and it is deliberately a flag rather than a phrase to match: the
  message beside it stays the operating system's own words, verbatim.
* The app layer's code path is gone. `invite()`, `inviteOpen()` and `join()` are
  replaced by `pairWith({host, port})` for the click-to-pair dial and
  `setAcceptsPairingRequests(bool)` for the switch. The core keeps `invite()`
  and `join()`; nothing in `lib/ui` can reach them, which is correct while there
  is no surface that shows a code.

## Alternatives considered

**Keep the window, and add a "always answer requests" switch that opens it
permanently.** Rejected: it keeps the step that made the flow wrong — the user
of the Device being paired with still has to have gone and turned something on,
and a Device that has never been visited still cannot be paired with. It also
turns one clearly-labelled transient state into a mode, which is a worse thing
to explain.

**Let the listener admit a caller automatically once the digits are shown.** No:
with a published handshake secret, the digits plus the two confirmations are the
entire admission check. Admitting before the comparison is admitting whoever
asked first.

**Emit the request but run the admission exchange first, so the prompt can show
the digits immediately.** Rejected, and it is the trap this change is built
around. `_negotiate` is where the answering Device decides what group secret to
offer and sends it inside the sealed link. Running it before the user answers
would put this Device's group secret in the hands of any caller that completed a
handshake against a public constant — the user would be asked to approve
something they had already given away.

**Queue a second caller behind the first instead of refusing it.** Rejected: the
queue would be of prompts nobody asked for, arriving seconds after the tap that
caused them, and the second caller's user has no way to see their place in it.
Refusing is answerable; queueing is not.

**Leave a request open until somebody answers it.** Rejected: the caller is
blocked on it. A Device with nobody at it would accumulate diallers for the life
of the process, each holding a link, and each caller watching a spinner with no
way to tell "being considered" from "gone".

**Route the request through the app layer's own stream and let it decide whether
to auto-answer.** Rejected: the app layer answering a Pairing is exactly the
thing this design forbids, and making it possible as a code path is how it comes
back.

## Consequences

- A Device answers requests from the moment it starts, so a caller's tap always
  finds a listener, and adding a second, third or tenth Device to a group asks
  nothing new of any Device already in it.
- A Device on the link can start a Pairing against a Device that is answering,
  whenever it likes. What stops it from being admitted is a person: the question
  says who is asking, says plainly that the name is the caller's own claim, and
  the comparison behind it is what actually checks. A Device that wants to be
  unreachable turns the switch off, and the preference survives a restart.
- Pairing is something you do once. Nothing about a Device being *reachable*
  depends on a screen being open any more: the pairing listener is only for
  pairing, and sending files runs on the Session layer, which comes up when the
  Pairing commits and stays up.
- The window is gone from the interface: `showReceiveDialog` and its state,
  `receiveAConnection`, `receiveWaiting`, and the two controller entry points
  that drove it. What replaced them is one switch, one dialog, and five strings
  (`acceptPairingRequests`, `pairingListening`, `pairingNotListening`,
  `factPairingRequests`, and `failureCannotReach`).
- `test/pairing/pairing_service_test.dart` pins the invariants the design rests
  on, in a group called *What a Pairing request must never do*: a caller is
  given nothing until its request is allowed (its `joinOpen` has not resolved,
  and neither side holds a secret), a second caller while the first is on screen
  is turned away without disturbing the first, an unanswered request is refused
  once it expires and cannot be admitted afterwards, the listener and the code
  path are mutually exclusive, turning the listener off takes the port away, and
  answering one request leaves the listener up for the next Device.
- `test/app/app_controller_test.dart` covers the switch at the app layer, and
  `test_flutter` covers it on screen — including that allowing the request is the
  whole of the Pairing and that refusing pairs nobody, which is the user-visible
  form of the invariants above.
- The test harness changed with the flow. `pairDevices` now starts the dial,
  answers the request through the controller and confirms, standing in for the
  host's user; because it answers underneath the screen rather than through it,
  it must run **before** the host's window is pumped, and it says so with a
  guard rather than leaving the next reader to work it out from a timeout. Tests
  that need a paired Device before they need a screen pair first and pump after.
- A window's Pair button can only dial the well-known pairing port, because
  there is no port to put on screen. A test that drives the whole flow through
  two windows therefore has to bind the default port, and a test that only needs
  the request machinery dials the port the Device actually bound — which keeps
  the two test files, which `flutter test` runs side by side, off each other's
  port.
- `requestTimeout` is two minutes by default and is injected, so the expiry
  behaviour is tested in milliseconds rather than by waiting.

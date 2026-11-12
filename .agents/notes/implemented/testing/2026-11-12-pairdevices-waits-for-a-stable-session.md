# Agent Note: pairDevices waits for a stable Session, not a lucky instant

Status: implemented

## Problem

`pairDevices` in `test_flutter/support/ui_harness.dart` ended with a fixed
300 ms delay and a single assertion that both Devices still held a Session.
That was a bet on timing, and the three-Device test in `pages_test.dart` —
the only one that puts a third Device on the same beacon hub — lost it
roughly two runs in three.

The mechanism is not a bug in the Session layer; it is a documented product
behaviour the test did not wait out. When a Device joins the Owner Group the
group secret rotates, `_syncLayers` sees `secretChanged`, tears the whole
session layer down and rebuilds it, and every member redials. Each rebuilt
`LinkManager` also binds a *new* ephemeral Session port, so for a short
window after the rotation the port Discovery advertises and the port a still
-open handshake remembers legitimately disagree. The test asserted both
facts — "the Session stayed open" and "the header names the advertised
port" — at a single instant inside that window.

## Decision

**The harness waits for continuity, not for an instant.** `pairDevices`
now requires both Devices' Sessions to have been continuously non-empty for
300 ms before returning, resetting its window whenever either side is
observed empty. For the two-Device tests that make up almost the whole
suite nothing rotates after pairing, so the cost is the same half-second
the fixed delay already paid; for the three-Device test the wait simply
lasts until the last rotation's redials have landed.

**The port assertion waits for convergence the same way.** The remembered-
conversation test now polls until the conversation header names the port
Discovery currently advertises for Carol, reading the advertised port on
every poll rather than snapshotting it once. The negative half — Bob's port
must *not* be on the header — is unchanged, because the ports are distinct
ephemerals and no timing makes them equal.

## Alternatives considered

**Give the test Devices fixed Session ports.** Rejected: `sessionListenPort`
is per-Device and three Devices on one host would need three coordinated
ports; ephemeral ports are what production uses, and a test that pins them
stops exercising the fallback path `_serveSessionLayer` exists for.

**Wait for "no session-layer rebuild in the last N ms".** Rejected: the
rebuild is not observable from the widget tree, and reaching into the
controller's private layer state from a test would couple the suite to an
implementation detail the harness deliberately does not know.

**Retry the whole test on failure.** Rejected: a retry hides the same race
in every other test that pairs Devices, and teaches the suite that flakiness
is acceptable. The window check removes the race at the one place it lived.

## Consequences

**Bought.** The three-Device test went from roughly one pass in three to
six consecutive passes, and `pairDevices` is now honest about what it
asserts: not "a Session existed once" but "a Session stayed up". Any future
test that adds a Device mid-scenario inherits the same tolerance.

**Cost.** Each `pairDevices` call can take up to 20 s before failing instead
of failing fast at 300 ms — but only when Sessions genuinely cannot stay
up, which is exactly when a longer look is warranted. The ~35 existing call
sites pay at most the same 300 ms they already did.

**Testing.** Verified by repetition rather than a new test: the previously
flaky case was run six times consecutively, and the full `test_flutter`
suite was run once end to end.

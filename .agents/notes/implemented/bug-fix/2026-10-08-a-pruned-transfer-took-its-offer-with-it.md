# Agent Note: A pruned Transfer could take an undelivered offer with it

Status: implemented

English | [中文](2026-10-08-a-pruned-transfer-took-its-offer-with-it.zh.md)

## Problem

`LocalTransferController._pruneTransfers` trims the tracked-Transfer list to a
hundred entries once it has grown past them. It dropped settled Transfers first,
then the oldest regardless of state:

```dart
_transfers.removeWhere((tracked) => tracked.transfer.isSettled);
while (_transfers.length > keep) {
  _transfers.removeAt(0);
}
```

Two things besides the list hold on to a Transfer. One is a
`StreamSubscription` on its progress, cancelled on settlement. The other is
`_incoming` — a **broadcast** `StreamController`, which a pair of widget tests
exposed:

```
Bad state: No element
#0      List.single
#1      main.<anonymous closure>  (test_flutter/ui/pages_test.dart:414:68)
```

An incoming offer had been added to `_incoming` and the test's listener had not
run yet. A broadcast controller does not keep an undelivered event alive — the
event is held by whatever the `add` captured — so when the only strong reference
to the Transfer was the `_Tracked` record that `_pruneTransfers` removed, the
offer became collectable and the question a peer asked was dropped rather than
delivered.

The window is narrow, which is exactly why it survived: a hundred Transfers have
to accumulate, a listener has to be mid-flight, and the ordering has to line up.
A test that sends one file in a fresh controller never sees it. A test suite
that runs a hundred Transfers across twenty cases does.

## Decision

`_pruneTransfers` only ever drops **settled** Transfers. The `while` loop that
drops the oldest regardless stays, because the alternative is a list that grows
for the life of the process, and a hundred *live* Transfers is far past anything
a person is watching — but a Transfer that has not settled is a question still
in flight, and is never a candidate while anything settled is available to drop.

`_pruneTransfers`'s doc comment now states both the rule and the reason, so the
next person to reach for the `while` loop has to read why it is there.

## Alternatives considered

**Keep a strong reference to every undelivered offer until its listener runs.**
Rejected: it duplicates on the controller's side the exact accounting a
`StreamController` is for, and every event added to `_incoming` would have to be
paired with a removal on every path out — a listener that throws, a listener
that cancels, a listener that is never attached at all. The asymmetry rule is
smaller and has no failure mode of its own.

**Make `_incoming` a non-broadcast controller.** Rejected: it would drop the
second listener that a rebuilt widget tree attaches, and a page that is disposed
and rebuilt while an offer is on screen would lose it — trading a rare drop for
a common one.

**Emit the offer on `_incoming` before tracking it, so the reference is
irrelevant.** Rejected as a fix and kept as an observation: it narrows the
window without closing it, and it makes the ordering of `_track` and `_incoming`
load-bearing for a reason nothing else shares. The list's pruning rule is the
thing that was wrong.

**Add a listener to `_incoming` in the controller purely to hold events.**
Rejected: a no-op subscriber whose only purpose is to defeat the garbage
collector is a comment that cannot be read as one, and the next person to delete
it reintroduces the bug with no test failing.

## Consequences

- An incoming offer can no longer be collected before it is delivered, whatever
  the tracked list is doing.
- The pruning bound holds for settled history, which is what the bound was for.
  A controller with more than a hundred *live* Transfers still drops the oldest,
  as before.
- `_incoming` gained documentation stating that a broadcast controller does not
  hold its own undelivered events, so a caller that adds an event and drops its
  last reference to the payload has created a race — the rule this fix obeys
  rather than a note about the fix.

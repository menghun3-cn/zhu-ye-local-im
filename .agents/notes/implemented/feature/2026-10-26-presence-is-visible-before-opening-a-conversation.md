# Agent Note: Presence is visible before opening a conversation

Status: implemented

English | [中文](2026-10-26-presence-is-visible-before-opening-a-conversation.zh.md)

## Problem

The conversation list did not say whether a peer was online. A connected peer
showed no state at all, and an offline peer showed a Connect button or a
reconnect sentence without naming the condition. The only explicit "offline"
word lived in the opened conversation's header, while the Devices surface
buried "Session open" inside a long facts line. A user therefore had to open
each conversation, or read the Devices cards closely, to answer a question
that belongs to the list itself: can I send to this Device right now?

## Decision

This note now owns the row-label part of the decision. The avatar dot and the
application-wide summary were removed by
[Presence indicators leave the chrome and the avatar](../simplification/2026-10-27-presence-indicators-leave-the-chrome-and-avatar.md);
that note owns the removal and its rationale.

`PeerView.presence` reads the live Session table and answers
`PeerPresence.online`, `PeerPresence.connecting`, or `PeerPresence.offline`.
A live Session wins over a dial that is still in progress; everything else
without a Session is offline. Discovery alone does not make a peer online.

Every conversation row carries a short label beside its title. Online is
"在线"; connecting is "连接中"; offline is "离线", with the last-seen time
appended when one is known.

The right-hand clock column now means only when the last message moved. An
offline row already carries last-seen beside its name, so a row with no
history leaves the clock blank rather than printing the same fact twice. A
connected row with no history still uses `peer.lastSeen`, because nothing else
on that row carries it. No periodic timer was added; relative times refresh
with the same controller notifications that already refresh the Devices
surface.

## Alternatives considered

The avatar-dot and chrome-summary alternatives below record the original
decision. The current choice is in the
[removal note](../simplification/2026-10-27-presence-indicators-leave-the-chrome-and-avatar.md).

**Only a coloured dot on the avatar.** Rejected: a dot is compact, but it
requires the reader to remember what green and gray mean. The label costs a
few characters and makes the state explicit without opening anything.

**Restore a global AppBar for the summary.** Rejected: the shell deliberately
has no AppBar. A permanent title strip would bring back the chrome that was
removed, and it would spend every page's height on a fact that belongs to the
navigation area. The rail on a wide window and the strip above the bottom bar
on a narrow one keep the summary in chrome that already exists.

**Put the counts only on the Devices navigation item.** Rejected: a badge can
say how many are online, but it cannot say how many are offline, and it would
compete with the transfer badge that already means "something needs an
answer". The summary needs its own words.

**Count a discovered peer as online.** Rejected: discovery is presence, not
reachability. A Device that has just been heard but has no Session cannot
accept a message, so calling it online would make the status less useful than
the Connect button it replaced.

**Refresh last-seen with a one-minute timer.** Rejected: it would add a timer
to every window for a label that already refreshes whenever discovery or a
Session changes. The existing relative-time helper and controller ticks are
the same contract the Devices surface already uses.

## Consequences

- A user can tell whether each conversation can send without opening it.
- The conversation row's right column no longer prints a duplicate last-seen
  time for an offline peer with no history. The row-time note was updated to
  record that narrower rule.
- The status is a LAN Session state. It says nothing about internet access or
  whether the other machine is powered on.

## Testing

`test/app/views_test.dart` pins the presence precedence.
`test_flutter/ui/presence_test.dart` pins the row label.
`test_flutter/ui/pages_test.dart` asserts that online and offline rows carry
their labels before a conversation is opened.

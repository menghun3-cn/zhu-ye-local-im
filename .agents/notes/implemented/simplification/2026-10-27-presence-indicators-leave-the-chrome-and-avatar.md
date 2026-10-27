# Agent Note: Presence indicators leave the chrome and the avatar

Status: implemented

English | [中文](2026-10-27-presence-indicators-leave-the-chrome-and-avatar.zh.md)

## Problem

The [earlier presence feature](../feature/2026-10-26-presence-is-visible-before-opening-a-conversation.md)
put presence in three places: a label on every conversation row, a dot on
every avatar, and an online/offline count in the application chrome. In use,
the chrome count repeated what the rows already said and spent navigation
space on a fact that changed with Discovery. The avatar dot repeated the row
label in a second, less legible form and made each avatar read as a status
control rather than as a Device identity.

## Decision

`PeerView.presence` and `labelForPeerPresence` remain the source of presence
in the conversation list. A row still prints 在线, 连接中, or 离线 beside its
title, including last-seen time when an offline peer has one. The avatar is
now a plain `Avatar`; it carries no lower-right mark.

The application chrome no longer draws `ConnectionSummary` under the rail's
brand mark or above the narrow window's bottom navigation bar.
`AppNavRail` has no status slot. The support code that existed only for those
indicators is gone: `PresenceAvatar`, `PresenceDot`, `PresenceCounts`, their
count and tooltip strings, and their widget tests. The Devices surface remains
the place for full addresses, last-seen facts, and per-Device connection
detail.

## Alternatives considered

**Keep the summary only on narrow windows.** Rejected: the strip still
duplicated every visible row label, and keeping one layout different would
leave two chrome contracts to maintain for a count that was not being used.

**Keep the dot but make it quieter.** Rejected: the row already states the
condition in words. A smaller or lower-contrast dot would still repeat the
same fact and would still be harder to read than the label.

**Remove the row label with the dot.** Rejected: the label is the accessible,
non-colour-dependent answer to whether a message can be sent now. The request
was to remove the redundant indicators, not the useful text.

**Leave the now-unused widgets and count model in place.** Rejected: unused
chrome APIs invite another caller to bring back the same duplication and make
tests imply behavior that no longer ships.

## Consequences

- The rail gives its vertical space back to the destinations, and the narrow
  window's bottom area contains only the navigation bar.
- Users lose the global at-a-glance count and the summary's shortcut to the
  Devices surface. The conversation rows still answer presence per peer, and
  the Devices destination remains one press away.
- The avatar now identifies the Device without also encoding Session state.
  Presence remains explicit in text at the one place a user acts on it.
- No wire format, durable data, or Session behavior changed.

## Testing

`test_flutter/ui/presence_test.dart` pins the remaining row labels.
`test_flutter/ui/pages_test.dart` asserts that a connected row says 在线 and
that its avatar contains no positioned status overlay.
`test_flutter/ui/shell_test.dart` asserts that neither the wide rail nor the
narrow bottom navigation carries online, offline, or empty summary text.


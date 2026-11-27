# Agent Note: The conversation header carries presence once

Status: implemented

English | [中文](2026-11-26-conversation-header-presence.zh.md)

## Problem

The strip above an open conversation drew the peer's address as its title and
then repeated it in the supporting line inside "10.0.0.7，不接受连接 · 离线".
Three faults in one line: the address printed twice; "不接受连接" claimed a
configuration fact — that the peer refuses Sessions — which a quiet LAN
cannot support, since an offline, unpaired, or restarting peer announces no
Session port for the same reason; and "离线" restated the disconnect mark
beside the title. The second line's whole height was spent saying what the
title line and the list row already said.

## Decision

Presence moved onto the title line. `_PaneHeader` and the pushed
`ConversationPage` AppBar draw `labelForPresenceState` — 在线 / 连接中 /
离线 — beside the title, replacing the `link_off` icon whose only job was to
say "not online" without saying which not-online state. The word reads
without colour vision exactly as the icon did, and it names the state the
icon could not.

`describePeerConnection` now returns `String?` and carries only what neither
the title nor the presence word says: the listening port, or 从未出现 for a
peer Discovery has not placed — unless a Session is open anyway, because the
connection is the stronger fact. A placed peer with no Session port gets no
supporting line at all, so the header collapses to a single line.

The forward-target picker keeps the state in its subtitle, because its rows
have no title line for presence to move to; `labelForPresenceState` is the
shared one-word reading there. The now-unread `conversationDisconnected`
string is removed from the ARB files.

## Testing

`test_flutter/ui/labels_test.dart` pins the nullable contract: a placed peer
with no Session port says nothing, a connected peer says nothing its
presence word does not already say, and a never-placed peer still says
从未出现 unless a Session is open anyway.

## Alternatives considered

**Keep "不接受连接" and drop only the repeated address.** Rejected: the
phrase is the misleading half. A null `sessionPort` means "no port was
announced", which every not-currently-dialable peer produces; the only fact
that disproves it is a live Session, and that case never showed the phrase.

**Keep the `link_off` icon beside the presence word.** Rejected: the word
already carries the state as text, which reads without colour vision exactly
as the icon did, and the pair would say 离线 twice.

**Show the list row's "离线 · 3 分钟前" in the header.** Rejected: the title
line has room for the state, not for a timestamp; last-seen stays on the row,
where `labelForPeerPresence` already puts it.

## Consequences

- The conversation header is one line shorter whenever the peer has no
  Session port to report, and the state is readable at a glance in both
  themes.
- "不接受连接" still appears in the conversation list's preview fallback via
  `describePeerAddress`, where it is the only place the address shows; the
  header no longer makes the claim.
- `describePeerConnection`'s reachability tail is gone for every caller; the
  forward picker restores it explicitly through `labelForPresenceState`.

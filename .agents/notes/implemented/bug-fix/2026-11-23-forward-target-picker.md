# Agent Note: The forward target picker reads like the conversation list

Status: implemented

English | [中文](2026-11-23-forward-target-picker.zh.md)

## Problem

The dialog a forward raises — "转发给" — listed its targets as Material
`ListTile`s: a platform icon, the peer's `displayName`, and a connection
subtitle, inside a `ListView` with `shrinkWrap` and no height bound. Two
things followed from that shape:

* **The rows did not match the list they pick from.** The conversation list
  draws an `Avatar`, the peer's address-or-name title, and a supporting
  line; the picker drew a generic icon and a bare name. A Device named by
  its alias showed only the alias, so two machines both called "DESKTOP"
  were indistinguishable — the address that tells them apart never
  appeared.
* **A long list had no way to be searched and could outgrow the dialog.**
  `shrinkWrap` asks for every row's height at once; with enough peers the
  dialog sized itself to the whole list rather than scrolling inside a
  bound.

## Decision

The picker is now a small stateful dialog that mirrors the conversation
list's row, because a forward target *is* a conversation:

* Each row is an `Avatar` (name, Fingerprint seed, `avatarLabel`) beside
  the peer's `displayName` over a supporting line. The supporting line is
  `describePeerConnection` led by the address whenever the peer has a real
  alias — the one case where the title does not already carry it. When the
  peer is nameless the display name already *is* the address, and the
  address is not repeated.
* A search field sits above the list, filtering on the two strings a row
  prints — name and address — with the same dense, sunken decoration the
  conversation list's own search field wears, including its clear button.
* The list is a `ListView.builder` inside a `ConstrainedBox` capped at
  340px, so a long peer list scrolls within the dialog instead of sizing
  it. The dialog itself widened from 340 to 380 to give the address-led
  subtitle room.

Ordering is unchanged: connected first, then by name (now
case-insensitively, matching the conversation list's own comparison).

## Alternatives considered

**Keep the `ListTile`s and only bound the height.** Rejected: it fixes the
overflow but leaves the actual complaint — rows that do not look like the
conversations they pick, and no way to find one Device among dozens
except scrolling.

**Title each row with `describePeerTitle` (the address) exactly as the
conversation list does.** Rejected: consistent, but the picker answers
"which Device do I send this to", and the alias is the name a person
recognises; the address still appears, as the subtitle's lead, for the
peers whose alias does not identify them. The conversation list can afford
the address-first reading because its rows also carry message previews;
the picker's whole content is the identity line.

**Reuse `ConversationRow` from `conversations_page.dart`.** Rejected:
`forward.dart` is imported by `conversation_view.dart`, which the
conversations page imports in turn — taking the row from there would make
the dialog depend on the page that hosts it. The row drawn here is the
same shape (hover wash, padding, hairline-free) without the page's
machinery: no selection state, no context menu, no unread count.

**Filter on message content like the conversation search does.** Rejected:
the picker lists Devices, not messages; there is no transcript here to
match against, and a search that silently ignored half of what a user
typed would be worse than one that searches exactly what the rows show.

## Consequences

- `test_flutter/ui/forward_message_test.dart` still finds targets by the
  displayed name — the title is still `displayName` — so the existing
  taps keep working; the row's new subtitle is asserted nowhere and
  needed no test change.
- Two new strings joined the ARB pair: `searchForwardTargets` and
  `forwardTargetNoMatch`, generated into `lib/ui/l10n/generated` as
  usual.
- The dialog now takes focus into its search field on open
  (`autofocus`), which is the point of the field; cancelling still
  returns null exactly as before, so every caller's backed-out path is
  untouched.

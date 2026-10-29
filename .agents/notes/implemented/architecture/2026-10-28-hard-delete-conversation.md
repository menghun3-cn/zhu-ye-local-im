# Agent Note: Deleting a conversation also forgets the Device

Status: implemented

English | [中文](2026-10-28-hard-delete-conversation.zh.md)

## Problem

The conversation list offered one destructive action, named "Delete". What it
actually ran was `clearConversation`: it removed the messages and the reading
watermark, and left every other fact about the peer in place. The Device stayed
in the Owner Group, in the favorites set, on the clipboard-sharing whitelist and
in `known`, so it kept reconnecting on its own, kept its clipboard permissions,
and its row reappeared on the next launch or the next beacon. A user who deleted
a conversation and then watched the Device come straight back had no way to tell
that the delete had happened at all.

Three different operations were living under one word — clearing a chat,
forgetting a Device, and deleting files from disk — and any build that shipped a
single button had to silently leave two of them undone.

The other half of the problem was the files. A pasted picture is written to a
shared temporary directory before it is sent, while a received file and a file
the user picked are the user's own. Nothing recorded which was which, so a
deletion could not take its own litter away without risking a user's file.

## Decision

List deletion is now a hard `deleteConversation`, not a `clearConversation`. It
unwinds everything one Device left behind on this Device, in one pass:

- **In-flight Transfers are cancelled, not merely hidden.** `Transfer.cancel`
  moved to the base class so a deletion can stop both directions with one call,
  and the peer is told the Transfer ended.
- **The Session is closed** — the wired link is disposed and its socket closed.
- **Messages and reading state go**, and when nothing is left the history file is
  removed rather than written back empty. `MessageStore.remove` exists for that;
  `ConversationReading.isEmpty` is what decides it.
- **The Device is forgotten** through one `DeviceProfile.forgetDevice`, which
  drops the known-device record, the favorite, the clipboard whitelist entry and
  the Owner Group membership together. They describe one peer, and a deletion
  that missed one of them would leave a permission whose owner is unlisted.
- **Clipboard memory for the peer is cleared** through `ClipboardMirror.forgetPeer`
  — staged entries, the applied list, the duplicate and ordering state — while
  the system clipboard's current content is left alone.
- **Temporary files this app created are removed**, and nothing else. A pasted
  image carries `appOwned` through `MessageRecord` and `TransferView`, so the
  deletion takes away exactly the files it wrote.

The Owner Group secret is deliberately kept: the other Devices still hold it,
and rotating it is a different operation. The peer is told nothing, and no
persistent ignore list is written: it may be re-discovered and re-paired at any
moment, which starts a brand-new empty conversation.

`clearConversation` remains, unchanged and lighter: the three-dot menu inside a
conversation still clears messages and reading state without forgetting the
Device, closing the Session or touching drafts.

## Consequences

- Deleting from the list actually removes the Device: it leaves the group and
  the clipboard whitelist, and its Session ends.
- A deleted Device can come back by itself, because re-pairing is automatic on
  the local link; it comes back as a new, empty conversation.
- Received files, files the user sent, and the current system clipboard content
  all survive a deletion.
- Pasted pictures that were sent are cleaned up; pasted pictures from older
  builds carry no `appOwned` flag and are left alone rather than guessed at.
- The `_deletedPeers` page-local set is gone, so what the list shows is exactly
  what the controller currently knows.
- Open drafts, staged attachments and text selection do not survive a deletion,
  because the conversation view is unloaded when the selection clears.

## Alternatives considered

**Add a persistent ignore list so a deleted Device cannot re-pair.** Rejected:
the local link is the admission boundary everywhere else in this product, and a
second, invisible trust layer would make "come back by re-pairing" behave
differently from "come back by beacon" in a way no screen explains.

**Tell the peer to un-pair, and rotate the group secret.** Rejected: the secret
is shared by every member, so rotating it on one Device's say-so would re-pair
the whole group and disconnect uninvolved Devices. Forgetting one peer is a
local decision and is recorded as one.

**Guess which files are temporary by their path or name.** Rejected: the paste
path writes into the same temporary directory other programs use, and a delete
that removed a file it did not create would be far worse than a leftover. The
flag travels with the record instead.

**Keep the one-button delete and only add a confirmation sentence.** Rejected:
the button already existed, and its name was the problem. Naming the composite
action and doing what the name says is the fix; wording alone would still leave
the Device in the group.

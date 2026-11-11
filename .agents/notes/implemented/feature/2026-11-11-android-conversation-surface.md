# Agent Note: Android lands on the conversation list and answers the message menu by long press

Status: implemented

## Problem

Two places where the Android build did not behave like the phone it runs on.

A message could be deleted only from the menu a right-click opens, and
`TransferContextMenu` listened for `onSecondaryTapDown` alone. Android has no
secondary mouse button, so on the platform this product ships to there was no
gesture at all that reached 删除 — the action existed in the controller and was
unreachable in the interface.

Opening the app also skipped the conversation list. `ConversationsPage` falls
back to `controller.lastConversation` while nothing has been picked, which on a
wide surface is only a pre-selection beside the list — but the narrow layout
shows one pane at a time, so the same fallback made the remembered conversation
the whole screen. Launching landed inside a chat nobody had asked for, one tap
away from the list that is the actual home of the surface.

## Decision

`TransferContextMenu` answers `onLongPressStart` next to
`onSecondaryTapDown`, opening the same menu at the point the gesture happened.
The long press is gated on `TransferMenuGestures.longPressMenu`, a static field
defaulting to `Platform.isAndroid`: everywhere else the held press is left to
the `SelectionArea`, where it is how a word inside the selectable body gets
selected. The answer is a field rather than a platform read inside `build`
because a widget test runs on the host — where `Platform.isAndroid` is never
true — and the gesture it exists for could otherwise never be exercised.

`ConversationsPage` gains `restoresLastConversation`, defaulting to true. The
remembered-peer fallback applies only while `widget.restoresLastConversation`
holds, and `HomeShell` passes `widget.seams.platform != DevicePlatform.android`.
A `requestedPeer` — the Devices surface asking for a conversation — is
unaffected: that is a user action, not a fallback.

The gate is on the platform, not on the width. A narrow Windows window still
restores the last conversation exactly as before; what changed is which
platforms get the one-pane-at-a-time convention where the list is the landing.

## Alternatives considered

**Long press on every platform.** Rejected: on a desktop the held press is
already the selection gesture, and answering it with a menu takes word
selection away — the `words in a bubble can be selected` widget test caught
exactly that. Touch-only platforms other than Android can opt in later by
changing the one field.

**`defaultTargetPlatform == TargetPlatform.android` in `build`.** Rejected:
`flutter_test` answers `defaultTargetPlatform` with Android, so the gesture
would have been active in every widget test — including the selection test it
breaks — and it conflates "what the framework thinks the platform is" with
"what this binary runs on", which the seams already answer as
`DevicePlatform`.

**Gate on the narrow layout instead of the platform.** Rejected: the
requirement is about the platform's convention, not the window's width. A
narrow Windows window is still a desktop surface, and changing what it opens
with would alter behaviour nobody asked to change.

**Restore the last conversation on every arrival, only skip it at cold
start.** Not needed as a separate mechanism: the fallback only applies while
`_untouched`, which ends at the first selection or back-navigation, so
withholding it already affects only arrivals with nothing picked — the cold
start and a first visit to the tab within a session.

## Consequences

**Bought.** On Android a long press on any message bubble opens the same menu
a right-click opens — 删除 included — and the app opens on the conversation
list rather than inside the last chat. Desktop behaviour is unchanged in both
directions.

**Given up.** On Android the long press no longer starts word selection inside
a bubble: the menu gesture wins the arena. Copying part of a sentence is
therefore unavailable there; copying the whole message (复制) still is, which
is the action the menu already carries. This matches the messaging convention
the gesture comes from.

## Testing

`test_flutter/ui/delete_message_test.dart` gains a long-press test that sets
`TransferMenuGestures.longPressMenu` and asserts the menu opens and deletes;
the existing right-click and selection tests run with the field at its
`Platform.isAndroid` default — false under `flutter test` — so they pin the
desktop side unchanged.

`test_flutter/ui/pages_test.dart` gains an Android restart test: a Device
started with `platform: DevicePlatform.android` opens a conversation, the
window is rebuilt, and the list — not the conversation — is what shows. The
existing `the default conversation is ready to type in on startup` test pins
the Windows side of the same fallback.

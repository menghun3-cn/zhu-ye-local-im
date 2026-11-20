# Agent Note: a covered surface still took the dropped file

Status: implemented

English | [中文](2026-11-20-a-covered-surface-still-took-the-dropped-file.zh.md)

## Problem

Dragging a file onto the 通过短链分享 page did two things at once: it
created a share link, and the file also appeared staged in a conversation's
composer — a conversation the user was not looking at.

The cause is `desktop_drop`, not the pages. Its `DropTarget` listens to the
OS drag globally and decides by coordinates alone: every enabled target in
the tree checks whether the drop landed inside its own render bounds, with
no hit test and no regard for what is actually painted on top. The plugin's
own documentation warns about exactly this — a target covered by a pushed
page still receives drag events — and this app covers its targets twice over:
the shell's `IndexedStack` keeps every tab mounted, and a pushed
`ConversationPage` sits on top of the shell without unmounting it.

So a drop on the share page fired both targets whose bounds covered the
window: `ShareByLinkPage` made the link, and the hidden `ConversationView`
staged the file into its composer, where it waited for the user to return.

## Decision

A `DropTarget` is enabled only while the surface holding it is the one
actually on top, and the framework already tracks both ways a surface can
be covered — so the fix adds no parameters and touches no caller:

- `Visibility.of(context)` answers the `IndexedStack` case. Flutter wraps
  every child of the stack in a `_VisibilityScope` that reports whether it
  is the selected index, and `Visibility.of` reads exactly that —
  reactively, so a tab switch re-enables or disables the target on the same
  frame the page changes. Both `ConversationView` and `ShareByLinkPage`
  AND it into `enable`.
- `ModalRoute.isCurrentOf(context)` answers the route case: a pushed
  `ConversationPage` or a dialog covering the shell leaves the shell's
  targets mounted under a route that is no longer current. The pushed page's
  own `ConversationView` passes, because its route *is* current — which is
  also what makes the standalone page keep working with no extra wiring.

The symmetric leak needed no second fix: the share page's target is gated
by the same two checks, so once it has been opened it stays mounted under
the other tabs but takes no drops while covered.

## Testing

`test_flutter/ui/share_by_link_page_test.dart` gains "a covered
conversation takes no drop meant for this page": with a conversation open
and the share page on top, the conversation's `DropTarget` reports
`enable == false` while the share page's reports `true`; after switching
back to the conversations tab the flags invert, because the share page
stays mounted under the `IndexedStack`. The lookups go in with
`skipOffstage: false`, since `find` skips the `IndexedStack`'s unselected
children by default — the mounted-but-covered widget is exactly what is
under test. The existing drop tests invoke `onDragDone` directly — the OS
drag is not drivable in a widget test — so the `enable` flag is the
contract they now also pin.

## Alternatives considered

**Unwrap the conversation when another tab is selected.** Rejected: the
`IndexedStack` exists precisely so a half-typed conversation survives a tab
switch; unmounting it to fix an input-routing bug would trade the bug for
the reason the stack is there.

**Thread `isVisible` from the shell into every drop-bearing page.**
Rejected: it works, but it duplicates a fact the framework already tracks —
`IndexedStack` marks its unselected children through `_VisibilityScope`,
and `Visibility.of` was added for exactly this question. A parameter per
page is a second source of truth that can disagree with the stack's own
notion of "selected"; the route case would still have needed
`ModalRoute.isCurrentOf` anyway.

**Hit-test the drop position against the widget tree instead of trusting
coordinates.** Rejected: `desktop_drop` already does the coordinate check
inside each target; layering a second, visibility-aware hit test on top
would mean reimplementing the plugin's dispatch to fix one flag it already
exposes.

**Disable the targets only while the share page is open.** Rejected: the
leak is not specific to that page — any surface covering a mounted
conversation (another tab, a pushed route, a dialog) has the same hole, and
a fix scoped to one pair of pages leaves the next one to be found the same
way.

**Wrap every `DropTarget` in a route-aware gate inside the plugin.** Not
possible: the plugin is a dependency, and its documented contract is that
the *caller* disables covered targets.

## Consequences

- A drop lands on exactly one target: the one whose surface is on top.
- `enable` is now a statement about visibility, not just about whether the
  surface can use a file — future `DropTarget`s in this app owe the same
  two-part answer (surface visible, route current).
- A dialog open over a conversation disables its drop target for the
  dialog's lifetime; dropping onto a modal was never meaningful anyway.
- [a drop stages in the composer](../feature/2026-11-11-a-drop-stages-in-the-composer.md)
  keeps its decision — one road in, one rule — and gains the precondition
  that the road is only open while the conversation is on top;
  [the conversation looks like WeChat](../feature/2026-10-09-the-conversation-looks-like-wechat.md)
  is updated in place where it says the target is "enabled only when there
  is a peer".

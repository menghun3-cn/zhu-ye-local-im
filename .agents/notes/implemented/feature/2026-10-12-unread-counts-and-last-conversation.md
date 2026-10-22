# Agent Note: Unread counts, and coming back to the conversation you were in

Status: implemented

## Problem

Seven things about the surfaces were reported at once, and five of them were
cosmetic while two were not.

The cosmetic ones were all the same defect wearing different hats: a control
that had been told to be as small as it could be. The theme set
`minimumSize: Size.zero`, `tapTargetSize: shrinkWrap` and `visualDensity:
compact` on both button themes, and `border: InputBorder.none` with
`isDense: true` on the input decoration theme. The result was a 检查更新 that
was a flat green word rather than a button, dialog actions a couple of
centimetres of nothing tall, and an address field with no line around it on a
panel of nearly the same fill — a labelled blank rather than somewhere to type.

The two that were not cosmetic:

1. **Nothing knew what had been read.** `MessageRecord` carries what was said;
   `LocalTransferController` held no notion of the user having looked at any of
   it. So a conversation list could not say that something had arrived while the
   user was elsewhere, and the only way to find out was to open every
   conversation in turn.

2. **Arriving at the Conversations surface always landed on a blank pane.**
   `_selected` started null and the wide-window branch drew `conversationPickOne`
   at it, so a user who came back to the surface had to pick the same
   conversation again — every single time. A messenger whose list sits beside an
   empty pane is a messenger asking the user to re-answer a question they
   already answered.

There was also a smaller one hiding inside the second: a bubble's words were
`Text`, deliberately not selectable, because a selectable body would have taken
the secondary click away from the message's own menu. The right-click menu
therefore had a 复制文字 line that copied the *whole* message, which is not what
anybody dragging across three words is asking for.

## Decision

### Standard-sized controls

`WeChat` gains a family of standard metrics — `buttonHeight` (36),
`buttonHPadding` (16), `fieldHeight` (44), `fieldHPadding` (12), `fieldVPadding`
(10) — and the theme's button themes and `inputDecorationTheme` are built from
them.

- A `TextButton` and a `FilledButton` are now the same height, because the two
  sit shoulder to shoulder at the foot of a dialog and a row of buttons at two
  heights looks broken. Any action that genuinely belongs *inside* a line — the
  row action in the conversation list, a bubble's own answer, the send button —
  overrides every one of those metrics at its own call site rather than relying
  on the theme being small.
- Every field gets a real outline, in `borderStrong`, with a brand hairline and a
  wider brand line on focus. The one field that wants no outline is the
  conversation composer's, which is written straight onto the board it sits
  on; it turns all six border slots off and zeroes the constraints at its own
  call site. (The composer was redrawn to match WeChat's desktop client
  afterwards — see [the composer is WeChat's](2026-10-21-the-composer-is-wechat-and-refusals-land-at-the-top.md),
  which is where that field's metrics now live.)
- 检查更新 became a `FilledButton.icon`, the style every other primary action in
  the application already wears; 打开下载页 stayed a `TextButton.icon`, because
  it opens a page rather than doing something in this window.

### Unread is a watermark, not a count

`ConversationReading` (`lib/core/history/conversation_reading.dart`) holds one
timestamp per peer: everything *incoming* with an `at` later than it is unread.
A count would have to be maintained through every deletion, resend and restart,
and would be wrong the first time any of those disagreed with it; a watermark is
one number compared against the messages that actually exist.

The rule is the desktop client's, and the whole of what a user expects is in one
sentence: **opening a conversation reads it, and leaving does not un-read it.**
Nothing is sent to the peer — there is no read receipt, and a peer has no
business knowing.

- `LocalTransferController.unreadCount(peer)` counts from `transfers`, the same
  list the conversation draws, so a badge and the messages under it cannot
  disagree. Clipboard entries are excluded, as they are everywhere else.
- `markConversationOpened(peer)` is called when a conversation is *selected*, not
  from the conversation widget's own `build`. "The user is looking at it" is a
  fact about the list's selection: the shell keeps every page alive in an
  `IndexedStack`, so a conversation rebuilds while the user is on another
  surface, and that is not reading.
- The mark is monotonic and the write is conditional. A clock that stepped back
  cannot make a read conversation show everything again, and the file is only
  rewritten when something actually changed — the call site is a `build`.
- `unreadCount` leads the preview as a plain bracketed number — `[3] 明天见` —
  rather than a red badge. A badge belongs on an avatar where it cannot be
  mistaken for the message's first characters; this shares a line with the text,
  and the brackets are what keep the two apart. The row is also *louder*: the
  name goes semibold and the preview steps up from secondary ink to body ink.

### The last conversation, remembered

`ConversationReading.lastPeer` holds it, in the same object and the same file,
because the two are written together and a file holding one without the other
would be read in a state neither writer intended.

The remembered peer is a **fallback**, not an override. `_untouched` is true only
until the user taps a row or a request arrives from another surface; after that
the remembered peer stops applying, so a choice made in this sitting is never
overwritten by an older one. The remembered conversation is marked read on the
frame that shows it, exactly as a tapped one is.

### Words are selectable, and the menu is still the message's

The message list is wrapped in a `SelectionArea`, so a double-click takes a word
and a drag takes a range. `SelectableRegionState` is reachable only by the widget
that created it — `SelectionArea` keeps its key private and offers no `of` — so
`MessageSelection`, an `InheritedWidget`, carries the selected text from the area
down to the menus.

`TransferContextMenu` is therefore the *whole* of the reconciliation: it is the
platform's copy toolbar and the message's own menu in one. When there is a
selection it offers 复制 of the selected words *above* 打开所在目录 and 删除; the
whole-message 复制文字 line steps aside while a selection exists, because "copy
this message" and "copy these three words" are different requests and a menu that
silently switched between them would be unpredictable.

## Alternatives considered

**A red numeric badge in the row's corner.** What WeChat itself does, and
rejected here for a layout reason rather than a taste one: that corner already
holds the clock on the first line and the action button or the state on the
second, and `_ConversationTile` bounds both to about a third of the row. A badge
would either displace one of them or be a third thing competing for the same
space. The `[N]` prefix costs nothing, sits where the preview already is, and is
unambiguous for the same reason the brackets are.

**Storing the unread count rather than a watermark.** One integer per peer is
less to write than one timestamp, and it is the wrong integer: it has to be
decremented on delete, incremented on arrival, reset on open, and reconciled on
every path that can do any of those. Six places to be wrong in exchange for four
bytes.

**A per-peer "has been read" boolean.** Cheaper still, and it cannot answer the
question the moment a second message arrives while the first is unread — the row
would say "unread" and the count would be a lie.

**Marking read from `ConversationView.build`.** It is where the conversation is
actually drawn, which is tempting, and wrong for the reason above: the shell's
`IndexedStack` rebuilds every page on every tick, so the mark would fire for
conversations nobody is looking at while leaving genuinely-read ones unmarked
whenever the app sat on another surface.

**Letting `SelectionArea` draw its own context menu over the words.** The
library's default behaviour, and it takes the message's own lines away exactly
where a user most wants them: a right-click on the text of a file message would
open a copy toolbar with no 打开所在文件夹 and no 删除. That is the trade the old
`Text` avoided by making the words unselectable; this keeps the words *and* the
lines.

**Giving each bubble its own `SelectionArea`.** A selection that stops at a
bubble's edge is not what a user dragging across two messages is asking for, and
it would put a `SelectableRegion` per message in the tree.

**Bumping the conversation file's version key when the reading state was added.**
The envelope gained a key rather than changing one, and the reader that has to
stay compatible with it is the one that reads `messages` and ignores the rest —
which is exactly what a version bump breaks. `version` stays `1`; it should move
when a key's *meaning* changes, not when one appears.

## Testing

`test/history/conversation_reading_test.dart` (new, pure Dart): the watermark
direction, the monotonic guard, `unreadFor` counting only incoming messages,
`retainOnly` pruning, and the JSON round trip including a file written before the
key existed.

`test/history/message_store_test.dart`: the envelope still round-trips, and a
stored file with no `reading` key reads back with an empty one rather than
throwing or losing the messages.

`test_flutter/ui/pages_test.dart`: the unread prefix on a row, the louder styling
of an unread row, arrival at the surface opening the remembered conversation
rather than the empty pane, and a tapped row not being overwritten by the
remembered one.

`test_flutter/ui/about_page_test.dart`: 检查更新 is a `FilledButton`.

`test_flutter/ui/delete_message_test.dart`: unchanged assertions, because the
whole point of the reconciliation is that they stay true — 复制文字 and 删除 are
both still on the menu a right-click on a text message opens.

## Consequences

- Every dialog in the application gains taller buttons and outlined fields at
  once, which is the intent; the widget tests that drove them by text were
  unaffected, and the ones that measure were checked.
- The composer is the one place that opts out of the new field styling, so a
  future change to `inputDecorationTheme` will not reach it. That is deliberate
  — it is not a field on a panel, it is a field in a channel — but it is a
  second place to look. (It now draws no frame at all, since the composer was
  redrawn to match WeChat's desktop client; see [the composer is
  WeChat's](2026-10-21-the-composer-is-wechat-and-refusals-land-at-the-top.md).)
- `conversationDisconnected` now reads 离线 / "Offline" rather than 连接已断开 /
  "Session closed". Shorter, and the same fact: 离线 is what a user says about a
  Device they cannot reach.
- A conversation opened on the *narrow* layout is also marked read, and so is one
  arrived at from the Devices surface — every road that shows a conversation ends
  in `_open` or in the remembered-fallback branch, and both mark it.
- A right-click with nothing selected on a text message still offers 复制文字, so
  the whole-message copy is never lost; it is only *out of the way* while a
  selection exists.

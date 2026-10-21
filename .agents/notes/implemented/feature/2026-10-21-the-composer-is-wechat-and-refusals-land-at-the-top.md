# Agent Note: The composer is WeChat's, and refusals land at the top

Status: implemented

English | [中文](2026-10-21-the-composer-is-wechat-and-refusals-land-at-the-top.zh.md)

## Problem

Two things about the conversation surface did not match WeChat, and one of
them was in the wrong place entirely.

**The input area was not WeChat's.** Ours was a framed text box with a brand
hairline that lit up when focused, a row of three buttons beside it, and a
send button that was a plain green pill. WeChat's desktop client draws
something else: a rounded white board floating on the conversation, the text
written straight onto it with no frame at all, a row of bare line-drawn
tools along its lower edge, and a small grey "send" block in the corner.

The difference was not only cosmetic. A framed field inside a white panel is
a box in a box, and the frame was doing the work that a caret does in
WeChat — saying "type here". A row of little bordered squares reads as a
form, not as a row of tools. And a green send button on an empty box is a
promise that nothing will happen.

**The refusal notice was in the wrong place.** When a message could not be
sent — the peer is offline, there is no Session — the app said so with a
`SnackBar`. A `SnackBar` rises from the **bottom** of the window, which is
exactly where the input area is. So the notice about a message that could
not be sent landed on top of the box the user was about to type the next
one into, covering the thing they were looking at in order to tell them
something about the thing they had just done.

## Decision

**The composer is drawn as WeChat draws it.** The metrics are measured off
WeChat's desktop client rather than chosen, and they live in `WeChat` as
named tokens so they are stated once:

- The input area is a **rounded board** (`composerBoardRadius` 8) in
  `composerBoard` (#FAFAFA), drawn with a one-pixel `composerBoardBorder`
  hairline (#E0E0E0) around it, floating with `composerBoardMargin` (10)
  from the window's edge.
- The **text area** is `composerFieldHeight` (56) tall and **unframed**: no
  border, no fill of its own, no focus ring. The board *is* the frame. The
  text is `composerFontSize` (15), the size of the conversation body it
  belongs to.
- The **tools** are bare line-drawn glyphs (`ComposerTool`) at
  `composerIconSize` (22) in a `composerIconBox` (28) tap area, `composerIconGap`
  (17) apart — a 45-pixel step from one glyph's centre to the next, which is
  what WeChat measures. The face comes first, then the file, and neither is
  framed, lit, or rippled.
- The **send** is a small block at the board's **bottom right**:
  `composerSendWidth` (60) by `composerSendHeight` (31), cornered at
  `composerSendRadius` (6), `composerSendRightInset` (13) from the right
  edge and `composerSendBottomInset` (10) from the bottom.

The send's colour follows what is in the box: grey
(`composerSendDisabled` #EDEDED) on `onComposerSendDisabled` (#A5A5A5) when
there is nothing to send, and the action green when there is. It stays
**clickable** either way — grey says "there is nothing here to send", and a
control that stopped answering the click would swallow the click *and* the
focus with it. An empty send is a no-op, guarded at the call site.

**A refusal is a toast at the top.** `TopToast` draws the notice over the
app, in an `Overlay` entry, `toastTopMargin` (48) below the window's top
edge. It keeps the bar the `SnackBar` used to draw — the same inverse
surface, the same text — because only its *position* was wrong.

The overlay is taken **before** the await that produced the failure, for the
same reason the strings were: the widget that started the call may be gone
by the time the call answers, and a refusal with nowhere to be drawn is a
refusal that says nothing. `guarded` and the three copy/reveal actions in
`transfer_actions.dart` all show their notices this way now.

## Alternatives considered

**Keep the framed field, and only move the buttons.** Rejected: the frame was
the loudest part of the difference. In WeChat there is no frame at all — the
caret and the placeholder are what say where to type — and a hairline box
with a brand focus ring inside a white panel is the opposite of that. A
half-measure would have left the one thing a user touches most drawn the
way WeChat does not draw it.

**Keep the `SnackBar` and only change where it is anchored.** Rejected:
`ScaffoldMessenger` places a `SnackBar` at the bottom of the scaffold, and
the only way to move it is to stop using it. The toast is the same idea
drawn somewhere else.

**Put the toast at the top of the *composer* rather than the window.**
Rejected: the composer is only in the conversations surface. A refusal can
arise anywhere — connecting to a Device, applying a staged clipboard entry,
copying a file's text — and a notice that only had one home would have to be
reinvented at each of the others.

**Keep the send disabled when the box is empty.** Rejected: a disabled
control stops answering the click, and with it the focus. The send is the
one button a user reaches for twice, and a grey button that swallows the
second press is worse than a grey button that does nothing. The colour
carries the meaning; the click is simply harmless.

**Use Material's own `IconButton` defaults for the tools.** Rejected on
measurement: the framework's `IconButton` pads its icon by 8 on every side
and asks for a 40-pixel minimum, so inside a 28-pixel box a 22-point glyph
renders at 12 points — a tool at half the size it is supposed to be. The
padding and the minimum size are therefore set at the call site.

**Draw the board without the hairline, on the grounds that the two greys are
a step apart and the line is redundant.** Rejected: the reference has one
(#E0E0E0, a pixel wide), and it is not redundant. The greys separate the
board from the conversation; the line says where the board *ends*. Measuring
the reference is what settled it — the "no line" reading was an assumption
that the pixels did not support.

## Consequences

- **The composer reads as WeChat's.** The board, the borderless text area,
  the bare tools, and the small grey send in the corner are all measured off
  the reference rather than eyeballed.
- **The tools are one widget.** `ComposerTool` draws the bare glyph, and
  `EmojiPickerButton` uses it — so the face and the file cannot drift apart
  in size, colour, or pressed state. `EmojiPickerButton` became stateful so
  the picker panel can be anchored to the glyph that opened it.
- **The send's colour tracks the box.** The button listens to the text
  controller rather than to the composer, because the controller does not
  rebuild the composer when it changes.
- **The token `composerControl` is gone.** It measured the height of the
  buttons in the old row, and that row no longer exists.
- **The notice about a failed send no longer covers the input area.** It
  appears at the top, over the conversation, where it cannot hide the box.
- **The tests assert the measurements.** The composer tests check the
  board's colour, radius and hairline; the text area's height; the tools'
  glyph size and 45-pixel step; the send's size, position, and grey-to-green
  change. The toast tests check that a refusal lands at the top, that no
  `SnackBar` is in the tree, and that the toast leaves on its own.

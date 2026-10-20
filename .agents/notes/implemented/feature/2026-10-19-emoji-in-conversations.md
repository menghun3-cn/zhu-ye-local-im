# Agent Note: Emoji in conversations

Status: implemented

English | [中文](2026-10-19-emoji-in-conversations.zh.md)

## Problem

A conversation could carry text, files and pictures, but not the small
expressions that make a chat feel like a chat. WeChat users expect a face
button beside the attach button and a set of faces to choose from; without one,
the only way to send a face was to type an emoji code point by hand, and a
receiver could not tell it apart from ordinary text.

This device was also the only device a recent-emoji strip could live on: the
faces somebody uses are a per-Device preference, the same way favorites are,
and forgetting them on restart would make the strip a history of the last ten
minutes.

## Decision

An emoji is a message of its own. The composer gains a face button beside the
attach button; it opens a floating panel anchored to the button, with a Recent
row and then the full grid. Picking a face sends it immediately as its own
message — it is not staged into the box, because a face is a complete message
the way a sent file is.

- `PayloadKind.emoji` is a new wire kind. Like text and clipboard content, it
  travels inside the Offer, so it never needs a confirm on the receiving
  Device (`_landingFor` answers `''` for it, the same as text).
- The transfer limits treat it as an inline payload; the engine gains
  `sendEmoji` alongside `sendText`; the controller gains `sendEmoji`.
- A bubble renders an emoji as a large face (`emojiBubbleFontSize`, 48) with
  no "kind · state" receipt line and no file block, so it reads as a sticker
  rather than a line of words.
- The recents are a new profile field (`recentEmojis`), capped at eight and
  kept newest-first. `EmojiEntry` holds the face and its English name; the
  picker shows faces from `emojiTable` in a fixed order, and recents are drawn
  first in recency order. Faces outside the table are never drawn and never
  promoted, but never corrupt the file either.
- `emojiTable` is pure Dart data (`lib/core/emoji/`), so the widget layer reads
  it without pulling Flutter into `lib/core`.

## Alternatives considered

**Stage the face into the text box and let 发送 release it.** Rejected: a face
typed into the box reads as text a person has to finish sending, and the emoji
button would be a character palette rather than a message. WeChat sends the
face immediately, and "tap, face appears" is the behavior users know.

**Bundle the face into the existing text payload and detect it on receipt.**
Rejected: that would make every future text look-alike ambiguous, and the
receiver could not tell "😀 the user typed" from "😀 the user chose". A distinct
wire kind is exactly what a distinct rendering needs.

**Use platform stickers (pictures) instead of code-point faces.** Rejected: a
sticker set is licensed artwork, and two builds would have to carry identical
bytes to render the same face. A code-point face is a fact about Unicode that
the receiving platform draws — same character, same face, no assets in the
repo.

**Read recents live from the conversation history.** Rejected: history is
cleared on restart, and a strip that resets on restart is not "recently used",
it is "used in this session". The profile persists the tiny list the same way
it persists every other per-Device preference.

## Consequences

- Sending an emoji is two clicks (open the panel, pick a face) and the result
  is a large face on both Devices. The Recent strip makes the second click
  land on the face used last time.
- The wire adds one value to `PayloadKind`; older builds that do not
  know `emoji` will reject it via the kind's own validation on a version
  boundary, which is the same behavior a text message that changed shape would
  get.
- `emojiTable` is a fixed ordered palette. Adding or removing a face is a
  one-line change to the table, and every surface that draws faces reads the
  table, so the picker, the recents store and the profile cannot drift apart.
- The test suites gained a wire test for `PayloadKind.emoji`, profile and
  recents-store tests, a composer widget test, and a two-window test that
  sends a face and checks the large-face rendering.

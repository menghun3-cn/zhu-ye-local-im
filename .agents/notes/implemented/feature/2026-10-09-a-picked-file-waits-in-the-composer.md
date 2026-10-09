# Agent Note: a picked file waits in the composer until it is sent

Status: implemented

## Problem

Choosing a file sent it. The paperclip, the image button and Ctrl+V each ended
in the same place: `_pickAndSend`/`_pickAndSendImage` opened the operating
system's own dialog and put whatever came back on the wire in the same breath.
There was no moment in between. No way to write the sentence the file was
about, no way to take back the wrong one, and nothing on screen afterwards to
say what had just gone — the only record was the message that had already
arrived on the other machine. Pasting had been given exactly the same shape a
round earlier, which made it a pattern rather than an accident: three ways into
the composer, three immediate sends. Requested as "选择文件、选择图片，点击发送
之后再发".

## Decision

**The composer holds a draft.** `_ConversationViewState` gains
`List<StagedAttachment> _staged` — a path, the name to show, and whether the far
side will draw it as a picture — and all three ways in now **stage**:
`_pickFiles`, `_pickImage` and `_pasteIntoComposer` each end in `_stagePaths`,
which classifies the paths and appends them in the order they were chosen.

**发送 is what releases it.** `_sendMessage` sends the text that was typed and
then every staged file, one message each, exactly as a picked file was always
sent; images go as images so they draw. The box and the tray are cleared **only
after the whole send has succeeded**, so a send that fails leaves the draft
where it was and the user can try again rather than choosing the files over
again. An empty box with an empty tray sends nothing at all.

**What is staged is visible, and can be taken back.** `_AttachmentTray` draws a
`Wrap` of chips above the field: the kind's icon, the file's name bounded to 180
pixels and given a tooltip, and a remove `IconButton`. A `Wrap` rather than a row
or a bottom sheet — two files fit on one line, sixteen do not, and a composer
that silently hid the eleventh would send something the user could not see. The
remove control is a real `IconButton` so it keeps its focus ring, its keyboard
activation and its semantic label; a hand-rolled tappable glyph loses all three.

**`classifyPaths` becomes the primitive and `classifyDrop` is written over it.**
The tray has to show the files in the order they were chosen, which the old
two-list `({images, files})` split threw away. One existence check and one
`looksLikeImage` call now live in `classifyPaths`, and `classifyDrop` — still
used by the drop path — groups its answer.

**A dropped file still sends immediately.** The overlay a drag draws over the
history says 松手即发送, so a drop is a person deciding to send a thing rather
than to compose around it, and it is left alone. That is the one asymmetry this
change introduces, and it is stated in the code and in the tests rather than
left to be discovered.

## Alternatives considered

**Keep sending on pick, and add an undo.** The request is the opposite, and an
undo after the other machine has already been asked to accept the file is not an
undo.

**Put the staged files in the message queue as unsent messages.** A conversation
is a list of things that happened; a message that has not been offered yet
belongs in the composer, not in the history.

**A confirmation dialog when 发送 is pressed.** A second question where the
first answer was already given, and it still gives nowhere to type the sentence
the file is about.

**A bottom sheet or a route for the tray.** It would cover the field it is
supposed to sit beside, and it needs somewhere to navigate back from.

**Change the drop path to stage as well.** Defensible — it would make "nothing
leaves until 发送" a single rule — but the drop overlay already promises
immediate send in so many words, and the request named the two picker buttons.
Left as it is, and flagged here.

**Disable 发送 when there is nothing to send.** It would remove a no-op button,
and it would also make the button appear and disappear as the user types and
pastes, moving the click target under the pointer.

## Consequences

**The tray grows the composer.** With many files the box wraps onto more lines
and the history shrinks. Bounded by what a person stages by hand, and the
alternative — scrolling or paging the tray — is more machinery than the case
deserves.

**A file deleted between staging and sending fails at send.** The engine opens
the path when the offer is built, so a path that has gone away surfaces as the
guarded error the composer already reports. The staged item stays in the tray,
which is the useful half: the user can see which one it was.

**A draft belongs to one conversation.** The shell keys `ConversationView` by
peer, so switching conversations already rebuilds the state;
`didUpdateWidget` clears the tray anyway, so "a draft never crosses into
somebody else's conversation" is a property of the widget rather than of how its
callers happen to key it.

**Pasting a file now takes two actions rather than one.** Ctrl+V puts it in the
box and then it has to be sent. That is the requested behaviour and it is what
makes the same Ctrl+V able to be followed by a sentence, but it is a change in
what the chord *achieves*, and it is the part most likely to read as a
regression to somebody who had learned the old one.

**The composer's callers must pass the tray through.** `ConversationComposer`
gained `attachments` and `onRemoveAttachment`; they default to an empty list and
null, so a caller that does not want a tray (a test, a future surface) does not
have to know about one.

## Testing

`test_flutter/ui/pages_test.dart` gains a "choosing a file for the composer"
group: a picked file appears in the tray and **no Transfer exists** until 发送 is
pressed; a picked image travels as `PayloadKind.image` when it goes; and a
staged file can be taken back out, after which 发送 sends nothing. The two paste
tests now assert the same two steps — the file appears in the composer with
`controller.transfers` still empty, then 发送 produces the message — so the
paste path and the picker path are held to one rule.

`test_flutter/e2e/two_window_e2e_test.dart`'s end-to-end file transfer now taps
发送 between choosing the file and the offer reaching the other window, which is
what a person does; everything after that tap is unchanged.

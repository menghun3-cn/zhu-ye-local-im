# Agent Note: a picture stands on its own, and can be copied

Status: implemented

## Problem

**「发送或者接收的图片，不要包裹在气泡里面，和微信显示图片一样直接显示缩略图，点击后放大。
也可以右键图片进行复制」** — three complaints about one subject: a picture in a
conversation was drawn as a *transfer* rather than as a picture.

A picture was already drawn where its bytes were, and clicking one already opened
it full size. What was wrong was everything around that: the thumbnail sat inside
`MessageBubbleShape`, so every picture arrived in a coloured rectangle with bubble
padding and a tail. WeChat puts a picture into a conversation as a picture, and a
picture in a green rectangle reads as a file that happens to have a preview. The
third part was missing outright — the right-click menu, added the same day for
「打开所在目录」, offered a folder and nothing else, so a picture that had just
arrived could be found on disk but not taken back out.

## Decision

**The bubble is skipped for exactly one message, and one predicate says which.**
`MessageBubble._drawsBareImage` is `view.kind == PayloadKind.image &&
view.localPath != null`: a picture whose bytes are on this machine. It is drawn as
itself — a rounded thumbnail, no fill, no bubble padding, no tail — in the space
the bubble would have occupied, with the avatar still beside it and a click still
opening the full-size view. Everything else keeps its bubble, and the reason is
not nostalgia for the shape: **a picture with no path has something to say beside
its content**, which is a name, a progress bar and possibly the two answers an
offer needs. There is no bubble around a picture because a picture is its own
content, exactly as a text is.

**A picture without a path is not a third state, it is the transfer's state.**
`MessageBubble._image` used to draw either the file name or the picture. Its
picture half is now unreachable — `_drawsBareImage` routes around it — so it was
deleted rather than left as dead code, and what remains is the one honest thing
that can be drawn for a message whose bytes are not here yet: a picture glyph and
a name, which is exactly what a file message draws, because at that point the two
*are* the same thing.

**The progress bar stays, below the picture.** An outgoing picture has a
`localPath` from the instant it is sent and is not settled until the other Device
has taken it, so a bare thumbnail has to be able to say it is still going. It is
bounded by the thumbnail's own bound — `WeChat.imageMaxSide` — so a bar drawn
under a wide screenshot cannot outrun the picture it is a bar for. An incoming
picture has no such bar to draw: it has a path only once its bytes have landed.

**Two more tokens in the theme, not two numbers at the call site.** `imageRadius`
is 4 rather than `bubbleRadius`'s 6 — a thumbnail has no fill behind it, and the
desktop client's pictures are squarer than its bubbles — and `imageMaxSide` is
200, the square bound `ImageBubble` already used, promoted to a token because the
progress bar above needs the same number.

**The placeholder turned grey.** `ImageBubble`'s placeholder and its
unreadable-picture fallback were `WeChat.surface` — white — chosen expressly so
they would read as a hole *in a bubble*. Outside one they are white boxes on the
conversation's white. They are `WeChat.pageBackground` now, which is what the rest
of the interface uses for "a surface darker than the page".

**Copy goes out through the clipboard seam that already existed, the other way.**
`ClipboardPaste` — the seam the composer reads Ctrl+V through, over the
`pasteboard` plugin, because Flutter's own `Clipboard` is text and nothing else —
grew `writeImage`, answered over `Pasteboard.writeImage`. The picture is put back
on the clipboard as a picture rather than as a file list, which is what makes it
pasteable into anything that takes a picture.

**`writeImage` answers a `bool`, and says no where it cannot know.** On Windows
the plugin writes the bytes to a scratch file whose name has no extension and
hands it to GDI+, which is known to consult the extension when it picks a decoder;
that assumption was verified out of the process before the call was written, by
reproducing it in isolation and getting a 24×12 bitmap back. A platform the plugin
has no implementation for falls through it as a silent no-op, and a no-op that
reported success would put "copied" on screen for a clipboard nothing happened to,
so the four platforms this build claims are named and the rest answer false.

**The failure is said out loud; the success is not.** A clipboard an app may not
write is an ordinary condition — Android gives that answer while the window is
unfocused — so it reaches the user as `cannotCopyImage` rather than as a stack
trace or as silence. A copy that worked says nothing, because the pasted picture
is the confirmation.

**One menu, and the predicates decide what is on it.** `TransferContextMenu`
already took a `TransferView` and wrapped both a conversation message and a
Transfers card; it now asks `canRevealTransfer` and `canCopyImage` rather than one
predicate, lists an item per answer, and switches on which one came back. So a
picture offers both — the folder it is in and the clipboard it can go back to, two
things that are not alternatives — and no surface can drift from another, because
no surface decides. The two are read once before the `await`, so the list cannot
change under the menu the user is looking at.

**The bytes are read back from disk.** The file the Transfer points at is the one
copy of the picture, and reading it back is what keeps a conversation holding a
hundred pictures from holding a hundred decodes. A file that is no longer there is
a copy that cannot happen, reported the same way as one that failed.

## Alternatives considered

**Copy as a file list (`Pasteboard.writeFiles`).** Rejected: that is a clipboard
holding *a file*, which pastes into a chat as an attachment and into an editor not
at all. 「复制图片」 means the picture, and the bitmaps are the half of the
clipboard every target understands.

**Copy the path as text.** Rejected: it is what the reveal action already achieves
in a more useful form, and "paste the path into the address bar" is not what
anybody means by copying a picture.

**Call `Pasteboard.writeImage` without the platform gate.** Rejected: the plugin
is a no-op on a platform it has no implementation for, and from the Dart side a
no-op is indistinguishable from a success. Naming the four platforms is one
condition and it is the difference between a failure sentence and a lie.

**Implement the clipboard write directly, through `package:win32`.** Rejected: a
native dependency bought to duplicate a call the project's own paste path already
depends on. One plugin, two directions.

**Keep the white placeholder.** Rejected: it was white for a reason that no longer
holds. Leaving it would put an invisible box on the conversation for the length of
every decode.

**Draw a picture that has not arrived yet without a bubble too.** Rejected: there
is nothing to draw. A grey box of unknown shape, or a name with no fill behind it,
would be a message pretending to be further along than it is — and an offer's two
answers need a surface to be legible on.

**A progress ring over the thumbnail, the way the phone client does it.** Rejected:
it needs a `CustomPainter` and a spinner per in-flight picture, for a state that
the desktop client reports with the same bar as everything else. The bar is also
what a file's bubble already shows, so a send in flight looks the same whichever
kind it is.

**Offer Copy on files as well.** Rejected: "copy" would then mean two different
things — a file list to Explorer, a bitmap to everything else — and the menu would
have to guess which the user meant. A file already has a folder to be shown in,
which is the question a file raises.

## Consequences

The wire is untouched. A picture already travelled with a digest and a sink; what
changed is a colour, a rectangle, and a local clipboard write, so
`wireProtocolVersion` is not raised and an older peer keeps working.

The conversation has one message that is not a bubble. Anything that counted
`MessageBubbleShape` to mean "a message is on screen" now has to count
`MessageBubble`, and the same goes for anything measuring a message's box.

`ClipboardPaste` is no longer read-only, so `ScriptedClipboard` records writes
separately from reads — a copy that landed in the field the paste reads from would
make a test that pasted its own copy look like a test that copied what it pasted.

`copyImage` and `cannotCopyImage` join `openContainingFolder` and
`cannotOpenFolder` in both languages, and the packaging script's probe list goes
from 19 sentences to 21.

## Testing

`test_flutter/ui/pages_test.dart` grows an `a picture on a conversation` group,
built on one helper that gets as far as Bob's window looking at a picture Alice
sent — paired, filed into a folder Bob was told about, landed, on screen. One test
asserts the conversation holds no `MessageBubbleShape` at all, and that tapping
the thumbnail opens the full-size view; a second that a right-click offers *both*
actions on one menu; a third that choosing Copy hands the clipboard exactly the
bytes that were sent, byte for byte, and says nothing; a fourth that a clipboard
which refuses the write produces `cannotCopyImage`.

`ScriptedClipboard` gained `copiedImages` and `answersWrites`, so all of that runs
without a platform channel and without anything being copied on the machine
running the suite.

`test_flutter/ui/image_bubble_test.dart` is unchanged and still pins the shape of
the preview — the widest side bounded, the aspect ratio kept, a small picture not
blown up, an unreadable one falling back to its name — because none of that moved.

The Windows clipboard path was verified out of process rather than assumed: the
plugin writes its scratch file with no extension, and a probe that called
`GdipCreateBitmapFromFile` on exactly such a file returned a bitmap of the right
size. The widget tests stop at the seam by design; what they cannot see is the
operating system's clipboard, and the call between the two is the plugin's own.

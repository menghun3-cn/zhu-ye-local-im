# Agent Note: pasting a file into the composer, and choosing where it lands

Status: implemented

## Problem

Two requests arrived from using the packaged Windows build, and both are about a
thing the user could already do only the long way round.

**A file the user already had on the clipboard could not be pasted.** The
composer could *send* a file, but only through the paperclip button, which opens
the operating system's own file chooser. A file copied in Explorer, a screenshot
of a region, an image copied out of a browser — all of these are on the clipboard
already, and Ctrl+V in the message box did nothing with any of them. It could not
have: Flutter's own `Clipboard` reads and writes **text** on every platform and
nothing else, so a file and a picture are not merely unhandled, they are
invisible to the field. The only road to a message was to save the thing to disk
and pick it by hand.

**The folder received files go to could only be typed.** The Settings surface
reported it (`factReceivedFiles`) as a fact and nothing else, and the dialog
behind the accept flow was a text field. `askForDirectory` had no way to reach
the platform's own folder chooser at all. A destination that can only be typed is
a destination most users cannot set: the path to a folder is not something a
person knows, and a network share is not something they can spell.

## Decision

**The composer claims Ctrl+V, and offers the clipboard to the conversation
first.** `_ComposerField` gains a `PasteIntoComposerIntent` bound to both Ctrl+V
and Cmd+V, so the chord is answered above `TextField`'s own paste rather than
alongside it. `ConversationComposer.onPaste` runs
`_ConversationViewState._pasteIntoComposer`, which reads the clipboard through
the seam below and **returns whether it sent anything** — files first, then a
picture. When that answer is false — no peer, no file, no picture — the field's
ordinary text paste is reproduced by hand in `_pasteText`, selection-replace
rule and all, because claiming the chord is exactly what stopped the framework's
own paste from ever running. A clip holding only text is therefore unchanged;
what is new is that a clip holding a file or a picture becomes a message.

**The clipboard is read through a seam.** `lib/ui/clipboard_paste.dart` defines
`ClipboardPaste` (`files()` → paths, `image()` → encoded bytes) with
`SystemClipboardPaste` over the `pasteboard` plugin and `PasteResolution` as the
substitution point. This is the same shape as `FilePicker`/`PickerResolution`,
and for the same reason: a platform channel cannot answer inside a
`testWidgets` body, so a clipboard the tests cannot replace is a flow the tests
cannot drive. `pasteboard` is the plugin that can see a file and a picture on
Windows (`CF_HDROP` and `CF_DIB`); Flutter's own `Clipboard` cannot.

**A pasted picture is named by its bytes.** A screenshot arrives with no name at
all, so `lib/ui/pasted_image.dart` sniffs PNG/BMP/JPEG/GIF/WebP magic bytes
(`imageExtensionOf`) and writes them to `pasted-<micros>.<ext>` in the temporary
directory (`writePastedImage`). Writing it is what makes it a Transfer: the
engine offers a digest and streams from a path, and an image is not a special
case anywhere below that. The function answers `null` for bytes it cannot draw,
which is the caller's signal that this was not a picture after all — and the
reason it does not fall back to an extension is that a `.png` name on a JPEG's
bytes would only ever produce a bubble that cannot decode.

**The incoming folder becomes a profile preference, and it can be chosen.**
`DeviceProfile.incomingDirectory` — null meaning "the platform's default" — is
persisted (written as an absent key, never as an explicit null) and surfaced as
`LocalTransferController.incomingDirectory` / `setIncomingDirectory`.
`HomeShell` resolves `controller.incomingDirectory ??
seams.defaultIncomingDirectory` **once** and hands that to the three pages, so
"where do received files go" has one answer in the running app. `SettingsPage`
shows it with a hint that says whether a choice has been made, and a "Change…"
button that opens **the same** `askForDirectory` dialog the accept flow uses —
one folder is chosen one way, whether it is being set up in advance or answered
as a file arrives. `_DirectoryDialog` gains a "Choose a folder…" button over
`FilePicker.directory()` (`getDirectoryPath`), which fills the field rather than
committing: the field stays editable for a path no native dialog can reach.

## Alternatives considered

**Leave text pasting to the framework, and handle files and pictures out of
band.** There is no out-of-band hook to use: the chord reaches the focused field,
and the field's paste is text-only. Claiming the chord and reproducing the text
case is the only shape in which both can work.

**Send a pasted picture as bytes rather than writing a temporary file.** A
Transfer reads from a path — offer, digest, sink — and threading raw bytes
through would add a second way to be a Transfer for one caller's benefit. The
file is left behind on purpose: the sender's own bubble points at it.

**Guess an extension when the bytes are not a known image.** A name that lies
about the bytes is worse than no message at all; the bubble would be one that can
only fail to draw, and the failure would arrive far from the cause.

**Resolve the incoming folder inside each page that needs it.** Three pages each
writing `?? default` is three chances to disagree about one setting. The shell
resolves it once and passes a value.

**Make the folder chooser's answer commit immediately, without the dialog.** The
dialog is shared with the accept flow, where the user is in the middle of a
decision; filing the answer into the field keeps one confirmation and keeps the
path editable for the shares a chooser does not show.

**Bump `wireProtocolVersion` for the new payload shapes.** Not bumped, and there
is nothing to bump for: a pasted file travels as a file and a pasted picture as
an image, both of which the wire already carries. Raising the version would
reject peers that work perfectly, trading a display difference for a connection
failure.

## Consequences

**Ctrl+V now means two things, decided by the clipboard.** With a file or a
picture on the clipboard, Ctrl+V sends a message and puts nothing in the box;
with text on it, Ctrl+V pastes into the box as before. That is the behaviour the
request asked for, and it is the one surprising consequence: the same chord does
not always leave the message box changed. The fallback is what keeps the ordinary
case ordinary, and it is the part most likely to break silently — which is why a
test drives a real Ctrl+V over a clipboard holding only text and asserts the text
lands in the box.

**The text-paste path is now the app's code, not the framework's.** `_pasteText`
reimplements `TextField`'s rule (replace the selection, caret after what was
inserted). It has to be kept in step with what a text field does, and it only
runs on the fallback path — so a regression in it is invisible to anyone who only
ever pastes files.

**A pasted image leaves a file in the temporary directory.** Deliberate — the
sender's bubble draws from that path — and it means a session of pasting
screenshots accumulates files the operating system reaps rather than the app. The
name is seeded from the clock with a collision suffix, because two pastes in the
same microsecond would otherwise share a path and the second write would truncate
a file the first Transfer was still streaming.

**`flutter test test_flutter` runs on this machine again, and it was hiding two
latent failures — both fixed in this change.** With the Sangfor loopback
interference cleared, the widget suite runs, and two tests failed for reasons
that have nothing to do with this feature. Both were verified pre-existing by
re-running the **unmodified** test file against HEAD's `conversation_view.dart`
and `home_shell.dart`:

* `two_window_e2e_test.dart` called `tearDown(PickerResolution.reset)` **from
  inside a `testWidgets` body**. `tearDown` declares a hook and only works while
  the suite is still being declared, so the call threw `Bad state: Can't call
  tearDown() once tests have begun running` and failed the test before a single
  line of it ran — the end-to-end file transfer had therefore never actually run.
  It is `addTearDown` now, and the test passes.
* `pages_test.dart`'s "Enter sends and leaves the caret in the box" asserted
  `hasFocus` on the frame the send landed. `_ConversationComposerState._send`
  re-requests focus from a **post-frame callback** — deliberately, so the request
  lands after the frame that rebuilt the field — so the caret arrives one frame
  later. A probe confirmed `hasFocus` becomes true after exactly one more pump.
  The test now waits for the documented behaviour instead of asserting it one
  frame early; the product was never wrong.

## Testing

`test/ui/pasted_image_test.dart` (new, plain Dart — it must be loadable by
`dart test`) pins the magic-byte sniffing for each format, the near-misses that
must not be taken for one, and that `writePastedImage` names the file by what the
bytes are and refuses what it cannot draw.

`test/profile/device_profile_test.dart` pins the incoming folder: unset to begin
with, remembered when set, trimmed, cleared by an empty or whitespace-only
answer, absent from the JSON when unset, decoded as unset when the key is
missing, and preserved by a round trip.

`test_flutter/ui/pages_test.dart` drives the flows the way a person does them. A
file on the clipboard and a screenshot on the clipboard each become a message,
through a **real Ctrl+V** over a `ScriptedClipboard` — the shortcut table is part
of what is asserted, not just what it does. A clipboard holding only text still
pastes into the box and sends nothing. The Settings folder button drives the
platform chooser via `ScriptedPicker` and remembers the answer, and a cancelled
dialog changes nothing.

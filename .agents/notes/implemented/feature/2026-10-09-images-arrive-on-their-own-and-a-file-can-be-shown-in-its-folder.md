# Agent Note: images arrive on their own, and a landed file can be shown in its folder

Status: implemented

## Problem

Two requests, both about the moment after something has crossed the wire.

**「传输接收完毕后，可以右键选择打开所在目录」** — once a file had landed, there
was no way to get to it. The receiver had chosen a folder, watched the progress
bar finish, and then had to go and find the folder themselves. The application
had the path the whole time (`_Tracked.localPath`, and from it
`TransferView.localPath`) and never offered it.

**「图片类发送不需要接收，直接发送后自动接收显示」** — a picture was asked about
exactly like a file. The receiver was shown accept/refuse and a folder dialog
before they saw anything. Text had already been changed to arrive on its own;
an image is the case between the two: it streams bytes and lands on disk like a
file, but the one thing a file's question is *for* — where should this go — is
already answered by this Device's settings, which hold the folder a received
file lands in. Asking anyway is the application forgetting its own setting in
front of the user.

## Decision

**The folder is the deciding fact, and one function states it.** The controller
grew `_landingFor`, which answers where an arriving offer goes, and the four
`PayloadKind`s split three ways:

| kind | `_landingFor` | meaning |
|---|---|---|
| `text` | `''` | accepted inline; the body is in the offer, so it lands nowhere |
| `image` | the profile's chosen folder, else the platform default | filed on arrival |
| `file`, `clipboard` | `null` | the user's question |

`null` is the value that means "ask the user", so `_onOffer` reads the same
function: `null` hands the offer to the UI, `''` calls `_acceptInline`, and any
other path calls `_acceptIntoDefault` — which creates the folder (so "the
pictures go to Downloads/LocalTransfer" is true the first time it is used) and
then takes the ordinary `acceptInto` road.

**The empty string is deliberate, not null.** Text lands *nowhere*: it has no
sink, no bytes, no digest. That is a different fact from "nobody has decided
where it goes", and collapsing the two would make text look like a question
again.

**`_answerableOffer` consults the same rule rather than restating it.** A
`TransferView.offer` is non-null only for something the controller did not
answer itself — a file, or an image on a platform with nowhere to write. The
rule lives once, so a device that has a folder cannot draw a prompt for a
transfer it is already accepting, and a device that has none cannot silently
file a picture into a directory nobody named.

**A platform with no folder keeps its image prompt.** Both the user's chosen
folder and the platform default absent is the honest "nowhere to write" case;
it is resolved by `_landingFor` returning null, and the image waits like a file
rather than failing or being written somewhere untraceable.

**`defaultIncomingDirectory` became a constructor parameter of
`LocalTransferController`.** Where the platform puts received files is a fact
about the platform — the user's Downloads on Windows, the app's private
directory on Android — and `lib/app` may not ask a platform anything. It is
injected from `PlatformSeams` by `lib/ui/app.dart`, exactly as the pages are
already told, and null means "nowhere", which is what the unverified Android
build resolves to.

**"Where is this" is a right-click, and it belongs to the surface the user is
looking at.** A settled Transfer whose file is on this machine offers
打开所在目录 in a context menu — `TransferContextMenu` wraps both a conversation
bubble and a Transfers card, adding a `GestureDetector.onSecondaryTapDown` that
opens `showMenu` at the pointer. An offer's *answers* stay buttons in the open,
because a decision behind a menu is a decision nobody finds; this is the other
kind of action, a thing wanted after the question is over.

**`TransferView.localPath` is the one input.** It is recorded for a received file
when `acceptInto` has written it (so after the bytes are verified and closed,
which is when a received picture first has a path worth drawing), and at once
for a *sent* file and a sent image, because the sender's own file is already
whole on disk. So the reveal works in both directions and on both an image and
a file; the only transfer without an answer is the receiver's still-undecided
file, which is exactly the one with nothing on disk yet.

**The folder is opened, not the file.** `explorer` can highlight one file with
its `/select,` switch, but that switch carries its argument in the same token —
`/select,C:\a b\c.png` — and any launcher that sees a space in an argument
quotes the whole of it, which breaks the pairing. A space in a path is the
ordinary case on Windows, so the reliable half is taken: the folder opens, and
the file is in it.

**Windows only, and it says so.** `SystemRevealer` asks the platform's own shell
(`explorer <folder>`) — the same trade `external_links.dart` makes to open a web
address, rather than buying a native launcher registration for one call — and
answers false anywhere else. The caller shows `cannotOpenFolder` rather than
leaving a menu item that does nothing.

## Alternatives considered

**Auto-accept files too.** The largest version of the request, and rejected: a
file's folder is a real question the arrival raises, and it is the reason the
receiver can say where anything went at all. The whole point of the other half
of this change is that a landed file has an answer to "where is it"; a file
filed without being asked would have no such answer to give.

**Leave images as they were.** Rejected: the question has an answer the Device
already holds. This is the complaint, verbatim — a picture should not raise a
dialog whose only sensible answer is the setting the receiver already made.

**Auto-accept images always, even with no folder.** Rejected: it would file a
picture into a directory nobody named, or fail the transfer outright with
nothing for the user to do about it. Keeping the prompt where there is nowhere
to write is the honest fallback, and it is what makes the feature safe to ship
on a platform whose folder is not yet known.

**A button or toolbar on every message, instead of a right-click.** Rejected: it
puts chrome on every bubble for an action wanted occasionally, and the
conversation is the wrong place to spend a permanent control on "where did that
go". The right-click is the desktop gesture for exactly this question.

**Raise the right-click to the whole conversation rather than the bubble.**
Rejected: the bubble is what the pointer is on and what the file belongs to. A
handler on the surface around it would have to work out which message was meant,
or offer one file's folder from a press that landed on the padding.

**`explorer /select,<file>` to highlight the file itself.** Rejected on the
argument-quoting above: it works for a path without a space and silently opens
the wrong thing for one with a space, which is the more common path.

**A launcher plugin (`url_launcher`, `open_file`, and their relatives).**
Rejected: a *native* registration bought for one call, and one more thing that
has to exist on every platform this build claims. The platform's own shell
already does it.

**Give `RevealResolution` no seam and call `Process.run` directly.** Rejected: a
widget test that drove the real thing would launch an Explorer window on the
machine running the suite — a side effect with no bearing on the assertion, and
one that cannot run on a headless one. The seam is in the shape of
`PickerResolution`, so the test asserts the path it was handed instead.

## Consequences

The wire is untouched. An image already travelled with a digest and a sink;
only *who answers* and *where it goes* moved, and both are local, so
`wireProtocolVersion` is not raised and an older peer keeps working.

The conversation's empty-state sentence now says the rule out loud — text and
images arrive straight away, a file waits for the other Device to accept it —
and `openContainingFolder` and `cannotOpenFolder` join it, in both languages.

Any test that asserts "an image is offered" now has to start the receiving
Device with no default folder, because that is the one configuration in which
it still is. The plain-Dart suite states the fallback explicitly for this
reason.

`RevealResolution` joins `PickerResolution` and `PasteResolution` as a mutable
seam that a test must reset in a `tearDown`; leaving it installed would answer
for the next test.

`_landingFor` is now the single place a new `PayloadKind` is taught what happens
to it: because `_onOffer` and `_answerableOffer` both read it, a kind that
should be filed on arrival needs no second edit anywhere.

## Testing

`test/app/app_controller_test.dart` grows an `an image with somewhere to go`
group. One test asserts a sent picture completes with nobody answering
anything: the receiver holds no offer, its Transfer is `completed` with
`needsDecision` false and no `offer`, and the landed file's bytes match what
was sent, under the sender's name, inside the folder the Device was told about.
A second asserts a folder the *user* chose beats the platform default. In the
transfers group, `an image with nowhere to go is asked about after all` pins the
fallback: with no default folder, the picture is offered like a file.

`test/ui/reveal_test.dart` covers `folderOf` as plain Dart — it names the folder
a file sits in, and refuses a bare name and an empty path, because a path with
no directory part resolves to the process's working directory and opening that
would be opening a folder nobody asked about.

`test_flutter/ui/pages_test.dart` grows a `showing a landed file in its folder`
group. One test right-clicks a received file on the Transfers surface and
asserts the context menu opens and the path it carries is the file that landed;
the other sends a picture to a Device with a default folder, asserts no offer
reaches it, that the conversation draws an `ImageBubble`, and that the bubble's
own right-click reveals the same path. Both install a `ScriptedRevealer`, so
neither opens an Explorer window.

`test_flutter/support/ui_harness.dart` now hands `defaultIncomingDirectory` to
the controller as well as to the seams — the shipping wiring — so a Device under
test answers an image the way the Device a user runs does.

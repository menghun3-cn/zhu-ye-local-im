# Agent Note: A folder spelled with the wrong slash opened Documents

Status: implemented

English | [中文](2026-10-10-a-folder-spelled-with-the-wrong-slash-opened-documents.zh.md)

## Problem

A file arrives, the user right-clicks it and chooses **打开所在目录**, and Explorer
opens the wrong folder — not the folder the file is in, and not with an error
either: it opens the user's Documents. The one action whose whole job is to
answer "where did that go" answers it about somewhere else, silently.

The path is not wrong. `LocalTransferController.acceptInto` records the file the
sink actually wrote (`lib/app/app_controller.dart`), `folderOf` takes the
directory part off it, and a probe against the real shape of a received path
confirms both halves:

```
incoming      = C:\Users\admin/Downloads/LocalTransfer
file          = C:\Users\admin/Downloads/LocalTransfer\WinDirStat (2).exe
parent        = C:\Users\admin/Downloads/LocalTransfer
parent == incoming? true
```

`parent` is the folder the file is in. It is also **spelled with `/`**, and that
is the whole bug: `explorer.exe` parses a `/` inside an argument as the start of
one of its own switches. `/e`, `/select` and `/root` are the documented ones, and
the parse happens before anything is resolved as a path — so
`C:\Users\admin/Downloads/LocalTransfer` is read as the drive `C:` followed by
two switches nobody sent, no path token survives, and Explorer falls back to its
default shell folder. "Documents" is the symptom; a forward slash in an argument
is the cause. It is Explorer's own parser and nothing else's: `open` on macOS,
`xdg-open` on Linux and every code editor on Windows take `/` happily. This is a
known Windows trap, not a guess — a Stack Overflow answer from the Python
`subprocess` world and a GitHub PR fixing exactly this in a Windows desktop app
(`explorer.exe "D:/Projects/x"` → Documents, `explorer.exe "D:\Projects\x"` →
the folder) both describe it in the same terms.

Why this project hands it a `/`-joined folder rather than a Windows one is
deliberate and documented: `defaultIncomingDirectory` joins paths with `/` on
every platform, because it has to answer for Android through the same function
and a function that built separators from the *host's* convention could not do
that. `incomingPathFor` then appends the file name with
`Platform.pathSeparator`, so a received file's path is a real mix — `/` up to the
folder, `\` before the name — and `folderOf` hands the `/` half straight to
Explorer.

Only the default folder was hit in practice (`Downloads/LocalTransfer`), which is
why the sender's side and a hand-typed `D:\inbox` both looked fine: a folder the
user typed with `\` has no slash to misread.

## Decision

The folder is converted where it stops being a Dart string and becomes an
argument to somebody else's parser — one function, at the one call site:

```dart
// lib/ui/reveal.dart
await Process.run('explorer', [explorerArgument(folder)]);

/// The one argument [folder] becomes on `explorer`'s command line.
String explorerArgument(String folder) => folder.replaceAll('/', r'\');
```

Only the argument is converted. The folder itself goes on being the string the
rest of the app uses, because `\` is not a fact about the folder — the same
string is opened by `Directory`, `File` and the pickers on every platform — it
is a fact about Explorer. Doing it here also covers a folder the user typed with
`/` into the accept dialog, which no amount of care in the path builders would
have reached: the conversion is on the road out, after every path in the app has
already been decided.

The test asserts the argument, not a window: `explorerArgument` is pure Dart, so
`test/ui/reveal_test.dart` pins the regression end to end — a received file's
whole path in, a backslash folder out — alongside the two trivial cases (a
`/`-spelled folder is converted, a Windows-spelled one is untouched).

## Alternatives considered

**Build the folder with `Platform.pathSeparator` in `defaultIncomingDirectory`.**
Rejected: that function takes `platform` as an *input* and is tested for Android
and Windows without running on either, so it cannot ask the host anything. Its
callers need one answer per platform, not one answer per machine.

**Normalise in `incomingPathFor`.** Considered — it would have fixed the observed
case, since the received path would become fully native. Rejected as the *only*
fix for two reasons: it does nothing for a folder the user typed with `/` into
the accept dialog, and it would leave the rule living in a function that builds
names rather than at the boundary that needs it. A mixed-separator path is
harmless to every consumer this app has *except* Explorer, so the exception is
what should be local, not the path.

**Convert inside `folderOf`.** Rejected: `folderOf` answers *which* folder, and
its answer is tested as a plain string on any platform. Making it hand back a
Windows-spelled path would fold a fact about one shell's parser into a function
that has nothing to do with that shell.

**Highlight the file with `explorer /select,<file>` while we are here.**
Rejected, unchanged from the decision recorded in
`2026-10-09-images-arrive-on-their-own-and-a-file-can-be-shown-in-its-folder`:
the switch and its argument share one token, so a path with a space in it needs
the whole token quoted, and it is the ordinary case on Windows. Worth noting that
the switch parsing above is the same root cause looked at from the other side:
`/select,` is a switch Explorer is *meant* to receive, and a bare path's `/` is
one it was never meant to see.

**Open the folder through `cmd /c start`, as `external_links.dart` does for a
URL.** Rejected: that trades Explorer's parser for `cmd`'s, and `cmd` brings its
own quoting hazards (`&`, `^`, spaces) to a path that is partly peer-influenced
by way of the file name. `explorer <folder>` has nothing to quote and nothing to
escape once the slashes are right.

## Consequences

- **打开所在目录** on a received file now opens the folder the file is in — the
  default `Downloads\LocalTransfer` included, which is the case that was broken.
- A folder the user typed with `/` into the accept dialog works too, because the
  conversion happens after their answer rather than before it.
- `folderOf` and the sent-file path are untouched, so nothing about *which*
  folder is answered changes: only how it is spelled for the one program that
  cannot read it.
- Sending the wrong separator to another program is now a thing the project has
  a name for (`explorerArgument`) and a test for, rather than a hazard that lives
  in nobody's head — the previous decision to avoid `/select,` was recorded
  without knowing that Explorer reads `/` as a switch at all.
- Plain Dart only: `dart test` covers the new function, and the reveal seam in
  `test_flutter` still stands in for the whole revealer, so the suite's
  `ScriptedRevealer` assertions are unaffected.

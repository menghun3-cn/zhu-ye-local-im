# Agent Note: The first run of a gate that could not run, and the nine expectations it had been carrying

Status: implemented

English | [中文](2026-10-12-the-tests-that-had-never-run.zh.md)

## Problem

[`2026-09-29-dart-test-as-the-core-gate.md`](2026-09-29-dart-test-as-the-core-gate.md)
records a long stretch in which `flutter test` could not execute on this machine
at all — the Sangfor aTrust client broke every loopback WebSocket handshake, so
each file failed while loading. `dart test` kept working, and it was made the
gate that can always be run. Widget tests were written anyway, under
`test_flutter/`, type-checked by `flutter analyze` on every change.

The cost of that arrangement was not the missing runner. It was that **eight
widget expectations and one source-reading assertion were written, reviewed,
merged and treated as coverage without ever having been executed.** A green
`analyze` was read as "the widget suite passes" often enough that it stopped
being read as "it compiles" — the distinction the earlier note warned about.

On 2026-10-12 the widget runner worked again, and the first real run reported
`+105 -8`. `dart test` reported one failure of its own. None of the nine was a
product defect. Each was a test that had never been told it was wrong:

| Where | What it asserted | What was actually true |
| --- | --- | --- |
| `test/platform/android_bridge_test.dart` | the channel named by **the first** `MethodChannel(` in `seams.dart` | that stopped being the paths channel when the host shell added one above it in PR #47. Kotlin says `…/paths`; the test read `…/host` |
| `test_flutter/ui/shell_test.dart` | the light palette on the frame `themeMode` flips to light | `MaterialApp` cross-fades one theme into the next, so that frame still carries the palette it is coming *from* |
| `test_flutter/ui/pages_test.dart` (settings) | 「一切正常。」, the last line on the Settings surface | the surface is a `ListView`; at 800 px the line is below the fold and had never been *built*, so `find.text` matched nothing |
| `test_flutter/ui/pages_test.dart` (a picked picture) | the picture's name as a `Text` in the composer | a picture is drawn as a thumbnail of its own bytes; the name lives on its tooltip |
| `test_flutter/ui/pages_test.dart` (a mixed selection) | the two Transfers in the order they were chosen | `controller.transfers` reads **newest first**, because that is how the conversation draws it |
| `test_flutter/ui/window_settings_test.dart` ×2 | the label and the hint *after* a radio or a switch was tapped | `pumpUntil` pumps only while its condition is still false, so a condition a tap satisfies synchronously was observed with the tree a frame behind the tap |
| `test_flutter/ui/composer_attachment_test.dart` | that the tray shows the broken-picture glyph, after a 200 ms sleep | 200 ms of real time is a guess; the decode had not answered yet. Its teardown also deleted a file a decoded picture still had mapped, which Windows refuses |

The last two are the interesting ones, because they are not one test's mistake.
They are gaps in the harness that every test after them would have inherited.

## Decision

**A wait has to draw a frame before it can be believed.** `pumpUntil` now pumps
once more after its condition holds. Its loop only runs while the condition is
false, so a condition that a tap satisfies on the way into
`onSelectionChanged` — a `SegmentedButton`, a `SwitchListTile` — was reported
with the window still showing the frame from before the tap. The helper's
promise is "the window shows it", not "the condition is true", and the two had
drifted apart.

**Seeing a whole page is a window size, not a scroll.** `tallWindow` moved into
the harness beside `wideWindow` and `narrowWindow`, and the settings test that
asserts the bottom of the page uses it. The page is a lazy list, so a line below
the fold has not been built; a test that scrolled to it would be testing the
scroll as much as the line.

**A decode is waited for, not slept at.** `letDecodeSettle` waits for the
thumbnail to have answered — with pixels, or with the glyph `errorBuilder`
substitutes when the bytes cannot be decoded — instead of sleeping a fixed
200 ms. Sleeping cannot distinguish "slow" from "the codec was never going to
finish", and the second is the bug worth catching.

**A decoded picture maps its file, so its cleanup is best-effort.**
`pngFixture` now writes through `tempDirectory`, which already swallows the
delete Windows refuses while a mapped file is open, for the same reason and with
the same reasoning that helper already documents.

**A source-reading assertion is anchored to the declaration it means.**
`android_bridge_test.dart` reads the string out of
`defaultPathsChannel = MethodChannel(…)` rather than taking whichever channel
happens to be nearest the top of the file. A first-match regex over a file that
grew a second declaration is a test that silently changes subject.

The rule this leaves behind: **an expectation that has never executed is not
evidence.** After any stretch in which a gate could not run, the first job of
that gate is to re-read what it was told, and the first job of whoever is
reading the result is to remember that the assertions in it were written blind.

## Alternatives considered

**Delete the assertions that turned out to be hard to satisfy.** Rejected: every
one of them was about real behaviour — the palette each theme resolves to, the
last line on the settings page, the order two attachments are sent in, the glyph
a broken staging shows. Deleting them would have removed the coverage rather than
the mistake, and left the same class of mistake available.

**Loosen them instead — `findsWidgets` for the settings line, a set of kinds for
the attachment order.** Rejected: it would have made the failures disappear while
leaving every claim weaker than the one being made. `{image, file}` does not say
the picture goes as a picture and the file as a file *in the order chosen*, which
is what the test exists to pin.

**Fix the harness and leave the individual tests.** Rejected: five of the nine
were one-off mistakes in the test in front of them, and a harness fix would have
hidden them behind a green run.

**Keep the 200 ms sleep and raise it.** Rejected: any number is a guess about
this machine, and the test would keep passing on a machine where the decode never
answers at all — which is the one outcome it is meant to catch.

**Make the Settings surface a `Column` inside a `SingleChildScrollView` so every
line is always built.** Rejected: the Notices card renders up to twenty entries,
and a surface that builds what a user cannot see is a surface that gets slower as
its input grows. The laziness is right; the test was looking at the wrong size.

**Have the settings test scroll to the line it is asking about.** Rejected for
the same reason the existing window-settings tests took a tall window: the claim
is about what the page reports, and a scroll would put the scroll's behaviour
into the assertion as well.

## Consequences

- **The gate is green for the first time as a whole**: `dart test` passes 485
  cases and `flutter test test_flutter` passes 120. Both are totals that a reader
  can compare against the next run; neither existed before today.
- Every wait in the widget suite now costs one extra frame. That is the price of
  the helper being able to say what it means, and 16 ms is below anything a test
  in this suite observes.
- **One flaky test is left in place and known.**
  `test/app/app_controller_test.dart`, "a copy travels to a peer that mirrors",
  waits up to 10 s for a mirrored entry to land over a real socket. It failed
  once during a full-suite run and passes three times out of three on its own,
  in under a second. It is timing under load rather than a defect, and it is
  recorded here rather than papered over with a longer timeout, so that a red
  `dart test` naming that test is read as "the machine was busy" and not as a
  clipboard regression.
- The source-reading pattern in `test/platform/` is now explicitly coupled to a
  declaration name, not to a file's shape. Renaming `defaultPathsChannel`
  fails that test loudly, which is the intended behaviour: the failure names the
  channel Dart asks for, and the reader can see it is a real one.
- The widget suite is the third thing this project has measured only after it
  worked — after `ControllerScope` was found by the suite's own first run, and
  after the portable package's probes were found to be looking for a sentence
  that had been deleted. Expectations are cheap to write and expensive to have
  written blind.

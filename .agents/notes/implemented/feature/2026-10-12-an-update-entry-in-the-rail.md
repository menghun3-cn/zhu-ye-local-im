# Agent Note: An update entry pinned under the rail

Status: implemented

## Problem

The application knew about newer releases and told nobody. The only surface that
could find out was the About card, and only after the user pressed 检查更新 —
so a person who never opened About never learned that a newer build existed,
which is the one fact this application could have volunteered and did not.

That was not an oversight. `update_check.dart` said so in as many words: the
checker is *"asked only when the user presses the button — never at startup, and
never on a timer"*, and the reason was the promise the About text makes — that
everything this application does happens inside the local network. So the
requirement could not be met by adding a button somewhere. It could only be met
by either breaking that promise quietly or amending it out loud, and a promise
kept quietly is not a promise.

Three things had to be decided together, because they constrain each other: how
often the question may be asked, where the answer lives, and how a rail that
holds six surfaces makes room for something that is not one.

## Decision

**One silent question, at launch, and never again on its own.** `UpdateNotice`
asks once, `_LocalTransferAppState.initState` starts it un-awaited, and a timer
or a re-ask on visiting a page stays forbidden. The About card's button still
asks on demand. Two requests per run at the very most, and the one that nobody
asked for carries nothing about this Device.

**The answer lives in a `ChangeNotifier` the application owns.** It is built in
`_LocalTransferAppState` — not by the shell, because the shell is rebuilt on
every controller change and a notice made there would re-ask GitHub on each one
— and handed to `HomeShell` as a constructor argument. It is nullable, and that
is the point rather than an accident: a tree assembled without one (which is
what every widget test that is not about updates builds) has no entry and asks
nothing.

**One checker, two askers.** The notice asks through `UpdateResolution.checker`,
the same seam the About card reads, rather than through a checker of its own. Two
ways to ask would be two things for a test to stand in for and two answers that
could disagree on one screen.

**The rail's `trailing`, pinned to the bottom.** `NavigationRail(trailingAtBottom:
true, trailing: …)`. Not a seventh destination: a destination is a place in the
app and this one leaves it for a browser, and a seventh entry in the middle of
the list would move every tab below it the day an eighth surface arrives.

**Drawn only when there is something to fetch.** No entry while the question is
out, and none when the answer is "you are up to date" or "the question could not
be asked". A rail is a map of where things are; an entry that is usually a
no-op is noise on it.

**The version number rides on the tooltip.** The label is one word — `railUpdate`,
「更新」 — and `Tooltip` carries `l10n.aboutUpdateAvailable(version)`, the same
sentence the About card already uses for the same fact. A second spelling of one
version number is a second place for the two to drift apart.

**Pressing it opens the release the answer named**, falling back to
`updateReleasesPage` when the response named no page, which is the same fallback
the About card makes. Opening a web address is now behind `LinkOpener` /
`LinkResolution`, mirroring `Revealer`: it hands over to the operating system's
shell, so a widget test that drove the real one would start a browser on the
machine running the suite and never come back.

**The About text was amended, and the amendment is the deliverable.** It used to
say 「以上一切都只在本网络内」. It now says that every transfer stays inside the
network and names the one exception: a single question to GitHub at startup about
the version it has published, carrying no content. If that sentence is ever wrong
again, the bug is in the code and not in the documentation.

## Testing

`test_flutter/ui/update_rail_test.dart` covers the entry: absent while this build
is the latest, absent when the question could not be asked, below the first and
last of the six destinations rather than among them, carrying the newer version
in a tooltip that a hover actually puts on screen, opening the address the answer
named when pressed, falling back to the download page when it named none, and
absent in a window with no rail at all.

The two seams that make it assertable are in the harness: `ScriptedUpdateChecker`
(the question would otherwise leave a real request behind) and `ScriptedLinkOpener`
(the press would otherwise start a browser). `app_tree_test.dart` now installs
the first for the same reason it already installs a recorded host shell, and
`about_page_test.dart` uses it in place of its own private double — one scripted
checker for the suite instead of two.

## Alternatives considered

**A seventh `NavigationRailDestination`.** Rejected: it would be selectable, so
`selectedIndex` would need a value that means "no surface", and it would be drawn
among the tabs rather than under them — which is the opposite of the requirement
and would move every existing tab the day another surface is added.

**Putting the check on `LocalTransferController`.** Rejected on a layering rule
this project enforces with a test: `lib/app` may not import `lib/ui`, and
`UpdateChecker` lives in `lib/ui`. Moving the interface down would have been the
only way, and it would have bought a shared `changes` stream at the price of
making the controller's subject — Devices, Sessions, Transfers — include GitHub
releases.

**An `InheritedWidget` scope for the notice.** Rejected: exactly one widget reads
it. `ControllerScope` exists because a dozen widgets across two trees read the
controller; a scope for a single reader is a third lifetime to reason about, and
it would have had to be installed by the test harness too, since the harness
builds the shell directly.

**A permanent entry, reading 已是最新版本 when there is nothing newer.**
Rejected: that turns a rail whose whole job is to say where things are into a
permanent question mark, and the answer "nothing to do here" is not a place.

**A coloured dot or badge instead of the word.** Rejected: an unlabelled dot in a
rail is the first thing a user learns to ignore, and the requirement asks for a
button reading 更新.

**Checking on a timer, or whenever a page is opened.** Rejected: that is the
promise being broken quietly rather than deliberately. One request per run is
defensible in a sentence; one per visit is not.

**A setting to turn the check off.** Rejected for now: a switch that has to be
found before this application behaves the way its own About text describes is a
worse bargain than one named exception. It is the obvious next step if anybody
asks for it, and `UpdateNotice` is the single place it would touch.

**Leaving the About text alone.** Rejected: it would have been false the moment
this shipped.

## Consequences

**Bought.** An available update is announced without the user having to go and
ask, the asking happens once per run, and the About button still re-asks on
demand for anybody who wants a fresh answer. The entry cannot be confused with a
surface because it is not one.

**The promise now has an exception, and it is written down.** In the About text,
in `update_check.dart`, in `about_page.dart` and here. Every future feature that
wants to reach outwards inherits the burden of naming itself in the About text —
which is the point of writing it there rather than in a doc.

**A window with no rail has no entry.** A narrow window swaps the rail for a
bottom bar, and 「左侧菜单栏最下方」 has no left menu bar to be at the bottom of.
The About card remains the way to check from there. Asserted in the test suite so
that it stays a decision rather than becoming a surprise.

**The notice is asked with nobody waiting on it.** `UpdateNotice.check` catches
and answers `UpdateCheck.unreachable`, which is a value the interface already
has. This is for the call site rather than for the checker: a future checker that
broke the contract would otherwise surface as an unhandled asynchronous error
instead of as the state that exists to describe it.

**One more thing a widget test has to set up.** Any test that pumps
`LocalTransferApp` — or a shell holding a notice — now needs an answer, because
the question is asked on start rather than on a press. `ScriptedUpdateChecker`
is the way, and the two test files that needed it say why in place.

**None of the new widget tests has ever been run.** `flutter test test_flutter`
cannot start on the machine this was written on: Dart cannot spawn a child
process there at all (`ERROR_PIPE_BUSY` on any piped stdio, from a third-party
network hook), so the widget suite, `dart test`, `flutter analyze` and the
packaging script are all unavailable. The seven tests above are statically
checked — `dart format`, and an in-process `package:analyzer` pass reporting zero
errors and zero warnings — and nothing more. Running them is the first thing to
do on a working toolchain.

**The version number and the release pipeline are not in this change.**
`appVersion` is still `1.0.0`; dropping it to `0.1.0` and the tag-triggered
pipeline are the next two changes, and the entry this adds will not light up
until the first release is actually published.

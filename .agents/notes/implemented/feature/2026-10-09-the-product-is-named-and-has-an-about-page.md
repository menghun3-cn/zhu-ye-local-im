# Agent Note: the product is named, and it has an About page

Status: implemented

## Problem

`local_transfer` was a description, not a name. It reached the user in three
places that had to be kept in step by hand — the string the Flutter shell renders
(`l10n.appTitle`), the Windows window title created in `windows/runner/main.cpp`,
and the executable's `FileDescription` and `ProductName` in
`windows/runner/Runner.rc` — plus the packaging note. The request was a name of
its own: 竹叶局域网传输. A rename is only ever as complete as its least obvious
copy, so the work was finding the copies rather than writing the string.

The shell also opened with an `AppBar` that did no work. It carried the
application's name a *second* time, under a window title bar that already shows
it, and beside it this Device's own name, its platform icon, and an "unpaired"
marker. None of the three is a fact about the page being looked at: all three
are facts about *this Device*, and the Devices surface already states every one
of them, in more detail, one tab away. A strip of chrome that repeats the window
title and duplicates another page's content is a strip that can go.

And there was nowhere to answer "which build is this, and how would I get a
newer one". This program has no updater and is not meant to grow one — it ships
no backend and its promise is to stay inside the local network — but a person
handed a zip by a colleague has a fair question about the version, and nothing
in the application answered it.

## Decision

**The name lives where the platform reads it, and nowhere else invents it.**
`l10n.appTitle` holds 竹叶局域网传输 for both languages (`appTitle` is a proper
noun and is not translated), the runner's window title and its resource strings
carry the same characters, and the packaging note opens with them. The
executable's *filename* stays `local_transfer.exe`: it is not user-visible
except to somebody who went looking in the folder, and the packaging script and
its smoke test both key off that name, so changing it would buy nothing and
break the pipeline that proves the package works.

**The `AppBar` is removed, not trimmed.** The temptation was to keep the bar and
drop one of its three items, but each item is either a duplicate of the window
title or a duplicate of the Devices surface, so there was nothing to keep. With
no `AppBar` the body is the whole window, which is also what the six surfaces
wanted: every page already draws its own `SectionHeader`, and a second title
line above the first was one title line too many. The `notPairedYet` string,
which existed only for the bar's tooltip, is removed with it.

**About is a surface of its own, not a Settings section.** It is the one page
whose subject is the *program* rather than this Device or this network, and it
is the only page that ever talks to the outside world, so it is the last thing
that should be folded in beside "where do received files go". It becomes the
sixth destination on the navigation rail, after Settings.

**Nothing leaves the machine until the user presses 检查更新.** The page shows
the version (`appVersion`, read from a constant kept honest against
`pubspec.yaml` by a test) and a paragraph of how to upgrade by hand, which works
with no network at all. Only the button asks GitHub, and only when pressed —
never at startup, never on a timer. An application whose whole claim is that it
stays on the local network must not quietly open a socket to GitHub the moment a
page is opened.

**The update question is asked of a repository, and every answer is a noun.** A
`GitHubUpdateChecker` asks
`api.github.com/repos/menghun3-cn/zhu-ye-local-im/releases/latest`. Its answer
is one of `upToDate`, `available`, `noRelease`, `unreachable` — four names, not
a sentence, because turning an outcome into words belongs to the layer that
knows what language the reader reads. `noRelease` and `unreachable` are kept
apart because they are different things to tell a person: "there is nothing
published to compare against yet" and "the question did not get through" send
them to different places.

## Alternatives considered

**Use `package_info_plus` to read the version off the platform.** It is the
normal way to learn a build's version, and it is a *native* plugin registration
bought to read back one string that the source already contains. `appVersion`
is a constant in `lib/app/app_version.dart`, and `test/app/app_version_test.dart`
reads `pubspec.yaml` and fails the build if the two drift — which is the whole of
what the plugin would have bought, without a native dependency.

**Use `url_launcher` to open the download page.** Same trade: a native
registration for one call. `openInBrowser` asks the platform's own shell
(`cmd /c start "" <url>`) on Windows instead, and refuses anything that is not an
`https` address on `github.com` before it goes near a shell — the address
normally comes from a GitHub response, but a shell is a shell, and the check is
what stops a crafted one being read as further commands.

**Auto-download and install the newer build.** The largest version of the
request, and rejected: writing and launching an installer is a native,
platform-specific, security-sensitive capability, and this program has no
signing story. The About page hands the user a link; installing stays a thing a
person does.

**Keep a short "unpaired" chip in a corner instead of the whole bar.** It would
preserve the one signal the bar carried that nothing else shows as loudly. It
lost to the Devices surface already stating pairing explicitly, and to the bar's
cost: a permanent strip of window spent on a fact that changes twice in a
lifetime.

**Show the update answer as a sentence built in the checker.** Fewer moving
parts. Rejected because the checker is in the Flutter-free part of the tree and
must not know about language; `describeUpdateCheck` in `labels.dart` is where an
outcome becomes the user's words.

## Consequences

The application's name is now a proper noun in both languages, so `appTitle` is
no longer something a translator should touch, and the packaging note and the
window title agree with it.

Six surfaces are now `IndexedStack` children where there were five, and the
navigation rail and bar both grow a destination; anywhere that asserted "five
surfaces" or listed the tab labels is updated to six.

`AboutPage` is the only surface that holds network state and the only one whose
button is inert while a request is out. `UpdateResolution.checker` is a mutable
seam in the shape of `PickerResolution`, so a widget test drives every branch of
the page — including `available` — without a socket, and `UpdateResolution.reset`
restores the real checker in `tearDown`.

A build with no route out now has a button that says so rather than a page that
hangs: the checker's own timeout is eight seconds and it turns every failure —
timeout, DNS, a proxy refusing the `CONNECT` — into `unreachable`, because which
exception it was never changes what there is to do about it.

## Testing

`test/app/app_version_test.dart` reads `pubspec.yaml` and asserts that
`appVersion` matches its `version:` with the build number dropped, so the
displayed version cannot drift from the one the file was built as; it also pins
`isNewerVersion` against a leading `v`, a `-rc` suffix and a missing component.

`test_flutter/ui/about_page_test.dart` installs a `_StubUpdateChecker` through
`UpdateResolution` and drives the page through every outcome. It asserts that
nothing is asked until the button is pressed (the stub records that it was
called), that `available` reveals the download link and its address, that
`noRelease` and `unreachable` each produce their own sentence, and that the
how-to-upgrade paragraph is on screen in every state.

`test_flutter/ui/shell_test.dart` asserts the shell puts *no* `AppBar` above the
surfaces and that the application's name is not rendered as chrome, while this
Device's name is still reachable on the Devices surface — the two halves of "the
bar went, the facts stayed". Its navigation-label test now lists six surfaces,
with 关于 among them.

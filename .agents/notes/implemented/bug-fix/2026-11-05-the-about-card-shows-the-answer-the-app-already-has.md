# Agent Note: The About card shows the answer the app already has

Status: implemented

English | [中文](2026-11-05-the-about-card-shows-the-answer-the-app-already-has.zh.md)

## Problem

The application asks GitHub once as it comes up — `UpdateNotice` holds that
answer all run — and the My card's About summary already reads it: with a newer
build published, the card says 「有新版本」 and names the version. But the page
behind the card did not. `AboutPage` kept its own `_answer`, which stayed null
until its button was pressed or the rail's install entry arrived, so a user who
followed the card's own hint to find out what the new version was met
「检查更新」 — the same question, asked a second time, on the one surface whose
whole job is to answer it.

The gap was deliberate once: `offeredUpdate` was adopted only when an install
request arrived, which kept the card silent until somebody asked it something.
That rule made sense when the notice's answer was used for exactly one thing —
starting an install — and stopped making sense the moment the My card started
*displaying* it: the summary and the page disagreed about a fact both of them
already knew.

## Decision

`AboutPage` mirrors `offeredUpdate` until it has an answer of its own.
`_adoptOffered()` runs from `initState` and `didUpdateWidget`, covers both ways
the offered answer can change — the page built after the notice already
answered, and the notice answering or re-answering while the page is open — and
assigns rather than calling `setState`, because both call sites run inside a
build.

Mirroring continues while `_mirroring` is true: a newer answer the notice
brings — the hourly re-check — replaces what is on screen, so the version this
card offers to install is the version the rail's entry would install. The
page's own check (`_check`) or an install ends the mirroring, after which a
notice answer arriving later must not rewrite what a download is running
against. Adoption is skipped while a question is out or a download is in
flight, and a fetched package is discarded only when the newly shown answer
names a different version — the hourly re-check hands a new `UpdateCheck` for
the same release, and throwing away the download for that would make "answer
no, then yes later" pay for the fetch twice.

Showing the answer asks nothing: the question was already asked, once, by the
application. The page's promise is unchanged — it still never reaches outside
the local network on arrival.

`MyPage` hands the notice's answer down live: both the About card's summary and
the About sub-page are wrapped in a `ListenableBuilder` on the `UpdateNotice`,
so an answer that lands while either is on screen appears without waiting for
an unrelated rebuild. Before this, the summary itself could stay stale — the
shell rebuilds the page for its own reasons, not the notice's.

The same repair exposed a second dropped request. The rail's update entry
counts presses into `installRequest`, which `AboutPage.didUpdateWidget` used to
answer — but the card only exists while its My sub-page is open, so a press
that arrived with the card list showing met nothing and was lost; the request
is now held by `MyPage` as `_pendingInstallRequest` and handed down only while
unacknowledged, which `AboutPage.onInstallRequestHandled` reports back. A card
mounted after the press answers it from `initState` on the next frame, and the
count returning to zero is the acknowledgement landing, not a second press.

The same code serves Windows and Android: the rail entry is wide-window only,
but the My → About path is identical on both, so the fix covers both platforms
at once. On Android the mirrored answer is also what makes the 「更新」 button
offer the system-installer flow for the version the summary named.

`test_flutter/support/ui_harness.dart`'s `openMyCard` was repaired in the same
change: it still looked for a 「查看详情」 button the My page stopped rendering
when cards became whole-card taps, which had left every test that opens a My
card failing on `develop`.

## Alternatives considered

**Ask again on arrival.** Rejected: it would turn one deliberate request per
run into one per visit, which is exactly what the page's own documentation
forbids — and it would answer a question that already has an answer.

**Adopt the offered answer once, in `initState` only.** Rejected: an answer
that lands after the page opened — the startup check finishing while the user
is already on the card — would never appear, and a newer answer the hourly
re-check finds would leave the card offering to install a stale version.

**Mirror the notice forever, even after the page asked.** Rejected: once the
page's own check or an install has run, its answer is the fresher fact, and a
notice answer arriving later must not rewrite what a download is carrying out.

**Show only `UpdateOutcome.available`, keep silent for the other three.**
Rejected: `upToDate`, `noRelease` and `unreachable` are answers too, and the
card saying 「已是最新」 or 「无法检查」 from the check the app already ran is
more honest than a button that implies nothing is known. The My card's summary
still surfaces only the available case, which is the only one worth a hint.

## Consequences

- `lib/ui/pages/about_page.dart`: `_mirroring` flag and `_adoptOffered()`;
  `initState`/`didUpdateWidget` adopt the offered answer; `_check` ends
  mirroring; doc comments updated to say the card mirrors rather than waits.
- `lib/ui/pages/my_page.dart`: the About card summary and the About sub-page
  listen to the `UpdateNotice`; `_pendingInstallRequest` holds a rail press
  until the card acknowledges it; new `_aboutCard`/`_aboutPage`/`_aboutPageWith`
  helpers.
- `lib/ui/pages/about_page.dart`: `onInstallRequestHandled` acknowledges a
  press from `didUpdateWidget` or, for a card mounted after it, from
  `initState`; only an increasing `installRequest` counts as a press.
- `test_flutter/ui/about_page_test.dart`: `show` takes `offeredUpdate`; new
  tests cover showing a known answer without asking, adopting a late answer,
  and keeping the page's own answer over a later offered one.
- `test_flutter/ui/update_rail_test.dart`: new test opens My → About with a
  known newer build and asserts the version, the install button, and no
  「检查更新」.
- `test_flutter/support/ui_harness.dart`: `openMyCard` taps the card itself.

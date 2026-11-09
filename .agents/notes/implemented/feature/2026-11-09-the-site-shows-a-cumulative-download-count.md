# Agent Note: The site shows a cumulative download count

Status: implemented

## Problem

The site is a pure-static GitHub Pages bundle with no backend, and its only
data source is the public GitHub REST API. Download numbers existed — GitHub
counts every release asset's `download_count` — but they were buried on the
Releases pages, invisible to a visitor deciding whether to download. The
request was to surface one cumulative number on the landing page.

The site deliberately carries no analytics ("不做埋点、不读 Cookie"), so the
count has to come from data GitHub already publishes, not from tracking the
visitor.

## Decision

`site/app.js` already fetches `releases/latest` to fill the download links. A
second, independent fetch walks `GET /repos/{repo}/releases?per_page=100&page=N`
until a page comes back short (capped at 10 pages), sums `download_count`
over **every asset of every release**, and writes the total into a
`#heroDownloads` span inside the hero's `hero__meta` row in `index.html`.
The element stays `hidden` until the fetch succeeds, so offline visitors,
rate-limited responses, and a repository with no releases see nothing rather
than a misleading `0`.

Two properties fall out of summing the raw asset list instead of matching
known suffixes:

- **Future platforms count automatically.** A Linux, macOS, or iOS asset is
  just another entry in `assets[]`; no site code changes when one ships.
- **The `-latest-` alias assets count too.** Each alias is a separately
  downloadable file with its own `download_count`, and downloads through it
  (the fixed-address LAN pulls) are real downloads. Excluding them would
  under-report; the alias and the versioned asset are never the same file,
  so there is no literal double-count of one event.

The count is per-asset, which is GitHub's real completion number — closer to
"downloads" than a click beacon would be — at the cost of one extra API
request per page view. Unauthenticated calls are rate-limited per visitor IP
(60/hour), which a single request per visit never approaches.

## Alternatives considered

**Show per-asset counts on each download card.** Rejected for this request:
the ask was one cumulative number as social proof near the primary CTA. The
per-release `download_count` is still available on each asset object if a
later change wants it.

**Third-party analytics (Umami, GoatCounter) or a counting redirect.**
Rejected: both measure clicks, not completed downloads; the former breaks
the site's no-third-party-script stance, the latter needs a backend the
project does not have. Reading GitHub's own counter needs neither.

**Bake the number in at build/deploy time.** Rejected: Pages deploys are
triggered by merges to `master`, not by downloads, so a baked figure would
be stale between releases and would need a scheduled workflow to stay
fresh — machinery for a number one client-side fetch already gets live.

**Use the Traffic API.** Rejected: `/traffic/*` exposes clones and page
views, not release-asset downloads.

## Consequences

**Bought.** Visitors see a live cumulative figure next to the download
button; the number counts real completed downloads on GitHub's side; new
platform assets are included with zero code changes; and the site still
ships no tracking of its own.

**One more request per visit.** Each page view now issues two GitHub API
calls (`releases/latest` plus the paginated list). Both are anonymous and
cached by the browser only per session; GitHub's `ETag`/rate-limit headers
apply as usual.

**The figure can tick backwards in appearance.** GitHub's counters are not
real-time and assets can be deleted or a release replaced, so the displayed
total may occasionally decrease — acceptable for a decorative stat, which is
why failure hides the element instead of showing `0`.

**Alias downloads inflate the total relative to "installs".** A LAN script
pulling the `-latest-` alias and a user downloading the versioned asset are
two events; the sum counts both. That matches "downloads", not "unique
installs" — the label says 累计下载, not 安装量.

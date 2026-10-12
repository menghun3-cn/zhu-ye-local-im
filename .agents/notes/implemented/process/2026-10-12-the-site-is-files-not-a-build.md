# Agent Note: The site is files, not a build

Status: implemented

## Problem

The project needed a place that answers "what is this, how do I install it, what
will bite me after I do" without making a reader clone a repository first. The
request was explicit: a `site/` directory holding the pages, published to GitHub
Pages automatically.

The obvious implementation is the one this repository would have resented. Every
other deliverable here is reproducible and checkable — `scripts/*.ps1` build the
packages, `test/` and `test_flutter/` measure the source tree, `release.yml`
produces the artifacts from a tag. A site that needs `npm ci && npm run build`
before it can be looked at would add a fourth toolchain that runs on one machine
and not another, for a page whose entire content is prose.

## Decision

**`site/` is three files and nothing else.** `index.html`, `styles.css`,
`app.js`. No build step, no bundler, no package manager, no third-party script
or font loaded at runtime — so `upload-pages-artifact` uploads the directory
as-is and the workflow contains no compile action at all.

- **The design language is borrowed, not re-invented.** The tokens come from
  `design-preview/styles.css` — the same brand green, the same hairline borders,
  the same type scale, the same `reveal` choreography. Only the layout layer is
  new, because that file is an application mock rather than a marketing page.
  Changing a colour now means changing it in both, which §6.3 of `AGENTS.md`
  says out loud.
- **Deployment is `master`-only** (`push` filtered to `site/**`, plus
  `workflow_dispatch`). By §2.2 `master` is production; the site describes what
  users can actually download, so it follows a release rather than leading one.
  `workflow_dispatch` exists so a typo does not require a version bump.
- **The download buttons degrade instead of breaking.** They ship pointing at
  `releases/latest`; when the GitHub API answers, `app.js` swaps in the exact
  asset from the newest release and fills in its real filename. Offline, rate
  limited, or before the first release exists, the page keeps working with the
  link it already had. A page whose only job is to hand out downloads must not
  be able to hand out a dead one.
- **Theme follows the system first, and the choice is remembered second.** An
  inline script in `<head>` sets `data-theme` before first paint (a localStorage
  read that fails in private mode is caught and ignored), so there is no flash
  of the wrong theme; the toggle then persists an explicit choice.

## Testing

- Both workflows parse under `package:yaml` (`pages.yml`, `release.yml`, 0
  failures) — a workflow that does not parse is a workflow that never runs, and
  GitHub only says so in the Actions tab, after the push.
- The page has no automated test; it is static markup with no logic worth
  pinning beyond what the browser preview shows.
- `pages.yml` has **not** been run locally, and cannot be: it is GitHub's
  runner that uploads an artifact and GitHub's Pages service that serves it.
  The first real run is the first push to `master` that touches `site/**`.

## Alternatives considered

**Publishing from a branch (`gh-pages`, or `docs/`).** Rejected: it makes a
second copy of the site the source of truth, and the two drift the first time
someone edits the deployed one. Actions deployment keeps `site/` as the only
place the site exists.

**A static site generator (Hugo, Eleventy, Astro).** Rejected: a generator buys
templating and content collections for a single page that has neither. It would
also make "look at the site" require the toolchain, which is exactly the
property the rest of this repository works to avoid.

**Fetching the whole page from the GitHub API.** Rejected: the prose is static
and must not depend on a network call, a rate limit, or GitHub being up. Only
the version number and the three asset links are dynamic, because only those
actually change.

**Linking each button at `releases/latest` and stopping there.** Rejected as
the *only* mechanism: it forces the user to pick the right file out of a list,
and the filename is how they tell a portable zip from an installer. Filling the
specific asset in is worth the one `fetch`, with the plain link as the fallback.

**Not building a site; let the README serve.** Rejected: the request was for a
site, and a README is written for people who already decided to read code.

## Consequences

**Bought.** A site that is deployed by copying files, reviewable as a diff, and
openable by double-clicking `index.html` — on any machine, with no toolchain.

**Given up.** The prose is now in two places: `site/index.html` and
`packaging/使用说明.txt` say many of the same things, and nothing keeps them in
step. The package notes are the ones that ship inside the zip and are the more
authoritative of the two; the site is the shorter summary. Editing one does not
update the other, and there is no gate that would notice.

**Owed.** The first deployment has to happen from `master`, which means it
rides along with the next release rather than going out on its own.

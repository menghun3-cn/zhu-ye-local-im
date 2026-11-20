# Agent Note: The About page names the website

Status: implemented

## Problem

The About card explained what the app is and how to get a newer build, but
said nothing about where the project lives on the web. The website carries
information the card cannot — full requirements, the honest-network notes,
release history — and a user reading About had no pointer to it. The only
outward addresses the card knew were the update check's GitHub endpoints,
which are plumbing, not a place to send a person.

## Decision

`appWebsiteUrl` (`https://menghun3-cn.github.io/zhu-ye-local-im/`, the Pages
deployment of `site/`) is a constant in `about_page.dart`, beside the page
that shows it. The card gains a row after the update block: a 官网 label, an
「打开官网」 `TextButton` that goes through `LinkResolution.opener` like every
other outward link, and the address itself as `SelectableText` — the same
treatment the download URL gets, so a machine with no default browser still
has somewhere to copy from.

Two strings joined both ARB files: `aboutWebsite` (官网 / Website) and
`aboutOpenWebsite` (打开官网 / Open the website). The generated
`app_localizations*` files are regenerated and committed per `l10n.yaml`.

## Alternatives considered

**Derive the URL from `updateRepository`.** Rejected: `updateRepository` is
`owner/repo` for the API and release pages; the Pages address is a different
shape (`owner.github.io/repo`) that only coincidentally shares the parts, and
string surgery on it would hide the actual address being shipped.

**Put the link in the description text.** Rejected: `aboutDescription` is a
paragraph about what the app does; a bare URL inside prose is neither
selectable-by-design nor translated, and the card already has a pattern for
"label + button + selectable address" that this reuses.

**Link to the GitHub repo instead of the site.** Rejected: the repo is already
reachable through the update flow's download page; the website is the surface
a user can actually read — it is the one address worth adding.

## Consequences

- About now names one stable outward address that does not depend on any
  update-check outcome; it renders unconditionally.
- The URL is hardcoded, so a domain or Pages-path change must edit
  `appWebsiteUrl` — acceptable because the site itself is the thing being
  renamed in that scenario, and the constant sits next to the only consumer.
- `test_flutter/ui/about_page_test.dart` needed no changes: the new row adds
  widgets but no new network behavior — the opener goes through the same
  `LinkResolution` seam the download button already uses.

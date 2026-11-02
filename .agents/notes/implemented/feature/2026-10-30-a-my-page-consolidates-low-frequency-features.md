# Agent Note: a "My" page consolidates low-frequency features

Status: implemented

English | [中文](2026-10-30-a-my-page-consolidates-low-frequency-features.zh.md)

## Problem

The application has six navigation surfaces: Conversations, Devices, Transfers, Clipboard, Settings, and About. All six hang on the rail and the bottom bar as equal entries, which treats a core task (talking to somebody) the same as a configuration task (changing where files land). A six-item navigation is also a crowd: on a narrow screen the bar's icons run together, and on a wide screen the rail's two-item break (the `Spacer` between the four surfaces and the two tools) is a visual hack rather than a principle.

The user's actual workflow splits the six into two groups:
- **High-frequency**: Conversations (every session), Transfers (every send/receive)
- **Low-frequency**: Devices (setup time), Clipboard (sync needs), Settings (once set, rarely touched), About (version check only)

A navigation that does not say which is which makes the user scan six items to find the one they want, when three would be enough for 90% of sessions. The low-frequency items also have no way to surface their most useful information before the user clicks them: the Settings page only shows the folder when opened, and the About page only shows the update status when opened.

## Decision

**Two surfaces on the rail, one aggregator page for the rest.** The navigation now shows three entries:
- Conversations (high-frequency, kept)
- Transfers (high-frequency, kept)
- My (new, aggregates Devices, Clipboard, Settings, About)

The "My" page is a card-based list, each card representing one of the four low-frequency surfaces. Every card shows:
- The surface's icon and title
- A short summary of the most useful information (e.g., "Known devices: 3" for Devices, "v0.1.2" for About)
- A "View details" button that opens the full surface as a new route

The full surfaces (DevicesPage, ClipboardPage, SettingsPage, AboutPage) are unchanged except that they are now reached by pushing a route from "My", rather than by switching the rail selection. The rail's `pinnedCount` drops from 2 to 0 because there are only three entries now.

The split follows actual usage: a user opens the app to talk or to transfer, and everything else is a detour. Putting the detours in one place lets the navigation be lean while still keeping everything reachable.

## Alternatives considered

**Keep all six on the rail.** Rejected: it is a crowd, and it treats configuration as equal to the core task. The visual break was already admitting that the six are not one group.

**A popup menu instead of a page.** Rejected: a menu is for quick actions, not for surfaces that carry state. The Settings page needs a field, the About page needs a download progress, and a menu cannot hold those.

**A tab controller inside "My".** Rejected: it adds complexity without a clear benefit. The user can already reach the four surfaces by clicking their cards, and a tab controller would need a way to explain which tab is current in a place that already has a navigation rail. Pushing routes is the pattern the app already uses (conversation routing), and "My" fits that.

**Move "My" to the bottom of the rail like Settings/About were.** Rejected: with only three entries there is no "foot" any more. The rail now just has three equal entries, which is simpler and matches the bottom bar.

**Make "My" the only entry and put everything inside it.** Rejected: Conversations and Transfers are the reasons the app exists. They should be at the top level, not hidden behind a click.

## Consequences

- `lib/ui/pages/my_page.dart` is new. It builds four cards, each pointing to one of the four low-frequency pages.
- `lib/ui/home_shell.dart` now builds three surfaces instead of six. The `surfaces` list drops Devices, Clipboard, Settings, and About; those pages are now children of `MyPage`.
- `lib/ui/nav_rail.dart` changes `pinnedCount` from 2 to 0, because there is no need to pin anything with only three entries.
- The bottom bar also drops from six to three entries.
- Four localisation keys are added: `tabMy`, `myPageTitle`, and the four card titles/summaries.
- Two widget tests are added: one for `MyPage` and one to verify the new navigation structure in the shell.
- The "My" page follows the existing card pattern (from SettingsPage) for visual consistency.

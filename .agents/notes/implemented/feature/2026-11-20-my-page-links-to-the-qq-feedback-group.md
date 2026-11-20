# Agent Note: The My page links to the QQ feedback group

Status: implemented

## Problem

Users who hit a problem or have a suggestion had no in-app route to the project community. The My page already aggregates low-frequency surfaces, but every card opened an in-app sub-page; there was no outward community entry.

## Decision

The My card list gains a 「反馈问题或建议」 card between Troubleshooting and About. Its title and summary are localized (`myCardFeedback`, `myCardFeedbackSummary`), and tapping it hands `https://qm.qq.com/q/rpttgcx0MC` to `LinkResolution.opener` rather than opening a sub-page. The address is the private `_qqGroupUrl` constant in `my_page.dart`, beside its only consumer.

A widget test installs `ScriptedLinkOpener`, taps the card on a tall window, and asserts the exact QQ group address is the only link opened.

## Alternatives considered

**A feedback sub-page.** Rejected: the requested destination is an external QQ group page; an in-app page would only add a button that does the same hand-off one tap later.

**Put the link on the About card.** Rejected: About describes the program and updates; feedback is a community destination and belongs with the My page's other outward cards. Keeping About last also preserves the existing card order users have learned.

**A remote or configurable group address.** Rejected: there is no settings or remote-config surface for community links, and hardcoding beside the only consumer matches `appWebsiteUrl` and the update endpoints.

## Consequences

- The card appears on both Windows and Android because opening a browser is a platform-shell capability already covered by `LinkResolution`.
- If the opener cannot launch a browser, the card currently gives no on-screen fallback; that matches other direct link taps, while About keeps a selectable address where a failed launch is more consequential.
- Changing QQ groups requires editing `_qqGroupUrl`; the widget test pins the current address so an accidental edit fails loudly.

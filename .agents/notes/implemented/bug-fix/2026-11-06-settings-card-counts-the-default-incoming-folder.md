# Agent Note: The Settings card counts the default incoming folder

Status: implemented

English | [中文](2026-11-06-settings-card-counts-the-default-incoming-folder.zh.md)

## Problem

The Settings card on the My page read `controller.incomingDirectory` — the
folder the user typed — and nothing else. Every platform ships a
`defaultIncomingDirectory` (Downloads on Windows, the app's own `incoming`
directory on Android), and received files already land there when no choice
has been made. On Android the card therefore said "receive folder not set"
while a real destination was in effect, which read as a broken setting rather
than an unmade choice.

## Decision

The card's summary now keys on the resolved folder the page already computes:
`controller.incomingDirectory ?? seams.defaultIncomingDirectory`. "Unset" is
shown only when neither a choice nor a platform default exists — today that is
the `other` platform, or an Android build that could not name its app-data
directory. The distinction the controller keeps (a chosen folder versus the
platform's suggestion) is unchanged: the Settings page still shows the default
as a suggestion, not as a stored choice.

## Testing

`test_flutter/ui/pages_test.dart` gains two widget tests on the Settings
surface group: one device with a `defaultIncomingDirectory` shows the
configured summary and not the unset one, and one with neither shows the
unset summary.

## Alternatives considered

**Show the resolved path in the summary.** Rejected: the card's summaries are
short localized labels, and a raw path is long, unlocalized, and already one
tap away on the Settings page.

**Add a third "using the default folder" wording.** Rejected for now: it would
need new strings in both ARB files and a regeneration, to distinguish two
states the user cannot act on differently — both mean "files have somewhere to
land".

**Leave the card as the record of the user's choice.** Rejected: the label
"not set" answers a question nobody asked. What the user wants to know is
whether received files have a destination, and the platform default is one.

## Consequences

- On Windows and Android the Settings card now always reports the folder as
  configured, matching where files actually land.
- The unset summary survives only for platforms with no default at all.
- The chosen-versus-default distinction still lives on the Settings page,
  where it can be edited; the card stays a summary.

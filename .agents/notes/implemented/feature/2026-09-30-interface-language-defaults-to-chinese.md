# Agent Note: The interface speaks Chinese by default

Status: implemented

English | [中文](2026-09-30-interface-language-defaults-to-chinese.zh.md)

## Problem

The packaged build came up in English. Every string a user reads was a literal
inside a widget, and there was no localization layer at all: no ARB files, no
`flutter_localizations`, no delegates. Handing the build to its intended users
meant either rewriting each literal in Chinese or teaching it to speak more
than one language, and only the second one survives contact with the next
string.

Two parts of the problem were not obvious from reading the widgets.

The first is that a window is not made only of the application's own words.
The text-selection menu on every `TextField` — Cut, Copy, Paste, Select all —
the semantics of an `AlertDialog`, and the rest of Material's own vocabulary
come from `GlobalMaterialLocalizations`. Translating the literals and stopping
there would have produced a Chinese screen whose text fields still offered
"Paste" in English. Only installing `flutter_localizations` fixes that.

The second is that not every user-facing sentence is written where it can be
translated. `AppStateException` carried a prose `message` composed in `lib/app`,
and that layer is forbidden from importing Flutter — `test/app/plain_dart_test.dart`
is the gate that keeps it true. A refusal such as "no address is known for
3f9a…; it has to be discovered before it can be dialled" was therefore English
by construction, and no amount of work in `lib/ui` could reach it.

## Decision

The interface is localized with Flutter's own generator, and Chinese is what it
opens in.

* `lib/l10n/app_en.arb` is the template — every key first, with placeholder
  types declared — and `lib/l10n/app_zh.arb` is the translation. `l10n.yaml`
  generates the class into `lib/ui/l10n/generated`, which is committed, so the
  analyzer and the formatter see exactly the files the build does rather than a
  synthetic package that only `flutter build` knows about. The ARB files are
  under `lib/l10n` and the class they generate is under `lib/ui` on purpose:
  the ARB imports nothing, the class imports Flutter, and keeping them apart is
  what lets `test/app/plain_dart_test.dart` go on asserting — without an
  exception for it — that Flutter is confined to `lib/ui`.
* `appLocale` is `Locale('zh')` and is passed to every `MaterialApp` as
  `locale`. It is fixed rather than resolved from the platform, because there
  is no language setting on screen: following the platform would make the
  language depend on a Windows setting nobody chose for this app. `appLocales`
  is `[zh, en]` — ordered, so that if `appLocale` is ever relaxed to null the
  *fallback* for a language that is neither is Chinese rather than English
  (`AppLocalizations.supportedLocales` is alphabetical, and would fall back to
  English).
* `lib/ui/labels.dart` and `describeFailure` stay pure functions and take the
  looked-up strings as an argument. Pages keep reading
  `AppLocalizations.of(context)` once in `build` and handing the result down.
* `AppStateException` no longer carries a sentence. It carries an `AppRefusal`
  — a closed set of things a caller asked for and could not have — plus an
  optional `detail` that holds *data*: a Fingerprint, a port number, a file
  name. `describeRefusal` in `lib/ui/labels.dart` turns the pair into a
  sentence. The reason travels up in a form the UI can act on, and the app
  layer never writes prose.
* The opposite rule holds for the core layers' failures. `PairingException` and
  `HandshakeException` keep their `message` verbatim, and the UI wraps it in a
  localized frame — "无法连接到该设备：{detail}". What follows the colon is a
  fact about the network, often the operating system's own `SocketException`
  text; rewriting it would make it harder to act on rather than easier.
* One core failure gets a second frame, and gets it by *kind* rather than by
  matching its text. A `PairingException` raised because a dial never landed
  carries `unreachable: true`, and `describeFailure` answers that with
  `failureCannotReach` — the verbatim detail followed by what to check, because
  a dial that never arrived is a Device that is not running, is on another
  network, or is behind a firewall, and none of that is something this
  application can fix or infer from the operating system's word for it. The flag
  is what keeps that decision away from a phrase to match, which would break
  silently the first time the operating system reworded its own message.

## Alternatives considered

**Translate the literals in place and stop there.** Rejected: it leaves
Material's own words — the selection menu on every field, dialog semantics — in
English. A screen that is Chinese except for the field it is asking you to type
in is not a translated screen.

**Follow the platform locale, with Chinese as the fallback.** Rejected for this
build: nothing on screen can change the language, so the language would depend
on an operating system setting the user never connected to this app, and a
machine configured for English would look like the request had not been
fulfilled. It is a one-line change (`appLocale` to null) once a language setting
exists.

**Make `app_zh.arb` the template, so the generated `supportedLocales` puts
Chinese first.** Considered, and it does solve the fallback order. Rejected:
the template is where keys, docs and placeholder metadata are maintained, and
that belongs in the language the code is written in. Ordering is handled at the
one place that consumes it instead.

**Keep a prose `message` on `AppStateException` and translate it by looking the
English text up in a table.** Rejected: a lookup keyed on the sentence breaks
silently the first time somebody edits a word, and the breakage is a missing
translation rather than a compile error.

**Hand-roll a strings class instead of generating one.** Rejected: plurals,
interpolation and the Material delegates are exactly what the generator already
does, and a hand-rolled version would need each of them re-derived per string.

## Consequences

- The application opens in Chinese; English is complete, generated, and one
  line away from being the default.
- `lib/ui/l10n/generated` is committed source. Re-running `flutter gen-l10n` is
  what regenerates it, and `flutter pub get`, `flutter build` and
  `flutter test` all do it from `generate: true` in `pubspec.yaml`.
- `flutter_localizations` (SDK) and `intl` are new dependencies. Nothing was
  added to `lib/core`, which stays free of both.
- The app layer no longer composes user-facing text. `AppRefusal` is the
  contract between a refusal and its wording, and adding a refusal is a
  compile error until `describeRefusal` handles it.
- `test_flutter` builds its panes with the same locale and delegates as the
  real application, and exposes the loaded `l10n` for tests to drive labels
  with. A test that taps "配对" is therefore asserting what a user of this build
  sees, and the two-window E2E test would fail if the UI came up in a language
  nobody asked for.

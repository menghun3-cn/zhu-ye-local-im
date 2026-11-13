# Agent Note: Addresses in a message are clickable links

Status: implemented

English | [中文](2026-11-13-addresses-in-a-message-are-clickable-links.zh.md)

## Problem

A web address arriving in a message was dead text. The conversation drew it
in the same ink as the words around it, and the only way to use it was to
select it, copy it, and paste it into a browser — the same dozen steps every
chat application removed years ago. The sender had done the work of getting
the address onto the wire; the receiver still had to do the work of getting
it onto a screen that could open it.

## Decision

A text message's words are scanned for addresses when the bubble is built,
and each one is drawn as a link — underlined, in the theme's link colour —
that opens in the machine's browser on tap.

- **`messageLinks`** (`lib/core/util/message_links.dart`) is the recogniser,
  plain Dart so `dart test` covers it: `https?://` and `www.` beginnings, an
  RFC 3986 body, no bare `example.com` (a bare domain is indistinguishable
  from versions and file names often enough that guessing produces more
  false hits than the convenience is worth). Trailing sentence punctuation
  and unbalanced closing brackets are trimmed — `（见https://a.com）` links
  `https://a.com`, not the parenthesis — and a `www.` match is answered with
  an `https://` scheme, because a browser cannot be handed a scheme-less
  address.
- **`_LinkifiedText`** (`lib/ui/conversation_view.dart`) is a stateful
  wrapper around the message's `Text`: it builds `TextSpan`s — ordinary ink
  for the words, link style plus a `TapGestureRecognizer` for each address —
  and disposes the recognizers, which is the one thing a stateless build
  cannot do. A message with no address still builds the plain `Text` it
  always was. The `SelectionArea` around the conversation keeps working: a
  drag is not a tap, so selecting across a link still copies its characters.
- **`isOpenableLink` widened** from "https on `github.com`" to "any http or
  https address with a host and no whitespace or control characters". The
  GitHub restriction existed because the address came from a GitHub
  response; a message address is peer-written text, so the check is now a
  scheme whitelist — the thing that actually keeps a crafted address out of
  a shell — rather than a host list that would reject most of what people
  send each other.
- **Windows opens through `rundll32 url.dll,FileProtocolHandler`**, not
  `cmd /c start`. `start` was safe while every address came from GitHub;
  peer text can carry `&`, and `cmd` reads that as a command separator.
  `rundll32` is the same "open with the default handler" with no command
  shell in between.
- **Android opens through a new `browser` channel**
  (`cn.hnasct.local_transfer/browser`, method `openUrl`) in `MainActivity`,
  firing `ACTION_VIEW` — the same pattern the `files` and `update` channels
  already established, and the reason no launcher plugin was added. Kotlin
  re-checks the scheme and host before firing the intent, and the manifest's
  `<queries>` declares `VIEW` for `http`/`https` so Android 11+ package
  visibility does not answer "no browser" when one exists.
- The tap goes through the existing `LinkResolution.opener` seam, so widget
  tests substitute a stand-in exactly as the About page's link already did.

## Alternatives considered

**`flutter_linkify` / `linkify` package.** Rejected: a dependency bought for
one regular expression, in a project that already writes its own matching
elsewhere and keeps `lib/core` free of Flutter so the rules are testable
under `dart test`.

**`url_launcher` plugin.** Rejected for the third time on the same ground —
a native registration bought for calls the platform's own shell and the
runner's own channel already answer (`openInBrowser`'s doc comment records
the trade; `2026-11-12-tapping-a-landed-file-opens-it` rejected it for file
opening one day earlier). The Android half is thirty lines of Kotlin either
way, and the channel version keeps "the app ships no plugins" true.

**Keep `cmd /c start` and validate the address harder.** Rejected: the
characters that make an address dangerous to `cmd` — `&`, `|`, `>`, quotes —
are also legal inside real URLs (`?a=1&b=2` is ordinary), so a character
blocklist would break legitimate links to protect against an injection the
shell-free call does not have.

**`SelectableText.rich` per bubble instead of the shared `SelectionArea`.**
Rejected: the area already makes every `Text` in the list selectable,
including across message boundaries, and a per-bubble selectable would
break a drag that spans two messages — a selection that stops at a bubble's
edge is not what the user asked for.

**Linkify bare domains (`example.com`).** Rejected: versions (`1.2.3`), file
names (`a.b`), and dotted abbreviations are indistinguishable from domains
without a heuristic, and every false positive is a link that opens the wrong
thing. `www.` is the compromise — it is how people write a domain they
mean as a link.

## Consequences

- A received `https://…` or `www.…` address is underlined in
  `brandStrong` — the token the palette already documents as the link-text
  colour — and a tap opens it in the default browser on Windows and Android.
  On a bubble wearing a skin the link colour stays the theme's, which is a
  known rough edge on busy image skins.
- Both directions get links, not only incoming: the recogniser is a fact
  about the text, and an address the user sent is just as openable as one
  they received.
- The opener answers false where no browser exists or the platform is
  neither Windows nor Android; the address stays on screen to be copied —
  the same answer the About page's link already gives.
- `isOpenableLink` no longer names a host, so the About page's GitHub links
  pass through the same widened gate; what it actually opens is unchanged.
- The Kotlin half is verified by inspection and by the Dart-side contract
  test in `test/platform/android_bridge_test.dart`, not by an instrumented
  run — no gate on this machine builds an APK.

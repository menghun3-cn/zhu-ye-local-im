# Agent Note: AI providers speak four protocols through one canonical format

Status: implemented

English | [中文](2026-11-23-ai-provider-routing-codecs.zh.md)

## Problem

The app is gaining AI features — chat, message processing, smart replies —
and every one of them needs the same two things first: a way to configure
which models exist and where they live, and a way to call them. The reference
design is magpie, whose answer is a local gateway that speaks four wire
protocols (OpenAI Chat, OpenAI Responses, Anthropic Messages, Gemini) and
translates between them.

Porting magpie itself was never on the table: it is a Go application, and
Android cannot reasonably carry a Go sidecar. What could be borrowed is the
*shape* of the problem — and the shape turns out to be smaller than it
looks. magpie's "four protocols interoperate" is hub-and-spoke, not a
4×4 mesh: one canonical format plus one codec per protocol already lets any
provider serve any caller. The app controls both ends of every call, so a
full translation mesh would be paying for generality nobody uses.

Two product decisions framed the rest. Providers are configured per device
and never shared — the Owner Group trust boundary does not extend to API
keys. And the work splits into milestones: this note covers the core
(configuration, codecs, routing); the local gateway and the settings UI are
separate changes built on top.

## Decision

`lib/core/ai/` is a plain-Dart module with no Flutter imports, so `dart test`
covers it end to end:

- **`ai_message.dart`** — the canonical format: roles, text content, tool
  calls (arguments kept as raw JSON so codec boundaries do not have to
  agree on escaping), tool *definitions* (`AiToolDefinition` +
  `AiToolChoice`, with the JSON Schema kept decoded so each codec can
  re-emit it in its own dialect — OpenAI verbatim, Anthropic
  `input_schema`, Gemini `parametersJsonSchema`), usage, and a stream
  event that also carries
  reasoning deltas — thinking is generated output for timing purposes
  but never joins the answer's content.
- **`protocol/`** — `AiCodec` per protocol (`openai_chat`,
  `openai_responses`, `anthropic`, `gemini`) plus a shared SSE parser that
  survives multi-byte characters split across chunk boundaries. The
  router decodes every chat body through `sniffedDecodeStream`, which
  re-attaches the sniffed head when the body really is SSE and folds a
  plain JSON document — some compatible endpoints accept `stream: true`
  yet answer non-streamed — through `decodeResponse` instead of letting
  it vanish into zero frames. Each codec owns its URL paths, headers and
  body shapes; `modelsSpec`/`decodeModels` give the settings UI a
  fetch-models path without a second HTTP stack.
- **`provider.dart` + `presets.dart`** — providers hold per-protocol base
  URLs (a model entry records *which* protocol it speaks, since one custom
  endpoint can front several APIs), an encrypted-at-rest key, and a fetched
  model catalogue where enablement is explicit. References parse as
  `provider/model` or `group/<id>`, magpie's syntax. Each preset names a
  bundled brand-mark SVG (`assets/ai_providers/<id>.svg`, monochrome
  `currentColor` paths from the LobeHub icon set, tinted by the theme)
  that the add-provider dialog shows ahead of the label.
- **`secret_box.dart` + `provider_store.dart`** — AES-256-GCM via the
  already-present `cryptography` package. A random 32-byte key is generated
  once per install; `apiKey` fields persist as `v1:<nonce‖ct‖tag>` and
  unseal transparently on load. Pre-encryption plaintext values still read
  and are sealed on the next save. The store delegates file mechanics —
  atomic temp-then-rename, corrupt move-aside, write chaining — to the same
  `MessageStore` abstraction the conversation history uses.
- **`ai_router.dart`** — resolves a reference into concrete members
  (groups nest, cycles are cut), tries them in order, and fails over only
  on retryable errors (429/5xx/quota/network) with a per-member cooldown.
  A fatal error — bad key, unknown model — throws immediately rather than
  failing over, because the next member would fail the same way while
  hiding the real cause. Streaming replies fail over only until the
  provider starts answering; afterwards a half-written reply is worse than
  an honest error.

Transport sits behind `AiTransport` so tests script responses from fixtures;
`IoAiTransport` is the `dart:io` implementation.

## Consequences

- Any of the four protocols can serve any future AI feature without new
  plumbing; adding a fifth means one codec file.
- `providers.json` on disk contains no plaintext keys, but the sealing key
  lives beside it — this is obfuscation-grade, and OS keystores (DPAPI,
  Android Keystore) are recorded as the real hardening step.
- Failover is per-request and in-memory: a restart gives every member a
  fresh chance, matching how daily quotas actually reset.
- The gateway (PR2) and settings UI (PR3) consume this module unchanged;
  the codec layer was deliberately kept transport-agnostic for exactly
  that.
- Anthropic and Gemini tool calling is mapped best-effort; Gemini tool
  *results* currently fold into user text until function-calling work
  lands.

## Alternatives considered

- **Embed or fork magpie.** Rejected: it is a Go binary, Android has no
  reasonable way to host it, and forking a 40k-star project to use its
  gateway internals is a maintenance trap. The hub-and-spoke insight was
  worth keeping; the code was not.
- **OpenAI-compatible only.** Rejected by the requester in favour of
  magpie-grade protocol coverage; Claude and Gemini official endpoints
  would have been unreachable.
- **Pub packages for the protocols.** Rejected: coverage is partial across
  the four APIs and each brings its own HTTP stack; the codecs are a few
  hundred lines each and fully testable with fixtures.
- **Per-endpoint API keys.** Rejected: magpie's custom-provider model uses
  one key per provider, and upstreams needing different keys are honestly
  modelled as separate providers.
- **Plaintext keys on disk.** Rejected during design review; sealing was
  pulled into this milestone rather than deferred.

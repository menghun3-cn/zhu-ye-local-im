# Agent Note: The AI gateway is a loopback-only OpenAI endpoint over the router

Status: implemented

English | [中文](2026-11-23-ai-local-gateway.zh.md)

> **Superseded in part** by
> [gateway LAN scope and provider drafts](../feature/2026-11-24-ai-gateway-lan-and-draft.md):
> the bind is no longer loopback-only by fiat — `AiGatewayConfig.scope`
> selects loopback or `0.0.0.0`, and `enabled` now defaults on.
>
> **Amended by**
> [the gateway keyring](2026-11-24-ai-gateway-keys.md): the single
> generated bearer token is now a maintainable list of named keys; the
> endpoints, per-request store reads and bind lifecycle below are
> unchanged.

## Problem

The AI core (see
[2026-11-23-ai-provider-routing-codecs](2026-11-23-ai-provider-routing-codecs.md))
gives the app providers, codecs and a router — but only code inside the app
can reach them. The design's second milestone adds the piece that makes
"configure once, use everywhere" literal: tools that only speak OpenAI —
Claude Code, Codex, OpenCode, a curl one-liner — should be able to point at
a local endpoint and reach every enabled model, including routing groups,
without configuring a second set of keys.

The constraints come from the product decisions already made. Providers are
per-device and never shared, so the gateway must not become a way to expose
this device's keys to the LAN. It runs inside a Flutter app that must start
and stop cleanly with the process, on both Windows and Android.

## Decision

`lib/core/ai/ai_gateway.dart` is an `AiGateway`: a raw `dart:io`
`HttpServer` bound to `InternetAddress.loopbackIPv4`, serving two endpoints —
`GET /v1/models` and `POST /v1/chat/completions`, streaming included. It
holds an `AiConfigStore`, an `AiRouter` and a token, and re-reads
configuration through the store on every request, so a settings edit takes
effect without a restart.

- **Loopback only.** Binding wider would publish the owner's API keys to the
  LAN, which the per-device configuration decision ruled out. Port 0 by
  default — the endpoint is displayed in the UI, not written into configs.
- **A generated bearer credential** guards the port — originally one
  `lt-ai-` token (`gateway_token.dart`), now a keyring of named keys per
  [the gateway-keys note](2026-11-24-ai-gateway-keys.md). The
  threat is not the network — it is every other process on the machine,
  which could otherwise spend the stored keys. Secrets live in their own
  file beside `providers.json`, because they are shown in the UI in
  plaintext by design and must not drag the provider keys along if they
  leak. `sk-`/`lt-ai-` prefixes mark them like magpie's `sk-magpie-key`.
- **Inbound is OpenAI-shaped only.** `/v1/models` lists enabled
  `provider/model` refs plus `group/<id>` entries exactly as magpie exposes
  them; `/v1/chat/completions` maps the request onto canonical form (string
  or parts-array content, tool calls and results, `tools`/`tool_choice`
  function definitions, `max_tokens`/`top_p`/`stop`) and pipes
  canonical stream events back out as `chat.completion.chunk` frames ending
  in `data: [DONE]`. A non-stream request that receives a streamed reply —
  or the reverse — is folded across the boundary rather than left hanging.
  Anthropic/Gemini inbound endpoints are deliberately absent: the codec
  layer already translates both directions, so they are endpoints, not new
  machinery, and land when a consumer needs them.
- **Errors keep the OpenAI envelope** — `{"error": {"message": ...}}` with
  400 for malformed requests, 401 for a missing token, 404 for unknown
  paths, 502 for upstream failures — because every client already knows how
  to print that shape.
- **Lifecycle is the app's, not the store's.** `PlatformSeams` gained an
  `aiDirectory` path (`<appData>/ai`), resolved by the same
  `profile_location.dart` rules as every other durable path — null where
  there is nowhere durable to write. `_LocalTransferAppState` assembles
  `SecretBox` + `AiConfigStore` + `AiRouter` + `AiGateway` after the
  controller starts, binds only when `config.gateway.enabled` is persisted
  true, and stops the server in `dispose`. Android shares the code but
  ships with the flag off. Gateway start failures are swallowed: messaging
  must not depend on an AI listener.

## Consequences

- External tools can use the app's configured providers and routing groups
  unchanged; the only credential they need is the displayed token.
- `ai/` holds `providers.json` (sealed keys), `secrets.key` (the sealing
  key) and `gateway_token` — all per-device, none synced, none logged.
- Requests are re-read from disk-backed config per call, matching the
  router's existing load-per-request behaviour; there is no settings cache
  to invalidate.
- The gateway has no concurrency limit beyond the 1 MiB body cap — a local
  tool could still queue requests, but each is bounded and loopback.
- The settings UI (PR3) is the intended owner of enable/disable and token
  display; today the only way to flip the flag is editing `providers.json`.

## Alternatives considered

- **shelf instead of raw `dart:io`.** The repo already depends on shelf for
  the link-transfer server, but that server is a LAN file-transfer
  endpoint; the gateway needed per-request streaming control
  (`HttpResponse.flush()` between SSE frames) and the two-endpoint surface
  did not justify a router abstraction.
- **Bind `0.0.0.0` for LAN sharing.** Rejected: it would publish the owner's
  API keys to every device on the network, contradicting the per-device
  trust decision. LAN sharing, if ever wanted, is a separate feature with
  its own named keys and quotas, magpie-style.
- **Token inside `providers.json`.** Rejected: the document seals provider
  keys and is rewritten on every settings save; a UI-displayed credential
  belongs in its own file so rotation and display never touch the sealed
  store.
- **Inbound Anthropic/Gemini endpoints now.** Deferred: nothing consumes
  them yet, and each is a thin endpoint over codecs that already exist.
- **Gateway inside `LocalTransferController`.** Rejected: the controller
  owns peer sessions and transfers; an AI listener is a different lifecycle
  and would couple messaging startup to AI configuration.

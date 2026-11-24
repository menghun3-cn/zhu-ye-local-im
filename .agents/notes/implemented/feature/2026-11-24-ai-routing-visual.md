# Agent Note: Built-in public providers, a routing page with a flying leaf, and a named-provider editor

Status: implemented

English | [中文](2026-11-24-ai-routing-visual.zh.md)

> Extends
> [the LAN gateway and draft providers](2026-11-24-ai-gateway-lan-and-draft.md)
> and [the settings surface](2026-11-24-ai-settings-surface.md): the AI
> section gains first-run providers, a live routing view, and stricter
> editor semantics.

## Problem

Hands-on testing of the AI settings surface produced five corrections.

"Add provider" pre-filled the name with the preset's label, so every
provider ended up named after its vendor unless the user thought to
change it — the field taught the wrong default. The magpie project this
feature takes inspiration from animates a bird along the agent→provider
wire while a request is in flight; our settings page had no equivalent
answer to "which provider is being asked right now". And the only way to
reach a usable model was to know a vendor, find its key page, and paste a
credential — there was no zero-configuration path at all.

## Decision

**Two public providers ship enabled.** `aiBuiltinProviders`
(`builtin_providers.dart`) lists OpenCode Zen and Kilo — endpoints with a
shared credential (`public` / `anonymous`), no signup. `AiRuntime.open`
seeds them into `providers.json` exactly once, guarded by a new
`AiConfig.builtinsSeeded` flag: an absent id is appended, a present id is
left alone, and the flag flips either way. A user who deletes a built-in
keeps it deleted; a user who repoints an endpoint is never overwritten.
The seeded model lists are deliberately small — both upstreams rotate
their free catalogue, and a stale id fails honestly on use until the
editor's fetch button refreshes it. No network fetch happens at seed
time: first-launch latency must not depend on an external API.

Kilo's endpoint is `https://api.kilo.ai/api/openrouter/v1` — verified
live: anonymous `Bearer anonymous` returns real completions, and the
model catalogue answers on both `/models` and `/v1/models`. Zen's three
usable routes were provided by the requester and checked against the
codecs' path rules: `openaiChat`/`openaiResponses` on
`https://opencode.ai/zen/v1`, `anthropic` on `https://opencode.ai/zen`
(the codec appends `/v1/messages` itself). Zen's Gemini route is *not*
seeded — it speaks Zen's own model-path shape, not the Google-native
`/v1beta` layout the Gemini codec emits.

**The router broadcasts its route.** `AiRouter` gained
`Stream<AiRouteEvent> events` — `attempt`/`served`/`failed` per concrete
`provider/model` member, tagged with a per-`chat`-call id so failover
steps and concurrent requests never cross wires. A streamed reply counts
as served only when its event stream ends; a listener that walks away
mid-stream reports `failed`, because the provider never finished its
answer. Emission is best-effort: broadcast controller, no awaiting, a
throwing listener cannot slow a request.

**The routing view draws the wires and flies a leaf.**
`AiRoutingView` (embedded at the top of the AI settings page, not pushed —
the live route belongs above the configuration that decides it) draws
three columns — Agent, the 竹叶网关 node showing its `ip:port`, and every
enabled provider — with bezier wires for agent→gateway and
gateway→provider, each roughly half the length of the old single hop.
One `Icons.eco` leaf per in-flight request flies agent→gateway→provider
on `attempt` and back on `served`/`failed`; the wire a leaf is riding
turns dashed while the flight exists. Position is a pure function of
layout and the controller's 0→1 progress, so resizes re-anchor for free.
`MediaQuery.disableAnimations` drops the flights and keeps the status
line — magpie's reduced-motion degradation, same intent. Provider
enable/disable needed no new work: `AiProvider.enabled` already gated
the router and the gateway's exposed refs; the settings tile's switch
was already there.

**Member health is per-node, not global.** A `failed` event now carries
`cooling`: true when the member entered its cooldown rather than dying
fatally. The view keeps `member → cooldown-until` and `member →
last-fatal-error` maps, aggregates them worst-first onto each provider
node ("Cooling 42s" in amber, "Last request failed" in red for 30s), and
seeds cooldowns already in flight from `AiRouter.coolingDownUntil` — so
a benched member shows as cooling instead of the whole picture looking
dead. A 1s ticker expires marks, refreshes the countdown, and polls
`AiRuntime.configVersion` (bumped by every `save`) plus a gateway
signature so edits made elsewhere on the page repaint the canvas without
a reload handshake.

**The name field asks instead of answering.** A provider draft opens
with an empty name field — the preset label demotes to `hintText` — and
Save stays disabled until the name is non-empty. Fetch/test are
unaffected: they only read endpoints and key.

## Consequences

- Fresh installs get two working providers with zero configuration. Both
  are free-tier public endpoints: rate limits, catalog churn, and Zen's
  current anonymous 429s are upstream facts the UI surfaces honestly
  (the routing page shows the failed flight) rather than bugs to hide.
- `providers.json` gains `builtinsSeeded`; older files read `false` and
  are seeded on next open — which is correct, since they predate the
  feature.
- `AiProviderKind` gains `builtin`; unknown kind strings still fall back
  to `custom` on read.
- The routing page is only as live as `AiRouter.events`: gateway requests
  and any future in-app chat share the same stream, so the page needs no
  second instrumentation when chat lands.
- Leaves are per-flight `AnimationController`s — a `TickerProviderStateMixin`,
  not the single-ticker one, because concurrent requests are real.

## Alternatives considered

- **Fetch the built-in model catalog at seed time.** Rejected: first
  launch would block on an external API's mood, and the answer is stale
  by the next launch anyway. A pinned shortlist plus the existing fetch
  button is honest and instant.
- **Resurrect a deleted built-in when its id is missing.** Rejected:
  "seeded once" is the only rule that respects deletion. The flag makes
  the choice permanent rather than inferred.
- **A card-sized animation inside the settings page.** Partially
  adopted: what shipped is the full routing view embedded at the top of
  the settings page — not a pushed page, and not a thumbnail — because
  magpie proved people want the whole picture (nodes, wires, live
  flights) and top-embedded keeps "which route is live" always visible.
- **Pre-fill the name and let users ignore it.** Rejected by the
  requester: every provider named "DeepSeek" tells the user nothing about
  which endpoint it actually points at.

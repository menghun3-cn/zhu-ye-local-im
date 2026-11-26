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
steps and concurrent requests never cross wires. `attempt` is emitted
inside `_call` immediately before `transport.send`, after every
preflight check — a member rejected for a disabled model or a missing
endpoint produces `failed` only, because no request ever left the
device and the leaf must not pretend it did. A streamed reply counts
as served only when its event stream ends; a listener that walks away
mid-stream reports `failed`, because the provider never finished its
answer. Emission is best-effort: broadcast controller, no awaiting, a
throwing listener cannot slow a request.

**The routing view draws the wires and flies a leaf.**
`AiRoutingView` is the AI page's first tab, at full height — the live
route is what the page is *for*, so it leads rather than sits embedded
in a scrolling list. It draws three columns — Agent, the 竹叶网关 node
showing its `ip:port`, and provider nodes, all scaled to roughly
1.8× their original size so the flying leaf reads against them — with
bezier wires for
agent→gateway and gateway→provider — each hop deliberately short so the
three columns read as one pipeline, not three islands. The leaf never
crosses the gateway card's face: it rides each wire right up to the
card's edges, then arcs over the card's top — a short cubic whose
handles sit just above the card — for the middle slice of the trip
(eased progress 0.45–0.55), then picks the next wire back up. While the
leaf is on that arc it is on no wire at all, so neither segment claims
the dash. One bamboo leaf
(`Icons.eco`) per in-flight request flies agent→gateway→provider on
`attempt` and back on `served`/`failed` — magpie's own convention:
a **solid bead** rides on the leaf outbound (the request going out) and
a **hollow bead** on the way home (the reply coming back). Departures
queue behind any homeward leaf: a serial caller fires its next request
the moment the reply lands — mid-return — and launching then would put
two leaves on screen travelling opposite ways for what reads as one
sequential exchange; queued attempts re-validate and launch once the
last leaf docks. Outbound leaves still overlap freely, so genuine
concurrency keeps its per-`callId` shades. The trip's last slice is the
arrival "away" — magpie's own exit: the leaf drifts up and off the
provider node, shrinking and fading, instead of parking invisible on the
card. What stays behind is a **held dot** at the node's wire end,
breathing opacity 1→0.45→1 on a 1.2s cosine for as long as the reply is
out — the request is still visibly "there" without a bird loitering.
Progress along the wires is
cosine-eased — launch and dock gently rather than sliding at constant
speed — and the leaf sways as it flies. The leaf **dissolves into each
end node**: opacity follows the eased trip progress, so it fades out
as it reaches the agent on the way home — and on the way out it arrives
at the provider still visible, then spends its last slice flying the
away. The return leg fades it back in as it pulls away from the held
dot, and fades out again as it reaches the agent. Departures queue
behind homeward leaves, and an attempt whose request already ended
while queued is dropped on the end event — otherwise it would launch,
fly out, and dissolve at the provider forever with no second end event
left to bring it home.
The whole route lights up for the whole flight — magpie's own read:
agent→gateway and gateway→provider both dash **and flow** while a
request is out, outbound and held stretches included, so the path being
asked reads at a glance rather than a single busy-looking segment.
Dashed segments paint in the brand colour while idle wires keep the
faint line colour, the dash rhythm is a dense 4-on/4-off and the pattern
slides two periods per dash cycle (~20px/s) — visibly flowing, not
breathing. Direction still follows the leaf: a returning flight marches
both wires backwards, and forward wins when flights disagree. The dash
pattern slides toward the direction the leaf is actually travelling —
reversed on the return leg — driven by a repeating controller that only
runs while a leaf is airborne, so an idle canvas burns no frames. Each leaf's shade
is a pure function of its `callId` (four lightness × two saturation
steps around the brand green), so concurrent requests are tellable
apart while a failover's members — same call, different providers —
keep one colour. Position is
a pure function of layout and the controller's 0→1 progress, so resizes
re-anchor for free. `MediaQuery.disableAnimations` drops the flights
and keeps the status line — magpie's reduced-motion degradation, same
intent. Provider enable/disable needed no new work: `AiProvider.enabled`
already gated the router and the gateway's exposed refs; the settings
tile's switch was already there.

**Provider nodes are earned, not listed — and they linger.** The
catalogue can hold dozens of providers; drawing all of them would push
the column off-screen, so a node appears only when a route event names
its provider and stays for five minutes after its last request (or while
a leaf is still flying to it, however long a stream runs). Idle canvas
shows Agent and gateway only — "what can be asked" lives on the
Providers tab, "what is being asked" lives here. Nodes claim a fixed
slot in first-requested order (capped at 10) rather than packing
vertically, so a node arriving or expiring never slides its neighbours
— appear/disappear jitter was the difference between "alive" and
"seasick". Past the cap an active provider still earns its visibility
mark and a request, but no node: the canvas answers with a small
"N more providers active" caption rather than letting those requests
look ignored. A node card names both parties: the provider's name on the
headline row, and — while healthy — the concrete model its latest route
event asked for on the second line (`provider → modelId` from the member
ref, resolved through `model.label ?? id`), falling back to the
enabled-model count and yielding the line to a cooling/failed status
when health demands it. A node with a leaf in flight also breathes — a
soft brand-coloured glow swelling and fading on the shared dash
controller's 800ms cycle, so "being asked right now" needs no badge and
stops the moment the last leaf docks. A long stream must not read as an
unresponsive node either: while any flight to the provider has not yet
turned for home — outbound leg and the held stretch at the node both
count — the card's second line ends in a live mark. Bare "Answering…"
until the first content lands, then live numbers — estimated tokens and
tokens/sec (chars ÷ 4, shown with ≈: providers only report real token
usage once at the end, so mid-stream the honest figure is a rough
conversion, not a billed count), fed by throttled
`AiRoutePhase.progress` events the router emits from `_observeStream`
(chars, not tokens) — and after 15s without new content the
mark drops the claim and shows the numbers alone in the warning colour:
a quiet reply is not a failed one. The numbers repaint on a 15fps timer
that runs only while a flight exists — magpie's own cadence, fast enough
to read as live without repainting every frame. The provider card is
360px wide — up from 299 — so the mark fits whole beside the model
line, and the mark keeps its intrinsic width (no ellipsis on the live
numbers; the status text to its left is what shrinks). The mark lifts
the moment the return leg starts since the reply already arrived.
Stale `provider → modelId`
entries are pruned on reload when either side disappears.

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

**The canvas is answered by a request log.** Under the animation the
view splits its height with a request list — rendered inside its own
rounded, `borderStrong`-outlined panel so the records read as a bounded
region under the canvas rather than a bare strip on the page
background: the last 7 days of
*finished* requests, two lines each on its own `surfaceSunken` card
with a hairline `divider` border — `MM-dd HH:mm:ss` in its own
column beside the model that served, then a compact metrics line
(`2.3s · first token 2.1s · 37.4k tokens · 99% cached · 16.3 tok/s` —
the speed figure is completion tokens over the post-first-token span,
so a slow-thinking upstream does not read as a slow generator; rows
without a completion split show `—` rather than dividing the prompt-
inflated total) whose tooltip
expands the exact uncached-input/output/cache-read/cache-write counts.
`AiRouter` records every reply that completed (streams count only when
their event stream ends cleanly — an upstream error event closes the
route as failed and leaves no row; failures leave no row — the red
node already says that) into `requests.json` beside `providers.json`,
stamped with the
gateway key name when the request arrived through one, pruned to the
window on every write and hard-capped at 500 rows. Timing comes from
the router's own clock, tokens from `AiUsage`, which gained
`cachedTokens` — decoded per protocol (`prompt_tokens_details`,
`input_tokens_details`, `cache_read_input_tokens`,
`cachedContentTokenCount`) and re-emitted to gateway callers in the
OpenAI shape. The gateway therefore asks every upstream for a stream
even when the caller wants one folded response: only the stream shape
carries a first-token mark and per-chunk usage, and `_fullReply`
reassembles it — a non-stream upstream answer would leave TTFT and
usage permanently blank. Reasoning output counts as first-token
evidence: codecs surface thinking under a dedicated
`AiStreamKind.reasoningDelta` (never folded into content), and the
router's TTFT clock stops at the first text, reasoning, or tool-call
event — otherwise reasoning models would show `—` for exactly the
requests users wait longest on. When an upstream reports only
total/completion, the prompt share is derived as their difference so
the cache-hit math still renders. Recording is fire-and-forget and
serialized through a write queue with a unique temp name per write —
concurrent completions (the LAN gateway makes them real) cannot lose
each other's rows or collide on `requests.json.tmp`. A log
failure can never reach a request. The view reloads on `AiRequestLog.version`, polled by
the same 1s ticker that watches `configVersion`.

**The name field asks instead of answering.** A provider draft opens
with an empty name field — the preset label demotes to `hintText` — and
Save stays disabled until the name is non-empty. Fetch/test are
unaffected: they only read endpoints and key.

**The canvas is a shortcut, not just a picture.** Tapping a provider node
jumps to that provider's editor (the page owns an explicit
`TabController` for this). Below a minimum content width the canvas
scrolls horizontally rather than squeezing nodes together, and the
request log keeps a ~40% floor (min 120px) so a short window never
reduces it to a sliver. Cooldown uses the theme's new `warning` token —
amber for "wait", red stays for "failed".

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
- `requests.json` is a diagnostic log, not accounting: only served
  requests land in it, token figures are whatever the provider reported
  (absent stays absent, shown as `—`), and speed is completion tokens
  over the post-first-token span (the whole duration when there is no
  first-token mark) — `—` when the upstream reports no split.

## Alternatives considered

- **Fetch the built-in model catalog at seed time.** Rejected: first
  launch would block on an external API's mood, and the answer is stale
  by the next launch anyway. A pinned shortlist plus the existing fetch
  button is honest and instant.
- **Resurrect a deleted built-in when its id is missing.** Rejected:
  "seeded once" is the only rule that respects deletion. The flag makes
  the choice permanent rather than inferred.
- **A card-sized animation inside the settings page.** Rejected: what
  shipped is the full routing view as the AI surface's first tab — not
  a thumbnail, not a pushed page — because magpie proved people want
  the whole picture (nodes, wires, live flights) and a dedicated tab
  gives it the whole height of the window.
- **Pre-fill the name and let users ignore it.** Rejected by the
  requester: every provider named "DeepSeek" tells the user nothing about
  which endpoint it actually points at.

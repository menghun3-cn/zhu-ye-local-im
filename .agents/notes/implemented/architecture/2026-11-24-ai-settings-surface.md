# Agent Note: The AI settings surface edits one AiConfig through one AiRuntime

Status: implemented

English | [中文](2026-11-24-ai-settings-surface.zh.md)

## Problem

PR1 gave the app an AI core and PR2 a loopback gateway, but nothing on screen
could reach either: `providers.json` was only writable by hand, the gateway
flag had no switch, and the token a local tool needs was invisible. The third
milestone is the settings surface — and the interesting decision is not what
the page looks like but *who owns the write path*.

Two facts constrain the shape. The app already has a persistence convention —
JSON documents behind store abstractions, atomic writes, corruption moved
aside — and `AiConfigStore` honours it. And the gateway's bind is a side
effect of the `gateway.enabled` flag: persisting the flag without acting on
the socket leaves the document and the running server disagreeing, which is
exactly the kind of split-brain a settings page must not create.

## Decision

**`AiRuntime` (`lib/core/ai/ai_runtime.dart`) is the single write path.** It
owns the `AiConfigStore`, the `AiRouter`, the token and the bound
`AiGateway`. `save(config)` persists first, then reconciles the socket with
the flag — enable binds immediately, disable closes it, a bind failure leaves
the flag saved (the user's decision stands; the next launch retries) while
`gateway`/`endpoint` report null so the UI can say "configured but not
listening". `AiRuntime.open(directory)` is plain Dart — `dart:io` only — so
`dart test` exercises the whole lifecycle against a temp directory.

The app state opens the runtime whenever `seams.aiDirectory` exists — even
with the gateway flag off, because the settings page needs somewhere to write
the flag *to* — and hands it to `HomeShell`, which shows `AiPage` as a
fourth top-level surface between Transfers and My, only when a runtime
exists. The AI surface is a destination in its own right, matching the
screenshot card's rule one level up: a surface that can do nothing is
absent, not disabled. `AiPage` is a `DefaultTabController` with four
tabs — routing, providers, gateway, routing groups — over one shared
`AiConfig`; the routing tab is first because "what is being asked" is
the question the other three configure.

**The page is a view, not a second store.** `AiPage` holds the loaded
`AiConfig` and re-reads it after every save; edits go through
`runtime.save`, never around it. Provider and group editors are dialogs that
mutate a draft and hand one `AiProvider`/`AiRoutingGroup` back — the page
re-reads the document inside the save callback rather than closing over the
copy the tile was built from, so a fetch landing mid-edit cannot be silently
dropped.

Concretely the surface covers:

- **Gateway card** — the enable switch, and while enabled the endpoint as a
  read-only copyable field plus the keyring from
  [the gateway-keys note](2026-11-24-ai-gateway-keys.md): one tile per
  named key, masked secret behind an eye toggle, copy, per-key usage and
  delete (see that note for the auth model this replaced).
- **Providers** — one card per provider (a provider is acted on as a
  unit, so it gets its own boundary; disabled providers fade rather than
  disappear). The editor dialog is wide enough for a real catalogue and
  has name, API key (obscure, hint that local models need none), one tab
  per protocol holding its base-URL field with "Fetch models" and
  "Test connection" actions, and the model catalogue as *capsules* — a
  wrap of tappable pills, each showing a green 免费 tag and the context
  window when the endpoint reported them, selected state drawn as a
  check + brand border/background rather than a switch column. "Fetch
  models" calls `AiRouter.fetchModelCatalog(provider, protocol)`, which
  takes the provider object so it can fetch against *unsaved* endpoint
  edits; the codecs' new `decodeModelCatalog` keeps whatever metadata
  the listing volunteers (OpenRouter `context_length`/`pricing`, Zen
  `limit.context`/`cost`, Gemini token limits, Anthropic `display_name`)
  and merges it onto `AiProviderModel.contextTokens`/`isFree`/`label`,
  refreshing metadata on refetch while never touching enable flags —
  a refresh cannot silently widen what the gateway exposes. Built-in
  providers additionally drop anything the endpoint confirms as paid:
  they are free-tier by definition, and unknown pricing stays because
  some listings (Zen's Anthropic-shaped one) carry none.
- **Routing groups** — name plus an ordered member list with up/down
  reorder, because order *is* the failover order. The member picker offers
  `config.exposedModelRefs()` minus the group itself.
- **Delete** removes the provider *and* every group member prefixed
  `provider/` — a dangling reference would fail every request it was ordered
  into.
- **Brand marks everywhere.** `AiProvider.iconAsset` persists the preset's
  bundled SVG so the provider row, the editor header, and the routing node
  all render the same mark; it is copied from the preset at creation and
  carried through `copyWith`, so endpoint edits never lose it. Custom
  providers keep the generic glyph. The preset picker is grouped by kind
  (cloud / local / custom) with non-interactive section headers, and the
  editor title says "add" for an unsaved draft rather than always
  "provider". Fetch/test probing has its own busy flag so a slow network
  never traps Cancel — only an in-flight save does.

## Consequences

- Toggling the gateway switch binds or releases the port without an app
  restart; the endpoint and token are on screen for pasting into a client.
- `AiRouter.listModels(providerId, …)` remains for stored providers;
  `fetchModels(provider, …)` serves the editor's draft. Both share one code
  path.
- The AI surface's index shifts My one slot, so `_mySurface` is computed
  from `widget.ai != null` rather than written as a constant — the one
  index machinery still has to name stays single-sourced.
- New l10n keys (~45) landed in both ARB files and the generated
  localizations were regenerated and committed, per `l10n.yaml`.
- Still absent by design: in-app AI chat, message processing, smart replies —
  the consumers this configuration exists for.

## Alternatives considered

- **Gateway lifecycle inside the settings page.** Rejected: the socket must
  exist before anyone opens settings, and a page-owned server would die with
  the page. `AiRuntime` owns it for the app's lifetime.
- **Editing `providers.json` fields independently of the gateway flag.**
  Rejected: it is the split-brain described above. One `save` keeps document
  and socket in step.
- **A separate route/page per concern** (providers page, groups page, gateway
  page). Rejected: four pushed pages for ~45 fields would be navigation
  without payoff — the shipped shape is four tabs inside one surface, which
  keeps one back-navigation level and lets the routing view stay mounted.
- **AI as a card inside My.** Rejected by the requester: the routing
  animation is the feature's front door, and a card two taps deep buries
  it. Pulling AI out to its own top-level menu is what was asked for.
- **Fetch models only for persisted providers.** Rejected: the editor's whole
  point is fixing a wrong endpoint and *then* fetching; `fetchModels` taking
  the draft provider object is what makes that honest.
- **Auto-enabling fetched models.** Rejected, matching the store's documented
  rule: enablement is explicit so a refresh cannot widen exposure.

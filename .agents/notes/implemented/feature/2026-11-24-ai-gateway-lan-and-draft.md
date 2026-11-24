# Agent Note: The AI gateway defaults on and can answer the LAN; provider drafts stay unsaved

Status: implemented

English | [中文](2026-11-24-ai-gateway-lan-and-draft.zh.md)

> Amends
> [the loopback-only gateway](2026-11-23-ai-local-gateway.md): the bind is
> no longer loopback-only by fiat — scope is a persisted setting — and the
> flag now defaults on.

## Problem

First hands-on use of the AI settings surface produced two corrections.

The gateway shipped off by default and loopback-only. "Off by default" made
"configure once, use everywhere" a two-step discovery — a user had to know
the gateway existed before any local tool could benefit from it. "Loopback
only" was the right default but the wrong ceiling: the moment a second
machine on the LAN wants the same providers, there was no answer short of
editing `providers.json` by hand.

The provider editor had a subtler version of the same problem. Picking a
preset or "custom" wrote the new provider to `providers.json` *before* the
editor opened, so cancelling the dialog still left a provider behind — the
UI had already decided for the user.

## Decision

**Gateway scope is a persisted setting, on by default.**
`AiGatewayConfig` gained `scope` (`AiGatewayScope.loopback` | `lan`) and
`enabled` now defaults to `true` in both the constructor and
`fromJson` — a fresh install binds loopback at startup with an ephemeral
port, and an absent `gateway` section reads as on. Loopback exposure behind
a generated bearer token is nil-risk; the token file already exists for
exactly this.

**LAN is opt-in, and it means `0.0.0.0`, not a second socket.** Binding
`InternetAddress.anyIPv4` answers on `127.0.0.1` *and* every LAN address
with one listener — which is what "include both this machine and its IPs"
requires. `AiGateway` enumerates non-loopback IPv4 interfaces at bind time
(`NetworkInterface.list`, failures degrade to an empty list) so the settings
card can print one copyable endpoint per address. The card shows a
loopback/LAN `SegmentedButton`, the local endpoint always, and one
`http://<lan-ip>:<port>/v1` field per discovered address under LAN scope,
plus a hint that the token is the only credential on the wire.

**A scope or port change rebinds.** `AiRuntime` now remembers the
`AiGatewayConfig` the running server was bound with; a save whose
`enabled`/`port`/`scope` differs stops the old socket before binding the
new one. Before this, `running != null` short-circuited every enabled
save — a scope toggle would have silently kept serving loopback.

**Adding a provider is a draft until saved.** `_addProvider` no longer
persists the preset skeleton; it opens the editor on an in-memory
`AiProvider` and `_saveProvider`'s existing append path writes it only when
the user confirms. The delete button is hidden for unpersisted drafts —
there is nothing to delete — via a nullable `onDelete` on the editor
dialog.

## Consequences

- Every install now listens on loopback from first launch. The token is
  generated before the bind and is the only credential; a process on the
  machine can still read `gateway_token` from the app-data directory, which
  is the same exposure class as reading `providers.json` — accepted, since
  both files are per-user app data.
- LAN mode publishes the endpoint to every interface, including VPN and
  virtual adapters `0.0.0.0` covers. That is the documented trade of the
  mode; per-interface binding was rejected as complexity without a
  consumer.
- `providers.json`'s `gateway` section gains a `scope` string; files
  written before this change read back as `loopback` and whatever `enabled`
  they stored — except an absent section, which now reads enabled. No
  migration was needed because the feature had not shipped to users.
- Cancelling the add-provider dialog leaves `providers.json` untouched;
  the `_uniqueProviderId` slug is only claimed on save, so two cancelled
  drafts cannot collide.

## Alternatives considered

- **Keep the gateway off by default.** Rejected by the requester: the
  feature exists to be used, and loopback+token is not an exposure. The
  cost of "on" is one ephemeral port and one file.
- **Bind each LAN interface separately.** Rejected: `0.0.0.0` already
  answers on all of them plus loopback; enumerating and binding per
  address adds failure modes (interface appearing after bind) for no
  behavioural gain.
- **A second port for LAN.** Rejected: two listeners means two ports to
  display, two tokens' worth of confusion, and no isolation benefit —
  same process, same store, same token either way.
- **Auto-save the draft but mark it incomplete.** Rejected: a half-filled
  provider in the list is worse than none — it shows up in `/v1/models`
  conversations and group pickers as if it were real.

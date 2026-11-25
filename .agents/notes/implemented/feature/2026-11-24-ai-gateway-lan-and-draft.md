# Agent Note: The AI gateway defaults on and can answer the LAN; provider drafts stay unsaved

Status: implemented

English | [中文](2026-11-24-ai-gateway-lan-and-draft.zh.md)

> Amends
> [the loopback-only gateway](2026-11-23-ai-local-gateway.md): the bind is
> no longer loopback-only by fiat — scope is a persisted setting — and the
> flag now defaults on.
>
> Later amended by
> [the gateway keyring](2026-11-24-ai-gateway-keys.md): "the token" below
> is now one key in a named list; the scope, draft and rebind decisions
> stand.

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
`enabled` now defaults to `true` in the constructor — a fresh install
binds loopback at startup on the preferred port
(`AiGatewayConfig.defaultPort`, with ephemeral fallback when busy).
`fromJson` is deliberately different: a `providers.json` written before
the gateway existed has no `gateway` section, and an upgrade must not
silently start a listener the user never asked for — absent reads as
*off*; only files this feature wrote carry an explicit `enabled`. Loopback
exposure behind a generated bearer token is nil-risk; the keyring already
exists for exactly this.

**LAN is opt-in, and it means `0.0.0.0`, not a second socket.** Binding
`InternetAddress.anyIPv4` answers on `127.0.0.1` *and* every LAN address
with one listener — which is what "include both this machine and its IPs"
requires. `AiGateway` enumerates non-loopback IPv4 interfaces at bind time
(`NetworkInterface.list`, failures degrade to an empty list) so the settings
card can print one copyable endpoint per address. `dart:io` cannot tell a
virtual adapter from a physical NIC — Hyper-V `vEthernet`, VMware and
VirtualBox interfaces all report as ethernet — so the list filters known
virtual-adapter names and VirtualBox's default `192.168.56.0/24` host-only
subnet; a renamed virtual NIC may still appear, which costs a stray row,
never a wrong bind, because the socket is `0.0.0.0` either way. The
surviving list is sorted so RFC1918 space precedes overlay ranges —
interface enumeration order is arbitrary and an overlay NIC (Tailscale's
100.64/10, a VPN) routinely wins it, while the address a LAN peer
actually dials is the private one; the first entry is what the routing
node advertises as the gateway's address. The card shows a
`loopback`/`LAN` `SegmentedButton`, the local endpoint always, and one
`http://<lan-ip>:<port>/v1` field per discovered address under LAN scope,
plus a hint that the gateway key is the only credential on the wire.
Switching *to* LAN asks first: `0.0.0.0` plus plain HTTP means the key
can be sniffed on the network, so a confirmation dialog spells that out
before the scope is applied — the same courtesy destructive actions get.

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
  written before this change read back as `loopback`, keep their stored
  `enabled`, and — when they have no `gateway` section at all — read as
  disabled rather than silently opening a listener on upgrade. Only a
  fresh install (no file) gets the on-by-default.
- Cancelling the add-provider dialog leaves `providers.json` untouched;
  the `_uniqueProviderId` slug is only claimed on save, so two cancelled
  drafts cannot collide.

## Alternatives considered

- **Keep the gateway off by default.** Rejected by the requester: the
  feature exists to be used, and loopback+token is not an exposure. The
  cost of "on" is one listening port and one file.
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

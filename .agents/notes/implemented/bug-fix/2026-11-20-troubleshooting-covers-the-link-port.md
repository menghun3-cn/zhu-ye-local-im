# Agent Note: Troubleshooting diagnoses and repairs the link-share port, dynamic fallback included

Status: implemented

English | [中文](2026-11-20-troubleshooting-covers-the-link-port.zh.md)

## Problem

A share link generated on one machine could not be opened on another, and
the Troubleshooting page had nothing to say about why: its port check listed
the Session, Pairing and Discovery ports, and its firewall check judged
exactly those three against the inbound rules. The link-share HTTP server —
the thing actually serving `/s/` and `/f/` — was invisible to both.

Invisible was not the same as irrelevant, because the port is not fixed.
[LinkTransferServer](../../../../lib/core/link_transfer/link_server.dart)
binds lazily on the first share, prefers `defaultLinkTransferPort` (18080),
and falls back to a random port when that one is taken — after which every
generated link names the fallback. A firewall verdict keyed to 18080 alone
would call a machine "open" while the port its links actually use was
blocked, and the "open the ports" repair would write a rule that still did
not cover it.

## Decision

The diagnostics now carry the link port end to end, bound value preferred
over preferred value.

- **`linkPortLevel`** joins `sessionPortLevel`/`pairingPortLevel`. A `null`
  port — the server has not started, the ordinary state before the first
  share — reads `ok`; a bound port other than 18080 reads `warning`, the
  same verdict a Session or Pairing fallback gets.
- **`requiredInboundPortsFor({linkPort})`** extends the required set with
  `('TCP', linkPort)` for the firewall judgement, deduplicated against the
  base ports. `evaluateFirewallRules` and `firewallReportFromSnapshot` take
  the port as an optional parameter, so snapshots judged without it behave
  exactly as before.
- **The page passes the effective port**: `LinkTransfer.instance.port` while
  the server runs — the dynamic fallback the links name — and
  `defaultLinkTransferPort` while it has not, the best available answer
  because a share that would discover a different fallback cannot exist yet.
  The port check's detail line gained a `Link TCP` slot, a fallback note
  naming the actual port, and an idle note for the not-started state.
- **Repair covers both.** `firewallOpenScript` always writes the preferred
  18080 into the TCP rule — a server that fell back this run may well take
  it next time — and adds the bound `linkPort` when it differs, so the rule
  reads e.g. `18080,47655,47656,51234`. `openFirewallPorts` threads the
  parameter through, and `probeHostFirewall` does the same for detection.

## Alternatives considered

**Start the link server during diagnostics.** Rejected: binding a listener
is a side effect the page does not need — the first listen on a new port is
also what triggers the Windows Firewall prompt, and diagnostics offering to
*check* should not be the thing that makes the prompt appear. Reporting the
preferred port while idle answers the same question without binding.

**Judge only 18080.** Rejected: it is exactly the bug being fixed. Once the
server has fallen back, links name the fallback port, and a verdict or a
rule keyed to 18080 describes a port nothing is listening on.

**Open the program's TCP range instead of naming ports.** Rejected: a
`LocalPort Any` or ephemeral-range rule would cover every future fallback,
but it also admits this app on ports it never listens on — wider than the
problem needs, for a rule the app writes on the user's behalf.

**Fold the link port into `PortReport`.** Rejected as unnecessary: the class
carries the bound ports the controller reports at startup, while the link
server binds lazily and is read live from `LinkTransfer.instance` — there is
no startup snapshot for it to join.

## Consequences

- The port check now shows four ports and can warn on a link fallback; the
  firewall check flags `TCP <link port>` as missing when no rule covers it,
  and the repair button writes a rule that covers both the preferred and
  the bound port.
- `requiredInboundPorts` stays the three always-on ports; the link port is
  opt-in through `linkPort`, keeping every existing caller and test on the
  old behaviour until they pass one.
- A dynamic fallback is only as durable as the process: the next restart
  may rebind 18080, which is why the repair writes both ports rather than
  only the one currently bound.

## Testing

- `test/diagnostics/troubleshooting_test.dart` covers `linkPortLevel`
  (absent/preferred/fallback), a snapshot where the preferred link port is
  covered and where a dynamic `51234` is not — asserting the missing list
  names `TCP 51234` and not `TCP 18080` — and the elevated script containing
  `18080,47655,47656,51234` when `linkPort: 51234`.

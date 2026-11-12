# Agent Note: The troubleshooting page reports real answers, and can open the firewall itself

Status: implemented

English | [中文](2026-11-12-troubleshooting-diagnostics-are-real.zh.md)

## Problem

Every row on the troubleshooting page rendered the literal string `unknown` —
a hard-coded status in English, shown to a mostly Chinese-speaking user base,
answering nothing. The page was a placeholder that looked like a diagnostic.

Two of its questions are answerable without any new platform code: which ports
the listeners actually bound (the controller already exposes them), and whether
Windows Firewall has an inbound allow rule covering the ports peers need. The
third — "just let the app through the firewall" — is the natural follow-up,
and it is the one place where Windows insists on a UAC prompt.

## Decision

All four diagnostics now report real state, computed in `lib/core` so `dart
test` covers the judgement; the platform side is a MethodChannel snapshot
for the firewall read and one elevated PowerShell call for the write:

* **Ports** — pure functions over the ports the controller reports
  (`listenPort`, `pairingPort`). Serving on the well-known port is `ok`,
  serving on a fallback port is `warning` (Discovery still finds the Device;
  a bare-address dial on 47655 will not), and no listener is `error` for the
  Session and `warning` for Pairing, matching how the controller itself
  treats a missing Pairing listener as degraded rather than broken. The UDP
  discovery port needs no probe: a Device that could not bind 47654 never
  reached this page.
* **Network** — a count of non-loopback IPv4 interfaces; zero is `error`.
* **VPN** — interface names matched against tunnel/VPN markers (`tap`, `tun`,
  `wireguard`, `openvpn`, `ppp`, `vpn`, …). `tailscale` is deliberately not a
  marker: this app has a first-class Tailscale path, so its adapter is a
  feature. The result is a `warning` naming the adapters, because a name
  heuristic can only ever be a hint.
* **Firewall** — the Windows runner answers a `snapshot` method on the
  `cn.hnasct.local_transfer/firewall` channel (`windows/runner/
  firewall_probe.cpp`): `INetFwPolicy2` enumerates every enabled inbound
  allow rule and `INetworkListManager` reports the current network category
  and whether its profile's firewall is enabled — the same policy store the
  PowerShell cmdlets read, with no process spawned and no per-rule CIM round
  trip. Dart judges the decoded snapshot: a port counts as covered only when
  a rule matches protocol, port *and* applies to this process — either
  unscoped or scoped to `Platform.resolvedExecutable` — on a profile that
  matches the current network category, and a service-scoped rule never
  counts because it admits a service, not an executable. Program scoping is
  the part that is easy to get wrong: Windows' own "allow this app" prompt
  writes program-scoped rules, so judging by port alone would call a
  firewall that blocks this app "open".

The "Open firewall ports" button appears on Windows only, beside the port
check it exists for, and stays disabled until the probe reports `blocked` —
an open port or an unanswered question leaves it nothing to do. It cannot be
silent — adding a rule needs an administrator — so one click collects one UAC
consent and then runs `New-NetFirewallRule` twice, scoped with `-Program` to
the running executable: TCP `47655,47656` and UDP `47654`. The elevated half
is passed as `-EncodedCommand` (Base64 of UTF-16LE, encoded in Dart because
`dart:convert` has no UTF-16 codec) rather than as nested quoted arguments,
which is the one encoding that survives `Start-Process -ArgumentList`
intact. Each run first removes rules named `LocalTransfer` /
`LocalTransfer Discovery`, so re-running after the app moves updates the rule
instead of accumulating a stale one. Exit codes map to opened / cancelled
(declined UAC) / failed, and the page re-probes afterwards either way.

Every status word and detail line is a localized string; the old code put the
raw English token `unknown` on screen, which is what made the page read as
half-translated.

## Consequences

* `lib/core/diagnostics/troubleshooting.dart` is plain Dart with two seams:
  `ProcessRunner` for the elevated PowerShell call that *adds* rules, and the
  firewall MethodChannel for the probe. The channel itself is the thin half —
  COM in, a map out — while all parsing and verdict logic stays in Dart,
  covered by `test/diagnostics/troubleshooting_test.dart`; the channel's
  Dart-facing contract is covered by `test_flutter/platform/seams_test.dart`.
* The probe is one in-process COM enumeration, so re-checking is effectively
  instant — the earlier PowerShell version paid a CIM query per rule and
  took seconds on rule-heavy machines. It runs once per page visit and again
  on demand, which is the right cadence for a diagnostics screen.
* A runner built before the channel existed answers `MissingPluginException`,
  which the page reports as `unknown` — "cannot answer" rather than a guess.
* The firewall judgement is only as good as the rule data: a third-party
  firewall, a rule added after the probe, or traffic filtered outside Windows
  Firewall all read as "open" or "unknown" rather than as certainty. The
  heuristic is documented as such in the code.
* The opened rules are per-program and per-profile-agnostic (`Profile` left
  at the default `Any`), so they apply on Public networks too — deliberate,
  because the alternative is a feature that silently does nothing on the
  networks where users most need it.
* Android shows the port, network and VPN rows and hides the firewall button;
  the firewall row itself reports `unsupported`.

## Alternatives considered

**Binding the ports to test them.** Rejected: the app holds all three, so a
bind probe can never distinguish "our listener" from "a squatter", and the
question the page answers — "can peers reach me" — is about the listeners we
already know about, not about free ports.

**`netsh advfirewall` for the probe and the fix.** Rejected for the fix:
`netsh` cannot scope a rule to a program, so it would open the ports to every
process on the machine. For the probe it was viable but its output would need
a text parser that breaks on localization and formatting changes.

**`reg query` on `FirewallPolicy\FirewallRules`.** Rejected: the rules are
readable there without elevation and fast, but the `v2.x|key=value` format
is an implementation detail rather than a contract — a Windows update is
free to change it, and the failure mode is a silently wrong verdict.

**Keeping the PowerShell probe.** This is what the first version shipped,
and it was replaced: `Get-NetFirewallRule` resolves each rule through CIM,
so the probe took seconds on machines with hundreds of rules, and spawning
a shell for a read the process could answer itself was the expensive half
of the design. The COM snapshot reads the same store the cmdlets do, in
process, and the judgement stayed in Dart either way.

**The WFP API (`FwpmFilterEnum`) for the probe.** Rejected: kernel-level
filter enumeration mostly requires elevation, which would break the
"reading rules needs no administrator" property the probe relies on.

**Checking reachability by dialling our own LAN address.** Rejected:
hairpin behaviour through Windows Firewall is inconsistent, a loopback dial
bypasses the very filter being tested, and a failed self-dial cannot tell
"firewall" from "wrong address" apart anyway. Rule inspection answers the
question that is actually actionable.

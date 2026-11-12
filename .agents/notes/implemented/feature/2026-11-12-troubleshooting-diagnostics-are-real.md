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
test` covers the judgement and only the process-spawning is left to the
platform:

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
* **Firewall** — a PowerShell query (`Get-NetFirewallRule` + port and
  application filters, current `NetworkCategory`, profile `Enabled`) read
  without elevation, parsed as JSON. A port counts as covered only when an
  enabled inbound allow rule matches protocol, port *and* applies to this
  process — either unscoped or scoped to `Platform.resolvedExecutable` — on a
  profile that matches the current network category. Program scoping is the
  part that is easy to get wrong: Windows' own "allow this app" prompt writes
  program-scoped rules, so judging by port alone would call a firewall that
  blocks this app "open".

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
  `ProcessRunner` for the PowerShell calls and the enumerable interfaces for
  the network checks. The parsing and verdict logic is fully covered by
  `test/diagnostics/troubleshooting_test.dart`.
* The probe enumerates every enabled inbound allow rule, which is a CIM query
  per rule — on a machine with hundreds of rules it takes a moment. It runs
  once per page visit and again on demand, which is the right cadence for a
  diagnostics screen.
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
process on the machine. For the probe it was viable but the PowerShell object
model returns structured fields (protocol, port spec, profile, program)
directly, where `netsh` output would need a text parser that breaks on
localization and formatting changes.

**A MethodChannel into `windows/runner` for the firewall work.** Rejected:
the existing host channel exists for window and tray facts the runner owns.
Spawning PowerShell needs no native code, keeps the logic in testable Dart,
and the UAC boundary is the operating system's, not ours — a channel would
add a C++ surface for no capability gain.

**Checking reachability by dialling our own LAN address.** Rejected:
hairpin behaviour through Windows Firewall is inconsistent, a loopback dial
bypasses the very filter being tested, and a failed self-dial cannot tell
"firewall" from "wrong address" apart anyway. Rule inspection answers the
question that is actually actionable.

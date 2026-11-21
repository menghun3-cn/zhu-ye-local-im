# Agent Note: The firewall exception is attempted at install and offered once at startup

Status: implemented

English | [中文](2026-11-20-firewall-exception-at-install-and-startup.zh.md)

## Problem

Opening the firewall ports existed only as a manual repair: the user had to
suspect the firewall, find the troubleshooting page, and press the button —
while the site told every new user to "remember to allow the app through the
firewall" after installing. Green-package users had no installer at all, so
no install-time path could ever cover them, and nobody was going to read a
README line on a LAN tool.

The exception itself is worth having without being asked twice: once the
rules exist they are scoped to the program and survive updates, so the
product's job is to get them written once — at install where an installer
exists, and once at first run where it does not — and then never mention it
again.

## Decision

Two paths write the same pair of rules, named `LocalTransfer` (TCP
`47655-47657`, program-scoped) and `LocalTransfer Discovery` (UDP `47654`,
program-scoped), matching the ports
[the troubleshooting note](../feature/2026-11-12-troubleshooting-diagnostics-are-real.md)
already judges.

**Install time** (`packaging/local_transfer.iss`): after files are in place
(`ssPostInstall`), a non-silent install runs one elevated `netsh.exe -f
<script>` through `ShellExec`'s `runas` verb. The commands travel as a script
file in `{tmp}` rather than inline arguments, so delete-then-add is four
flat commands under **one** UAC prompt instead of four. `program=` scopes
each rule to `{app}\local_transfer.exe`; the earlier claim that netsh cannot
scope a rule to a program was wrong and is corrected in that note. A
declined UAC is not an install failure — the result is discarded on purpose,
and the runtime offer is the second chance. Silent installs (`/SILENT`,
including the in-app update) skip the step entirely: a UAC prompt mid-update
is a surprise, and program-scoped rules survive the file swap anyway.
Uninstall (`usUninstall`, non-silent) deletes the same two rule names so
nothing points at a removed executable.

**Runtime** (`lib/ui/dialogs.dart`, `lib/ui/home_shell.dart`): once per
install, after the first frame, the shell probes the firewall through the
existing `probeHostFirewall` seam. `blocked` opens a dialog naming the
uncovered ports with 「允许入站连接」 / 「暂不」; either answer — and any
non-blocked verdict — settles `DeviceProfile.firewallCheckDone`, persisted
like the other one-time preferences. 「允许」runs the existing
`openFirewallPorts` UAC flow and reports opened / cancelled / failed as a
`TopToast` reusing the troubleshooting strings. `unknown` leaves the flag
unset so an unanswerable probe is retried next launch rather than never
offered. Non-Windows platforms return before probing.

The manual troubleshooting page is unchanged and remains the way back for
everyone who answered 「暂不」.

## Alternatives considered

**Installer requires admin (`PrivilegesRequired=admin`).** Rejected: it
contradicts the per-user, no-UAC install the `.iss` header argues for, and
would charge every install a UAC prompt for a rule most users never needed
to think about. The elevated child process gets the same rule written with
the prompt appearing only where it is actually required.

**PowerShell `New-NetFirewallRule` inside the installer too.** Rejected for
quoting, not capability: the same commands would need `-EncodedCommand`
 Base64 plumbing inside Inno Pascal, while `netsh -f` takes flat lines. The
runtime keeps PowerShell because its idempotent script and test seam already
exist there; the two writers converge on rule names, which is what the
probe, the reinstall and the uninstaller all key on.

**A shipped helper exe calling `INetFwPolicy2` directly.** Rejected: one
firewall rule does not justify a second binary in the verified package, and
the COM API is exactly what `netsh` already wraps.

**Ask on every launch while still blocked.** Rejected: a user who said
「暂不」 or declined the UAC has answered; re-asking every start is nagging,
and the troubleshooting page is the honest place to revisit. `unknown`
probes are the one exception — they settle nothing.

**Mark settled when the dialog is merely shown.** Rejected: a crash between
the dialog and the answer would burn the one offer. The flag is written only
on a real outcome — a verdict or an answer.

## Consequences

- Installed users get the rules at setup with at most one UAC prompt;
  portable users get the same offer once at first run. Both converge on the
  same two rule names, so whichever path ran first, the others stay
  consistent.
- `DeviceProfile` gains `firewallCheckDone` (default false, tolerant read);
  `LocalTransferController` exposes `firewallCheckDone` /
  `markFirewallCheckDone()`.
- The installer script's UAC step cannot be exercised by `dart test`; it is
  verified by compiling the `.iss` in the packaging script and by the fact
  that a declined prompt leaves a working install. The runtime half is
  covered by the profile round-trip tests and the existing
  `ProcessRunner`/channel seams.
- Rules written at install cover the preferred link port 47657 only; a
  dynamic fallback port is still covered by the runtime script when the
  server binds it — same coverage the manual button always had.

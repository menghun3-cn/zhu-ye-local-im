# Agent Note: Starting with Windows is on by default for a fresh Device

Status: implemented

## Problem

The "start with Windows" switch exists so a Device meant to be reachable does not
have to be started by hand after every restart — but it ships off, so every new
install starts unreachable until someone finds the switch. The request was to
make it on by default.

The naive fix — write the registry entry whenever the profile has never been
touched — cannot tell a fresh install from an existing one whose user
*deliberately turned the switch off*: both look identical from the outside,
because "off" is just the absence of a `Run` entry. Retroactively turning the
default on would silently re-enable autostart for every user who had chosen it
off.

## Decision

`DeviceProfile` carries `autostartPreference`, a tri-state that records whether
the choice has been made: undecided, on, or off. It is persisted in the profile
JSON; a profile written before the field existed decodes as undecided.

`AppController.start()` is where the default lands, and only there. After the
profile loads, on a platform with a `HostShell`:

- If the preference is undecided **and** the profile did not exist before this
  launch — a genuinely new Device — `setAutostart(true)` runs once: the host
  writes the entry and the preference is recorded as on.
- If the preference is undecided but the profile already existed — an install
  that predates the default — the current registry state is read and recorded
  as the user's answer, without writing anything. Whatever the machine already
  does is what it keeps doing.
- Once the preference is on or off, startup never touches the entry. The
  registry stays authoritative for what will actually happen; the preference
  only answers "has anyone chosen".

`setAutostart` records the user's answer into the profile after the host write,
so an explicit "off" survives every later launch. The check for "did the
profile exist before" is a `ProfileStore.load()` taken before
`loadOrGenerateLocalProfile`, because that call creates and saves a fresh
profile as a side effect.

The whole block is Windows-shaped but platform-agnostic in code: Android has no
`controlsWindow` and its `hostShell` answers `MissingPluginException`, which
the existing `PlatformHostShell` handling already treats as "nothing happened".
Tests that need a decided profile get one from `ScriptedHostShell` defaults in
`ui_harness.dart`, so widget tests do not silently inherit the new default.

## What this deliberately does not do

It does not write the registry entry from the installer. The portable package
has no installer at all, and an installer-written entry would fight the
in-app switch: the app would read "on" while the profile says undecided, and
the first launch would record a choice the user never made.

It does not remember the autostart *state* — only whether it was chosen. The
entry itself is still read back on every launch, so a user who deletes it by
hand still sees the switch report what will actually happen.

## Alternatives considered

**Treat a missing registry entry as "new install".** Rejected: absence cannot
distinguish "never configured" from "deliberately turned off". That is the
whole reason the preference exists.

**Default on for everyone, once, on upgrade.** Rejected by decision: existing
installs keep what they had. Users who wanted autostart already turned it on;
users who turned it off keep it off; only genuinely new Devices get the new
default.

**Have the host shell own the default.** Rejected: the host cannot tell a
first-ever launch from a returning one either, and the "has this been asked"
fact belongs with the other user choices in the profile, beside
`CloseBehaviour`.

**Store the resolved state instead of the tri-state.** Rejected: caching
"enabled" or "disabled" would be a second copy of a fact the registry owns —
the rejected alternative in
[the desktop host shell](2026-10-12-the-desktop-host-shell.md) still stands.
The tri-state records only that a choice was made, never what the OS is doing.

## Consequences

**Bought.** A fresh Windows install is reachable after a reboot without anyone
visiting Settings; existing installs are untouched; an explicit choice — either
direction — is permanent; and the switch still tells the truth about the
registry rather than about a cached copy.

**The profile format grew a field.** Old JSON decodes as undecided, which is
the correct answer for "written before this existed" — the startup logic then
records the current state without writing. Forward compatibility is unchanged:
a newer build's value is an unknown string and decodes tolerantly.

**One extra store read at startup.** `start()` now loads the profile once
before generating it, to learn whether it existed. On the common path this is
a single small JSON read.

## Testing

`test/profile/device_profile_test.dart` covers the field: undecided by
default, missing key in old JSON, explicit on/off round trips, and the wire
name.

`test_flutter/ui/window_settings_test.dart` covers the behaviour against
`ScriptedHostShell`: a fresh Device is written the default once and it is not
repeated on the next launch; an install that predates the default records what
the host already had without writing; turning the switch off and restarting
keeps it off.

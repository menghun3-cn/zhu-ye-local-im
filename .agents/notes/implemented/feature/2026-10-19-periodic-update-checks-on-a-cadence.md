# Agent Note: Periodic update checks on a cadence

Status: implemented

English | [中文](2026-10-19-periodic-update-checks-on-a-cadence.zh.md)

## Problem

The rail's update entry knows only what the application asked once at startup.
An app that is opened, paired, and then sits in the tray for days is exactly
the app whose owner would benefit from a version that was published while the
window was not looking — but it would never hear about it until a restart.

那一次检查是刻意的一次性动作（About 文案把它写成「唯一的例外」）。把检查变成周期动作，
需要一个用户能看见、能关掉的开关：机器人式的静默轮询是另一回事，它从来不在设置里出现过，
也没有人同意它存在。

## Decision

**A per-Device preference in the profile, defaulting to hourly.** The enum
`UpdateCheckInterval` lives in `lib/core` (pure Dart, `test/`-reachable) and
persists in `DeviceProfile` as `updateCheckInterval`, with wire names
`off / hourly / six-hours / daily / three-days`. A profile written before the
key existed, or carrying a value this build does not know, decodes to the
default — the same tolerant rule the profile applies to optional preferences.

**Settings owns the choice.** A new 更新检查 section on the Settings surface
shows a switch (periodic on/off) and, while on, a `SegmentedButton` of the four
cadences. Changing either persists through the controller's `_persist()` and
notifies listeners, so the section redraws immediately.

**`UpdateNotice` re-arms a `Timer.periodic` from the profile interval.**
`attach(controller)` is called once the controller has started; the notice
listens to the controller's change stream and re-arms whenever the interval
changes. `off` cancels the timer. The timer lives in `lib/ui` (it already owns
`UpdateResolution.checker`), and the About text now names the startup question
*and* the chosen cadence as the two deliberate exceptions to staying inside
the local network.

## Alternatives considered

**A fixed internal timer with no Settings control.** Rejected: a background
probe the user can neither see nor stop is exactly the kind of network promise
this product is careful about, and the About text would need another exception
with no way to turn it off.

**Use `shared_preferences` for the interval.** Rejected: the interval is a
Device preference like `closeBehaviour`, and the profile is already the one
place such preferences live, persist, and are read at startup.

**Make every cadence its own switch.** Rejected: the choice is "how often", not
"which checks"; a single switch plus a segmented row says that in two controls.

**No periodic check, rely on the next manual check.** Rejected: the whole point
is that a build published while the tray icon sits closed still finds its way
to the rail without a restart or a manual press.

## Consequences

- `lib/core/update/update_check_interval.dart` is new; `DeviceProfile`,
  `LocalTransferController`, `UpdateNotice`, `lib/ui/app.dart` and the Settings
  page gained the interval.
- The About page's description now mentions the Settings-chosen cadence as the
  outgoing-request exception.
- Widget tests cover the Settings section and the timer cadence; profile tests
  cover defaults, tolerance, round-trip and wire names.
- The feature ships with the default hourly, a deliberately quiet cadence, and
  the user can choose six hours, a day, three days, or off.

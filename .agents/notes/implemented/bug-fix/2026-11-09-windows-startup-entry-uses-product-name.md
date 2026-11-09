# Agent Note: The Windows startup entry uses the product name

Status: implemented

English | [中文](2026-11-09-windows-startup-entry-uses-product-name.zh.md)

## Problem

The installed application's user-visible names were already Chinese: the installer shortcuts and start-menu group, the window title, and the executable's `FileDescription` and `ProductName` all say 竹叶局域网传输. One Windows surface still did not: the per-user `Run` entry behind 开机自启动 was stored under the value name `LocalTransfer`, and Windows uses that value name when it lists the startup app. The request was to make the displayed names consistent without renaming `local_transfer.exe`.

## Decision

The `Run` value is now `竹叶局域网传输`, matching the name the shortcuts, start menu, window title, and executable metadata already carry. The executable filename remains `local_transfer.exe`: the request was for display names, and the Flutter/CMake and packaging pipeline still keys off that filename.

`HostShell` reads both the current and the earlier `LocalTransfer` value names, so an entry written by an older build still counts as enabled. `Attach` migrates that legacy entry once per launch, but only when it points at the running executable: the new value is written first and the old one is deleted only after that write succeeds, so a failed write cannot cost the user their autostart entry. An entry pointing at another install is left alone. Turning the switch off deletes both names; turning it on writes the product name and removes the legacy one.

## Consequences

- New startup entries and migrated existing entries appear under 竹叶局域网传输 in Windows' startup lists instead of `LocalTransfer`.
- An older entry keeps working until the first launch of this build, when it is moved rather than left as a second startup entry.
- `autostartEnabled` still answers from the registry alone; the legacy name is compatibility input, not a second source of truth.
- Package names, the portable update payload check, installer paths, and the executable itself keep their existing `local_transfer` / `LocalTransfer` spellings.

## Alternatives considered

**Rename the executable to `竹叶局域网传输.exe`.** Rejected: the request scoped this to display names, and the build and update pipeline expects `BINARY_NAME.exe` plus the packaging scripts' `local_transfer.exe` contract.

**Keep `LocalTransfer` as the `Run` value name.** Rejected: it is exactly the internal-looking name the startup list was showing.

**Write both `Run` values.** Rejected: one application would have two startup entries, and every later read, write, and disable path would have to remember the pair forever.

**Migrate only when the user toggles the setting.** Rejected: users who already enabled autostart would keep the old display name until they happened to touch the switch.

## Testing

The Windows runner has no unit harness; the change is covered by compiling `windows/**` through the normal Windows build. The registry contract is deliberately small: both names are read for the enabled answer, writes always target the product name, deletes cover both names, and migration happens only for an entry that points at the running executable.

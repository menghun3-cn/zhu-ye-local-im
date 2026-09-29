# Windows and Android Platform Facts

Verified from primary sources on 2026-09-29. Facts only.

## Windows packaging and firewall

Flutter's official Windows distribution guidance offers:

- **MSIX** — via the `msix` package; distribute through the Microsoft Store or
  your own website. Notably: *"You don't need to manually create a signing
  certificate for this option as it is handled for you"* (for the Store path).
- **A zip file** — the build output directory contains `flutter_windows.dll`,
  `msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`, `data/app.so`,
  `data/icudtl.dat`, and the app `.exe`.
- **Third-party installers** — Flutter's docs state that adding the output
  folder to an installer "such as Inno Setup, WiX, etc." is "relatively simple",
  and point to a step-by-step Windows packaging guide.

**Firewall consequence.** Windows Defender Firewall blocks unsolicited inbound
traffic by default, and the `Public` profile is the default for unidentified
networks. An app that binds a listening socket therefore triggers a prompt, and
on a Public-classified network may be blocked outright. LocalSend documents the
same requirement: *"Make sure to configure your network as a 'private'
network."* A LAN app must either instruct the user, add a firewall rule at
install time (`netsh advfirewall firewall add rule`), or both.

The development machine used for this project has
`NetworkCategory = Public` on its active interface, so this is a live concern
rather than a hypothetical one.

## Android multicast reception

From the `WifiManager.MulticastLock` API reference:

> The Wifi stack filters out packets not explicitly addressed to this device.
> Acquiring a `MulticastLock` will cause the stack to receive packets addressed
> to multicast addresses. Processing these extra packets can cause a noticeable
> battery drain and should be disabled when not needed.

API surface:

- `acquire()` — "Locks Wifi Multicast on until `release()` is called."
- `release()` — "Unlocks Wifi Multicast, restoring the filter of packets not
  addressed specifically to this device and saving power."
- `isHeld()` — whether the lock is currently held.
- `setReferenceCounted(boolean refCounted)` — reference-counted vs
  non-reference-counted lock behaviour.

The permission `CHANGE_WIFI_MULTICAST_STATE` is required.

**Consequence:** multicast reception on Android is an explicit, battery-costly,
manually-managed state, not a default. A design that assumes always-on
multicast listening will drain battery; the lock should be acquired around the
discovery window and released after. Note this interacts with the "Known
Device unicast" approach: unicast reconnection needs no multicast lock at all,
which is a further argument for it on mobile.

## Related material

Other primary sources retrieved during research remain described in
`android-background-constraints.md`. This file covers what was extracted from
the Windows packaging (`_flutterwin.txt`) and multicast lock (`_mlock.txt`)
sources.

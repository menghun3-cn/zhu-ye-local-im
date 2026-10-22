# Agent Note: A reserved listener port falls back instead of stopping startup

Status: implemented

English | [中文](2026-10-22-reserved-listener-ports-fall-back.zh.md)

## Problem

Windows can reserve a range of TCP ports for WinNAT, Hyper-V, WSL, or Docker.
A bind inside that range fails with `WSAEACCES` (`errno = 10013`) even when no
process is listening on the port. One development machine had
`47622-47721` reserved, which contains both the Session port `47655` and the
Pairing port `47656`. Because a paired Device binds the Session port while
starting, the `SocketException` escaped `start()` and the application showed
its fatal startup screen instead of opening. The same reservation also left
the Pairing listener unable to answer new requests.

The fixed ports are useful: a peer with only an address can dial without
waiting for Discovery. They are not useful enough to make the application
unbootable or unable to pair when the operating system refuses them.

## Decision

Both listeners treat a non-zero configured port as a preference. The
controller first tries the requested port; if that bind fails, it binds port
`0` on the same listener and records a notice naming both ports. A requested
port of `0` has no second choice, so its failure still propagates.

The Session fallback belongs in the application layer rather than in
`LinkManager.serve`. `LinkManager` keeps its literal contract, while the
controller owns the policy and already has the Discovery layer that must carry
the port actually bound. `manager.advertised` and `LinkManager.listenPort`
continue to report that actual port.

The Pairing listener follows the same policy. `PairingService.receive` still
reports a failed bind instead of silently choosing another port, so a caller
that explicitly selected one can rely on the result.

Discovery's `DeviceDescriptor` carries an optional `pairPort` alongside the
Session port. The controller fills it with the Pairing listener's actual bound
port, and the click-to-pair flow dials that value. An older peer that does not
send the field, or a peer that is not answering Pairings, keeps the
well-known-port fallback.

## Testing

`test/app/app_controller_test.dart` blocks real ports with a `ServerSocket`.
One test pairs two Devices, restarts one with a blocked Session port, and
checks that it listens elsewhere, reports the substitution, and is reconnected
by Discovery. A second test starts a Device with a blocked Pairing port,
checks the fallback notice, waits for the peer to learn the actual port from
Discovery, and completes a Pairing using the host address alone.

`test/identity/identity_test.dart` checks that both ports survive the
descriptor's JSON round trip and that an out-of-range Pairing port is rejected.

The two-window end-to-end suite asks for a Pairing port of its own rather than
the shipped fixed one. `flutter test` runs the test files side by side, and
another file stands a whole `LocalTransferApp` up on the well-known Pairing
port; the two raced for it, and whichever lost failed a test that had nothing
wrong with it. A port of `0` gives the suite one of its own, and the guest
still reaches the host because the host says where it answers. The same
race was the reason the end-to-end suite failed intermittently under a full
parallel run.

## Consequences

- A paired Device starts and serves Sessions when its preferred port is
  reserved by Windows or held by another process.
- A Device with a reserved Pairing port remains answerable; Discovery carries
  the replacement port to peers that use click-to-pair.
- Discovery and the handshake advertise the ports actually bound, so automatic
  reconnection and pairing do not require the user to know a fallback happened.
- Settings notices explain each substitution instead of hiding it.
- A manual Session address that omits a port still assumes `47655`; after a
  fallback, the user has to enter the port shown by the application.
- A manual Pairing address uses the discovered Pairing port when Discovery
  knows that host, and otherwise keeps the `47656` default.

## Alternatives considered

**Choose another fixed default port** — it would only move the collision. The
ranges Windows reserves are dynamic and differ between machines.

**Keep treating a failed fixed bind as fatal** — this is the defect: a local
port reservation would prevent the application from opening at all.

**Always bind arbitrary ports** — this gives up the useful case where a peer
that already knows the address can dial without Discovery.

**Stop WinNAT before starting the application** — this is a machine-level
workaround that disrupts WSL, Hyper-V, and Docker, and the application cannot
perform it on behalf of the user.

**Make the core listeners silently fall back** — the core layers would stop
doing what their callers asked, and a caller that explicitly selected a port
could no longer rely on the result. The controller is the layer that knows the
port is only a preference and can advertise the replacement.

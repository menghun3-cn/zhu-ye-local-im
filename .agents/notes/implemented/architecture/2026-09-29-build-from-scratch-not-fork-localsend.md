# Agent Note: Build the transfer stack from scratch rather than fork LocalSend

Status: implemented

English | [中文](2026-09-29-build-from-scratch-not-fork-localsend.zh.md)

## Problem

LocalSend is Apache-2.0, mature (roughly 92k stars, commits within days of this
writing), and already ships most of what this product needs: LAN discovery,
TLS transport, six platforms, a transfer engine, and i18n. Forking it was the
obvious path, and the product was initially described as "a tool like
LocalSend".

But the two features that justify this product at all are the two LocalSend has
left open for years: clipboard sync (issue #163, open since February 2023) and
discovery across subnets (issue #1840, open since September 2024). A tool that
is strictly "like LocalSend" would inherit exactly the two defects it exists to
fix.

## Decision

This project writes its own client and its own wire protocol, and deliberately
does **not** implement LocalSend protocol compatibility. LocalSend is used as a
**shape reference** — the discover → pick device → send interaction, and the
feature set (files, folders, text, multiple recipients, favourites, history) —
not as a code base and not as a wire contract.

The Owner identity layer (see the owner-identity note) has no place in
LocalSend's device-only model, and conforming to its wire format would
constrain the transfer design to solve a compatibility problem this project
does not have.

## Alternatives considered

**Fork LocalSend.** Would inherit protocol v2.2, TLS client certificates, six
platforms, the transfer engine, and roughly 200 already-fixed bugs documented in
its changelog (filename sanitisation, path traversal, 2 GB size overflow,
Android SAF, macOS sandbox, Wayland tray). Rejected: its architecture is a Dart
UI over a Rust protocol core bridged with `flutter_rust_bridge` plus 1.1 MB of
Rust, so the identity layer becomes an invasive change to a foreign core rather
than an addition; and its two gaps are precisely this product's reason to exist.

**Own client, LocalSend-compatible protocol.** Would let existing LocalSend
users interoperate on day one, easing cold start. Rejected: pins the design to
a protocol with no Owner concept, and makes upstream's choices into this
project's constraints.

**Own client, own protocol.** Chosen.

## Consequences

- The bug classes LocalSend's changelog documents are re-inherited. Filename
  sanitisation, path traversal, and integer overflow on large transfers must be
  designed in from the start rather than patched later.
- Cross-subnet discovery and clipboard sync are first-class design problems
  rather than bolt-ons, which is the entire point of the project.
- Interoperating with LocalSend later would require adding a second protocol
  implementation, not adapting this one. That door is deliberately closed.
- Being a shape reference, LocalSend's UX decisions remain available as prior
  art; its code does not.

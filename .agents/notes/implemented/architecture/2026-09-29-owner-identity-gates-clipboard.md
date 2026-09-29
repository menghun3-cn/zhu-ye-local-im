# Agent Note: Owner identity layer gates clipboard mirroring

Status: implemented

English | [中文](2026-09-29-owner-identity-gates-clipboard.zh.md)

## Problem

LocalSend's model has Devices and a Favorite flag and nothing else. That is
sufficient for file transfer, where each transfer is a deliberate user action
with an explicit recipient, but it is unsafe for clipboard sync.

Clipboard content routinely contains passwords, one-time codes, and private
keys. "This Device may receive my files" and "this Device may read my
clipboard" are different trust levels, and a single Favorite flag cannot
express the difference. A user who once favourited a colleague's laptop in
order to send files would, on enabling clipboard sync, silently mirror
passwords to it.

## Decision

The domain gains an **Owner**: the person a Device belongs to, established by a
key pair that never leaves the Device. Devices sharing an Owner form an
**Owner Group**, and clipboard Mirroring happens only within that group. A
Device joins a group through a one-time **Pairing** — a scanned QR code, or a
short code with short-authentication-string comparison.

There is no account and no server. `Favorite` remains, but is explicitly
*not* membership of an Owner Group and confers no clipboard access; the two
concepts are kept distinct in the glossary for exactly this reason.

## Alternatives considered

**Per-Device clipboard toggle, decoupled from Favorite.** No new identity
concept: each Device gets an independent "share clipboard with this Device"
switch. Rejected because the failure mode is silent and severe. Configuration
error becomes a security incident, and users cannot be expected to reliably
manage a per-device matrix of trust levels.

**Treat Favorite as sufficient trust.** Simplest, and matches LocalSend
exactly. Rejected for the same reason: it conflates two trust levels that users
do not distinguish.

**Full account system.** Rejected outright: it requires a server, which the
product forbids.

## Consequences

- `Owner`, `Owner Group`, and `Pairing` become core domain concepts, and the
  model deliberately diverges from LocalSend's. The product is no longer "a
  LocalSend clone"; it is a LAN transfer tool with an identity layer.
- Pairing needs a user-facing flow, which is also the mechanism that makes
  cross-subnet connection possible without discovery: one feature serves both
  needs, and the QR code carries address, port, public-key fingerprint, and a
  one-time token at once.
- Key loss means losing the group: every Device must be re-paired. Recovery is
  a product decision, not a technical one, and is unresolved.
- Clipboard capability differs per platform (reading the clipboard is
  restricted far more tightly than writing it), so a Device's ability to
  originate and to apply a Mirror are declared separately.

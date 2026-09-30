# Agent Note: The Owner identity is a persisted key pair, and the profile is its local state

Status: implemented

English | [中文](2026-09-30-owner-identity-key-pair-and-device-profile.zh.md)

## Problem

[CONTEXT.md](../../../../CONTEXT.md) defines the Owner as "established by a
key pair that never leaves the Device", and the Fingerprint as "the SHA-256
of a Device's public key". Until this increment nothing in the codebase owned
that key pair: the Fingerprint inside a `DeviceDescriptor` was whatever the
running code chose to put there, a Device forgot everything — including who
it was — on restart, and there was no place for Known Devices, Favorites or
Owner Group membership to persist. Every later feature that needs identity
continuity — Pairing, Favorites skipping confirmation, Mirroring only within
an Owner Group — would have had to invent its own storage, and they would
have disagreed.

## Decision

A Device's persistent self is one object, `LocalProfile`, loaded and saved as
one unit through a `ProfileStore`:

- `OwnerIdentity` holds the Owner's Ed25519 key pair. The Fingerprint is
  SHA-256 of the raw public bytes — the same derivation a peer applies, so
  both sides agree on identity without a third party. The key signs identity
  challenges; it never contributes to session key agreement, so compromising
  it reveals nothing about session traffic. Only [SecureLink](../../architecture/2026-09-29-core-wire-protocol-and-secure-session.md)
  and the ephemeral X25519 exchange inside it derive session keys.
- `DeviceProfile` is the local state around that identity: the announced
  `alias` (sanitised by the same rules as a peer-supplied one, via
  `DeviceDescriptor.sanitiseAlias`), the platform, the [Owner Group](../../architecture/2026-09-29-owner-identity-gates-clipboard.md)
  the Device belongs to, the set of Favorites, and the Known Devices table
  with last-seen time and address.
- `ProfileStore` moves JSON. `MemoryProfileStore` covers tests;
  `FileProfileStore` writes a sibling temp file and renames it into place, so
  a crash mid-write leaves the previous profile intact. A file that cannot be
  decoded raises `ProfileCorruptedException` after being moved to
  `<path>.corrupt` — never deleted, because it is the only copy of the
  Device's identity.
- The persisted form embeds the Ed25519 seed under a `kind: ed25519-seed`
  tag, and loading refuses a profile whose `self` fingerprint disagrees with
  the seed's key: that combination is not a Device, it is a contradiction,
  and it fails loudly rather than silently becoming a different Device.
- A `session` section sits beside the identity and carries the group secret
  (`LocalProfile.groupSecret`, absent until a Pairing produces one), because a
  Device that forgot it would have to be re-paired after every restart. It
  lives on `LocalProfile` rather than on `DeviceProfile`: a profile is state a
  UI renders and a test builds by hand, and key material has no place in
  either.

Trust stays split exactly as the vocabulary demands: Owner Group membership
is the Mirroring grant, Favorites are the weaker "skip per-transfer
confirmation" grant, and Known Devices confer nothing — they are
observations.

## Alternatives considered

**Derive the Fingerprint from an ephemeral key and re-roll on restart.**
Rejected: a Device whose fingerprint changes on every restart cannot be
recognised, and every trust decision in the product — Favorites, Owner
Group, pinned peers — would reset with it.

**Store the key pair in the OS credential vault (DPAPI, Keystore).**
Rejected for v1: it needs a platform channel per platform, and the profile
file already lives in the user's own profile directory with the same threat
model as the rest of the on-disk state. The seed is base64 in a JSON file the
user can read, which is honest about what it is; a v2 that moves the seed
into a vault changes one accessor, not the model.

**Make Favorites imply Owner Group membership or vice versa.** Rejected: the
whole point of [Owner identity gates clipboard](../../architecture/2026-09-29-owner-identity-gates-clipboard.md)
is that "may receive my files" and "may read everything I copy" are different
grants. A Favorite that silently gained clipboard access would break that
boundary, and a group member forced to confirm every Transfer would make
Mirroring worthless in practice.

**Silently regenerate on a corrupt profile.** Rejected: the failure mode is
"one day all your devices treat this one as a stranger", which is exactly the
kind of quiet identity change the Owner concept exists to prevent. Moving the
damaged file aside and reporting it keeps the user in control.

## Consequences

- A Device survives a restart with the same fingerprint, the same Owner
  Group, and the same peer history. Pairing, Favorites and Mirroring can now
  be built on identity continuity instead of inventing their own.
- The private key sits in a JSON file on local disk. Anyone who can read that
  file can *be* this Device — the same trust boundary as the rest of the
  on-disk state, and deliberately no stronger.
- The group secret shares that boundary, and it is the stronger of the two in
  effect: the key proves identity, but the group secret is what opens Sessions
  inside the Owner Group at all.
- `lib/core/` remains Flutter-free: the platform is a parameter of
  `loadOrGenerateLocalProfile`, not something the core detects, so the
  `dart test` gate still covers everything here.
- A profile restored from a partial copy — identity seed without the profile
  section, or the reverse — fails at load with a `FormatException` naming
  the missing part, rather than defaulting silently.

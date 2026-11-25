# Agent Note: The gateway authenticates a keyring of named client keys, not one token

Status: implemented

English | [中文](2026-11-24-ai-gateway-keys.zh.md)

> Amends
> [the LAN gateway and draft providers](2026-11-24-ai-gateway-lan-and-draft.md):
> the single generated bearer token becomes a maintainable list of named
> keys, one per client.

## Problem

The gateway's only credential was one `lt-ai-` token shared by every
caller. Two practical gaps showed up immediately. Every client had to be
handed the *same* secret, so there was no way to tell which tool spent
the quota — the request log could say which model served, never which
client asked. And the token had no lifecycle at all: it was generated
once, displayed once, and the only way to rotate or revoke it was
deleting a file by hand.

## Decision

**`gateway_keys.json` holds a keyring; `gateway_token` migrates into it.**
`AiGatewayKeyStore` (`lib/core/ai/gateway_keys.dart`) persists
`[{name, secret, created_at}]` beside `providers.json`. On first open it
seeds a key named `default`: the secret is the legacy `gateway_token`
file's contents when that file exists — every already-configured client
keeps working with zero re-pasting — or a freshly generated
`sk-<random>` otherwise. Secrets are stored plaintext, same as the token
file they replace: they are bearer credentials shown in the UI by
design, and sealing them would only move the plaintext somewhere else.

**Corruption is an error, never a rotation.** `load()` throws
`AiGatewayKeyStoreException` when the file exists but does not parse —
the previous `catch → []` read corruption as "no keys", after which
`loadOrCreate` minted a fresh `default` and silently locked every
configured client out. `loadOrCreate` now seeds only when the file is
absent: an existing file is returned as-is, even an empty list, so a
deliberately emptied ring cannot resurrect `default`. `AiRuntime.open`
swallows the exception so the rest of the AI stack still comes up; the
gateway's per-request `keySource` rethrows (requests fail rather than
authenticate against rotated credentials) and the settings surface shows
a "key file corrupted" hint until the file is repaired.

**The gateway accepts any key in the ring.** `AiGateway` takes a
`keySource` callback re-read on every request, so adding or deleting a
key in settings is live immediately — no rebind, no restart. The
matched key's *name* (never its secret) is passed to
`AiRouter.chat(clientKey:)`, which stamps it on the `AiRequestRecord`;
the request log's per-key usage rollup is then a plain count over
`record.key`, with pre-key rows attributed to `default`.

**Authentication follows RFC 7235 and does not leak internals.** The
`Bearer` scheme is matched case-insensitively (`bearer`, `BEARER` and
`Bearer` all authenticate; other schemes do not), and secrets compare in
constant time — XOR-accumulated over the UTF-8 bytes so neither content
nor length shows in response timing on a LAN where the token is the only
credential. Handler failures answer a generic `internal gateway error` /
`stream interrupted` rather than echoing the exception text to the
caller.

**The UI is a list, not a field.** The gateway tab shows each key as a
tile — name, masked secret behind an eye toggle, copy, per-key usage
(`{requests} requests · {tokens} tokens` from the request log), and
delete. "Add gateway key" expands an inline row: a name field (hint
shows the convention, e.g. 笔记本） and an optional secret field —
empty means generate `sk-…` — with create/cancel. The last key cannot
be deleted: a gateway with zero credentials refuses every caller, which
is a locked door with no key under the mat. Duplicate names or secrets
are rejected with a toast. Deleting a key asks for confirmation first —
revoking a credential is the same weight as deleting a provider — and
the create button stays disabled until the name field has content, so
an empty name can no longer be a silent no-op. The masked secret shows
one dot per character instead of a fixed count, so a custom secret's
length reads honestly.

## Consequences

- Each client gets its own revocable credential; per-client usage is a
  group-by, not new instrumentation.
- `gateway_token` survives only as a migration source — new installs
  never write it.
- The old `lt-ai-` prefix is gone for new keys (`sk-` prefix, the same
  convention magpie uses); migrated `default` keys keep whatever secret
  they had, prefix included.
- Key comparison is constant-time over the UTF-8 bytes — cheap at any
  keyring size, and the LAN scope makes timing a real (if minor) signal.
- A corrupt `gateway_keys.json` leaves the gateway refusing every request
  until the file is fixed — the honest failure, versus silently rotating
  credentials every client depends on.

## Alternatives considered

- **One token plus a "regenerate" button.** Rejected: it rotates *all*
  clients at once — exactly the operation you cannot perform safely
  when one of them is a laptop you no longer have.
- **Per-key secrets sealed in `secrets.key` like provider API keys.**
  Rejected: the secrets exist to be pasted into other tools, so the UI
  must show them; sealing buys nothing a plaintext file beside
  `providers.json` does not already give.
- **Deleting `gateway_token` on migration.** Rejected: the file is
  harmless once seeded, and leaving it lets a downgrade still find its
  credential.

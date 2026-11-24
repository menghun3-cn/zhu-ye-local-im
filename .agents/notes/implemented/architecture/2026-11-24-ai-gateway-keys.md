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

**The gateway accepts any key in the ring.** `AiGateway` takes a
`keySource` callback re-read on every request, so adding or deleting a
key in settings is live immediately — no rebind, no restart. The
matched key's *name* (never its secret) is passed to
`AiRouter.chat(clientKey:)`, which stamps it on the `AiRequestRecord`;
the request log's per-key usage rollup is then a plain count over
`record.key`, with pre-key rows attributed to `default`.

**The UI is a list, not a field.** The gateway tab shows each key as a
tile — name, masked secret behind an eye toggle, copy, per-key usage
(`{requests} requests · {tokens} tokens` from the request log), and
delete. "Add gateway key" expands an inline row: a name field (hint
shows the convention, e.g. 笔记本） and an optional secret field —
empty means generate `sk-…` — with create/cancel. The last key cannot
be deleted: a gateway with zero credentials refuses every caller, which
is a locked door with no key under the mat. Duplicate names or secrets
are rejected with a toast.

## Consequences

- Each client gets its own revocable credential; per-client usage is a
  group-by, not new instrumentation.
- `gateway_token` survives only as a migration source — new installs
  never write it.
- The old `lt-ai-` prefix is gone for new keys (`sk-` prefix, the same
  convention magpie uses); migrated `default` keys keep whatever secret
  they had, prefix included.
- Key comparison is a plaintext string match per request — fine at
  keyring sizes (a handful), and constant-time comparison was rejected
  as ceremony for a loopback/LAN bearer check.

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

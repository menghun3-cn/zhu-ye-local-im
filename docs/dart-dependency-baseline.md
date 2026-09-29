# Dart Dependency Baseline

Verified against the pub.dev JSON API on 2026-09-29. Facts only.

Target toolchain: Flutter 3.47.x / Dart 3.13.x (per ADR-0004, the local
Flutter 3.29.2 / Dart 3.7.2 toolchain is upgraded before coding starts).

## Cryptography

| Package | Latest | Published | SDK constraint | Notes |
|---|---|---|---|---|
| `crypto` | 3.0.7 | 2025-11-04 | `^3.4.0` | Official Dart team. SHA-256/HMAC only — no asymmetric crypto. |
| `cryptography` | 2.9.0 | 2025-11-21 | `>=3.3.0 <4.0.0` | Pure-Dart + optional native. Ed25519, X25519, AES-GCM, HKDF, Chacha20. |
| `cryptography_plus` | 3.0.0 | 2026-03-02 | `^3.5.0` | Community continuation of `cryptography`; more recent than the original. |
| `pointycastle` | 4.0.0 | 2025-02-19 | `^3.2.0` | Pure Dart, low-level, huge API surface. Needed for runtime X.509 generation. |
| `basic_utils` | 5.8.2 | 2025-02-23 | `>=2.18.0 <4.0.0` | X.509 / CSR generation helpers on top of PointyCastle. |
| `ed25519_edwards` | 0.3.2 | 2026-08-25 | `>=2.12.0 <4.0.0` | Narrow: Ed25519 only. Actively published. |

**Note on the fork.** `cryptography` (original) last shipped 2025-11 and sits at
2.9.0; `cryptography_plus` forked and moved to 3.0.0 in 2026-03. Which of the
two is the live line needs a deliberate choice, not a default.

## Secure storage

| Package | Latest | Published | SDK constraint |
|---|---|---|---|
| `flutter_secure_storage` | 11.2.0 | 2026-09-16 | `>=3.8.0 <4.0.0` |
| `flutter_keychain` | 3.0.1 | 2026-03-30 | `>=2.17.0 <4.0.0` |

`flutter_secure_storage` 11.2.0 was published 13 days before this was written
and **requires Dart `>=3.8.0`** — the local Dart 3.7.2 cannot resolve it.
This independently confirms the toolchain upgrade is a prerequisite, not a
nicety.

## QR codes

| Package | Latest | Published | Status |
|---|---|---|---|
| `pretty_qr_code` | 3.6.0 | 2026-01-31 | Actively maintained. **Preferred generator.** |
| `qr_flutter` | 4.1.0 | **2023-05-14** | **Stale — over 3 years without a release.** |
| `mobile_scanner` | 7.4.2 | 2026-09-14 | Very active; the live scanner option. |
| `zxing2` | 0.2.4 | 2025-06-06 | Pure-Dart decoder; candidate for decoding from an image file. |
| `qr_code_tools` | 0.2.0 | 2025-05-14 | Low version number; treat with caution. |

`qr_flutter` is the package most commonly recommended for Flutter QR
generation and it has not shipped since May 2023. Use `pretty_qr_code`.

## Other

| Package | Latest | Published | SDK constraint |
|---|---|---|---|
| `permission_handler` | 13.0.2 | 2026-09-04 | `^3.6.0`, Flutter `>=3.24.0` |

## Discovery packages (from [lan-sync-research.md](lan-sync-research.md))

| Package | Latest | Newest usable on Dart 3.7.2 |
|---|---|---|
| `nsd` | 5.0.1 (`^3.11.0`) | 5.0.0 |
| `bonsoir` | 7.1.5 (`>=3.8.0`) | 5.1.11 |
| `multicast_dns` | 0.3.3+1 | query-only, no advertising |

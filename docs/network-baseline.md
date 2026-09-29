# Network Baseline — measured on this machine

Measured 2026-09-29 with `Get-NetIPAddress`, `Get-NetRoute`, `Get-NetNeighbor`,
`Get-NetConnectionProfile`, `tracert`. Facts only; no decisions here.

> **Scope warning.** This file records the machine the toolchain happens to be
> installed on. It is **not** a statement of the target scenario. The product's
> requirements come from the user's real topology, which is described
> separately. Do not derive requirements from this file.

## Current attachment

| Interface | IP | Prefix | Origin | Gateway |
|---|---|---|---|---|
| 以太网 (Realtek PCIe GbE) | 192.168.1.199 | /24 | DHCP | 192.168.1.1 |
| WLAN (Intel Wi-Fi 6 AX201) | 192.168.1.84 | /24 | DHCP | 192.168.1.1 — **disconnected** |
| 以太网 2 (Sangfor SSL VPN VNIC) | 2.0.1.28 | /24 | Manual | — **disconnected** |

- **Gateway 192.168.1.1 = TP-LINK** (OUI `F4:6D:2F`).
- **NetworkCategory = `Public`.** This matters: Windows Defender Firewall's
  public profile blocks inbound by default, so a listening app gets blocked
  until the network is reclassified or a rule is added.
- 16 IPv4 neighbours are visible on 192.168.1.0/24 (see ARP below), so this is
  a flat, populated /24 with working peer visibility.

## The "second subnet" in ARP is stale, not real

`192.168.31.1` (`50:D2:F5` = **Xiaomi**) appears in the ARP table but is **not
reachable**:

```
tracert 192.168.31.1
  1  <1 ms  192.168.1.1        <- our own gateway
  2   2 ms  112.66.64.1        <- a public China Telecom address
```

There is **no route to 192.168.31.0/24** (`Get-NetRoute` lists only
192.168.1.0/24 and 2.0.1.0/24), so the packet falls through to the default
route and leaves for the ISP. `192.168.31.x` is the factory-default subnet of
Xiaomi/Redmi routers, so this is a leftover ARP entry from a previously
connected network. TCP 80 to both `192.168.31.1` and `192.168.31.100` fails.

**Consequence: this machine currently sits on a single flat subnet.** The
cross-router problem is not reproducible from here as configured. It must be
reproduced deliberately, or described by the user from their actual topology.

## Environment facts

- **Flutter 3.29.2 stable / Dart 3.7.2** installed at `D:\tools\flutter`.
  Current stable is **3.47.5 / Dart 3.13.4** (released 2026-09-18) — the local
  toolchain is ~8 months and ~6 minor versions behind.
- Android SDK at `D:\tools\Android\sdk`.
- `D:\pcdata\code\aicg\ai-local-im` is a git repository whose only branch is
  `master`, with no commits and no remote configured. It contains `.agents/`,
  `docs/`, `scripts/`, `CONTEXT.md`, and `AGENTS.md`.
- **No LocalSend installation detected** on this machine.
- SSL VPN clients are installed (Sangfor SSL VPN, RuiJie SSLVPN). Both are
  currently disconnected, but VPN clients of this class routinely install
  routes and can hijack or blackhole LAN traffic — relevant because LocalSend
  has open issues about VPN breaking discovery (#1598, #2266).

### Dependency compatibility against the installed Dart 3.7.2

The toolchain gap is not cosmetic: the two discovery packages we need cannot
take their current versions on this SDK.

| Package | Latest | Latest SDK constraint | Newest usable on Dart 3.7.2 |
|---|---|---|---|
| `nsd` | 5.0.1 | `^3.11.0` (Flutter ≥3.41.0) | **5.0.0** (`>=3.0.0 <4.0.0`) |
| `bonsoir` | 7.1.5 | `>=3.8.0 <4.0.0` | **5.1.11** (published 2025-02-14) |
| `permission_handler` | 13.0.2 | `^3.6.0` (Flutter ≥3.24.0) | 13.0.2 — OK |
| `clipboard_watcher` | 0.3.0 | `>=3.0.0 <4.0.0` | 0.3.0 — OK |
| `super_clipboard` | 0.9.1 | — | OK (published 2025-06-11) |

Using `nsd` 5.0.0 or `bonsoir` 5.1.11 means forgoing 8–19 months of upstream
fixes on the exact packages this product depends on most.

## ARP neighbours observed on 192.168.1.0/24

```
192.168.1.1     F4-6D-2F-9B-4B-39   Reachable   TP-LINK (gateway)
192.168.1.157   00-0C-29-E4-02-FB   Reachable   VMware, Inc. (a VM host)
192.168.1.34    F4-3B-D8-16-54-B8   Stale
192.168.1.40    C8-58-C0-41-29-D1   Stale
192.168.1.73    04-F0-EE-8F-EF-30   Stale
192.168.1.83    86-5F-C1-F5-E9-FA   Stale   (randomised MAC)
192.168.1.85    6E-8F-A8-4D-01-61   Stale   (randomised MAC)
192.168.1.92    40-49-0F-9A-1E-D4   Stale
192.168.1.124   F4-CE-23-A3-02-91   Stale
192.168.1.133   C8-CB-9E-49-F8-31   Stale
192.168.1.141   A8-2B-DD-2D-D6-54   Stale
192.168.1.164   58-1C-F8-B8-C3-51   Stale
192.168.1.169   40-B0-76-0B-C8-93   Stale
192.168.1.177   5C-B4-7E-94-8A-0E   Stale
```

Two MACs (`86:5F:C1…`, `6E:8F:A8…`) have the locally-administered bit set —
these are phones using MAC randomisation, which is worth remembering: a Device
identified by MAC address would change identity between sessions.

# Agent Note: v1 ships on Windows and Android only

Status: implemented

English | [中文](2026-09-29-v1-scope-windows-and-android.zh.md)

## Problem

The product is a cross-platform Flutter app and the reference tool in this
space ships on six platforms, so scoping v1 to two looks like an omission.
Platform scope decides the clipboard feature's achievable guarantees, the
permission and packaging work, and the size of the test matrix, so it cannot be
left implicit.

## Decision

v1 targets **Windows and Android**. macOS and Linux are best-effort secondary
targets — they share almost all of Windows' code path so building them is
cheap, but neither is guaranteed. **iOS is out of scope.**

- **Windows** is the only platform with a clean, prompt-free, fully background
  clipboard path (`AddClipboardFormatListener` plus a message-only window). It
  is the reference platform for the clipboard feature and therefore primary.
- **Android** is the device actually present when the user hits the problem,
  and the main consumer of file transfer. It can apply an incoming clipboard
  Mirror in the background even though it cannot originate one.
- **macOS and Linux** cannot be relied on: Wayland exposes the clipboard only
  to the focused client, and macOS release builds silently fail to accept
  inbound connections unless `com.apple.security.network.server` is added to
  `Runner-Release.entitlements`, since it is present only in debug and profile
  builds by default.
- **iOS** is excluded because automatic clipboard sync is not achievable with
  public APIs, and receiving multicast requires the
  `com.apple.developer.networking.multicast` entitlement, which must be
  requested from Apple and approved. Neither cost buys v1 anything.

## Alternatives considered

**All six platforms, matching LocalSend.** Rejected: three of the six have
clipboard behaviour that cannot meet the product's promise, and iOS adds an
Apple approval process and a signing/distribution burden for a platform where
the headline feature is impossible.

**Windows only.** Would give the strongest single-platform clipboard story and
the smallest test matrix. Rejected because the motivating scenario is moving
content between a computer and a phone; a desktop-only tool does not solve it.

**Windows, Android, and iOS.** Rejected for the Apple entitlement and
approval cost combined with iOS's impossibility of automatic clipboard sync.

## Consequences

- Two platforms to test rather than six, which keeps the verification burden
  real rather than nominal.
- Clipboard guarantees differ per platform by construction. The UI must state
  per-Device capabilities rather than implying parity, which is why
  `Clipboard Capability` exists as a domain concept.
- Adding iOS later is additive, but its clipboard behaviour will never match
  Windows. That asymmetry is permanent and belongs in the product language
  rather than being hidden.

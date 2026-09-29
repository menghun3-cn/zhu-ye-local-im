# Platform Clipboard Constraints

Facts only. Verified against primary sources; AOSP read directly from source.
These are hard limits that shape what clipboard sync can be, per platform.

## The core asymmetry

**Reading the clipboard and writing the clipboard have completely different
rules.** Nearly every platform restricts *reading* (it leaks secrets) and
allows *writing* (it is not a disclosure). This means "can this Device mirror
its clipboard to others" and "can this Device receive a mirrored clipboard"
have different answers on the same platform.

| Platform | Read (detect a copy → send) | Write (apply a mirror → receive) |
|---|---|---|
| **Windows** | Yes, in background | Yes, in background |
| **macOS** | Yes, in background (macOS 15.4+ prompts) | Yes |
| **Linux X11** | Yes | Yes |
| **Linux Wayland** | **No** — focused client only | Restricted; needs data-control |
| **Android** | **Only while focused/visible** | **Yes, in background** |
| **iOS/iPadOS** | **Only in foreground, with a prompt** | **Only while running** |

## Android — verified in AOSP source

From `ClipboardService.clipboardAccessAllowed()` in
`platform_frameworks_base` (`services/core/java/com/android/server/clipboard/ClipboardService.java`):

```java
case AppOpsManager.OP_WRITE_CLIPBOARD:
    // Writing is allowed without focus.
    allowed = true;
    break;
```

Read is gated far more tightly. `OP_READ_CLIPBOARD` is allowed only if the
caller holds `READ_CLIPBOARD_IN_BACKGROUND` (a privileged permission ordinary
apps cannot obtain), **is the default IME**, has **window focus**
(`isDefaultDeviceAndUidFocused`), is SystemUI with window focus, is the
Content Capture service, is the Augmented Autofill service, or owns a
privileged VirtualDevice.

Consequences:

- **A foreground service does not help.** The read check requires *window*
  focus, not process liveness. An app with a running foreground service but no
  visible window still cannot read the clipboard.
- **An Android Device can therefore receive a Mirror but cannot originate
  one.** It can be a mirror *target* in the background; it can only be a
  mirror *source* while its window is actually on screen.
- `OnPrimaryClipChangedListener` exists, but AOSP re-checks access per listener
  when dispatching the change broadcast, so a background listener is never
  called.
- `ClipDescription.EXTRA_IS_SENSITIVE` is a **rendering hint only** — the docs
  state it "does not change clipboard behavior or add additional security". It
  must not be relied on as a security control.
- Android 13+ shows a system copy-preview overlay; it is SystemUI-owned with
  **no app-facing API to suppress it**.
- Android auto-clears the clipboard after 1 hour by default
  (`DEFAULT_CLIPBOARD_TIMEOUT_MILLIS = 3600000`).

## iOS / iPadOS

- `UIPasteboard.changeCount` increments on change and **resets to 0 on
  reboot** — it cannot be used as a persistent version marker.
- iOS 16+ raises an **Allow Paste** system prompt on programmatic reads of
  `UIPasteboard.general`. `UIPasteControl` pastes without a prompt.
- Prompt-free *checks* exist (`hasStrings`, `numberOfItems`, `types`,
  `detectPatternsForPatterns:`) but `detectPatternsForPatterns:` explicitly
  does **not** return contents — so you can learn *that* something was copied
  without being able to read it.
- **No background monitoring mode.** A backgrounded app cannot run the code
  that would read the clipboard, and cannot present the prompt.

## macOS

- `NSPasteboard.changeCount` polling works; `NSPasteboard.general` is the
  target.
- **macOS 15.4+** adds `NSPasteboard.AccessBehavior` (`.default` / `.ask` /
  `.alwaysAllow` / `.alwaysDeny`); the general pasteboard defaults to **ask**
  on programmatic access. A background sync can therefore be interrupted by a
  prompt.
- Flutter macOS apps are sandboxed by default and need
  `com.apple.security.network.client` (outbound) and
  `com.apple.security.network.server` (inbound).

## Windows

- `AddClipboardFormatListener(hwnd)` → `WM_CLIPBOARDUPDATE` (`0x031D`), Vista+.
  A **message-only window** works for a background app.
- `GetClipboardSequenceNumber()` gives a cheap change token.
- `SetClipboardViewer` / `WM_DRAWCLOARD` are legacy; the chain "can be broken
  by an application" — do not use.
- **This is the only platform with a clean, prompt-free, fully background
  clipboard path.** It is the reference platform for clipboard sync.

## Linux

- **X11**: the clipboard is a selection owned by a client; any client may read
  or take ownership. Contents are **lost when the owning client exits** unless
  a clipboard manager is running. No permission model at all.
- **Wayland**: core `wl_data_device` exposes the selection **only to the
  focused client**, so background reads are impossible by design.
  `wlr-data-control-unstable-v1` allows a privileged client to manage
  selections but is **explicitly deprecated** in its own documentation: "not
  intended for production use". Its replacement, `ext-data-control-v1`, is
  still in wayland-protocols **staging**, with varying compositor support
  [unverified].

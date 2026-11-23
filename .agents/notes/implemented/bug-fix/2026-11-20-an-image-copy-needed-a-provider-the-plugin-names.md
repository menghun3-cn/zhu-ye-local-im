# Agent Note: An image copy needed a provider the plugin names itself

Status: implemented

English | [中文](2026-11-20-an-image-copy-needed-a-provider-the-plugin-names.zh.md)

## Problem

Long-pressing a received picture and choosing *Copy image* always failed on
Android with the "could not copy this photo" toast, while the same action
worked on Windows.

`SystemClipboardPaste.writeImage` delegates to `Pasteboard.writeImage`. On
Android the plugin stages the bytes as a scratch PNG under `cacheDir` and hands
the clipboard a `content://` URI for it — and it builds that URI with
`FileProvider.getUriForFile(context, "${packageName}.provider", file)`, an
authority string **hardcoded inside the plugin**. The app's manifest declared
exactly one `FileProvider`, under the authority
`${applicationId}.update_file_provider`, which serves the update installer and
the file/folder openers in `MainActivity`. Nothing answered to
`<applicationId>.provider`, so `getUriForFile` threw before a single byte
reached the clipboard, the plugin answered `error`, and the Dart side — which
correctly treats a refused clipboard write as an ordinary outcome — surfaced
the failure toast.

Windows never sees this because its `writeImage` path is a different one: the
plugin writes a temp file and sets `CF_BITMAP` through its own channel, with
no `FileProvider` anywhere in the story. iOS and macOS likewise write the
image natively. The bug was Android-only by construction, not by accident of
testing.

Declaring the authority turned out not to be the whole story. On-device
verification showed `ContentResolver` routing `<applicationId>.provider` URIs
to the *update* provider's instance — logcat reported "The authority
`...provider` does not match the one of the contentProvider:
`...update_file_provider`" — so `getType` on the clipboard URI failed and the
clip went out without a usable MIME type. Android runs **one provider instance
per class name** within a package: two `<provider>` entries that both name
`androidx.core.content.FileProvider` collide in `ActivityThread`'s provider
cache, and the second authority is served by the first instance, which knows
nothing about the clipboard paths.

## Decision

The manifest declares the authority the plugin asks for, as a **second**
`FileProvider` beside the update one — and the second one is a distinct
*class*, `ClipboardFileProvider`, a trivial `FileProvider` subclass declared
in the app package:

```xml
<provider
    android:name=".ClipboardFileProvider"
    android:authorities="${applicationId}.provider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/clipboard_image_paths" />
</provider>
```

The paths file exposes **only** `cacheDir` (`<cache-path name="clipboard_image"
path="."/>`), which is the one directory the plugin writes its scratch PNG
into. The existing `update_paths.xml` already maps `cache-path`, but reusing
it would also expose `filesDir` and external storage under the new authority —
more surface than a clipboard write needs, for no gain.

Authorities alone do not disambiguate two providers of the same class: the
class name is what `ActivityThread` keys its running-provider cache on, so the
clipboard provider must be a different class to get its own instance. A
one-line subclass is the smallest way to get one.

## Alternatives considered

**Point the plugin at the existing `update_file_provider` authority.** Not
possible without forking or patching the plugin: the authority is a string
literal inside `PasteboardPlugin.kt`, not a parameter. A `dependency_override`
to a patched fork was rejected as too heavy a maintenance surface for one
manifest line.

**Write the image to the clipboard from `MainActivity` on our own channel.**
Rejected: it duplicates what the plugin already does on three other platforms
(decode, compress to PNG, `ClipData`), and the only thing actually missing was
the provider declaration. The fix belongs in the manifest, where the missing
fact lived.

**Reuse `@xml/update_paths` for the new provider.** Rejected on least
privilege: that file whitelists all of `filesDir` (received files, identity
data) and external storage. The clipboard needs one directory; the new paths
file grants exactly that.

## Consequences

- *Copy image* on Android now reaches the system clipboard; the same fix also
  covers the QR-code copy on the share-by-link page, which goes through the
  same `writeImage` seam.
- The plugin still leaves its scratch PNG in `cacheDir` after each copy — a
  pre-existing leak inside the plugin, bounded by the system's cache
  eviction, and not something this change takes on.
- There is no Dart-side or widget-test coverage for this: the failure lived
  entirely in manifest/plugin interaction, which `dart test` and
  `flutter test` cannot reach. Verification is a build-and-tap on a device —
  on the emulator, `content query`/`content read` against the staged
  `content://<applicationId>.provider/clipboard_image/…` URI returns the
  scratch PNG, and logcat no longer logs "Failed to get type" for it. Other
  apps reading the URI still get the usual clipboard grant: Android's
  `ClipboardService` grants read on a clip's URIs to each package that pulls
  `getPrimaryClip`, which is why the provider stays non-exported.

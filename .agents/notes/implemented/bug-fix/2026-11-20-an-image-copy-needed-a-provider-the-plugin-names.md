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

## Decision

The manifest declares the authority the plugin asks for, as a **second**
`FileProvider` beside the update one:

```xml
<provider
    android:name="androidx.core.content.FileProvider"
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

Two `FileProvider` entries in one manifest is ordinary Android: authorities
are the disambiguator, and each keeps its own paths file.

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
  `flutter test` cannot reach. Verification is a build-and-tap on a device.

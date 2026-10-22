# Agent Note: Give Android the Zhuye application identity

Status: implemented

English | [中文](2026-10-22-android-application-identity.zh.md)

## Problem

The Android build installed under the launcher label `local_transfer`, which is
the Dart package name rather than the product name people see in the rest of the
application. Its Gradle namespace, application ID, Kotlin package, and method
channel all used `cn.hnasct.local_transfer`, so Android also placed the
application's private profile, messages, and incoming files under
`/data/user/0/cn.hnasct.local_transfer/files`.

The product is **竹叶局域网传输**, and the repository's owner identity is
`io.menghun3-cn`. The requested dotted identity was
`io.menghun3-cn.zhu-ye-local-im`, but Android application IDs follow the Java
package grammar: hyphens are not legal characters in a package segment. Using
that spelling verbatim would produce a manifest that cannot be built.

## Decision

The Android identity is `io.menghun3_cn.zhu_ye_local_im`, the closest legal
spelling of the requested identity:

* Gradle uses it for both `namespace` and `applicationId`.
* `MainActivity.kt` lives at
  `android/app/src/main/kotlin/io/menghun3_cn/zhu_ye_local_im/MainActivity.kt`,
  declares the matching Kotlin package, and registers the
  `io.menghun3_cn.zhu_ye_local_im/paths` channel.
* Dart names the same paths channel, so `filesDir.absolutePath` continues to be
  the one source of the Android storage location.
* The launcher label is `竹叶局域网传输`.

Android derives the private storage location from `applicationId`. After this
change it is `/data/user/0/io.menghun3_cn.zhu_ye_local_im/files`; no Dart-specific
storage root is involved.

## Alternatives considered

**Use `io.menghun3-cn.zhu-ye-local-im` exactly.** Rejected: hyphens are not valid
in Android package segments, so the application would not build. Replacing them
with underscores preserves the owner and project words while satisfying the
platform grammar.

**Keep `cn.hnasct.local_transfer` and change only the launcher label.** Rejected:
the installed application identity and private storage directory would still
carry the old owner name. The request explicitly covers both code and storage.

**Keep the old application ID and migrate its private directory at startup.**
Rejected: Android gives one application ID no access to another application's
private sandbox. A new package cannot read the old package's
`/data/user/0/cn.hnasct.local_transfer/files` without an explicit export,
backup, or user-mediated transfer that does not exist in this product.

**Change the Windows runner channel and window class too.** Rejected for this
change: the request is Android-specific, and the Windows host-shell protocol is
an independent durable contract. Renaming it without a Windows migration would
turn a display fix into a second compatibility break.

## Consequences

The new APK is a different Android application package. It can coexist with the
old `cn.hnasct.local_transfer` installation, but it cannot upgrade it. Users
must uninstall the old package before installing this identity if only one launcher
entry is wanted. Old pairing records, messages, settings, and queued files remain
inside the old application's private sandbox and are not visible to the new
package; they must be paired again and configured again.

The benefit is a stable, owner-specific application identity, an unambiguous
Chinese launcher label, and a storage path whose package name matches the code
and platform channel. The Android bridge test reads the manifest, Gradle, Kotlin,
and Dart sources together and pins the label, namespace, application ID, package
directory, and channel to this identity.

## Testing

`test/platform/android_bridge_test.dart` verifies the launcher label, the
`io.menghun3_cn.zhu_ye_local_im` namespace and application ID, the Kotlin package
path, and the Dart/Kotlin paths-channel agreement without an emulator. The
profile-location tests use the new application-private directory fixture.

# Android Background Transfer Constraints

Verified from Android developer documentation on 2026-09-29 (pages fetched
directly; `developer.android.com` served content to `Invoke-WebRequest`).

## `dataSync` foreground service has a 6-hour budget

From *Foreground service timeouts*:

> If an app targets Android 15 or higher, the system places restrictions on how
> long certain foreground services are allowed to run while your app is in the
> background. Currently, this restriction only applies to `dataSync` and
> `mediaProcessing` foreground service type foreground services.

> The system permits `dataSync` and `mediaProcessing` foreground services to
> run for a total of **6 hours in a 24-hour period**, after which the system
> calls the running service's `Service.onTimeout(int, int)` method (introduced
> in Android 15).

Key details:

- The budget is **cumulative per 24 hours**, not per service instance. A
  `dataSync` service that already ran one hour leaves five.
- The budget is tracked **separately** for `dataSync` and `mediaProcessing`.
- On reaching the limit the service gets **a few seconds to call
  `Service.stopSelf()`**; after `onTimeout` it is **no longer considered a
  foreground service**.
- `shortService` has a more restrictive limit of its own.
- This applies to apps **targeting Android 15 (API 35) or higher**, and only
  while the app is in the background.

**Consequence for this product:** a LAN file transfer is exactly a `dataSync`
workload, and a multi-hour transfer budget is a real ceiling on a device that
is also expected to run all day. Transfer design cannot assume the app may
hold a `dataSync` foreground service indefinitely.

## Android 17 (API 37) blocks local network access by default

Confirmed via the Flutter documentation *Request local network permissions on
Android*:

> Starting in Android 17 (API level 37), Android blocks local network access by
> default. Apps targeting Android 17 or higher that discover, scan, or connect
> to devices on the local area network must declare and request the
> `ACCESS_LOCAL_NETWORK` runtime permission.

> Because Dart sockets cannot display an Android permission prompt, any attempt
> to connect to a local IP address without the required permission fails and
> throws a `SocketException`.

The documented pattern is to call `Permission.accessLocalNetwork.request()`
(via `permission_handler`) **before** opening any Dart socket, and to handle
`denied` / `permanentlyDenied` (the latter requiring `openAppSettings()`).
The permission is declared in `AndroidManifest.xml` as
`android.permission.ACCESS_LOCAL_NETWORK`. Testing is possible on API 36 by
opting in.

Note that LocalSend shipped a fix in 1.18.1 for exactly this ("add missing
ACCESS_LOCAL_NETWORK permission that is required for Android 17+").

## Multicast reception

Receiving multicast on Android requires `WifiManager.MulticastLock` plus the
`CHANGE_WIFI_MULTICAST_STATE` permission. Reference material for both was
retrieved but not yet read in detail — treat the exact current guidance as
**[partially verified]**.

## Related material retrieved

The following primary sources were downloaded to scratch files in the
workspace root (`_*.txt`) and remain available for reading:
`_bc14.txt`, `_bc15.txt`, `_bc16.txt`, `_bc17.txt`, `_bc17all.txt` (behaviour
changes per API level), `_fgs.txt`, `_fgsperm.txt`, `_timeout.txt`,
`_dto.txt` (background task options), `_lnp.txt` (local network permission),
`_mlock.txt` (`WifiManager.MulticastLock`), `_nwd.txt` / `_nwdref.txt` (nearby
Wi-Fi devices permission), `_postnotif.txt` (notification permission),
`_dkm.txt` (don't kill my app), `_flutterwin.txt`, `_flutterlinux.txt`,
`_fluttermacos.txt`, `_flutterdist.txt` (packaging), `_flatpaknet.txt`
(Flatpak sandbox permissions).

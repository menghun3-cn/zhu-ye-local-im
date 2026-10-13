# Agent Note: A download that went to the blocked host

Status: implemented

English | [中文](2026-10-13-a-download-that-went-to-the-blocked-host.zh.md)

## Problem

A user pressed 下载并更新 on the About card of a running build and was told
「下载没有完成。请检查网络后重试。」 — `UpdateInstallFailure.download`. The same
card had just answered 检查更新 with 「有新版本 v0.1.2。」, which is the part that
made it a defect rather than a report about a network: *this application* could
reach GitHub, and could not get the file.

The two are different hosts, and nothing in this application had ever noticed.
The question is asked at `api.github.com/repos/…/releases/latest`
(`GitHubUpdateChecker`, `update_check.dart`). The file is fetched at the asset's
`browser_download_url`, which is `github.com/…/releases/download/<tag>/<file>`
(`_download`, `update_install.dart`). Measured on the development machine
against the real `v0.1.2` release, with every proxy variable cleared so that the
copy under test was as isolated from a proxy as a double-clicked build is:

| request | result |
| --- | --- |
| the latest-release API on `api.github.com` | 200, `tag_name` `v0.1.2` |
| `github.com/…/releases/download/v0.1.2/LocalTransfer-0.1.2-windows-x64-portable.zip` | nothing, ever: `TimeoutException` after the 15 s the request allows |
| the asset's API address (`…/releases/assets/636200087`) with `Accept: application/octet-stream` | 200, 13,375,776 B, sha256 `b4e6cbd5…17294` — the artifact, byte for byte, matching the digest the release publishes |
| either of the two, through a working HTTP proxy | 200, the whole file |

So the failure is exact: **the host this application asks its question of is
reachable, and the host it fetches the answer from is not.** The check succeeds,
the install cannot, and retrying cannot change either.

Three things kept that from being visible anywhere:

- **The user's sentence named the network, and the network was fine.** 「请检查
  网络后重试」 is the right thing to say to somebody whose connection dropped,
  and the wrong thing to say to somebody whose connection is working and whose
  address is refused. It invites the one action that cannot help.
- **Every failure became one name.** `_download`'s `on Object` is deliberate —
  `UpdateInstallFailure.download` is the honest answer to "it did not arrive" —
  but it also meant a refused host, a timeout and a 404 were indistinguishable
  on screen and in any report.
- **Nothing in the repository had ever run this path.** The six gates do not
  download a release, and there is no test that could: `test/` may not use the
  network. The download was exercised for the first time by a user pressing the
  button on a released build.

## Decision

**A release's file has two addresses, and both are tried.** `UpdateAsset`
carries `apiUrl` — the asset's own `url` field, an `api.github.com` address —
beside the `browser_download_url` it already carried, and
`downloadAddresses(asset)` returns them API-first, without duplicates:

```dart
List<String> downloadAddresses(UpdateAsset asset) {
  final addresses = <String>[];
  final apiUrl = asset.apiUrl;
  if (apiUrl != null && apiUrl.isNotEmpty) addresses.add(apiUrl);
  if (asset.url.isNotEmpty && !addresses.contains(asset.url)) {
    addresses.add(asset.url);
  }
  return addresses;
}
```

`_download` walks that list, one `HttpClient` per attempt, and returns as soon
as an address delivers the whole file.

**The API address goes first, and it is not a fallback.** It is the host the
check has *already* reached — a copy that got as far as offering an install has
proven it can talk to `api.github.com` — so the order makes the download work on
exactly the networks where the check works, with no configuration and nothing to
try. It is `getUrl` with `Accept: application/octet-stream` that turns that
address from a description of a file into the file; the download address ignores
the header, so one request shape serves both.

**A 200 is not enough; the published byte count is checked before the
checksum.** A refusal is the loud failure, and the quiet one is an interception
answering 200 with a page of its own. Without the byte count, that answer would
end the attempt and the second address would never be asked; with it, an address
that delivered the wrong length is treated exactly like one that delivered
nothing. The checksum still decides whether the file is *right* — the count only
decides whether to keep trying.

**The failure name and its sentence are unchanged.** Both addresses failing is
still `UpdateInstallFailure.download` and still 「下载没有完成。请检查网络后重试。」
A third thing to say would have to be something a user could act on, and "the
host that serves the file refused this machine, and so did the other one" is a
sentence about this application's plumbing rather than about what to do next.

## Alternatives considered

**Fetch from the API address only.** Rejected: it fixes this network by making
the whole flow depend on one host. A network that filters `api.github.com` and
lets `github.com` through — the opposite arrangement, and no harder to imagine —
would then be unable to install at all, where today it can check and install
fine. The two-address list costs one pure function and one loop.

**Keep the one address and retry it.** Rejected: retrying a refused address is
the action the user had already taken, twice, prompted by this application. It
cannot work.

**Read the machine's proxy settings.** Rejected for this change, and worth
revisiting on evidence. Dart's `HttpClient` already resolves a proxy from
`http_proxy` / `https_proxy` / `no_proxy` — `findProxyFromEnvironment` is its own
default `findProxy` — which is why the table's last row works at all. What it
does not read is the Windows registry's WinINET configuration, which is what a
user who set a proxy in Settings, and launches a build by double-clicking it,
actually has. That would mean a registry read or a native side, for a
configuration that is this machine's own; and it would not have fixed this
defect, whose measured failure happens with no proxy configured at all.

**Publish through a mirror.** Rejected: this application ships no backend and
publishes only to the place its source already lives. A third-party
GitHub-fronting proxy is somebody else's machine between the user and the
release, and the API's own asset address is not a third party at all — it is the
same GitHub, reached by the name that answers.

**Tell the user to press 打开下载页.** Rejected: the browser is on the same
machine and reaches the same hosts, which is why the person who reported this
was already copying the address out of the card.

## Consequences

- **The download works on this machine now, and the bytes are the published
  ones.** A throwaway probe, run by hand against the live release — `test/` may
  not use the network, so nothing in the suite can be the thing that proves this
  — fetched `LocalTransfer-0.1.2-windows-x64-portable.zip` over the API address
  with no proxy configured: 200, redirected to
  `release-assets.githubusercontent.com`, 13,375,776 B, sha256 `b4e6cbd5…17294`
  — equal to the digest in the release's own metadata. The route the installer
  now takes first is the route that was measured to work.
- **The `release-assets.githubusercontent.com` hop is still there.** The API
  answers 302 to that host and Dart follows it; the artifact does not come back
  from `api.github.com` itself. This network reaches it, and a network that
  blocked it while allowing `api.github.com` would fail both addresses — a
  possible profile, and not one that can be checked from here. What is bought is
  that the two addresses are two *hostnames* to refuse rather than one.
- **The first attempt is a request the API counts, and the second is a
  redirect.** No rate limit is reached by checking for an update and installing
  it, and the fixed-name alias is not used for this — the versioned artifact is
  what a digest can be checked against.
- **The size guard is new information the installer holds.** An answer whose
  length disagrees with what the release published is now a reason to try the
  other address rather than a reason to throw the download away; the sentence
  the user sees when both fail did not change, so this is invisible until the
  day it saves a download.
- **The six gates still cannot see this.** `test/ui/update_install_test.dart`
  now covers the decision — which address is first, that the second is reached
  when the first refuses or answers short, and that both failing is still one
  failure — against loopback servers it stands up itself. What no gate covers is
  whether GitHub's real addresses behave as measured here; that is what the
  probe above is for, and it is run by hand.

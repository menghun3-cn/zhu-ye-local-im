# Agent Note: The update download retries and resumes

Status: implemented

English | [中文](2026-10-27-update-download-retries-and-resumes.zh.md)

## Problem

An update download that broke part-way through ended the whole attempt: the
About card reported 「下载没有完成。请检查网络后重试。」, the partial bytes on
disk were thrown away, and the next press fetched the entire package again.
A connection that stalls mid-file is one of the ordinary things a network does
— especially in a long download through a flaky route — and a downloader that
does not retry or resume turns that ordinary moment into a wasted download and
a user action.

## Decision

**Bytes on disk are only ever a package when the whole file has arrived.**
The fetch now writes into `<package>.part` and renames the partial into the
package's own name only once the complete byte count has been received. The
final package name still means "checked or not yet checked", never
"half-written".

**A step is retried; a new attempt resumes from where it stopped.** Each
address is allowed up to three network steps. A step that fails reconnects to
the same address, sends `Range: bytes=<offset>-`, and appends from the offset
already on disk. A server that does not serve ranges answers 200 with the whole
file and the receiver drops back to a fresh download at zero. The byte count
the release published is still checked after every step, and the digest check
is still the only judge of whether the bytes are right.

**A leftover partial is adopted by the next attempt.** `_recoverPartial` finds
the `.part` file an earlier attempt left behind, resumes from its length, and
renames the finished result into place. `_keepOnly` keeps the current partial
beside the current package, `_discard` removes both names, and the old
"delete the failed bytes" behaviour is gone.

## Testing

`test/ui/update_install_test.dart` now expects the address-stepping order (the
first address's allowed steps before the second address's), and that both
addresses failing is still the one `download` failure. The loopback server
records the paths it was asked for, so the tests pin the exact order.

## Alternatives considered

**Retry the same failing thing.** Rejected: retrying without pausing is just a
longer wait. The new step reconnects and resumes, so its retry is also the
recovery.

**Write the whole file directly and start over on failure.** Rejected: it is
the old behaviour, and the whole point of a partial file is that a crash does
not lose the bytes that already arrived.

**Resume only on the next button press.** Rejected: the user already pressed
once. The attempt should heal itself as far as the network allows, and the
next press only carries it across a longer outage.

## Consequences

- A stalled download is recovered without a fresh fetch on the same address.
- A failed button press leaves bytes that the next press reuses.
- The failure sentence is unchanged: both addresses exhausting their steps is
  still something the user can act on by trying again.
- A 200 fallback for non-range servers keeps a download possible where bytes
  cannot be resumed.

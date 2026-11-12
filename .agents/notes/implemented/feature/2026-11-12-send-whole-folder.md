# Agent Note: a folder sends as one Transfer with its tree in the names

Status: implemented

## Problem

The composer could send files and pictures, but a directory was the one
thing it could not carry: `classifyPaths` filtered folders out because a
directory has a path but no bytes, and the wire format had no way to say
"these items belong together under these directories". A user with a folder
of photos or a project tree had to send it as an archive or file-by-file.

## Decision

**The tree travels inside the item names.** A folder send is one
`PayloadKind.file` Offer whose items are named `folder/sub/dir/file.txt` —
`/`-separated relative paths rooted at the folder's own name. No new
`PayloadKind`, no manifest item, no protocol-version change: the receiver
reads a `/` in a name as "this is a path", sanitises each segment with the
same rules a flat name already gets ([incomingLandingFor]), rebuilds the
directories under the folder the user picked, and lands each file with the
usual staging-and-numbering. An old receiver sanitises the whole name flat
(`a_b_c.txt`) — degraded, not broken.

**One folder, one Transfer.** `LocalTransferController.sendFolder` lists the
tree ([listFolderForSend]), checks the counts against
`TransferLimits.defaults` *before* hashing anything, and hands the engine
one `sendFiles` call. The receiver answers once, lands once.

**Sources hold no handles.** A folder can name thousands of items, so each
item's bytes come from `ChunkedFileByteSource`, which stats the length up
front and opens and closes a handle per read — nothing stays locked while
the Offer sits unanswered, which on Windows would otherwise stop the user
moving the folder they just sent.

**What does not travel.** Empty directories produce no item (the wire has
no way to say "this is a directory"), links are not followed — a link can
point outside the picked folder — and unreadable entries are skipped and
counted. A folder over the Offer limits is refused before the hashing pass,
with its own `AppRefusal` names so the UI can say which limit was hit.

**The composer stages a folder as one attachment.** The toolbar gained a
second attach tool (`menuSendFolder`) that asks the OS for a directory;
drops and pastes that name a directory stage the same way. The chip shows
the folder's name, and the files are enumerated when 发送 is pressed, so a
folder that changed since it was picked sends what is actually there.

## Alternatives considered

**A new `PayloadKind.folder` with a manifest.** Rejected: an old receiver
answers an unknown kind by refusing the whole offer, which is a worse
degradation than flattened names; and "a directory with no byte stream"
would need item semantics the format does not have.

**Flatten everything into bare names.** Rejected: it loses the structure
the request was for, and collisions between same-named files in different
directories would renumber silently.

**One Transfer per file.** Rejected: N offers, N answers, and no "this is
one folder" for the receiver to land as a tree.

**Zip the folder and send the archive.** Rejected: it changes what the
bytes are — the receiver gets a file to unpack rather than the folder —
and hides the per-file digest verification the Transfer already provides.

## Consequences

**Bought.** A folder crosses the link as itself: same tree, same names,
same verify-every-byte guarantee, inside the limits the protocol already
enforced. Old and new builds interoperate in both directions.

**Cost.** `PayloadItem.name` now means "a name, or a `/`-separated path" —
a convention every future producer and consumer of item names must know,
which is why it lives in [incomingLandingFor] and this note rather than in
a comment alone. Per-read open/close costs a syscall per 64 KiB chunk,
which is noise beside the hashing pass that reads the same bytes anyway.
Empty folders silently do not arrive.

**Deferred.** Android's folder picker is unverified — `file_selector`'s
directory answer and `dart:io` reads under scoped storage may not reach a
user-picked folder; if they cannot, the entry hides there rather than
blocking the feature. The `skipped` count the listing keeps has no
surface yet.

**Testing.** `test/app/folder_listing_test.dart` pins the walk (tree
names, sizes, empty directories, links), `test/app/incoming_path_test.dart`
pins the landing rules (traversal, empty segments, backslashes), and
`test/transfer/chunked_file_byte_source_test.dart` pins the source; the
composer's folder chip and tool are covered in
`test_flutter/ui/composer_folder_test.dart`.

# Agent Note: a non-ASCII comment broke the Windows build

Status: implemented

## Problem

`windows/runner/main.cpp` is compiled by MSVC, and MSVC on this machine reads a
source file as the system code page (936) unless it is told otherwise.

The rename put the product's name into the title bar as `\u` escapes — correct,
and ASCII. But the comment beside it spelled the name out in prose and used an
em dash (`U+2014`) twice. Each em dash is three UTF-8 bytes, and three UTF-8
bytes read as GBK are not a valid character: MSVC answers **C4819** ("the file
contains a character that cannot be represented in the current code page"), and
the runner's own CMake settings promote warnings to errors (**C2220**), so the
build stops before it produces an exe.

Nothing caught it before the merge. `flutter analyze`, `dart format`,
`dart test` and `flutter test` never compile `windows/**`; the only thing that
does is `scripts/pack-windows-portable.ps1`, and that is a packaging step which
had not been run when the PR was merged. The one gate that would have caught it
runs only at packaging time.

## Decision

**The file is ASCII-only, and now says so.** The two em dashes are gone, and the
comment states the rule it obeys — that a non-ASCII byte here is C4819 read as
CP936, promoted to an error by the runner's build — so the next person who wants
to write 竹叶局域网传输 in the C++ source is told to use escapes instead. The
title was already escaped; only the prose around it was the problem.

**The Windows build is part of the gate for anything under `windows/`.** The six
gates say nothing about the runner, so a change there must be validated by
running `scripts/pack-windows-portable.ps1` (or at least
`flutter build windows --release`) before it merges, because nothing else will
notice that it no longer compiles.

## Alternatives considered

**Add `/utf-8` to the runner's compiler flags.** It is the general fix for this
whole class of problem, and it would let the source hold the characters
themselves. Rejected as a larger change than the defect: it edits the generated
CMake lists, which a future `flutter create` regeneration would overwrite, and
it would let the next non-ASCII byte through silently instead of being a thing
the file warns about.

**Keep the comment and save the file as UTF-8 with a BOM.** MSVC honours a BOM,
so this would also work. Rejected because the file's encoding then becomes
invisible in review and easy to lose on the next save — the same failure returns
the moment an editor rewrites the file.

**Drop the comment.** The escapes below it are self-explanatory. Rejected
because the *reason* for the escapes is exactly what a reader needs; without it,
the next edit spells the name out and breaks the build again.

## Consequences

`windows/runner/main.cpp` is pure ASCII again, so it compiles under whatever
code page the toolchain picks, and the rule is written down in the one place
somebody editing it is likely to look.

The deeper consequence is about the process, which is why it is written here and
not only in the file: **the six gates do not compile the Windows runner.** A
change under `windows/` is only proven by building it.

## Testing

`scripts/pack-windows-portable.ps1` now also carries the four glyphs the About
page introduced — `Icons.info`, `Icons.info_outline`, `Icons.system_update_alt`,
`Icons.open_in_new` — in its required set, and two whole sentences from the About
page in its text probes. Running it end to end is what proves the runner
compiles, that the icons reached the font (10/10) and that the new copy is in
`app.so` (17/17); its smoke step starts the packaged exe and confirms it answers
and binds UDP 47654 and TCP 47656/47655.

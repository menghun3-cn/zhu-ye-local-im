# Agent Note: The fixed name goes out with the release

Status: implemented

English | [中文](2026-10-12-the-fixed-name-goes-out-with-the-release.zh.md)

## Problem

[The fixed-name alias](2026-10-12-a-fixed-name-for-the-package-lan-scripts-pull.md)
gives a puller a URL that does not change, but it is published only into
`build/dist` — the directory that a machine on the LAN happens to be serving. A
machine outside that network cannot reach it at all. The one channel it has is the
GitHub Release, and every asset there carries its version in its name, so
`releases/latest/download/<name>` still requires the version to be known in advance.
The alias removed that requirement for the LAN and left it in place for everyone
else.

That is the case this repository's own distribution keeps running into. The LAN is
where the package is *served*; the internet is where the people who fetch it, and
the people who automate fetching it, are. A script that sets up a machine outside
the LAN — a build agent, a colleague's laptop on another network — has to ask the
API for the current version, or be edited on every release, which is exactly the
chore the alias exists to remove.

The previous decision [considered this and declined it](2026-10-12-a-fixed-name-for-the-package-lan-scripts-pull.md)
("Let the CI glob pick the aliases up and attach them to the Release"), on two
grounds: a release would then carry two names for each of two files, and the
release-side notion of "latest" already exists and is the tag, not a file name.
Both are still true. What changed is the weight on the other side: a fixed URL that
only works on one network is not a fixed URL for the party that needs it.

## Decision

The two aliases and their `.sha256` sidecars are attached to the Release, beside
the versioned artifacts. The `windows` job in `release.yml` uploads six files
instead of two — the versioned pair, the alias pair, the two sidecars — and the
release job attaches everything it downloaded. An outside machine can therefore
pull:

```
https://github.com/menghun3-cn/zhu-ye-local-im/releases/latest/download/LocalTransfer-latest-windows-x64-setup.exe
```

and the same address with `-portable.zip`. `releases/latest/download/<name>`
resolves to the asset of exactly that name in the latest release that is neither a
draft nor a pre-release, so the name has to be the alias: the version must not
appear in it. What changes from release to release is the release the alias lives
in, not its name.

**The release job fails rather than publishing a release without them.** Before
`gh release create`, one step checks each alias: the file exists and is non-empty,
its sidecar exists and is non-empty, and `cmp` says the alias is byte-identical to
this version's artifact. Then `sha256sum -c ./*.sha256` verifies every sidecar with
the real tool. Without the check, a missing alias reaches a puller as a 404 — a
download failure that says nothing about the release step having skipped it — and an
alias left over from the previous version becomes a fixed URL that silently serves
the wrong build.

**The website's asset matching skips the aliases.** `site/app.js` resolved each
download button by matching an asset name suffix (`setup.exe`, `portable.zip`), and
an alias ends in the same suffix. Whichever of the two the API listed first would
have been picked, so a download card could show "最新版本 v0.1.1" next to a file name
containing no version — the pairing the naming rule exists to prevent. Suffix
matching now prefers the versioned artifact and falls back to the alias only when
there is no versioned one.

**The download section states the two fixed addresses.** They are written into
`site/index.html` as plain text below the buttons, because the people who need them
are writing scripts and a button is not what they came for. Plain text rather than
something JavaScript fills in: the address does not depend on the API, so it should
not depend on the API call succeeding.

## Alternatives considered

**Let the CI glob (`build/dist/*-portable.zip`) pick the aliases up.** The shortest
version: the paths already matched, so the path list could go away entirely. Lost
because that directory also holds `使用说明.txt` and whatever a previous run left
behind, and because with a glob nobody can read the workflow and see what a release
is supposed to contain. The six explicit paths are that statement.

**Keep the release at three attachments and document an API call instead.** A
puller would call `GET /releases/latest`, read `assets[].browser_download_url`, and
pick by suffix — the website's approach, transplanted into a shell script. Lost
because it makes every puller depend on the API's availability, its rate limit, and
GitHub's JSON shape, in order to obtain a URL that could simply have been constant.
It also cannot work offline, which is a likely state for a machine being set up.

**Attach only the aliases and drop the versioned pair.** One name per file, and no
"which one do I download?" at the moment of choosing. Lost because the versioned
name is the primary one: a package fetched under a name with no version in it cannot
be identified afterwards, and every report that says "I used the latest" would be
missing the one fact that matters. The versioned pair stays; the alias is the
convenience.

**Make the tag roll, so `releases/latest` needs no alias.** GitHub has no rolling
release: a tag points at a commit and `latest` resolves by release date, not by tag
name. Reusing one tag name for every release would make each release collide with
the previous one's tag and lose the version the release list is ordered by.

**A redirect service, or a Pages file that answers with a 302.** Lost because a
redirect is one more thing that can be down, and because "there is no server" is
part of what this project promises. GitHub already serves the release assets; the
fixed name is the only piece missing.

**Ship the alias as the only Windows asset, with the version inside the file.**
Lost on the same ground as the versioned pair above, with the added cost that the
name would then have to be kept in step with `pubspec.yaml` by something other than
the packaging scripts.

## Consequences

**Bought.** One address that works from anywhere with internet access, never needs
editing, and — because the alias is written only after a packer's own checks pass —
cannot point at a package that failed them. The sidecar comes along, so a puller
outside the LAN can verify a download over the public internet, which is where a
download is likelier to arrive damaged.

**Paid.** A release now carries seven attachments: three artifacts, two aliases,
two sidecars. Two of them duplicate two others byte for byte, so the release page
shows two names for each of those files. Accepted: the duplicate is what makes the
constant address possible, the alias's name says `latest` and the artifact it
duplicates sits beside it, and the alternative is asking every puller to discover
the version before it can fetch anything.

**Not covered.** Releases published before this change carry no aliases, so the
fixed address 404s against them; it becomes valid with the next tag. `releases/latest`
never resolves to a pre-release or a draft, so a pre-release does not serve the
fixed address either. And nothing retrofits the aliases onto an older release —
copying this machine's aliases onto the released `v0.1.0` was declined: those bytes
would not be the bytes the tag built, which is the rule `AGENTS.md` §9 ends on.

**Still unexercised by the gate suite.** No gate in `AGENTS.md` §5 runs
`release.yml`; its first honest run is the next tag. This is the fourth defect class
in this area that reasoning has to catch instead of a run ([the define without its
D](../bug-fix/2026-10-12-a-define-that-was-spelled-without-its-d.md), [the steps
that had only ever run on one side](../bug-fix/2026-10-12-two-build-steps-that-had-only-ever-run-on-one-side.md),
[the alias itself](2026-10-12-a-fixed-name-for-the-package-lan-scripts-pull.md)) —
and a CI job that ran the packers and the release steps on a pull request is still
not written.

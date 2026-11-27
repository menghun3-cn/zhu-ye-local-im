/// The commit-set predicate and fingerprint parsing shared by the
/// changelog completeness test and the pre-tag fingerprint check.
///
/// "The commits a release must account for" is three filters, not one:
/// the `prevTag..tag` log range on the production topology, the
/// `isUserVisible` prefix filter, and `changedSomethingNew`, the tree-diff
/// against the previous tag that drops commits an earlier release already
/// shipped under a different id. Both callers must compute it identically,
/// so it lives here once. Git failures are loud: an unanswerable question
/// fails the gate rather than silently passing it.
library;

import 'dart:convert';
import 'dart:io';

/// The first version whose CHANGELOG entry carries commit fingerprints.
///
/// Versions before it are frozen history verified by the legacy fragment
/// matcher; versions from it on are verified by exact set equality between
/// parsed fingerprints and the range's commit set.
const String exactFrom = '0.1.63';

/// One commit in a release's range.
final class ChangelogCommit {
  ChangelogCommit(this.hash, this.subject);

  /// The commit's full hash.
  final String hash;

  /// The commit's subject line.
  final String subject;
}

/// Runs git and returns stdout, throwing when the command fails.
String _git(List<String> args) {
  final result = Process.runSync('git', args, stdoutEncoding: utf8);
  if (result.exitCode != 0) {
    throw StateError(
      'git ${args.join(' ')} failed (exit ${result.exitCode}): '
      '${result.stderr}',
    );
  }
  return result.stdout as String;
}

/// The repository's tags, oldest version first.
List<String> gitTags() =>
    _git(['tag', '--sort=v:refname'])
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

/// The user-visible commits [range] contains that the tree at [againstRef]
/// did not already have — or every user-visible commit when [againstRef]
/// is null (the first release).
///
/// [range] is a git revision range such as `v0.1.63..v0.1.64` or `HEAD`.
/// The filter matters because the tags do not sit on one line: a release
/// tag points at the merge commit on the production branch, and that
/// commit brings the integration branch's work in as *its own* commits
/// rather than as the integration branch's — so the range lists changes
/// the previous release already shipped, under ids that are not even
/// ancestors of the earlier tag. What decides the question is the
/// content: a commit that changed nothing the previous release did not
/// already have is a commit the previous release already announced.
List<ChangelogCommit> rangeCommits(String range, String? againstRef) {
  final result = _git(['log', '--format=%H%x1f%s', range]);
  return result
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .map((l) {
        final parts = l.split('\x1f');
        return ChangelogCommit(parts.first, parts.skip(1).join('\x1f'));
      })
      .where((c) => isUserVisible(c.subject))
      .where(
        (c) => againstRef == null || changedSomethingNew(againstRef, c.hash),
      )
      .toList();
}

/// The commits [version] (`0.1.63`) must account for: everything after the
/// previous tag up to its own tag.
List<ChangelogCommit> releaseCommits(String version) {
  final tag = 'v$version';
  final tags = gitTags();
  final index = tags.indexOf(tag);
  if (index < 0) {
    throw StateError('no tag $tag in the repository');
  }
  final previous = index == 0 ? null : tags[index - 1];
  final range = previous == null ? tag : '$previous..$tag';
  return rangeCommits(range, previous);
}

/// Whether [commit] changed anything that the tree at [ref] did not have.
///
/// The question is asked of the tree rather than of the history, because
/// the same change reaches the production branch as a different commit:
/// the production branch merges the integration branch, and the merge
/// brings the work in under a new id. Asking the history would count the
/// work twice; asking the tree counts it once.
///
/// Unlike the legacy matcher this fails loudly: a git error is an
/// unanswerable question, and an unanswerable question fails the gate.
bool changedSomethingNew(String ref, String commit) {
  final names = _git(['show', '--name-only', '--format=', commit])
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      // The changelog is what the release *produces*, not what it carries:
      // it differs between every two releases by definition, and it says
      // nothing about what the release contains.
      .where((l) => l != 'CHANGELOG.md')
      .toList();
  if (names.isEmpty) return false;
  // The files the commit touched, compared between the commit and the
  // previous release: where they differ, the previous release does not
  // have this change. Where they do not differ, the release already
  // shipped it under a different commit id.
  return _git(['diff', '--name-only', commit, ref, '--', ...names])
      .trim()
      .isNotEmpty;
}

/// Whether a commit is something a reader should have been told about.
///
/// The classification is the `git-publish` skill's own: `feat`, `fix`,
/// `refactor`, `perf` and `docs` reach the changelog, and `chore`, `test`
/// and `ci` are infrastructure that does not.
bool isUserVisible(String subject) {
  final match = RegExp(r'^([a-z]+)(\([^)]*\))?!?: ').firstMatch(subject);
  if (match == null) return false;
  const reach = {'feat', 'fix', 'refactor', 'perf', 'docs'};
  return reach.contains(match.group(1));
}

/// One bullet block of a changelog entry: its prose lines and the
/// fingerprint comment that must terminate it.
final class EntryBullet {
  EntryBullet({
    required this.prose,
    required this.fingerprints,
    required this.fingerprintBlockFinal,
  });

  /// The bullet line and its wrapped continuation lines, fingerprint
  /// line excluded.
  final List<String> prose;

  /// The `@`-prefixed commit tokens on the fingerprint line; empty when
  /// the block carries none.
  final List<String> fingerprints;

  /// Whether the fingerprint line — if any — is the block's last line.
  /// A fingerprint followed by more prose of the same bullet would orphan
  /// that prose in `readUpdateNotes`, so only block-final counts.
  final bool fingerprintBlockFinal;
}

/// The result of reading one version's fingerprints.
final class FingerprintReport {
  FingerprintReport({required this.bullets, required this.problems});

  /// Every bullet block of the entry, in order.
  final List<EntryBullet> bullets;

  /// Structural problems found while parsing, in order. An empty list
  /// means the entry's fingerprint syntax is well-formed.
  final List<String> problems;
}

final RegExp _versionHeading = RegExp(
  r'^## \[(\d+\.\d+\.\d+)\] - \d{4}-\d{2}-\d{2}$',
);
final RegExp _bulletStart = RegExp(r'^\s*-\s+');
final RegExp _categoryHeading = RegExp(r'^###\s');
final RegExp _fingerprintLine = RegExp(
  r'^\s*<!--\s*@[0-9a-f]+(?:\s+@[0-9a-f]+)*\s*-->\s*$',
);
final RegExp _commentLine = RegExp(r'^\s*<!--');
final RegExp _fingerprintToken = RegExp(r'@([0-9a-f]+)');

/// Parses the fingerprints of [version]'s entry in [lines] (the lines of
/// `CHANGELOG.md`).
///
/// A fingerprinted entry's rules: every bullet block ends with exactly
/// one fingerprint line — `<!-- @hash [@hash…] -->`, indented like the
/// bullet's continuation lines — and nothing but block terminators (a
/// blank line, a category heading, the next bullet, or the section's end)
/// may follow it.
FingerprintReport fingerprintReport(List<String> lines, String version) {
  var start = -1;
  var end = lines.length;
  for (var i = 0; i < lines.length; i++) {
    final heading = _versionHeading.firstMatch(lines[i]);
    if (heading == null) continue;
    if (heading.group(1) == version) {
      start = i;
    } else if (start >= 0) {
      end = i;
      break;
    }
  }
  if (start < 0) {
    return FingerprintReport(
      bullets: const [],
      problems: ['no entry for version $version'],
    );
  }

  final bullets = <EntryBullet>[];
  final problems = <String>[];
  var prose = <String>[];
  var fingerprints = <String>[];
  var fingerprintLines = 0;
  var malformedFingerprint = false;
  var contentAfterFingerprint = false;
  var blockOpen = false;

  void closeBlock() {
    if (!blockOpen) return;
    if (fingerprintLines == 0) {
      problems.add('bullet "${prose.first}" has no fingerprint');
    } else {
      if (fingerprintLines > 1) {
        problems.add(
          'bullet "${prose.first}" has more than one fingerprint line',
        );
      }
      if (contentAfterFingerprint) {
        problems.add(
          'fingerprint of bullet "${prose.first}" is not its last line',
        );
      }
    }
    bullets.add(
      EntryBullet(
        prose: List.unmodifiable(prose),
        fingerprints: List.unmodifiable(fingerprints),
        fingerprintBlockFinal:
            fingerprintLines == 1 &&
            !malformedFingerprint &&
            !contentAfterFingerprint,
      ),
    );
    prose = [];
    fingerprints = [];
    fingerprintLines = 0;
    malformedFingerprint = false;
    contentAfterFingerprint = false;
    blockOpen = false;
  }

  for (var i = start + 1; i < end; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || _categoryHeading.hasMatch(line)) {
      closeBlock();
      continue;
    }
    if (_bulletStart.hasMatch(line)) {
      closeBlock();
      blockOpen = true;
      prose = [line.trim()];
      continue;
    }
    if (_commentLine.hasMatch(line)) {
      if (!blockOpen) {
        problems.add('orphan fingerprint line at line ${i + 1}: $line');
        continue;
      }
      fingerprintLines++;
      if (!_fingerprintLine.hasMatch(line)) {
        malformedFingerprint = true;
        problems.add('malformed fingerprint line at line ${i + 1}: $line');
        continue;
      }
      fingerprints.addAll(
        _fingerprintToken.allMatches(line).map((m) => m.group(1)!),
      );
      continue;
    }
    if (!blockOpen) continue;
    if (fingerprintLines > 0) contentAfterFingerprint = true;
    prose.add(line.trim());
  }
  closeBlock();

  return FingerprintReport(bullets: bullets, problems: problems);
}

/// Resolves [report]'s fingerprint tokens against [commits] (the range's
/// commit set) and returns the set of full hashes they name, plus one
/// problem per token that matches no commit or several.
({Set<String> hashes, List<String> problems}) resolveFingerprints(
  FingerprintReport report,
  List<ChangelogCommit> commits,
) {
  final hashes = <String>{};
  final problems = <String>[...report.problems];
  for (final bullet in report.bullets) {
    for (final token in bullet.fingerprints) {
      final matches = commits
          .where((c) => c.hash.startsWith(token))
          .map((c) => c.hash)
          .toSet();
      if (matches.isEmpty) {
        problems.add('fingerprint @$token is not a commit of the range');
      } else if (matches.length > 1) {
        problems.add('fingerprint @$token is ambiguous in the range');
      } else if (!hashes.add(matches.single)) {
        // Set equality alone cannot see a hash claimed by two bullets:
        // the set still matches. Every commit is fingerprinted exactly
        // once, so a second claim is a problem.
        problems.add(
          'commit ${matches.single} is fingerprinted more than once',
        );
      }
    }
  }
  return (hashes: hashes, problems: problems);
}

/// Compares two dotted version strings by their numbers.
int compareVersions(String a, String b) {
  final left = a.split('.').map(int.parse).toList();
  final right = b.split('.').map(int.parse).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    if (left[i] != right[i]) return left[i].compareTo(right[i]);
  }
  return left.length.compareTo(right.length);
}

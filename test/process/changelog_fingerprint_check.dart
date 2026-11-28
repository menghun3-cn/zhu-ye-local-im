/// Pre-tag fingerprint check: the pending CHANGELOG entry's fingerprint
/// set must equal the commit set `prevTag..HEAD` produces on the release
/// branch — the same predicate `changelog_entries_test.dart` applies after
/// the tag exists, run while fixing is still free.
///
/// Run from the repository root:
///
/// ```
/// dart run test/process/changelog_fingerprint_check.dart            # check
/// dart run test/process/changelog_fingerprint_check.dart --commits  # list the set
/// ```
///
/// `--commits` prints the pending range's commit set (`hash<TAB>subject`,
/// one per line) so the changelog draft can fingerprint exactly it; the
/// release flow uses it at generation time, before the entry exists.
///
/// Exit code 0 means the pending entry accounts for every commit exactly
/// once; anything else prints the misses and exits 1. Versions before
/// [exactFrom] carry no fingerprints and are skipped.
library;

import 'dart:io';

import 'changelog_commits.dart';

void main(List<String> args) {
  if (args.contains('--commits')) {
    listCommits();
    return;
  }
  check();
}

/// Prints `hash⇥subject` for every commit the pending entry must cover:
/// the user-visible commits of `prevTag..HEAD` on this branch.
void listCommits() {
  final tags = gitTags();
  if (tags.isEmpty) {
    stderr.writeln('✗ the repository has no tags; nothing to compare against');
    exit(1);
  }
  final previous = tags.last;
  for (final commit in rangeCommits('$previous..HEAD', previous)) {
    stdout.writeln('${commit.hash}\t${commit.subject}');
  }
}

void check() {
  final lines = File('CHANGELOG.md').readAsLinesSync();

  // The pending entry is the first versioned section of the file.
  String? pending;
  for (final line in lines) {
    final heading = RegExp(r'^## \[(\d+\.\d+\.\d+)\] - \d{4}-\d{2}-\d{2}$')
        .firstMatch(line);
    if (heading != null) {
      pending = heading.group(1);
      break;
    }
  }
  if (pending == null) {
    stderr.writeln('✗ CHANGELOG.md has no versioned entry to check');
    exit(1);
  }
  if (compareVersions(pending, exactFrom) < 0) {
    stdout.writeln('✓ $pending predates fingerprints (exactFrom $exactFrom)');
    return;
  }

  final tags = gitTags();
  if (tags.isEmpty) {
    stderr.writeln('✗ the repository has no tags; nothing to compare against');
    exit(1);
  }
  final previous = tags.last;
  final commits = rangeCommits('$previous..HEAD', previous);

  final resolved = resolveFingerprints(
    fingerprintReport(lines, pending),
    commits,
  );

  final expected = commits.map((c) => c.hash).toSet();
  final missing = expected.difference(resolved.hashes);
  final unexpected = resolved.hashes.difference(expected);

  var failed = false;
  if (resolved.problems.isNotEmpty) {
    failed = true;
    stderr.writeln('✗ fingerprint problems in the $pending entry:');
    for (final problem in resolved.problems) {
      stderr.writeln('  - $problem');
    }
  }
  if (missing.isNotEmpty) {
    failed = true;
    stderr.writeln('✗ commits of $previous..HEAD no bullet fingerprints:');
    for (final hash in missing) {
      final commit = commits.firstWhere((c) => c.hash == hash);
      stderr.writeln('  - ${hash.substring(0, 7)} ${commit.subject}');
    }
  }
  if (unexpected.isNotEmpty) {
    failed = true;
    stderr.writeln('✗ fingerprints that are not commits of $previous..HEAD:');
    for (final hash in unexpected) {
      stderr.writeln('  - ${hash.substring(0, 7)}');
    }
  }
  if (failed) exit(1);

  stdout.writeln(
    '✓ $pending fingerprints match the $previous..HEAD commit set '
    '(${expected.length} commits)',
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The first version whose entry this test holds to the full rule.
///
/// `v0.1.8` is where the entries stopped being summaries and started being
/// lists — every change a version carried got its own bullet, written that
/// way on purpose. The versions before it are left alone: their notes were
/// written as a summary, and a note that is rewritten after the fact is a
/// note that no longer says what was announced.
const String guardedFrom = '0.1.8';

/// Whether every released change is accounted for in `CHANGELOG.md`.
///
/// The changelog of a version is written by hand, at release time, from the
/// commits that version contains. The format gate that runs beside it
/// (`changelog_check.py`) checks that the entry is *well-formed* — a titled
/// section, the allowed categories, a bullet under each. None of that is
/// about content: nothing asked whether a commit in the range is mentioned.
///
/// So a `feat:` commit could be left out, and nothing failed. The emoji
/// feature shipped in `v0.1.10` and `v0.1.11` and was in neither entry,
/// while the About card and the GitHub Release body — which are both that
/// entry — told users about everything else.
///
/// This test closes that gap. It reads the same history the release was
/// generated from, and asks of each release entry the question the format
/// gate cannot: is every change in this version mentioned somewhere in it?
///
/// The matching is deliberately loose. A changelog bullet is authored prose
/// in Chinese, not a copy of the commit subject, so the test looks for a
/// *distinguishing fragment* of the subject — a word or a pair of characters
/// that appears in the bullet. Requiring the whole subject would fail every
/// real entry.
///
/// **The rule applies from [guardedFrom] onwards.** The entries before it
/// were written when a version's notes were a summary rather than a list,
/// and rewriting history is not what a test is for: the entries are what
/// those releases published, and a release note that is rewritten after the
/// fact is a release note that no longer says what was announced. The
/// entries from [guardedFrom] on were written as lists, and those are the
/// ones this test holds to.
void main() {
  group('the changelog', () {
    test('matches an English subject to a translated release note', () {
      final release = Release('test', ['发现设备后自动建立设备组信任和会话。']);
      final commit = Commit(
        '0000000',
        'fix: connect discovered devices automatically',
      );

      expect(release.mentions(commit), isTrue);
    });

    test('matches a translated gesture and a translated address', () {
      final longPress = Commit(
        '0000000',
        'feat: long-press deletes a conversation row on mobile',
      );
      final address = Commit(
        '0000000',
        'fix: conversation row titles with IP address and focuses composer on pick',
      );

      expect(Release('test', ['移动端长按对话行支持删除确认。']).mentions(longPress), isTrue);
      expect(
        Release('test', ['对话列表的行标题改为显示对端的 IP 地址。']).mentions(address),
        isTrue,
      );
    });

    test('has a version for every tag', () {
      final changelog = File('CHANGELOG.md').readAsLinesSync();
      final releases = readReleases(changelog);
      final tags = gitTags();
      expect(
        tags,
        isNotEmpty,
        reason: 'the history has no tags, so there is nothing to check',
      );
      final documented = releases.map((r) => r.version).toSet();
      // A tag is written `v0.1.13` and a changelog heading `0.1.13`: the
      // prefix is the tag's, not the version's, so it is dropped on both
      // sides before they are compared.
      final missing = tags
          .where((t) => !documented.contains(t.replaceFirst(RegExp('^v'), '')))
          .toList();
      expect(
        missing,
        isEmpty,
        reason:
            'these tags have no entry in CHANGELOG.md, so the release notes '
            'for them are empty:\n${missing.join('\n')}',
      );
    });

    final changelog = File('CHANGELOG.md').readAsLinesSync();
    for (final release in readReleases(changelog)) {
      if (compareVersions(release.version, guardedFrom) < 0) continue;
      test('${release.version} mentions every change it contains', () {
        final commits = releaseCommits(release);
        if (commits.isEmpty) {
          // A version with no user-visible commit in it — a first release, or
          // one that carried only chores. There is nothing to have forgotten.
          return;
        }
        final unmentioned = commits
            .where((c) => !release.mentions(c))
            .map((c) => '${c.subject}\n      (in ${c.commit})')
            .toList();
        expect(
          unmentioned,
          isEmpty,
          reason:
              'these commits are in ${release.version} but no bullet of its '
              'entry mentions them. The entry is what the GitHub Release body '
              'and the in-app update panel show, so a change that is not in '
              'it is a change nobody was told about:\n'
              '${unmentioned.join('\n')}',
        );
      });
    }
  });
}

/// One version's entry in the changelog.
final class Release {
  Release(this.version, this.bullets);

  /// The version, as written in the heading: `0.1.10`.
  final String version;

  /// The tag that carries this version: `v0.1.10`.
  String get tag => 'v$version';

  /// Every bullet under this version's entry, whatever category it is in.
  final List<String> bullets;

  /// Whether some bullet of this entry mentions [commit].
  bool mentions(Commit commit) {
    final fragments = distinguishingFragments(commit.subject);
    if (fragments.isEmpty) return true;
    for (final bullet in bullets) {
      // Fragments are lower-cased. An authored bullet may capitalise the same
      // word, and that is the same mention.
      if (fragments.any(bullet.toLowerCase().contains)) return true;
    }
    return false;
  }
}

/// One commit in a version's range.
final class Commit {
  Commit(this.commit, this.subject);

  /// The commit's hash.
  final String commit;

  /// The commit's subject line.
  final String subject;
}

/// The versions of the changelog, newest first, with their bullets.
List<Release> readReleases(List<String> lines) {
  final releases = <Release>[];
  for (var i = 0; i < lines.length; i++) {
    final heading = RegExp(r'^## \[(\d+\.\d+\.\d+)\] - \d{4}-\d{2}-\d{2}$')
        .firstMatch(lines[i]);
    if (heading == null) continue;
    final bullets = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      if (lines[j].startsWith('## [')) break;
      final bullet = RegExp(r'^\s*-\s+(.*)$').firstMatch(lines[j]);
      if (bullet != null) bullets.add(bullet.group(1)!.trim());
    }
    releases.add(Release(heading.group(1)!, bullets));
  }
  return releases;
}

/// The tags of the repository, newest version first.
List<String> gitTags() {
  final result = Process.runSync('git', [
    'tag',
    '--sort=v:refname',
  ], stdoutEncoding: utf8);
  if (result.exitCode != 0) return const [];
  return (result.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

/// Compares two version strings by their numbers.
///
/// The strings are compared as numbers rather than as text, because text
/// puts `0.1.13` before `0.1.8` — the digit `3` sorts before `8` — and a
/// version that sorts before the oldest guarded version is one this test
/// would silently stop checking.
int compareVersions(String a, String b) {
  final left = a.split('.').map(int.parse).toList();
  final right = b.split('.').map(int.parse).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    if (left[i] != right[i]) return left[i].compareTo(right[i]);
  }
  return left.length.compareTo(right.length);
}

/// The commits that [release] contains and that a reader should have been
/// told about.
///
/// The range is the one the release was generated from: everything after the
/// previous tag, up to this tag — but only the commits that changed
/// something the previous release did not already have.
///
/// The filter matters because the tags do not sit on one line. A release
/// tag points at the merge commit on the production branch, and that commit
/// brings the integration branch's work in as *its own* commits rather than
/// as the integration branch's — so `v0.1.12..v0.1.13` lists changes
/// `v0.1.12` already shipped, and the commit ids are not even ancestors of
/// the earlier tag. What decides the question is the content: a commit that
/// changed nothing the previous release did not already have is a commit
/// the previous release already announced.
List<Commit> releaseCommits(Release release) {
  final tags = gitTags();
  final index = tags.indexOf(release.tag);
  if (index < 0) return const [];
  final previous = index == 0 ? null : tags[index - 1];
  final range = previous == null ? release.tag : '$previous..${release.tag}';
  final result = Process.runSync('git', [
    'log',
    '--format=%H%x1f%s',
    range,
  ], stdoutEncoding: utf8);
  if (result.exitCode != 0) return const [];
  return (result.stdout as String)
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .map((l) {
        final parts = l.split('\x1f');
        return Commit(parts.first, parts.skip(1).join('\x1f'));
      })
      .where((c) => isUserVisible(c.subject))
      .where((c) => previous == null || changedSomethingNew(previous, c.commit))
      .toList();
}

/// Whether [commit] changed anything that the tree at [ref] did not have.
///
/// The question is asked of the tree rather than of the history, because the
/// same change reaches the production branch as a different commit: the
/// production branch merges the integration branch, and the merge brings
/// the work in under a new id. Asking the history would count the work
/// twice; asking the tree counts it once.
bool changedSomethingNew(String ref, String commit) {
  final files = Process.runSync('git', [
    'show',
    '--name-only',
    '--format=',
    commit,
  ], stdoutEncoding: utf8);
  if (files.exitCode != 0) return true;
  final names = (files.stdout as String)
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
  final compare = Process.runSync('git', [
    'diff',
    '--name-only',
    commit,
    ref,
    '--',
    ...names,
  ], stdoutEncoding: utf8);
  if (compare.exitCode != 0) return true;
  return (compare.stdout as String).trim().isNotEmpty;
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

/// The fragments of a commit subject that a bullet may use to refer to it.
///
/// A bullet is authored prose, so it rarely repeats the subject verbatim. What
/// it does is keep the distinctive words: the ones that name the thing that
/// changed. This returns those — whole words for Latin text, and pairs of
/// characters for Chinese, where a word is not separated by anything.
///
/// A subject with no distinctive fragment in it — every word of it is common
/// to the whole application — produces nothing, and the commit is then
/// counted as mentioned: a bullet cannot be asked to contain a fragment that
/// does not exist.
Set<String> distinguishingFragments(String subject) {
  // The prefix (`feat(ui):`) is not part of what the commit changed.
  final text = subject.replaceFirst(RegExp(r'^[a-z]+(\([^)]*\))?!?: '), '');
  final fragments = <String>{};

  // Commit subjects are commonly English while the changelog is Chinese. Keep
  // the names of recurring features searchable in both languages, so a
  // translated release note is not reported as missing its commit.
  const translated = <String, String>{
    'automatically': '自动',
    'address': '地址',
    'connect': '连接',
    'discovered': '发现',
    'discovery': '发现',
    'device': '设备',
    'devices': '设备',
    'long-press': '长按',
  };

  // Latin words of four letters or more. Short words are excluded because
  // they are common to sentences that have nothing to do with each other —
  // the point of a fragment is to be distinctive.
  for (final word in RegExp(
    r'[A-Za-z][A-Za-z0-9_\-]{3,}',
  ).allMatches(text).map((m) => m.group(0)!.toLowerCase())) {
    fragments.add(word);
    final translation = translated[word];
    if (translation != null) fragments.add(translation);
  }

  // Pairs of Chinese characters: the shortest run of Chinese that can carry
  // meaning is two characters, and a bullet that names the change will share
  // at least one of them.
  for (final run in RegExp(r'[\u4e00-\u9fff]+').allMatches(text)) {
    final characters = run.group(0)!.split('');
    for (var i = 0; i + 1 < characters.length; i++) {
      fragments.add('${characters[i]}${characters[i + 1]}');
    }
  }

  // The common pairs of Chinese are noise: 「消息」 and 「一个」 occur in
  // sentences about entirely different things. Drop the ones that are common
  // in the changelog as a whole, so a fragment means something.
  final common = commonChinesePairs();
  return fragments.where((f) => !common.contains(f)).toSet();
}

/// The Chinese pairs that occur in so many entries that they prove nothing.
Set<String> commonChinesePairs() {
  const common = {
    '消息',
    '一个',
    '这个',
    '可以',
    '不再',
    '之前',
    '现在',
    '没有',
    '之后',
    '之间',
    '不会',
    '已经',
    '并且',
    '或者',
    '就是',
    '还是',
    '它们',
    '什么',
    '自己',
    '的时',
    '时候',
    '支持',
    '功能',
    '更新',
    '版本',
    '用户',
    '界面',
    '显示',
    '默认',
    '大小',
    '宽度',
    '应用',
    '程序',
    '文件',
    '内容',
    '问题',
    '地方',
    '进行',
  };
  return common;
}

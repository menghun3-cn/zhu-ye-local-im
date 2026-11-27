import 'dart:io';

import 'package:test/test.dart';

import 'changelog_commits.dart';

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
/// This test closes that gap, two ways depending on the version's age.
/// Versions from [exactFrom] on carry commit fingerprints — an own-line
/// `<!-- @hash -->` comment terminating each bullet — and are verified by
/// exact set equality between the parsed fingerprints and the range's
/// commit set. Versions from [guardedFrom] up to [exactFrom] predate the
/// scheme and keep the legacy fragment matcher: a bullet is authored prose
/// in Chinese, not a copy of the commit subject, so the matcher looks for
/// a *distinguishing fragment* of the subject in the bullet.
///
/// **Both rules freeze history the same way.** The entries before
/// [guardedFrom] were written when a version's notes were a summary rather
/// than a list; the entries before [exactFrom] carry no fingerprints. A
/// release note that is rewritten after the fact is a release note that no
/// longer says what was announced — except that a fingerprint is
/// tool-written invisible metadata, not prose, which is why `0.1.63` and
/// `0.1.64` were backfilled rather than left on the matcher that fails
/// them.
void main() {
  group('the changelog', () {
    test('matches an English subject to a translated release note', () {
      final release = Release('test', ['发现设备后自动建立设备组信任和会话。']);
      final commit = ChangelogCommit(
        '0000000',
        'fix: connect discovered devices automatically',
      );

      expect(release.mentions(commit), isTrue);
    });

    test('matches a translated gesture and a translated address', () {
      final longPress = ChangelogCommit(
        '0000000',
        'feat: long-press deletes a conversation row on mobile',
      );
      final address = ChangelogCommit(
        '0000000',
        'fix: conversation row titles with IP address and focuses composer on pick',
      );

      expect(Release('test', ['移动端长按对话行支持删除确认。']).mentions(longPress), isTrue);
      expect(
        Release('test', ['对话列表的行标题改为显示对端的 IP 地址。']).mentions(address),
        isTrue,
      );
    });

    test('parses a well-formed fingerprinted entry', () {
      final report = fingerprintReport(const [
        '## [0.1.63] - 2026-11-24',
        '',
        '### 新增',
        '- 可以给已发现的设备设置本地备注名',
        '  <!-- @c2bb4be -->',
        '- 修复「修改备注」弹窗的说明文字被截断',
        '  续行',
        '  <!-- @db2ed9b @39bd4f1 -->',
        '',
        '## [0.1.62] - 2026-11-24',
      ], '0.1.63');

      expect(report.problems, isEmpty);
      expect(report.bullets, hasLength(2));
      expect(report.bullets[0].fingerprints, ['c2bb4be']);
      expect(report.bullets[1].fingerprints, ['db2ed9b', '39bd4f1']);
      expect(report.bullets[1].fingerprintBlockFinal, isTrue);
      expect(report.bullets[1].prose, hasLength(2));
    });

    test('rejects fingerprint syntax violations', () {
      FingerprintReport parse(List<String> entry) => fingerprintReport([
        '## [0.1.63] - 2026-11-24',
        '',
        '### 修复',
        ...entry,
      ], '0.1.63');

      // A bullet with no fingerprint at all.
      expect(
        parse(['- 一条没有指纹的 bullet']).problems,
        contains(contains('no fingerprint')),
      );
      // A fingerprint that is not the block's last line.
      expect(
        parse(['- bullet', '  <!-- @c2bb4be -->', '  还有续行']).problems,
        contains(contains('not its last line')),
      );
      // A malformed fingerprint comment.
      expect(
        parse(['- bullet', '  <!-- @NOTHEX -->']).problems,
        contains(contains('malformed fingerprint')),
      );
      // A fingerprint outside any bullet.
      expect(
        parse([
          '',
          '- bullet',
          '  <!-- @c2bb4be -->',
          '',
          '  <!-- @db2ed9b -->',
        ]).problems,
        contains(contains('orphan fingerprint')),
      );
      // Two fingerprint lines on one bullet.
      expect(
        parse(['- bullet', '  <!-- @c2bb4be -->', '  <!-- @db2ed9b -->'])
            .problems,
        contains(contains('more than one fingerprint line')),
      );
    });

    test('resolves fingerprints against the range commits', () {
      final commits = [
        ChangelogCommit('c2bb4be0123', 'feat: one'),
        ChangelogCommit('db2ed9b0456', 'fix: two'),
      ];
      final report = fingerprintReport(const [
        '## [0.1.63] - 2026-11-24',
        '',
        '### 修复',
        '- bullet one',
        '  <!-- @c2bb4be -->',
        '- bullet two',
        '  <!-- @db2ed9b -->',
      ], '0.1.63');

      final resolved = resolveFingerprints(report, commits);
      expect(resolved.problems, isEmpty);
      expect(resolved.hashes, {'c2bb4be0123', 'db2ed9b0456'});

      // A token that names no commit of the range.
      final stranger = fingerprintReport(const [
        '## [0.1.63] - 2026-11-24',
        '',
        '### 修复',
        '- bullet',
        '  <!-- @fffffff -->',
      ], '0.1.63');
      expect(
        resolveFingerprints(stranger, commits).problems,
        contains(contains('not a commit of the range')),
      );

      // The same commit claimed by two bullets.
      final doubled = fingerprintReport(const [
        '## [0.1.63] - 2026-11-24',
        '',
        '### 修复',
        '- bullet one',
        '  <!-- @c2bb4be -->',
        '- bullet two',
        '  <!-- @c2bb4be -->',
      ], '0.1.63');
      expect(
        resolveFingerprints(doubled, commits).problems,
        contains(contains('more than once')),
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
      if (compareVersions(release.version, exactFrom) >= 0) {
        test('${release.version} fingerprints every change it contains', () {
          final commits = releaseCommits(release.version);
          if (commits.isEmpty) {
            // A version with no user-visible commit in it — a first
            // release, or one that carried only chores. There is nothing
            // to have forgotten, but its bullets still must not claim
            // commits: an empty fingerprint set is the only correct one.
            final resolved = resolveFingerprints(
              fingerprintReport(changelog, release.version),
              commits,
            );
            expect(
              resolved.problems,
              isEmpty,
              reason: 'the entry\'s fingerprint syntax must still be valid',
            );
            expect(resolved.hashes, isEmpty);
            return;
          }
          final resolved = resolveFingerprints(
            fingerprintReport(changelog, release.version),
            commits,
          );
          expect(
            resolved.problems,
            isEmpty,
            reason:
                'the fingerprint syntax of ${release.version}\'s entry is '
                'broken:\n${resolved.problems.join('\n')}',
          );
          final expected = commits.map((c) => c.hash).toSet();
          expect(
            resolved.hashes,
            expected,
            reason:
                '${release.version}\'s fingerprints and its commit range '
                'disagree. Missing (commits no bullet claims):\n'
                '${expected.difference(resolved.hashes).join('\n')}\n'
                'Unexpected (fingerprints no commit owns):\n'
                '${resolved.hashes.difference(expected).join('\n')}',
          );
        });
        continue;
      }
      test('${release.version} mentions every change it contains', () {
        final commits = releaseCommits(release.version);
        if (commits.isEmpty) {
          // A version with no user-visible commit in it — a first release, or
          // one that carried only chores. There is nothing to have forgotten.
          return;
        }
        final unmentioned = commits
            .where((c) => !release.mentions(c))
            .map((c) => '${c.subject}\n      (in ${c.hash})')
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

  /// Every bullet under this version's entry, whatever category it is in.
  final List<String> bullets;

  /// Whether some bullet of this entry mentions [commit].
  bool mentions(ChangelogCommit commit) {
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
///
/// This matcher serves only the frozen history before [exactFrom];
/// fingerprinted versions never reach it.
Set<String> distinguishingFragments(String subject) {
  // The prefix (`feat(ui):`) is not part of what the commit changed.
  final text = subject.replaceFirst(RegExp(r'^[a-z]+(\([^)]*\))?!?: '), '');
  final fragments = <String>{};

  // Commit subjects are commonly English while the changelog is Chinese. Keep
  // the names of recurring features searchable in both languages, so a
  // translated release note is not reported as missing its commit.
  const translated = <String, String>{
    'address': '地址',
    'addresses': '地址',
    'asking': '确认',
    'automatically': '自动',
    'bubble': '气泡',
    'button': '按钮',
    'busy': '忙碌',
    'card': '卡片',
    'check': '检查',
    'clickable': '点击',
    'close': '关闭',
    'colours': '颜色',
    'connect': '连接',
    'conversation': '会话',
    'customizable': '自定义',
    'diagnostics': '检查',
    'device': '设备',
    'devices': '设备',
    'discovered': '发现',
    'discovery': '发现',
    'changelog': '更新日志',
    'disabled': '禁用',
    'download': '下载',
    'downloads': '下载',
    'draft': '草稿',
    'drafts': '草稿',
    'drop': '拖放',
    'finished': '完成',
    'firewall': '防火墙',
    'folder': '文件夹',
    'forward': '转发',
    'hotkey': '快捷键',
    'image': '图片',
    'incoming': '接收',
    'lands': '落盘',
    'link': '链接',
    'links': '链接',
    'long-press': '长按',
    'low-frequency': '低频',
    'navigation': '导航',
    'offline': '离线',
    'one-click': '一键',
    'overlay': '遮罩',
    'page': '页面',
    'port': '端口',
    'presence': '在线',
    'probe': '探测',
    'progress': '进度',
    're-check': '重新检查',
    'resend': '重发',
    'resendable': '重发',
    'rules': '规则',
    'screens': '移动端',
    'screenshot': '截图',
    'screenshots': '截图',
    'searchable': '搜索',
    'secret': '密钥',
    'settings': '设置',
    'site': '官网',
    'share': '分享',
    'share-by-link': '链接分享',
    'share-link': '链接分享',
    'skin': '皮肤',
    'skins': '皮肤',
    'slice': '分片',
    'troubleshooting': '排查',
    'unicast': '单播',
    'website': '官网',
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

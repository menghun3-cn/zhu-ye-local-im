import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The app.so probes, and the words they stand for.
///
/// These probes are the only thing standing between "the package is the code
/// we just wrote" and "the package is whatever the last build left behind" —
/// a zip does not update itself, so a green test suite says nothing about the
/// zip. `scripts/pack-windows-portable.ps1` searches the packaged `app.so`
/// for these words.
///
/// The list used to hold the Chinese sentences themselves, and that made every
/// copy edit a release blocker: reword a message and the packaged binary no
/// longer contained the sentence the script was looking for, so the release
/// pipeline went permanently red. That cost two releases (v0.1.9 and v0.1.10
/// both died on it). The list now holds l10n **keys**, and the script reads the
/// current wording from `app_zh.arb` — so rewording costs nothing.
///
/// What this test guards is the part that is still a human's job: which keys
/// are worth probing, and whether each of them would actually prove anything.
void main() {
  group('the app.so probes', () {
    final manifest = jsonDecode(
      File('scripts/packaging-probes.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final probes = (manifest['probes'] as List).cast<String>();
    final arb = jsonDecode(
      File('lib/l10n/app_zh.arb').readAsStringSync(),
    ) as Map<String, dynamic>;

    String wordingOf(String key) => arb[key] as String;

    test('all name a word that exists', () {
      final missing = probes.where((key) => !arb.containsKey(key)).toList();
      expect(
        missing,
        isEmpty,
        reason:
            'these probe keys are not in app_zh.arb any more. A word that the '
            'product no longer shows cannot prove the package is current — '
            'remove it from scripts/packaging-probes.json:\n'
            '${missing.join('\n')}',
      );
    });

    test('none occurs inside another word of the application', () {
      // A short word proves little when it also occurs somewhere else: '对话'
      // sits inside '原生对话框', so hitting it says nothing about which build
      // is in the package. The repository has been bitten by exactly that
      // before.
      //
      // Length is not the test — '离线' is two characters and appears in
      // exactly one word, which is as good a proof as any sentence. What
      // matters is whether *another* word contains it, so that is what this
      // checks.
      final colliding = <String>[];
      for (final key in probes) {
        final wording = wordingOf(key);
        for (final other in arb.keys.where((k) => k != '@@locale')) {
          if (other == key) continue;
          final value = arb[other];
          if (value is String && value.contains(wording)) {
            colliding.add('$key = $wording  (also inside $other)');
          }
        }
      }
      expect(
        colliding,
        isEmpty,
        reason:
            'these probe words also occur inside another word of the '
            'application, so hitting them says nothing about which build is in '
            'the package:\n${colliding.join('\n')}',
      );
    });

    test('none carries a placeholder', () {
      // A word with a placeholder is stored in app.so as fragments, not as the
      // whole sentence, so searching for it finds nothing.
      final withPlaceholder = probes
          .where((key) => RegExp(r'[{}]').hasMatch(wordingOf(key)))
          .toList();
      expect(
        withPlaceholder,
        isEmpty,
        reason:
            'these probe words carry a placeholder, so app.so only holds the '
            'fragments around it:\n'
            '${withPlaceholder.map((key) => '$key = ${wordingOf(key)}').join('\n')}',
      );
    });

    test('none is contained in another probe', () {
      // If one probe's wording sits inside another's, the shorter one adds
      // nothing: it hits wherever the longer one does.
      final redundant = <String>[];
      for (final key in probes) {
        final wording = wordingOf(key);
        for (final other in probes) {
          if (key == other) continue;
          if (wordingOf(other).contains(wording)) {
            redundant.add('$key = $wording  (inside $other)');
          }
        }
      }
      expect(
        redundant,
        isEmpty,
        reason:
            'these probe words sit inside another one, so they never prove '
            'anything the other does not:\n${redundant.join('\n')}',
      );
    });

    test('the list is not empty', () {
      expect(
        probes,
        isNotEmpty,
        reason: 'a probe list with nothing in it checks nothing',
      );
    });
  });
}

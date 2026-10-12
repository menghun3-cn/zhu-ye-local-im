import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

import '../support/harness.dart';

void main() {
  final alice = testDevice('alice').fingerprint;
  final bob = testDevice('bob').fingerprint;
  final carol = testDevice('carol').fingerprint;

  group('an Owner Group', () {
    test('holds its own Device and nobody else at first', () {
      final group = OwnerGroup(self: alice);
      expect(group.contains(alice), isTrue);
      expect(group.isAlone, isTrue);
      expect(group.members, [alice]);
    });

    test('keeps its own Device even when the members list omits it', () {
      final group = OwnerGroup(self: alice, members: [bob]);
      expect(group.members, [alice, bob]);
      expect(group.isAlone, isFalse);
    });

    test('admits a Device, and admitting it again changes nothing', () {
      final group = OwnerGroup(self: alice).admitted(bob);
      expect(group.contains(bob), isTrue);
      expect(group.length, 2);
      expect(identical(group.admitted(bob), group), isTrue);
    });

    test('sorts its members, so two groups of the same Devices are equal', () {
      final one = OwnerGroup(self: alice, members: [carol, bob]);
      final other = OwnerGroup(self: alice, members: [bob, carol]);
      // Sorted by Fingerprint, which orders by hex and not by anything the
      // names suggest.
      final sorted = [alice, bob, carol]..sort();
      expect(one.members, sorted);
      expect(one, other);
      expect(one.hashCode, other.hashCode);
    });

    test('forgets a Device, but cannot forget its own', () {
      final group = OwnerGroup(self: alice, members: [bob, carol]);
      expect(group.without(bob).contains(bob), isFalse);
      expect(group.without(bob).length, 2);
      expect(group.without(alice), group);
      expect(group.without(testDevice('dave').fingerprint), group);
    });

    test('round-trips through JSON', () {
      final group = OwnerGroup(self: alice, members: [bob, carol]);
      final decoded = OwnerGroup.fromJson(group.toJson());
      expect(decoded, group);
      expect(decoded.self, alice);
    });

    test('rejects a malformed JSON body', () {
      expect(
        () => OwnerGroup.fromJson({'members': <Object?>[]}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => OwnerGroup.fromJson({'self': alice.hex}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => OwnerGroup.fromJson({
          'self': alice.hex,
          'members': ['not a fingerprint'],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('names no Devices when printed, so it is safe in a log', () {
      final group = OwnerGroup(self: alice, members: [bob]);
      expect(group.toString(), 'OwnerGroup(2 devices)');
      expect(group.toString(), isNot(contains(alice.short())));
    });
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:local_transfer/core/core.dart';

import '../support/harness.dart';

/// One Device's pairing service, with its own freshly minted identity and a
/// store in memory so persistence can be read back.
final class TestDevice {
  TestDevice._(this.service, this.store);

  static Future<TestDevice> start(String alias) async {
    final store = MemoryProfileStore();
    final local = await loadOrGenerateLocalProfile(
      store,
      platform: DevicePlatform.windows,
      alias: alias,
    );
    return TestDevice._(PairingService(local: local, store: store), store);
  }

  final PairingService service;
  final MemoryProfileStore store;

  Fingerprint get fingerprint => service.local.identity.fingerprint;
  Uint8List? get secret => service.local.groupSecret;
  OwnerGroup get group => service.local.profile.group;
  List<Fingerprint> get members => group.members;
  String get alias => service.local.profile.alias;

  /// What is on disk, as opposed to what is in memory.
  Future<LocalProfile?> persisted() => loadLocalProfile(store);

  Future<void> close() => service.close();
}

/// Pairs two Devices through the typed-code flow and returns both outcomes.
///
/// The two `confirm` calls are started together on purpose: each side waits for
/// the other's confirmation, so awaiting them in sequence would deadlock.
Future<(PairingOutcome, PairingOutcome)> pairUp(
  TestDevice host,
  TestDevice joiner, {
  int port = 0,
}) async {
  final invitation = await host.service.invite(port: port);
  final joinerAttempt = await joiner.service.join(
    host: '127.0.0.1',
    code: invitation.code,
    port: invitation.port,
  );
  final hostAttempt = await invitation.attempt;
  expect(
    hostAttempt.sas,
    joinerAttempt.sas,
    reason: 'both Devices derive the digits from the same session',
  );
  final outcomes = await Future.wait([
    hostAttempt.confirm(),
    joinerAttempt.confirm(),
  ]);
  expect(hostAttempt.isOpen, isFalse);
  expect(joinerAttempt.isOpen, isFalse);
  return (outcomes[0], outcomes[1]);
}

/// A Device that speaks the Pairing protocol but lies about who it is.
///
/// It is handed the code, so the code check is not what is under test: the
/// point is to isolate the identity check, which is the only thing standing
/// between "a peer knows the code" and "a peer is the Device it claims".
final class HostilePeer {
  HostilePeer._(this._link);

  /// Connects to a Pairing invitation and admits itself.
  ///
  /// [announced] is the Fingerprint put in the handshake, and [identity] is the
  /// key actually offered in the admission. When the two disagree, the Host is
  /// looking at a Device that cannot prove the identity it claimed.
  static Future<HostilePeer> connect({
    required int port,
    required String code,
    required OwnerIdentity identity,
    required String alias,
    required Fingerprint announced,
    required Uint8List signature,
  }) async {
    final link = await SecureLink.establish(
      transport: await SocketByteTransport.connect('127.0.0.1', port),
      role: LinkRole.initiator,
      local: DeviceDescriptor(
        fingerprint: announced,
        alias: alias,
        platform: DevicePlatform.windows,
        capability: ClipboardCapability.forPlatform(DevicePlatform.windows),
      ),
      secret: PairingSecret.fromCode(code),
    );
    await link.send(
      PairAdmitMessage(
        publicKey: await identity.publicKey(),
        alias: alias,
        signature: signature,
      ),
    );
    return HostilePeer._(link);
  }

  final SecureLink _link;

  /// Completes when the Host has closed the Pairing down.
  Future<void> get done async {
    try {
      await _link.messages.drain<void>();
    } on Object {
      // The Host tearing the link down is the expected end of a hostile
      // attempt, not a test failure.
    }
  }
}

/// The failure a future completed with, or null if it succeeded.
Future<Object?> failureOf(Future<Object?> future) =>
    future.then<Object?>((value) => null, onError: (Object error) => error);

/// A Fingerprint derived the way a real Device's is, for a Device that is not
/// here.
Fingerprint fingerprintOf(String label) =>
    Fingerprint.ofPublicKey(Uint8List.fromList(label.codeUnits));

void main() {
  group('Pairing by typed code over real TCP', () {
    test('a typed code pairs two Devices into one group', () async {
      final alice = await TestDevice.start('alice-laptop');
      final bob = await TestDevice.start('bob-phone');
      addTearDown(alice.close);
      addTearDown(bob.close);

      final changes = <LocalProfile>[];
      alice.service.changes.listen(changes.add);

      final (aliceOutcome, bobOutcome) = await pairUp(alice, bob);

      // Each side learned who the other is, and both held the same digits.
      expect(aliceOutcome.peer.fingerprint, bob.fingerprint);
      expect(aliceOutcome.peer.alias, 'bob-phone');
      expect(aliceOutcome.peer.platform, DevicePlatform.windows);
      expect(bobOutcome.peer.fingerprint, alice.fingerprint);
      expect(aliceOutcome.sas, hasLength(6));
      expect(aliceOutcome.sas, bobOutcome.sas);

      // One group, on both sides.
      expect(alice.members, containsAll([alice.fingerprint, bob.fingerprint]));
      expect(bob.members, containsAll([alice.fingerprint, bob.fingerprint]));
      expect(alice.group.contains(bob.fingerprint), isTrue);
      expect(bob.group.contains(alice.fingerprint), isTrue);

      // The peer is remembered as met, with the name it proved it chose.
      expect(alice.service.local.profile.known(bob.fingerprint), isNotNull);
      expect(
        alice.service.local.profile.known(bob.fingerprint)!.alias,
        'bob-phone',
      );

      await until(
        () => changes.isNotEmpty,
        description: 'a change was emitted',
      );
      expect(changes.last.profile.self, alice.fingerprint);
    });

    test(
      'the two Devices end up with the same group secret, and it sticks',
      () async {
        final alice = await TestDevice.start('alice-laptop');
        final bob = await TestDevice.start('bob-phone');
        addTearDown(alice.close);
        addTearDown(bob.close);

        expect(alice.secret, isNull, reason: 'nothing paired yet');
        expect(bob.secret, isNull);

        final (aliceOutcome, bobOutcome) = await pairUp(alice, bob);

        expect(alice.secret, isNotNull);
        expect(alice.secret, hasLength(32));
        expect(alice.secret, bob.secret);
        expect(aliceOutcome.sessionSecret, alice.secret);
        expect(bobOutcome.sessionSecret, bob.secret);

        // And it is the same secret a restart would come back to, not just
        // something held in memory.
        final aliceOnDisk = await alice.persisted();
        final bobOnDisk = await bob.persisted();
        expect(aliceOnDisk!.groupSecret, alice.secret);
        expect(bobOnDisk!.groupSecret, bob.secret);
        expect(aliceOnDisk.profile.group.contains(bob.fingerprint), isTrue);
        expect(bobOnDisk.profile.group.contains(alice.fingerprint), isTrue);
      },
    );

    test('neither Device can pair itself', () async {
      final alice = await TestDevice.start('alice-laptop');
      addTearDown(alice.close);

      final invitation = await alice.service.invite(port: 0);
      final hostSaw = failureOf(invitation.attempt);

      await expectLater(
        alice.service.join(
          host: '127.0.0.1',
          code: invitation.code,
          port: invitation.port,
        ),
        throwsA(isA<PairingException>()),
      );
      expect(await hostSaw, isA<PairingException>());
      expect(alice.secret, isNull);
    });
  });

  group('Pairing that must not succeed', () {
    test('a wrong code leaves both Devices unpaired', () async {
      final alice = await TestDevice.start('alice-laptop');
      final bob = await TestDevice.start('bob-phone');
      addTearDown(alice.close);
      addTearDown(bob.close);

      final invitation = await alice.service.invite(port: 0);
      final hostSaw = failureOf(invitation.attempt);
      var wrongCode = PairingSecret.generateCode();
      while (wrongCode == invitation.code) {
        wrongCode = PairingSecret.generateCode();
      }

      await expectLater(
        bob.service.join(
          host: '127.0.0.1',
          code: wrongCode,
          port: invitation.port,
        ),
        throwsA(isA<PairingException>()),
      );
      expect(await hostSaw, isA<PairingException>());

      // Nothing was written on either side, and the invitation is over.
      expect(alice.secret, isNull);
      expect(bob.secret, isNull);
      expect(alice.group.isAlone, isTrue);
      expect(bob.group.isAlone, isTrue);
      await until(
        () => !alice.service.isInviting,
        description: 'the failed invitation stopped listening',
      );
    });

    test(
      'a Device that cannot prove the identity it announced is refused',
      () async {
        final alice = await TestDevice.start('alice-laptop');
        final victim = fingerprintOf('the-device-bob-meant');
        addTearDown(alice.close);

        final invitation = await alice.service.invite(port: 0);
        final hostSaw = failureOf(invitation.attempt);

        // The imposter knows the code, completes the handshake, and claims the
        // victim's Fingerprint — but can only offer its own key.
        final imposter = await HostilePeer.connect(
          port: invitation.port,
          code: invitation.code,
          identity: await OwnerIdentity.generate(),
          alias: 'the-device-bob-meant',
          announced: victim,
          signature: Uint8List(64),
        );
        addTearDown(() => imposter.done);

        final error = await hostSaw;
        expect(error, isA<PairingException>());
        expect(
          (error! as PairingException).message,
          contains(victim.short()),
          reason: 'the refusal names the claimed identity',
        );
        expect(alice.secret, isNull);
        expect(alice.group.isAlone, isTrue);
      },
    );

    test('a Device that cannot sign with its own key is refused', () async {
      final alice = await TestDevice.start('alice-laptop');
      addTearDown(alice.close);

      final identity = await OwnerIdentity.generate();
      final invitation = await alice.service.invite(port: 0);
      final hostSaw = failureOf(invitation.attempt);

      // Announcing its own Fingerprint, so the identity claim is consistent —
      // only the signature over this Pairing's context is not.
      final imposter = await HostilePeer.connect(
        port: invitation.port,
        code: invitation.code,
        identity: identity,
        alias: 'honest-looking',
        announced: identity.fingerprint,
        signature: Uint8List(64),
      );
      addTearDown(() => imposter.done);

      final error = await hostSaw;
      expect(error, isA<PairingException>());
      expect((error! as PairingException).message, contains('did not prove'));
      expect(alice.secret, isNull);
    });

    test('two Devices already in different groups refuse each other', () async {
      final alice = await TestDevice.start('alice-laptop');
      final bob = await TestDevice.start('bob-phone');
      final carol = await TestDevice.start('carol-tablet');
      final dave = await TestDevice.start('dave-desktop');
      addTearDown(alice.close);
      addTearDown(bob.close);
      addTearDown(carol.close);
      addTearDown(dave.close);

      await pairUp(alice, bob);
      await pairUp(carol, dave);
      expect(alice.secret, isNot(carol.secret));

      final invitation = await alice.service.invite(port: 0);
      final hostSaw = failureOf(invitation.attempt);

      await expectLater(
        carol.service.join(
          host: '127.0.0.1',
          code: invitation.code,
          port: invitation.port,
        ),
        throwsA(isA<PairingException>()),
      );
      expect(await hostSaw, isA<PairingException>());

      // Neither group changed: a refusal must not half-admit anybody.
      expect(alice.group.contains(carol.fingerprint), isFalse);
      expect(carol.group.contains(alice.fingerprint), isFalse);
      expect(alice.secret, isNot(carol.secret));
    });

    test('a code that is not a code fails before anything is opened', () async {
      final alice = await TestDevice.start('alice-laptop');
      final bob = await TestDevice.start('bob-phone');
      addTearDown(alice.close);
      addTearDown(bob.close);

      await expectLater(
        bob.service.join(host: '127.0.0.1', code: 'nope'),
        throwsA(isA<PairingException>()),
      );
      expect(bob.secret, isNull);
    });

    test('a dead port is a reported failure, not a crash', () async {
      final bob = await TestDevice.start('bob-phone');
      addTearDown(bob.close);

      // Bind a port to learn one that is currently free, then release it.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();

      await expectLater(
        bob.service.join(
          host: '127.0.0.1',
          code: PairingSecret.generateCode(),
          port: deadPort,
        ),
        throwsA(isA<PairingException>()),
      );
      expect(bob.secret, isNull);
    });
  });

  group('Joining a group that already exists', () {
    test('the third Device joins the whole group, not just the one it paired '
        'with', () async {
      final alice = await TestDevice.start('alice-laptop');
      final bob = await TestDevice.start('bob-phone');
      final carol = await TestDevice.start('carol-tablet');
      addTearDown(alice.close);
      addTearDown(bob.close);
      addTearDown(carol.close);

      await pairUp(alice, bob);
      final groupSecret = alice.secret;

      await pairUp(alice, carol);

      // Carol knows Bob, who she never met: without the roster she would refuse
      // a Mirror from him, because the gate that decides who may mirror reads
      // the group.
      expect(carol.group.contains(bob.fingerprint), isTrue);
      expect(carol.group.contains(alice.fingerprint), isTrue);
      expect(alice.group.contains(carol.fingerprint), isTrue);

      // The group's secret is what Carol adopted; the new code did not mint a
      // new one, which would have cut Bob off.
      expect(carol.secret, groupSecret);
      expect(alice.secret, groupSecret);
      expect(bob.secret, groupSecret);
    });

    test(
      're-pairing two Devices already in one group changes nothing',
      () async {
        final alice = await TestDevice.start('alice-laptop');
        final bob = await TestDevice.start('bob-phone');
        addTearDown(alice.close);
        addTearDown(bob.close);

        await pairUp(alice, bob);
        final (secret, members) = (alice.secret, alice.members);

        await pairUp(alice, bob);

        expect(
          alice.secret,
          secret,
          reason: 'the group secret is not re-minted',
        );
        expect(alice.members, unorderedEquals(members));
        expect(alice.group.length, 2);
      },
    );
  });

  group('Confirming and abandoning', () {
    test('one side cancelling leaves neither Device paired', () async {
      final alice = await TestDevice.start('alice-laptop');
      final bob = await TestDevice.start('bob-phone');
      addTearDown(alice.close);
      addTearDown(bob.close);

      final invitation = await alice.service.invite(port: 0);
      final bobAttempt = await bob.service.join(
        host: '127.0.0.1',
        code: invitation.code,
        port: invitation.port,
      );
      final aliceAttempt = await invitation.attempt;
      expect(aliceAttempt.sas, bobAttempt.sas);

      // Alice confirms; Bob walks away instead of confirming.
      final aliceConfirm = failureOf(aliceAttempt.confirm());
      await bobAttempt.cancel();

      final error = await aliceConfirm;
      expect(error, isA<PairingException>());
      expect(alice.secret, isNull, reason: 'a half-pairing is not a pairing');
      expect(bob.secret, isNull);
      expect(alice.group.isAlone, isTrue);
      expect(bob.group.isAlone, isTrue);
      expect((await alice.persisted())!.groupSecret, isNull);
      expect((await bob.persisted())!.groupSecret, isNull);
    });

    test(
      'an attempt settles once, and a second confirmation is refused',
      () async {
        final alice = await TestDevice.start('alice-laptop');
        final bob = await TestDevice.start('bob-phone');
        addTearDown(alice.close);
        addTearDown(bob.close);

        final invitation = await alice.service.invite(port: 0);
        final bobAttempt = await bob.service.join(
          host: '127.0.0.1',
          code: invitation.code,
          port: invitation.port,
        );
        final aliceAttempt = await invitation.attempt;
        await Future.wait([aliceAttempt.confirm(), bobAttempt.confirm()]);

        expect(aliceAttempt.isOpen, isFalse);
        expect(bobAttempt.isOpen, isFalse);
        await expectLater(
          aliceAttempt.confirm(),
          throwsA(isA<PairingException>()),
        );
        // Cancelling a settled attempt is harmless, and does not undo anything.
        await bobAttempt.cancel();
        expect(alice.group.length, 2);
        expect(alice.secret, isNotNull);
      },
    );
  });

  group('The invitation lifecycle', () {
    test(
      'an invitation nobody answers can be withdrawn without hanging',
      () async {
        final alice = await TestDevice.start('alice-laptop');
        final bob = await TestDevice.start('bob-phone');
        addTearDown(alice.close);
        addTearDown(bob.close);

        final invitation = await alice.service.invite(port: 0);
        expect(alice.service.isInviting, isTrue);
        expect(invitation.port, greaterThan(0));
        expect(invitation.code, hasLength(10));

        final hostSaw = failureOf(invitation.attempt);
        await invitation.cancel();

        expect(await hostSaw, isA<PairingException>());
        await invitation.done;
        expect(alice.service.isInviting, isFalse);

        // The port is gone, so a Device that shows up later cannot get in.
        await expectLater(
          bob.service.join(
            host: '127.0.0.1',
            code: invitation.code,
            port: invitation.port,
          ),
          throwsA(isA<PairingException>()),
        );
      },
    );

    test('only one invitation can be open at a time', () async {
      final alice = await TestDevice.start('alice-laptop');
      addTearDown(alice.close);

      final invitation = await alice.service.invite(port: 0);
      await expectLater(alice.service.invite(port: 0), throwsStateError);
      expect(alice.service.isInviting, isTrue);

      await invitation.cancel();
      final second = await alice.service.invite(port: 0);
      addTearDown(second.cancel);
      expect(alice.service.isInviting, isTrue);
    });

    test('closing the service ends an open invitation', () async {
      final alice = await TestDevice.start('alice-laptop');
      final invitation = await alice.service.invite(port: 0);
      final hostSaw = failureOf(invitation.attempt);

      await alice.close();

      expect(await hostSaw, isA<PairingException>());
      await invitation.done;
      expect(alice.service.isInviting, isFalse);
      await expectLater(alice.service.invite(port: 0), throwsStateError);
      await expectLater(
        alice.service.join(
          host: '127.0.0.1',
          code: PairingSecret.generateCode(),
        ),
        throwsStateError,
      );
      // Closing twice is harmless.
      await alice.close();
    });

    test('a peer that connects after the first one is dropped', () async {
      final alice = await TestDevice.start('alice-laptop');
      final bob = await TestDevice.start('bob-phone');
      final carol = await TestDevice.start('carol-tablet');
      addTearDown(alice.close);
      addTearDown(bob.close);
      addTearDown(carol.close);

      final invitation = await alice.service.invite(port: 0);
      final bobAttempt = await bob.service.join(
        host: '127.0.0.1',
        code: invitation.code,
        port: invitation.port,
      );
      final aliceAttempt = await invitation.attempt;

      // The invitation stops listening as soon as it has its one peer, so
      // Carol's attempt fails rather than being queued behind Bob.
      await until(
        () => !alice.service.isInviting,
        description: 'the invitation stopped listening once Bob connected',
      );
      await expectLater(
        carol.service.join(
          host: '127.0.0.1',
          code: invitation.code,
          port: invitation.port,
        ),
        throwsA(isA<PairingException>()),
      );

      // Bob's Pairing is unaffected, and Carol is in nobody's group.
      final outcomes = await Future.wait([
        aliceAttempt.confirm(),
        bobAttempt.confirm(),
      ]);
      expect(outcomes[0].peer.fingerprint, bob.fingerprint);
      expect(carol.secret, isNull);
      expect(alice.group.contains(carol.fingerprint), isFalse);
    });
  });
}

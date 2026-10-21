// ignore_for_file: avoid_print
//
// The capture harness behind the pictures in README.md.
//
// Run it by hand:
//
//   flutter test tool/screenshots/capture_screenshots.dart
//
// It drives the shipping widget tree over the shipping controller, writes
// PNGs into `docs/screenshots/`, and prints where they went.
//
// It lives under `tool/` rather than under `test_flutter/` because it is not a
// test: it writes files, and a suite that rewrote the repository's own
// documentation on every run would be a suite nobody could trust to be green.
// The gate `flutter test test_flutter` therefore does not run it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';

import '../../test_flutter/support/screenshot_harness.dart';
import '../../test_flutter/support/ui_harness.dart';

/// Where the pictures go.
///
/// A tracked directory, for the reason the README cares about: a picture that
/// is not in the repository is not on GitHub, and a README that points at one
/// shows a broken image to every reader.
final Directory outputDirectory = Directory('docs/screenshots');

/// The window size the pictures are taken at.
///
/// Wide enough for the rail rather than the bottom bar, and tall enough for
/// the conversation's list and its composer to both be in the picture.
const Size captureSize = Size(1280, 800);

/// The address the captured Devices are shown at.
///
/// A real address on this machine's own network, so the pictures show what a
/// user sees rather than a loopback address that cannot happen on a LAN.
const String capturedAddress = '192.168.1.115';

/// The names the captured Device and its peers are shown under.
const String capturedAlias = '我的笔记本';
const String pairedAlias = '书房台式机';

/// The ports the captured Devices are shown listening on.
///
/// A Device that is told port 0 takes whatever the operating system hands
/// it, so the port in the picture would be a different one on every run —
/// and a picture whose only difference from the last one is a port is a
/// picture that cannot be compared with the last one.
///
/// Not the project's own default ports: a copy of the application is
/// usually running on the machine that takes these pictures, and it holds
/// 47655 already — a socket cannot be bound twice, and the capture would
/// fail to serve a Session. These are above the default range for that
/// reason, and they are four rather than two because both Devices run in
/// this one process.
const int capturedSessionPort = 47855;
const int capturedPairingPort = 47856;
const int peerSessionPort = 47857;
const int peerPairingPort = 47858;

/// The folder the captured Device is shown as saving received files into.
///
/// A real path rather than the harness's own temporary one: a picture that
/// shows `C:\Users\admin\AppData\Local\Temp\local-transfer-shot-52ea63b4`
/// is a picture of a test run, and the path in it says nothing about the
/// product. The folder does not have to exist — the settings surface shows
/// the path it was given, not the folders on disk.
const String capturedIncomingDirectory = r'D:\Downloads\LocalTransfer';

/// The pictures this run produced.
final List<String> written = [];

Future<void> main() async {
  await _runCapture();
}

/// Runs the whole capture.
Future<void> _runCapture() async {
  testWidgets('capture the shipping surfaces', (tester) async {
    // The font loader talks to the engine, which only answers on the real
    // event loop — a `testWidgets` body outside `runAsync` waits for it
    // forever.
    await tester.runAsync(ScreenshotFonts.load);

    final hub = MemoryBeaconHub();
    // The address every peer is reported at. The hub speaks over loopback, so
    // it would report `127.0.0.1` — a fact about the harness rather than
    // about the product, and one the picture would be showing.
    final address = InternetAddress(capturedAddress);

    final home = tempDirectory('local-transfer-shot-');
    // A fixed identity for each Device. A Device mints a key pair on first
    // launch and its Fingerprint is derived from that key, so without this
    // every run of the capture would produce a different picture for a
    // reason that has nothing to do with the interface — and re-running the
    // script to refresh the README's images would leave a diff made of
    // fingerprints.
    final meStore = await SeededProfileStore.overSeed(
      List<int>.filled(32, 0x11),
      alias: capturedAlias,
      platform: DevicePlatform.windows,
    );
    final peerStore = await SeededProfileStore.overSeed(
      List<int>.filled(32, 0x22),
      alias: pairedAlias,
      platform: DevicePlatform.windows,
    );
    final me = await startUiDevice(
      tester,
      AddressedBeaconTransport(hub.a, address),
      capturedAlias,
      clipboardMode: ClipboardMode.stage,
      defaultIncomingDirectory: capturedIncomingDirectory,
      profileStore: meStore,
      sessionListenPort: capturedSessionPort,
      pairingPort: capturedPairingPort,
    );
    final peer = await startUiDevice(
      tester,
      AddressedBeaconTransport(hub.b, address),
      pairedAlias,
      platform: DevicePlatform.windows,
      defaultIncomingDirectory: home.path,
      profileStore: peerStore,
      sessionListenPort: peerSessionPort,
      pairingPort: peerPairingPort,
    );

    await _pair(tester, me, peer);
    await _connect(tester, me, peer);
    await _talk(tester, me, peer);

    await pumpWindow(tester, me, size: captureSize);
    await _settle(tester);

    written.add(
      await _capture(tester, 'conversation.png', () async {
        await openTab(tester, l10n.tabConversation, window: windowA);
        await openConversation(tester, windowA, name: pairedAlias);
      }),
    );
    written.add(
      await _capture(tester, 'devices.png', () async {
        await openTab(tester, l10n.tabDevices, window: windowA);
      }),
    );
    written.add(
      await _capture(tester, 'transfers.png', () async {
        await openTab(tester, l10n.tabTransfers, window: windowA);
      }),
    );
    written.add(
      await _capture(tester, 'clipboard.png', () async {
        await openTab(tester, l10n.tabClipboard, window: windowA);
      }),
    );
    written.add(
      await _capture(tester, 'settings.png', () async {
        await openTab(tester, l10n.tabSettings, window: windowA);
      }),
    );

    await shutdown(tester, [me, peer]);

    // Printed from inside the test body, not from `main`: `testWidgets`
    // only registers the test, so a summary printed after the registration
    // would report the pictures of a run that has not happened yet — and
    // report zero of them, every time.
    print(
      'wrote ${written.length} pictures into ${outputDirectory.path}:\n'
      '${written.map((path) => '  ${path.replaceAll('\\', '/')}').join('\n')}',
    );
  });
}

/// Pairs the two Devices, answering the request here rather than by a tap.
///
/// A picture has no user to answer a Pairing question, so the answer is given
/// at the level the request arrives at. Everything below that — the
/// handshake, the group secret, the Session — is the shipping path.
Future<void> _pair(WidgetTester tester, UiDevice host, UiDevice guest) async {
  await tester.runAsync(() async {
    await _until(
      () => host.controller.isAcceptingPairings,
      'the host to answer Pairing requests',
    );
    final port = host.controller.pairingPort!;
    final joining = guest.controller.pairWith(
      host: InternetAddress.loopbackIPv4.address,
      port: port,
    );
    final request = await host.controller.pairingRequests.first.timeout(
      const Duration(seconds: 15),
    );
    final hostAttempt = await request.admit();
    final guestAttempt = await joining;
    await Future.wait([hostAttempt.confirm(), guestAttempt.confirm()]);
    await _until(
      () => host.controller.isServing && guest.controller.isServing,
      'both Devices to serve Sessions',
    );
  });
}

/// Opens the Session the two Devices talk over.
///
/// Dialled over the machine's own LAN address rather than over loopback, so
/// the address the picture shows is the one the Session really runs on. A
/// loopback Session would put `127.0.0.1` in the picture, which is a fact
/// about the harness rather than about the product.
Future<void> _connect(WidgetTester tester, UiDevice me, UiDevice peer) async {
  await tester.runAsync(() async {
    await me.controller.connectAfterPairing(peer.fingerprint);
    await _until(
      () =>
          me.controller.sessions.isNotEmpty &&
          peer.controller.sessions.isNotEmpty,
      'the Session to come up on both Devices',
    );
  });
}

/// Fills the conversation with something worth photographing.
///
/// A text in each direction, a file and a picture: the four kinds the
/// conversation view draws differently, and the only way a reader can tell
/// from the picture that the bubble really does draw each of them.
Future<void> _talk(WidgetTester tester, UiDevice me, UiDevice peer) async {
  await sendText(tester, me, '投影仪的信号是不是不稳？', to: peer.fingerprint);
  await sendText(tester, peer, '昨天重启过路由了，现在应该稳了。', to: me.fingerprint);
  await sendText(tester, me, '好，我把这份纪要发给你。', to: peer.fingerprint);

  final outbox = tempDirectory('local-transfer-shot-out-');
  final document = File('${outbox.path}${Platform.pathSeparator}周会纪要.txt');
  document.writeAsStringSync(
    '2026-10-21 周会纪要\n\n'
    '1. 投影仪固件升级完成。\n'
    '2. 局域网传输工具进入内网测试。\n'
    '3. 下周安排一次跨平台验收。\n',
  );
  await _sendFile(tester, me, peer, document);

  final picture = File('${outbox.path}${Platform.pathSeparator}现场照片.png');
  await writePicture(tester, picture, width: 640, height: 360, caption: '现场');
  await _sendPicture(tester, me, peer, picture);
}

/// Sends [file] and answers it on the far side.
///
/// A file offer is the one kind the controller does not answer on its own:
/// the user is asked where it should land, and there is no user in a picture.
/// The answer is given at the level the offer arrives at, and the bytes take
/// the shipping road either way.
Future<void> _sendFile(
  WidgetTester tester,
  UiDevice from,
  UiDevice to,
  File file,
) async {
  final inbox = tempDirectory('local-transfer-shot-in-');
  await tester.runAsync(() async {
    final sent = await from.controller.sendFile(file, to: to.fingerprint);
    await _until(
      () => to.offers.isNotEmpty,
      'the far side to be offered the file',
    );
    await to.controller.acceptInto(to.offers.single, inbox);
    await sent.outcome;
  });
}

/// Sends [file] as a picture and lets it land where it lands.
///
/// An image offer is answered by the controller itself, into the folder the
/// Device saves received files in.
Future<void> _sendPicture(
  WidgetTester tester,
  UiDevice from,
  UiDevice to,
  File file,
) async {
  await tester.runAsync(() async {
    final sent = await from.controller.sendImage(file, to: to.fingerprint);
    await sent.outcome;
  });
}

/// Waits for [condition] on the real event loop.
Future<void> _until(
  bool Function() condition,
  String description, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) {
      throw StateError('timed out waiting for $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Lets the tree catch up before the shutter.
///
/// A decode is a real file read followed by a real codec, and its
/// continuation lands back in the test's own clock — so the two have to
/// alternate: a turn of the real event loop for the bytes, a pump for the
/// frame that draws them. Pumping only would wait for a picture that has
/// not been read yet, and waiting only would never draw one.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Opens the surface, takes its picture, and returns where it went.
Future<String> _capture(
  WidgetTester tester,
  String name,
  Future<void> Function() open,
) async {
  await open();
  await _settle(tester);
  final file = File('${outputDirectory.path}${Platform.pathSeparator}$name');
  await captureWindow(tester, file);
  return file.path.replaceAll('\\', '/');
}

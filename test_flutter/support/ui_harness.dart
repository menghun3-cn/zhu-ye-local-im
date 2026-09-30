import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/controller_scope.dart';
import 'package:local_transfer/ui/home_shell.dart';
import 'package:local_transfer/ui/seams.dart';

/// Shared scaffolding for the tests that need a widget tree.
///
/// These tests live apart from `test/` on purpose: `test/` is the plain Dart
/// suite and has to stay loadable by `dart test` on a machine where no widget
/// test can run. Anything importing `flutter_test` belongs here instead, and
/// becomes part of the `flutter test test_flutter` gate.

/// A window size that takes the wide branch of the shell (a rail).
const Size wideWindow = Size(1000, 800);

/// A window size that takes the narrow branch of the shell (a bottom bar).
const Size narrowWindow = Size(600, 900);

/// The two windows a two-Device test shows side by side.
const ValueKey<String> windowAKey = ValueKey('window-a');
const ValueKey<String> windowBKey = ValueKey('window-b');

/// The five surfaces, in the order the shell lists them.
const int devicesSurface = 0;
const int transfersSurface = 1;
const int clipboardSurface = 2;
const int settingsSurface = 3;

/// A Device under test: the controller, and the seams it was handed.
///
/// The seams are the in-memory ones, so two Devices run inside one process.
/// Everything below them is the real thing — a real `ServerSocket`, a real
/// handshake, real sealed records — which is what makes the two-window test an
/// end-to-end test rather than a widget test against a stubbed controller.
final class UiDevice {
  UiDevice({
    required this.controller,
    required this.clipboard,
    required this.store,
    required this.seams,
  });

  /// The one object the widget tree talks to.
  final LocalTransferController controller;

  /// The clipboard the controller writes to, and a test simulates copying on.
  final MemorySystemClipboard clipboard;

  /// Where the profile is kept — in memory, so nothing is left on disk.
  final MemoryProfileStore store;

  /// What the pages are told about the platform.
  final PlatformSeams seams;

  /// Offers this Device has been asked to answer, in arrival order.
  final List<IncomingTransfer> offers = [];

  /// This Device's name.
  String get alias => controller.self.alias;

  /// This Device's identity.
  Fingerprint get fingerprint => controller.self.fingerprint;
}

/// Brings a Device up on [transport], with an ephemeral port for everything.
///
/// Port 0 for both listeners unless the test asks otherwise, so several Devices
/// run on one host and one test file never fights another over a fixed port.
/// The exception is the Device that *receives* a click-to-pair Pairing in a
/// two-window test: the guest dials the default pairing port, so the receiver
/// has to be listening where that dial looks.
///
/// ## Why this takes a [WidgetTester]
///
/// `controller.start()` binds a real `ServerSocket`, and a `testWidgets` body
/// runs on a fake clock: the real event loop does not run while that body is
/// suspended on a real socket, so awaiting one is a deadlock rather than a
/// wait. `tester.runAsync` is the only door out to the real event loop, and
/// everything below that touches a socket goes through it. Without this the
/// suite does not fail — it hangs at `+0` forever.
Future<UiDevice> startUiDevice(
  WidgetTester tester,
  BeaconTransport transport,
  String alias, {
  int sessionListenPort = 0,
  int pairingPort = 0,
  ClipboardMode clipboardMode = ClipboardMode.off,
  String? profilePath,
  String? defaultIncomingDirectory,
  DevicePlatform platform = DevicePlatform.windows,
}) async {
  late final UiDevice device;
  await tester.runAsync(() async {
    final store = MemoryProfileStore();
    final clipboard = MemorySystemClipboard();
    final controller = LocalTransferController(
      store: store,
      beaconTransport: transport,
      clipboard: clipboard,
      alias: alias,
      sessionListenPort: sessionListenPort,
      pairingPort: pairingPort,
      clipboardMode: clipboardMode,
    );
    await controller.start();
    device = UiDevice(
      controller: controller,
      clipboard: clipboard,
      store: store,
      // The same objects the controller was built on, plus the two facts the
      // pages need but the controller does not carry.
      seams: PlatformSeams(
        store: store,
        profilePath: profilePath,
        beacon: transport,
        clipboard: clipboard,
        platform: platform,
        defaultIncomingDirectory: defaultIncomingDirectory,
      ),
    );
    // Recorded here the way a screen would, by rendering them.
    controller.incoming.listen(device.offers.add);
  });
  addTearDown(() async {
    // `shutdown` has normally closed this already, and the call is a no-op by
    // then. When a test failed before reaching `shutdown`, the close is issued
    // here, outside the fake clock — where a close that needs the fake clock
    // cannot finish. Bounded rather than awaited forever: a leaked controller
    // shows up as a port still in use, which is a far better failure than a
    // suite that never ends.
    await device.controller.close().timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
  });
  return device;
}

/// One window in the test's tree, as a Finder.
///
/// Every helper that looks for a widget takes one of these, because a
/// two-window test has two of everything: two rails, two dialogs, and the same
/// label on both.
final class TestWindow {
  const TestWindow(this.finder);

  /// Everything inside this window.
  final Finder finder;

  /// [matching], restricted to this window.
  Finder within(Finder matching) =>
      find.descendant(of: finder, matching: matching);

  /// The button showing [label], anywhere in this window.
  Finder button(String label) => _buttonShowing(finder, label);

  /// The button showing [label] inside this window's open dialog.
  ///
  /// Scoped to the dialog on purpose. The Devices page shows a `Connect`
  /// button on every peer row that has not been dialled yet, and the Manual
  /// Address dialog's own confirm button carries the same label — so a finder
  /// that searched the whole window would match two and tap neither.
  Finder dialogButton(String label) =>
      _buttonShowing(within(find.byType(AlertDialog)), label);
}

/// The button showing [label], as a finder rooted at [scope].
///
/// `find.widgetWithText(ButtonStyleButton, label)` finds nothing, and the
/// reason is worth writing down: `find.byType` matches an exact `runtimeType`,
/// and no widget in this app *is* a `ButtonStyleButton` — the tree holds
/// `FilledButton`s, `TextButton`s and `OutlinedButton`s, which are subclasses
/// of it, plus whatever the `.icon` factories build. `bySubtype` is the matcher
/// that means what was intended.
Finder _buttonShowing(Finder scope, String label) => find.descendant(
  of: scope,
  matching: find.ancestor(
    of: find.text(label),
    matching: find.bySubtype<ButtonStyleButton>(),
  ),
);

/// The first window.
TestWindow get windowA => TestWindow(find.byKey(windowAKey));

/// The second window.
TestWindow get windowB => TestWindow(find.byKey(windowBKey));

/// A route transition that does nothing.
///
/// A real transition would still be sliding while a test awaits a socket on the
/// real event loop, which leaves the tree mid-offset and every later tap
/// landing somewhere else.
class _InstantTransitions extends PageTransitionsBuilder {
  const _InstantTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

const _instantTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.windows: _InstantTransitions(),
    TargetPlatform.android: _InstantTransitions(),
  },
);

/// One window: a size, a controller, and the real shell.
///
/// The scope is deliberately *above* `MaterialApp`. A dialog is pushed onto the
/// root navigator's overlay, which is a sibling of `home` rather than a
/// descendant of it — a scope around `home` would be invisible to every dialog
/// this app opens, and the dialog is where pairing happens.
Widget _pane(Key key, UiDevice device, Size size) {
  return SizedBox(
    key: key,
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: ControllerScope(
        controller: device.controller,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            pageTransitionsTheme: _instantTheme,
          ),
          home: HomeShell(seams: device.seams),
        ),
      ),
    ),
  );
}

void _resizeView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pumps one Device's window into the first window slot.
Future<void> pumpWindow(
  WidgetTester tester,
  UiDevice device, {
  Size size = wideWindow,
}) async {
  _resizeView(tester, size);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: _pane(windowAKey, device, size),
    ),
  );
  await tester.pump();
}

/// Pumps two Devices' windows side by side, both alive at once.
///
/// Both have to be alive together for pairing: an invitation is only offered
/// while the dialog showing its code is open, so tearing the host's window down
/// to build the guest's would cancel the very invitation being joined.
Future<void> pumpTwoWindows(
  WidgetTester tester,
  UiDevice left,
  UiDevice right, {
  Size paneSize = const Size(790, 900),
}) async {
  _resizeView(tester, Size(paneSize.width * 2 + 1, paneSize.height));
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          Expanded(child: _pane(windowAKey, left, paneSize)),
          const VerticalDivider(width: 1),
          Expanded(child: _pane(windowBKey, right, paneSize)),
        ],
      ),
    ),
  );
  await tester.pump();
}

/// Waits until [done] holds, letting the real event loop run in between.
///
/// Sockets and streams are real here, so a check has to yield to the real event
/// loop (`runAsync`) *and* advance the fake clock (`pump` with a non-zero
/// duration). Doing only one of the two waits forever.
///
/// Reports what it is still waiting for once a second. A wait that ends in a
/// timeout should say which one it was without the reader having to bisect the
/// test, and a wait that is *stuck* — as opposed to slow — is the one case
/// where a test suite produces no output at all and nothing to go on.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 20),
  String description = 'condition',
}) async {
  final watch = Stopwatch()..start();
  var reported = 0;
  while (!done()) {
    final seconds = watch.elapsed.inSeconds;
    if (seconds > reported) {
      reported = seconds;
      debugPrint('pumpUntil: still waiting for $description (${seconds}s)');
    }
    if (watch.elapsed > timeout) {
      // The screen is the evidence: a wait that times out is almost always a
      // dialog showing an error instead of the step that was expected, and
      // failing with the visible text turns a bisect into a read.
      final visible = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .where((text) => text.trim().isNotEmpty)
          .join(' | ');
      fail(
        'timed out after $timeout waiting for $description; '
        'visible text: $visible',
      );
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Advances past a route transition without waiting for the tree to quiesce.
///
/// `pumpAndSettle` is unusable here: the controller keeps real timers alive, so
/// a tree that never goes quiet is the normal state rather than a fault.
Future<void> settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Drains timers a finished test would otherwise be failed for leaving.
Future<void> drainTimers(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Stops [devices] and tears the tree down, in that order.
///
/// Discovery announces and sweeps on periodic timers, and a Transfer holds an
/// acceptance timeout, so a test that ends with a live controller ends with a
/// pending timer — which `flutter_test` fails it for. Closing first is what
/// makes the difference: pumping alone would only fire the timers and have them
/// reschedule themselves.
///
/// ## Why this pumps instead of merely awaiting
///
/// In a widget test the work a close has to do is spread across two clocks. The
/// controller was built inside [startUiDevice]'s `runAsync`, so *its* objects
/// live on the real event loop — but a Session opened by a *tap* was opened
/// from the fake zone, and the socket carrying it completes its futures on the
/// fake microtask queue. Closing that socket therefore needs the fake clock to
/// advance as well as the real one. Awaiting the closes with `runAsync` alone
/// waits on a clock nothing is advancing, and the suite hangs — not fails —
/// with no output at all. Driving both is what makes teardown finish.
Future<void> shutdown(WidgetTester tester, List<UiDevice> devices) async {
  final closings = <Future<void>>[
    for (final device in devices) device.controller.close(),
  ];
  var open = closings.length;
  for (final closing in closings) {
    unawaited(closing.whenComplete(() => open--));
  }
  final watch = Stopwatch()..start();
  while (open > 0) {
    if (watch.elapsed > const Duration(seconds: 15)) {
      fail('$open controller(s) did not finish closing');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await drainTimers(tester);
}

/// Taps the destination labelled [label] in [window] and lets the switch settle.
Future<void> openTab(
  WidgetTester tester,
  String label, {
  required TestWindow window,
}) async {
  // The rail is the wide-window control and the bar the narrow one; whichever
  // this window built is the one to tap.
  final rail = window.within(find.byType(NavigationRail));
  final control = rail.evaluate().isNotEmpty
      ? rail
      : window.within(find.byType(NavigationBar));
  await tester.tap(find.descendant(of: control, matching: find.text(label)));
  await settleRoute(tester);
}

/// Which surface is on top in [window], as the shell itself decides it.
int selectedSurface(WidgetTester tester, {required TestWindow window}) {
  final stack = tester.widget<IndexedStack>(
    window.within(find.byType(IndexedStack)),
  );
  return stack.index ?? 0;
}

/// Taps the button labelled [label] in [window], wherever it sits.
Future<void> tapButton(
  WidgetTester tester,
  String label, {
  required TestWindow window,
}) async {
  await tester.tap(window.button(label));
  await settleRoute(tester);
}

/// The six digits currently shown in [window]'s dialog, or null when the
/// window is not at the comparison step.
///
/// Read off the screen rather than out of the controller, because reading
/// them off the screen is what a person does: the digits are derived on each
/// Device and never sent, so the only way they cross between windows is
/// through the user's eyes.
String? shownSas(WidgetTester tester, {required TestWindow window}) {
  final pattern = RegExp(r'^[0-9]{6}$');
  final texts = tester.widgetList<SelectableText>(
    window.within(find.byType(SelectableText)),
  );
  for (final widget in texts) {
    final data = widget.data;
    if (data != null && pattern.hasMatch(data)) return data;
  }
  return null;
}

/// Whether [window] is showing an open dialog.
bool dialogIsOpen(TestWindow window) =>
    window.within(find.byType(AlertDialog)).evaluate().isNotEmpty;

/// Types [value] into the field labelled [label] in [window]'s open dialog.
Future<void> fillField(
  WidgetTester tester,
  String label,
  String value, {
  required TestWindow window,
}) async {
  final field = window.within(find.widgetWithText(TextField, label));
  expect(field, findsOneWidget, reason: 'expected a "$label" field');
  await tester.enterText(field, value);
  await tester.pump();
}

/// Taps the action labelled [label] inside [window]'s open dialog.
Future<void> tapDialogButton(
  WidgetTester tester,
  String label, {
  required TestWindow window,
}) async {
  await tester.tap(window.dialogButton(label));
  await settleRoute(tester);
}

/// [matching], restricted to the [page] inside [window].
///
/// The shell keeps all four surfaces alive in an `IndexedStack`, so every page
/// is in the tree whatever is on top, and the same string can be in several of
/// them at once. Naming the page is what keeps an assertion about one surface
/// from being satisfied by another.
Finder onPage(TestWindow window, Type page, Finder matching) =>
    find.descendant(of: window.within(find.byType(page)), matching: matching);

/// A directory that goes away when the test does.
Directory tempDirectory(String prefix) {
  final directory = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

/// Waits for [condition] on the real event loop, with no widget tree involved.
///
/// Has to be called from inside `tester.runAsync` (as [pairDevices] and
/// [connectDevices] do): it waits by yielding to the real event loop, and a
/// `testWidgets` body outside `runAsync` has no real event loop to yield to.
Future<void> untilTrue(
  bool Function() condition,
  String description, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) {
      fail('timed out after $timeout waiting for $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Pairs two Devices through the controller, with no window in the way.
///
/// This is state setup, not the subject under test: pairing as a *user* does it
/// — two windows, a code read off one screen and typed into the other — is what
/// the two-window test covers. Every other test would otherwise pay for that
/// whole flow just to reach a paired Device.
///
/// Inviting, dialling and confirming are all real sockets, so the whole exchange
/// runs on the real event loop — see [startUiDevice] for why that is not
/// optional.
Future<void> pairDevices(
  WidgetTester tester,
  UiDevice host,
  UiDevice guest,
) async {
  await tester.runAsync(() async {
    final invitation = await host.controller.invite();
    final guestAttempt = await guest.controller.join(
      host: InternetAddress.loopbackIPv4.address,
      code: invitation.code,
      port: invitation.port,
    );
    final hostAttempt = await invitation.attempt;
    expect(
      hostAttempt.sas,
      guestAttempt.sas,
      reason: 'both Devices must derive the same digits to compare',
    );
    await Future.wait([hostAttempt.confirm(), guestAttempt.confirm()]);
    await untilTrue(
      () => host.controller.isServing && guest.controller.isServing,
      'both Devices to serve Sessions',
    );
  });
}

/// Opens a Session from [from] to [to] over a real loopback socket.
Future<void> connectDevices(
  WidgetTester tester,
  UiDevice from,
  UiDevice to,
) async {
  await tester.runAsync(() async {
    final port = to.controller.listenPort;
    expect(port, isNotNull, reason: 'a paired Device listens');
    await from.controller.connectTo(
      address: InternetAddress.loopbackIPv4.address,
      port: port,
    );
    await untilTrue(
      () =>
          from.controller.sessions.isNotEmpty &&
          to.controller.sessions.isNotEmpty,
      'the Session to come up on both Devices',
    );
  });
}

/// Pairs two windows by clicking, the way two people now do it.
///
/// One window receives: its user taps Receive a connection and waits. The
/// other's user taps Pair on the card of the Device they want, which dials the
/// receiver's open Pairing. Nothing is typed anywhere — the digits both
/// screens show are derived on each Device and never sent, so the test reads
/// them off both screens only to assert they agree.
Future<void> pairThroughWindows(
  WidgetTester tester,
  TestWindow host,
  TestWindow guest, {
  required UiDevice hostDevice,
  required UiDevice guestDevice,
}) async {
  await openTab(tester, 'Devices', window: host);
  await tapButton(tester, 'Receive a connection', window: host);
  await pumpUntil(
    tester,
    () => dialogIsOpen(host),
    description: 'the host to open its receive dialog',
  );
  await pumpUntil(
    tester,
    () => windowHostListening(tester, host),
    description: 'the host to be listening for a connection',
  );

  await openTab(tester, 'Devices', window: guest);
  await pumpUntil(
    tester,
    () => hasButton(tester, 'Pair', window: guest),
    description: 'the guest to discover the host and offer Pair',
  );
  await tapButton(tester, 'Pair', window: guest);

  // Both sides now hold an attempt and show the digits to compare.
  await pumpUntil(
    tester,
    () => hasButton(tester, 'They match', window: guest),
    description: 'the guest to reach the comparison step',
  );
  await pumpUntil(
    tester,
    () => hasButton(tester, 'They match', window: host),
    description: 'the host to reach the comparison step',
  );
  final guestSas = shownSas(tester, window: guest);
  final hostSas = shownSas(tester, window: host);
  expect(guestSas, isNotNull, reason: 'the guest to show six digits');
  expect(hostSas, isNotNull, reason: 'the host to show six digits');
  expect(guestSas, hostSas, reason: 'both screens show the same digits');

  await tapDialogButton(tester, 'They match', window: guest);
  await tapDialogButton(tester, 'They match', window: host);

  await pumpUntil(
    tester,
    () => hostDevice.controller.isServing && guestDevice.controller.isServing,
    description: 'both Devices to serve Sessions',
  );
  // The guest opens the Session itself once the Pairing is committed; that is
  // what lands the user on a Device they can send to, and it is the
  // user-visible proof the flow is complete.
  await pumpUntil(
    tester,
    () =>
        hostDevice.controller.sessions.isNotEmpty &&
        guestDevice.controller.sessions.isNotEmpty,
    description: 'the Session the guest opens to come up on both Devices',
  );
}

/// Whether [window]'s receive dialog is past opening the invitation, i.e.
/// whether the listener the guest will dial is actually up.
bool windowHostListening(WidgetTester tester, TestWindow window) => window
    .within(find.textContaining('Waiting for a Device'))
    .evaluate()
    .isNotEmpty;

/// Whether [window] currently has a button labelled [label].
bool hasButton(
  WidgetTester tester,
  String label, {
  required TestWindow window,
}) => window.button(label).evaluate().isNotEmpty;

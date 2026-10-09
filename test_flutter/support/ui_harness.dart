import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/controller_scope.dart';
import 'package:local_transfer/ui/conversation_view.dart';
import 'package:local_transfer/ui/home_shell.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/pages/conversations_page.dart';
import 'package:local_transfer/ui/pages/devices_page.dart';
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
///
/// Written out here rather than imported from the shell: the shell's own names
/// are what the shell uses, and a test that read them would agree with any
/// ordering the shell happened to pick. These numbers are the assertion — a
/// tab that moved is a tab a user has to relearn.
const int conversationsSurface = 0;
const int devicesSurface = 1;
const int transfersSurface = 2;
const int clipboardSurface = 3;
const int settingsSurface = 4;

/// The strings the windows under test are showing.
///
/// Looked up from the same generated class the application reads, for the same
/// [appLocale] the panes below are built with — so a test that taps "配对" is
/// asserting the label a user of this build actually sees, rather than a
/// translation the test made up and the UI would have to keep matching.
///
/// `lookupAppLocalizations` rather than the delegate's `load`: the delegate is
/// asynchronous by contract, and a test that had to await it before it could
/// name a tab would need a `tester` it does not have.
final AppLocalizations l10n = lookupAppLocalizations(appLocale);

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
///
/// The `MaterialApp` here is configured the way the real one is — same locale,
/// same delegates, same supported list — because the point of these tests is
/// the shipping tree. Without the delegates every `AppLocalizations.of` below
/// throws, and a window built with the platform's locale instead would show a
/// different language from the window a user gets.
Widget _pane(Key key, UiDevice device, Size size) {
  return SizedBox(
    key: key,
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: ControllerScope(
        controller: device.controller,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: appLocale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: appLocales,
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
  // A question that has just been answered is still on its way out: the pop
  // animation leaves the dialog — and the modal barrier under it — in the tree
  // for a few frames, and a tap aimed at a rail item lands on that barrier
  // instead. `tester.tap` reports that as "would not hit test", a message about
  // coordinates that says nothing about the dialog actually in the way, so it
  // is worth waiting the question out rather than debugging the geometry.
  await pumpUntil(
    tester,
    () => !dialogIsOpen(window),
    description: 'the question on this window to finish closing',
  );
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
///
/// Best effort, and deliberately so: a TestDevice that is still holding a
/// source file open — an undecided Transfer keeps its handle — would make the
/// delete throw on Windows, and failing a test over the cleanup of a directory
/// under the system temp rather than over what it asserted is the wrong
/// failure. The directory lives under `Directory.systemTemp`, so a handle that
/// outlives the test is reaped by the operating system instead.
Directory tempDirectory(String prefix) {
  final directory = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } on FileSystemException {
      // A file still open somewhere. See above.
    }
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

/// Offers [file] from [device] without waiting for it to be answered.
///
/// The returned future resolves when the send itself returns, which for a file
/// means *after the other side has answered*. Nothing in [file]'s reads has
/// happened by the time this call returns, which is the point: a test that
/// wants to look at the state a Transfer waits in cannot first wait for the
/// answer that ends it.
///
/// ## Two clocks, and why the underlying call is posted rather than awaited
///
/// A send crosses a real socket, so it lives on the real event loop and has to
/// start inside [WidgetTester.runAsync]. But `runAsync` refuses to be
/// re-entered: while the send is outstanding, every later `runAsync` — which is
/// what [pumpUntil] and [untilTrue] use to yield — throws
/// `Reentrant call to runAsync() denied` instead of waiting.
///
/// So this starts the send and immediately returns, and the *caller* must
/// arrange for it to be answered before awaiting the result — with
/// [UiDevice.controller]'s own `reject`/`acceptInto` on the receiving Device,
/// driven through `runAsync` *after* the send has found its offer. Awaiting it
/// with the answer still outstanding hangs the test with no output at all,
/// which is a far worse failure to debug than this comment is to read.
///
/// The default `sendFile` is deliberately not used directly by tests that need
/// this: awaiting it inline is correct for every test that *does* answer
/// promptly, and a helper that hid the distinction would make the wrong one
/// easy to reach for.
Future<void> offerFile(WidgetTester tester, UiDevice device, File file) {
  return tester.runAsync(() => device.controller.sendFile(file));
}

/// Pairs two Devices through the controller, with no window in the way.
///
/// This is state setup, not the subject under test: pairing as a *user* does it
/// — two windows, a request answered on one and a tap on the other — is what
/// [pairThroughWindows] covers, and every other test would otherwise pay for
/// that whole flow just to reach a paired Device.
///
/// ## The host must have no window yet
///
/// A request reaches a screen as a dialog. This helper answers it through the
/// controller instead, so if the host's window is already in the tree the
/// dialog is left open — and a modal dialog swallows every later tap, which
/// fails a test somewhere else entirely. Pair first, then pump. The guard at
/// the end of this function says so out loud rather than leaving the next
/// reader to work it out from a timeout.
///
/// The exchange is real sockets, so the whole thing runs on the real event
/// loop — see [startUiDevice] for why that is not optional. Allowing the
/// request here is the test standing in for the tap on the host's screen; it is
/// *not* optional, which is the property the flow is built on, so there is no
/// path through this helper that skips it.
Future<void> pairDevices(
  WidgetTester tester,
  UiDevice host,
  UiDevice guest,
) async {
  await tester.runAsync(() async {
    // A Device answers requests as a standing state, so the host came up
    // listening and the guest has somewhere to dial without anybody opening
    // anything.
    await untilTrue(
      () => host.controller.isAcceptingPairings,
      'the host to answer Pairing requests',
    );
    final port = host.controller.pairingPort;
    expect(port, isNotNull, reason: 'an answering Device bound a port');

    final request = host.controller.pairingRequests.first;
    // Deliberately not awaited yet: this call does not return until the host
    // has answered, so waiting for it here would be waiting for a step the next
    // line is about to perform.
    final guestJoin = guest.controller.pairWith(
      host: InternetAddress.loopbackIPv4.address,
      port: port,
    );
    final asking = await request.timeout(
      const Duration(seconds: 15),
      onTimeout: () => fail('the host was never asked about the guest'),
    );
    final hostAttempt = await asking.admit();
    final guestAttempt = await guestJoin;
    expect(
      hostAttempt.sas,
      guestAttempt.sas,
      reason: 'both Devices must derive the same digits to sign over',
    );
    await Future.wait([hostAttempt.confirm(), guestAttempt.confirm()]);
    await untilTrue(
      () => host.controller.isServing && guest.controller.isServing,
      'both Devices to serve Sessions',
    );
  });
  // See the note above: a host window in the tree means the question went
  // somewhere this helper does not answer.
  await tester.pump();
  for (final window in [windowA, windowB]) {
    expect(
      window.within(find.text(l10n.pairingRequestTitle)).evaluate(),
      isEmpty,
      reason:
          'pair the Devices before pumping the host window: this helper '
          'answers the request through the controller, so a host window that '
          'is already on screen is left showing a question nobody taps',
    );
  }
}

/// Opens a Session from [from] to [to] over a real loopback socket.
///
/// Tolerates the Session already existing, and tolerates losing the race to
/// create it: a peer in the Owner Group is connected to as soon as Discovery
/// places it, so by the time a test asks for a Session the two Devices may
/// already have one — and *which* of the two dials the LinkManager counts as
/// the one that established it is not something a test can pin down. The two
/// shapes of "already connected" are an `AppStateException` from the
/// controller, which checks before it dials, and a `HandshakeException` from
/// the LinkManager, which is what the slower of two simultaneous dials sees.
Future<void> connectDevices(
  WidgetTester tester,
  UiDevice from,
  UiDevice to,
) async {
  await tester.runAsync(() async {
    if (from.controller.sessions.isEmpty) {
      final port = to.controller.listenPort;
      expect(port, isNotNull, reason: 'a paired Device listens');
      try {
        await from.controller.connectTo(
          address: InternetAddress.loopbackIPv4.address,
          port: port,
        );
      } on AppStateException {
        // Already open, as the controller saw it.
      } on HandshakeException {
        // Already open, as the LinkManager saw it: the peer dialled us at the
        // same instant and got there first.
      }
    }
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
/// The host does nothing to prepare: it answers requests for as long as it is
/// running, so the guest simply taps Pair on the found Device's row in its
/// conversation list. What the host's user is asked is *one question* — whether
/// to let the Device that dialled in — and allowing it is the whole of the
/// Pairing. Nothing is typed and nothing is compared: both Devices confirm on
/// their own once the question is answered.
///
/// Pair lives on the conversation list, not on the Devices surface: a Pairing is
/// the first line of a conversation, so the button that starts one sits beside
/// the conversation it is going to start. Only the host's *listening* state is
/// read from the Devices surface, which is still where "can anything reach me"
/// is answered.
Future<void> pairThroughWindows(
  WidgetTester tester,
  TestWindow host,
  TestWindow guest, {
  required UiDevice hostDevice,
  required UiDevice guestDevice,
}) async {
  await openTab(tester, l10n.tabDevices, window: host);
  await pumpUntil(
    tester,
    () => windowHostListening(tester, host),
    description: 'the host to be answering Pairing requests',
  );

  await openTab(tester, l10n.tabConversation, window: guest);
  await pumpUntil(
    tester,
    () => conversationHasButton(guest, button: l10n.pair, name: 'Alice'),
    description: 'the guest to discover the host and offer Pair',
  );
  await tapButton(tester, l10n.pair, window: guest);

  // The guest is now blocked on the host's user. The question arrives on the
  // host by itself — nobody opened a window for it — and the guest stays out
  // until it is answered.
  await pumpUntil(
    tester,
    () => hasButton(tester, l10n.acceptPairing, window: host),
    description: 'the host to be asked about the request',
  );
  await tapDialogButton(tester, l10n.acceptPairing, window: host);

  await pumpUntil(
    tester,
    () => hostDevice.controller.isPaired && guestDevice.controller.isPaired,
    description: 'allowing the request to pair both Devices',
  );
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

/// Opens [window]'s conversation with the Device shown as [name].
///
/// By the row in the conversation list, because that is what a user has now:
/// connecting a Device and talking to it both happen on the Conversations
/// surface, so the list row is where a peer is reached from rather than the
/// Devices card.
///
/// Assumes the window is already showing the conversation list; [openTab] with
/// [l10n.tabConversation] is how a test gets there.
Future<void> openConversation(
  WidgetTester tester,
  TestWindow window, {
  required String name,
}) async {
  await tester.tap(
    onPage(window, ConversationsPage, find.widgetWithText(ListTile, name)),
  );
  await settleRoute(tester);
}

/// Whether [window]'s conversation list has a row for [name] at all.
///
/// Weaker than [conversationOffered]: a row is drawn for a Device that has only
/// been found, so this answers "is it in the list" and not "can it be talked to
/// yet". Use it for the discovery half of the flow and
/// [conversationConnectable] for the action half.
bool conversationListed(TestWindow window, String name) => onPage(
  window,
  ConversationsPage,
  find.widgetWithText(ListTile, name),
).evaluate().isNotEmpty;

/// Whether [window]'s row for [name] is offering a button labelled [button].
///
/// The button rather than the label, so a button offered by a different peer on
/// the same list cannot answer for this one — which matters as soon as two
/// Devices are in the list at once. A row offers Connect when the peer is in the
/// group, and Pair when it is not, so this names the button rather than assuming
/// which one is there.
bool conversationHasButton(
  TestWindow window, {
  required String button,
  required String name,
}) => onPage(
  window,
  ConversationsPage,
  find.descendant(
    of: find.widgetWithText(ListTile, name),
    matching: _buttonShowing(find.byType(ConversationsPage), button),
  ),
).evaluate().isNotEmpty;

/// Whether [window]'s row for [name] is offering Connect.
bool conversationConnectable(TestWindow window, String name) => onPage(
  window,
  ConversationsPage,
  find.descendant(
    of: find.widgetWithText(ListTile, name),
    matching: _buttonShowing(find.byType(ConversationsPage), l10n.connect),
  ),
).evaluate().isNotEmpty;

/// Whether [window]'s Devices surface is offering a conversation with [name].
///
/// The signal is the card's own button rather than the row merely being drawn:
/// every known peer is a row, but only a Device with a live Session has
/// somewhere to send to, and tapping the row of one that is not connected does
/// nothing at all. Naming the peer keeps a second connected Device on the same
/// surface from answering for this one.
bool conversationOffered(TestWindow window, String name) => onPage(
  window,
  DevicesPage,
  find.descendant(
    of: find.widgetWithText(ListTile, name),
    matching: find.text(l10n.openConversation),
  ),
).evaluate().isNotEmpty;

/// [matching], restricted to the conversation [window] has open.
///
/// `descendant` rather than `ancestor`: the ancestor form collapses to the
/// conversation widget itself, so a tap aimed through it lands in the middle of
/// the message list rather than on the control the finder named. This form
/// answers the same question for an assertion — is this inside the conversation
/// — and is also the thing to tap.
///
/// Keyed on [ConversationView], which is the body of a conversation wherever it
/// is drawn: the shell's Conversations surface puts one in a pane, and the
/// pushed page puts one under an `AppBar`. Both are "the conversation this
/// window has open", so a test does not have to know which way it got there —
/// and the composer, the history and the two answers are the same widgets
/// either way.
Finder onConversation(TestWindow window, Finder matching) => window.within(
  find.descendant(of: find.byType(ConversationView), matching: matching),
);

/// Whether [window]'s pairing card says this Device is answering requests.
///
/// Read off the card's switch rather than the controller, and read off the
/// *subtitle* rather than the switch: the subtitle reports the listener while
/// the switch reports the preference, and it is the listener — the thing the
/// guest's dial can actually reach — that has to be up before the guest taps
/// Pair.
bool windowHostListening(WidgetTester tester, TestWindow window) => onPage(
  window,
  DevicesPage,
  find.text(l10n.pairingListening),
).evaluate().isNotEmpty;

/// Whether [window] currently has a button labelled [label].
bool hasButton(
  WidgetTester tester,
  String label, {
  required TestWindow window,
}) => window.button(label).evaluate().isNotEmpty;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/clipboard_paste.dart';
import 'package:local_transfer/ui/controller_scope.dart';
import 'package:local_transfer/ui/conversation_view.dart';
import 'package:local_transfer/ui/external_links.dart';
import 'package:local_transfer/ui/home_shell.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/nav_rail.dart';
import 'package:local_transfer/ui/pages/conversations_page.dart';
import 'package:local_transfer/ui/pages/devices_page.dart';
import 'package:local_transfer/ui/pickers.dart';
import 'package:local_transfer/ui/reveal.dart';
import 'package:local_transfer/ui/seams.dart';
import 'package:local_transfer/ui/update_check.dart';
import 'package:local_transfer/ui/update_install.dart';
import 'package:local_transfer/ui/update_notice.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

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

/// A window tall enough for a whole page to be laid out at once.
///
/// Taller than [wideWindow] on purpose. The Settings surface is a lazy list, so
/// a line below the fold is not merely out of sight — it has not been *built*,
/// and `find.text` matches nothing. A test that scrolled to reach one would be
/// testing the scroll as much as the line. The width is left at the wide value
/// so the shell still takes its rail branch.
const Size tallWindow = Size(1000, 1600);

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

/// Where the About surface sits, and the sixth of the ordered list.
///
/// Named for the same reason the first five are: a test that pressed a tab and
/// then asserted which surface came up would be reading the shell's own
/// ordering back to itself. It earns its own name twice over, because the
/// rail's update entry switches here rather than leaving the application — the
/// test of that needs a number to press against.
const int aboutSurface = 5;

/// The strings the windows under test are showing.
///
/// Looked up from the same generated class the application reads, for the same
/// [appLocale] the panes below are built with — so a test that changes a
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
    required this.messageStore,
    required this.hostShell,
    required this.seams,
  });

  /// The one object the widget tree talks to.
  final LocalTransferController controller;

  /// The clipboard the controller writes to, and a test simulates copying on.
  final MemorySystemClipboard clipboard;

  /// Where the profile is kept — in memory, so nothing is left on disk.
  ///
  /// A [ProfileStore] rather than a [MemoryProfileStore], because a test may
  /// hand in a store that hands out a fixed identity: a Device mints a key
  /// pair on first launch, and a picture of a Device whose Fingerprint
  /// changes on every run is a picture that changes for no reason.
  final ProfileStore store;

  /// Where the conversation is kept — in memory too, and handed back so that a
  /// test can stand a second Device up over the same one. That is the only way
  /// to assert "this message is still here after a restart" without a real file
  /// and a real second process.
  final MessageStore messageStore;

  /// The window and startup behaviour this Device was given, and where a test
  /// reads back what the app told the window to do.
  final ScriptedHostShell hostShell;

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
  ProfileStore? profileStore,
  String? defaultIncomingDirectory,
  DevicePlatform platform = DevicePlatform.windows,
  MessageStore? messageStore,
  // The recording stand-in specifically, rather than any [HostShell]: this
  // argument exists so that a test can start from a host whose state is already
  // set -- starting with the system, say -- and read it back afterwards, and
  // both of those need the scripting. A host that does something other than
  // record is not what this harness is for.
  ScriptedHostShell? hostShell,
  bool controlsWindow = true,
}) async {
  late final UiDevice device;
  await tester.runAsync(() async {
    final store = profileStore ?? MemoryProfileStore();
    final clipboard = MemorySystemClipboard();
    // Handed in when a test wants a conversation to survive a restart: the
    // second Device over the same store is the restart.
    final conversation = messageStore ?? MemoryMessageStore();
    // A host that records instead of acting. Installed by default rather than
    // left null so that every Device under test has one to look at, exactly as
    // the platform layer hands one to the real Device.
    final host = hostShell ?? ScriptedHostShell();
    final controller = LocalTransferController(
      store: store,
      beaconTransport: transport,
      clipboard: clipboard,
      alias: alias,
      sessionListenPort: sessionListenPort,
      pairingPort: pairingPort,
      clipboardMode: clipboardMode,
      // The same folder the pages are told about, handed to the controller as
      // well — which is what the shipping wiring does. Without it here, a
      // Device under test would answer an image offer differently from the
      // Device a user runs: the pages would name a folder the controller had
      // never heard of, and an image would be offered instead of filed.
      defaultIncomingDirectory: defaultIncomingDirectory,
      messageStore: conversation,
      hostShell: host,
    );
    await controller.start();
    device = UiDevice(
      controller: controller,
      clipboard: clipboard,
      store: store,
      messageStore: conversation,
      hostShell: host,
      // The same objects the controller was built on, plus the two facts the
      // pages need but the controller does not carry.
      seams: PlatformSeams(
        store: store,
        profilePath: profilePath,
        messageStore: conversation,
        messagePath: null,
        beacon: transport,
        clipboard: clipboard,
        platform: platform,
        defaultIncomingDirectory: defaultIncomingDirectory,
        hostShell: host,
        controlsWindow: controlsWindow,
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
Widget _pane(
  Key key,
  UiDevice device,
  Size size,
  UpdateNotice? update, {
  EdgeInsets padding = EdgeInsets.zero,
}) {
  return SizedBox(
    key: key,
    child: MediaQuery(
      data: MediaQueryData(size: size, padding: padding, viewPadding: padding),
      child: ControllerScope(
        controller: device.controller,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: appLocale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: appLocales,
          // The shipping theme, not a stand-in. A window built on some other
          // scheme would pass every assertion here while the real one regressed
          // — and the whole point of the palette being one file is that a test
          // can hold it to what it claims. Only the route transition is
          // replaced, because a real one is still sliding while a test awaits a
          // socket on the real event loop.
          theme: WeChat.theme(WeChatColors.light)
              .copyWith(pageTransitionsTheme: _instantTheme),
          home: HomeShell(seams: device.seams, update: update),
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
///
/// [update] is the shell's update notice. Left null — which is what almost
/// every test wants — the shell draws no update entry at all and asks the
/// network nothing: the notice is a constructor argument rather than something
/// the shell makes for itself precisely so that a test which is not about
/// updates does not pay for one.
Future<void> pumpWindow(
  WidgetTester tester,
  UiDevice device, {
  Size size = wideWindow,
  UpdateNotice? update,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  _resizeView(tester, size);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: _pane(windowAKey, device, size, update, padding: padding),
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
          Expanded(child: _pane(windowAKey, left, paneSize, null)),
          const VerticalDivider(width: 1),
          Expanded(child: _pane(windowBKey, right, paneSize, null)),
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
  // The loop only pumps while the condition is still false, so a condition that
  // already held when this was called — a radio that sets its field on the way
  // into `onSelectionChanged`, or a switch whose handler fires synchronously —
  // would be reported with the tree still showing the frame from *before* the
  // tap. One frame drawn after the condition is known to hold is what makes
  // "waited until" mean "and the window shows it".
  await tester.pump(const Duration(milliseconds: 16));
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
  final rail = window.within(find.byType(AppNavRail));
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

/// Waits for two discovered Devices to trust and connect to each other.
///
/// This is state setup, not a user action. Discovery performs the handshake and
/// opens the Session with no window or controller call, so the helper only
/// observes that the automatic flow finished. The exchange uses real sockets,
/// which is why the wait runs through [WidgetTester.runAsync].
Future<void> pairDevices(
  WidgetTester tester,
  UiDevice host,
  UiDevice guest,
) async {
  await tester.runAsync(() async {
    await untilTrue(
      () => host.controller.isPaired && guest.controller.isPaired,
      'Discovery to establish trust on both Devices',
    );
    await untilTrue(
      () =>
          host.controller.isServing &&
          guest.controller.isServing &&
          host.controller.sessions.isNotEmpty &&
          guest.controller.sessions.isNotEmpty,
      'both Devices to serve and connect automatically',
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      host.controller.sessions,
      isNotEmpty,
      reason: 'the automatically opened Session must stay open',
    );
    expect(
      guest.controller.sessions,
      isNotEmpty,
      reason: 'the automatically opened Session must stay open',
    );
  });
  await tester.pump();
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

/// Waits for the two windows to report the connection Discovery opened.
///
/// There is no click in this flow. The windows are pumped only so a rendering
/// failure or a leftover confirmation surface would be visible; the controller
/// does the whole exchange after the two Devices discover each other.
Future<void> waitForAutomaticConnection(
  WidgetTester tester,
  TestWindow left,
  TestWindow right, {
  required UiDevice leftDevice,
  required UiDevice rightDevice,
}) async {
  await pumpUntil(
    tester,
    () =>
        leftDevice.controller.isPaired &&
        rightDevice.controller.isPaired &&
        leftDevice.controller.isServing &&
        rightDevice.controller.isServing &&
        leftDevice.controller.sessions.isNotEmpty &&
        rightDevice.controller.sessions.isNotEmpty,
    description: 'Discovery to establish trust and open the Session',
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
  expect(leftDevice.controller.sessions, isNotEmpty);
  expect(rightDevice.controller.sessions, isNotEmpty);
  expect(dialogIsOpen(left), isFalse);
  expect(dialogIsOpen(right), isFalse);
}

/// Opens [window]'s conversation with the Device shown as [name].
///
/// By the row in the conversation list, because that is what a user has now:
/// connecting a Device and talking to it both happen on the Conversations
/// surface, so the list row is where a peer is reached from rather than the
/// The conversation row for [name] in [window]'s list.
///
/// Keyed on [ConversationRow] — the row's own type — rather than on the text
/// alone, because the list holds several peers at once and a finder for the
/// name would be satisfied by a row this test is not talking about. The row
/// carries its peer's name for exactly this reason.
Finder _conversationRow(TestWindow window, String name) => onPage(
  window,
  ConversationsPage,
  find.byWidgetPredicate(
    (widget) => widget is ConversationRow && widget.peer == name,
  ),
);

/// The row for [name] in [window]'s conversation list, for a test that wants to
/// look inside it itself.
///
/// Exported alongside [_conversationRow] because a test asserting *what* a row
/// offers needs the row, not a boolean about it.
Finder conversationRow(TestWindow window, String name) =>
    _conversationRow(window, name);

/// Devices card.
///
/// Assumes the window is already showing the conversation list; [openTab] with
/// [l10n.tabConversation] is how a test gets there.
Future<void> openConversation(
  WidgetTester tester,
  TestWindow window, {
  required String name,
}) async {
  await tester.tap(_conversationRow(window, name));
  await settleRoute(tester);
}

/// Whether [window]'s conversation list has a row for [name] at all.
///
/// Weaker than [conversationOffered]: a row is drawn for a Device that has only
/// been found, so this answers "is it in the list" and not "can it be talked to
/// yet". Use it for the discovery half of the flow and
/// [conversationConnectable] for the action half.
bool conversationListed(TestWindow window, String name) =>
    _conversationRow(window, name).evaluate().isNotEmpty;

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
    of: _conversationRow(window, name),
    matching: _buttonShowing(find.byType(ConversationsPage), button),
  ),
).evaluate().isNotEmpty;

/// Whether [window]'s row for [name] is offering Connect.
bool conversationConnectable(TestWindow window, String name) => onPage(
  window,
  ConversationsPage,
  find.descendant(
    of: _conversationRow(window, name),
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

/// The rail's update entry in [window], as the thing to tap.
///
/// Found through the label rather than by index: the entry is pinned under the
/// destinations rather than listed with them, so there is no position to name
/// it by — and if there were, a test would then be asserting the position
/// twice over. A window whose rail has no entry matches nothing.
Finder updateEntry(TestWindow window) => find.descendant(
  of: window.within(find.byType(AppNavRail)),
  matching: find.ancestor(
    of: find.text(l10n.railUpdate),
    matching: find.byType(TextButton),
  ),
);

/// The composer's send button in [window]'s open conversation.
///
/// Found by the label the user reads rather than by a tooltip: the send control
/// is a labelled button in the WeChat layout, and a tooltip that only shows on
/// hover is not what a user identifies it by.
///
/// A [FilledButton] because that is what it is — a filled pill in the action
/// green, the same shape the primary action at the foot of a dialog wears. It
/// was a [TextButton] with a hand-painted background, which drew the same thing
/// and was not the type it looked like.
Finder sendButton(TestWindow window) =>
    onConversation(window, find.widgetWithText(FilledButton, l10n.send));

/// The composer's attach button in [window]'s conversation.
///
/// The single entry for everything that can be attached — a picture is chosen
/// through the same dialog as a file and told apart by its extension, so there
/// is no second button to find.
Finder attachButton(TestWindow window) =>
    onConversation(window, find.byTooltip(l10n.menuSendFile));

/// Hands [device] a text message, through the controller rather than the screen.
///
/// For a test that needs a *conversation* to have something in it and is not
/// about typing: an unread count, a preview line, a remembered conversation.
/// Driving the composer instead would drag the sender's window into the tree,
/// which a test about the receiver's list does not want and cannot easily undo.
///
/// Waits for the message to settle, because a caller that read the count on the
/// next line would otherwise be racing the arrival.
Future<void> sendText(
  WidgetTester tester,
  UiDevice device,
  String body, {
  Fingerprint? to,
}) async {
  await tester.runAsync(() async {
    final sent = await device.controller.sendText(body, to: to);
    await untilTrue(() => sent.isSettled, 'the sent text to settle');
  });
}

/// Hands [device] a face as a payload of its own kind, through the
/// controller rather than the screen.
///
/// The composer does not send faces that way any more — a face picked in the
/// picker is part of the text — but a peer running v0.1.10 or v0.1.11 still
/// does, so the kind has to keep working on the wire and on screen.
Future<void> sendEmojiPayload(
  WidgetTester tester,
  UiDevice device,
  String face, {
  Fingerprint? to,
}) async {
  await tester.runAsync(() async {
    final sent = await device.controller.sendEmoji(face, to: to);
    await untilTrue(() => sent.isSettled, 'the sent face to settle');
  });
}

/// Whether [window] reports that automatic connections are listening.
bool windowAutomaticConnectionsReady(WidgetTester tester, TestWindow window) =>
    onPage(
      window,
      DevicesPage,
      find.text(l10n.automaticConnectionsReady),
    ).evaluate().isNotEmpty;

/// Whether [window] currently has a button labelled [label].
bool hasButton(
  WidgetTester tester,
  String label, {
  required TestWindow window,
}) => window.button(label).evaluate().isNotEmpty;

/// A [FilePicker] that hands back whatever the test put in it.
///
/// The composer's picker is the one thing in this product a widget test cannot
/// drive: the real one opens the operating system's dialog, which lives outside
/// Flutter's event loop and never returns to a `testWidgets` body. Without a
/// stand-in, every test of sending a file would have to go around the UI and
/// call the controller — which is exactly the part that then goes untested.
///
/// Installed with [install], which returns the fixture so a test can queue
/// answers and assert what was asked for.
///
/// ```dart
/// final picker = ScriptedPicker.install();
/// picker.willOffer([source.path]);
/// await tester.tap(onConversation(windowA, find.byTooltip(l10n.menuSendFile)));
/// ```
class ScriptedPicker implements FilePicker {
  ScriptedPicker._();

  /// Installs a scripted picker in place of the system one.
  ///
  /// A test that calls this must also call [PickerResolution.reset] in a
  /// `tearDown`: the resolution is a static, and a test that left a scripted
  /// picker behind would silently answer for the next one.
  static ScriptedPicker install() {
    final picker = ScriptedPicker._();
    PickerResolution.picker = picker;
    return picker;
  }

  List<String> _files = const [];
  String? _directory;

  /// How many times the file picker was opened.
  int filesAsked = 0;

  /// How many times the folder chooser was opened.
  int directoriesAsked = 0;

  /// What the next file picker answers with — pictures included.
  ///
  /// One queue for both, because there is one dialog for both: whether a path
  /// is a picture is the conversation's reading of its extension, and a fixture
  /// that answered pictures from a second queue would be asserting which button
  /// was pressed rather than what the user chose.
  void willOffer(List<String> paths) => _files = paths;

  /// What the next folder chooser answers with, or null to cancel.
  void willChooseDirectory(String? path) => _directory = path;

  @override
  Future<List<XFile>> files() async {
    filesAsked += 1;
    return [for (final path in _files) XFile(path)];
  }

  @override
  Future<String?> directory() async {
    directoriesAsked += 1;
    return _directory;
  }
}

/// A [ClipboardPaste] that hands back whatever the test put in it, and keeps
/// whatever the app put in it.
///
/// The same seam argument as [ScriptedPicker]: reading or writing the real
/// clipboard means a platform channel, and a method call to a channel with no
/// engine behind it throws in a `testWidgets` body. A test installs this,
/// presses the real Ctrl+V or chooses the real menu item, and asserts on what
/// the conversation did with the answer.
///
/// ```dart
/// final clipboard = ScriptedClipboard.install();
/// clipboard.holdingFiles([photo.path]);
/// await sendCtrlV(tester, windowA);
/// ```
class ScriptedClipboard implements ClipboardPaste {
  ScriptedClipboard._();

  /// Installs a scripted clipboard in place of the system one.
  ///
  /// A test that calls this must also call [PasteResolution.reset] in a
  /// `tearDown`, for the same reason [ScriptedPicker.install] insists on it.
  static ScriptedClipboard install() {
    final clipboard = ScriptedClipboard._();
    PasteResolution.paste = clipboard;
    return clipboard;
  }

  List<String> _files = const [];
  Uint8List? _image;

  /// What the next read of the clipboard answers with.
  void holdingFiles(List<String> paths) {
    _files = paths;
    _image = null;
  }

  /// Puts an encoded picture on the clipboard.
  void holdingImage(Uint8List bytes) {
    _image = bytes;
    _files = const [];
  }

  /// Empties it, so a paste falls through to text.
  void holdingNothing() {
    _files = const [];
    _image = null;
  }

  @override
  Future<List<String>> files() async => _files;

  @override
  Future<Uint8List?> image() async => _image;

  /// Every picture the app has put on the clipboard, in order.
  ///
  /// Kept separate from [_image] — what the app *reads* — because a copy that
  /// landed in the same field it reads from would make a test that pastes its
  /// own copy look like a test that copied what it pasted.
  final List<Uint8List> copiedImages = [];

  /// What the next write answers. False stands in for a platform that will not
  /// let the app write its clipboard, which is what the failure sentence is for.
  bool answersWrites = true;

  @override
  Future<bool> writeImage(Uint8List bytes) async {
    if (!answersWrites) return false;
    copiedImages.add(bytes);
    return true;
  }
}

/// A [Revealer] that records what it was asked to show.
///
/// The same seam argument as [ScriptedPicker]: the real revealer hands over to
/// the operating system's shell, so a test that drove it would open an Explorer
/// window on the machine running the suite. A test installs this, right-clicks a
/// settled Transfer, chooses the action, and asserts on the path it was handed.
///
/// ```dart
/// final revealer = ScriptedRevealer.install();
/// await rightClick(tester, onConversation(windowA, find.text('holiday.png')));
/// await tester.tap(find.text(l10n.openContainingFolder));
/// expect(revealer.revealed.single, landedPath);
/// ```
class ScriptedRevealer implements Revealer {
  ScriptedRevealer._();

  /// Installs a scripted revealer in place of the system one.
  ///
  /// A test that calls this must also call [RevealResolution.reset] in a
  /// `tearDown`, for the same reason [ScriptedPicker.install] insists on it.
  static ScriptedRevealer install() {
    final revealer = ScriptedRevealer._();
    RevealResolution.revealer = revealer;
    return revealer;
  }

  /// Every path the action was asked to show, in order.
  final List<String> revealed = [];

  /// What the next call answers — false stands in for a machine with no file
  /// manager, which is what the failure sentence exists for.
  bool answers = true;

  @override
  Future<bool> reveal(String path) async {
    revealed.add(path);
    return answers;
  }
}

/// An [UpdateChecker] that answers what the test tells it to, and counts how
/// often it was asked.
///
/// The same seam argument as [ScriptedPicker]: asking GitHub is the one thing a
/// widget test cannot do. What makes this one worth having even where the
/// answer does not matter is that the question is no longer asked only by a
/// button — the application asks it once as it comes up — so every test that
/// pumps `LocalTransferApp` has to hand in an answer or leave a real socket
/// attempt behind.
///
/// ```dart
/// final checker = ScriptedUpdateChecker.install(
///   const UpdateCheck(UpdateOutcome.available, version: '9.9.9'),
/// );
/// ```
class ScriptedUpdateChecker implements UpdateChecker {
  /// Answers [answer] to every question.
  ScriptedUpdateChecker(this.answer);

  /// What [latest] answers with. Settable, so a test can change its mind
  /// between two presses.
  UpdateCheck answer;

  /// How many times it was asked.
  int asked = 0;

  /// Installs a scripted checker in place of the real one.
  ///
  /// Registers [UpdateResolution.reset] with `addTearDown` itself, rather than
  /// leaving it to the caller as [ScriptedPicker.install] does: a static
  /// resolution left pointing at a stand-in would silently answer for the next
  /// test in the file, and that is worth making impossible rather than
  /// documented.
  static ScriptedUpdateChecker install(UpdateCheck answer) {
    final checker = ScriptedUpdateChecker(answer);
    UpdateResolution.checker = checker;
    addTearDown(UpdateResolution.reset);
    return checker;
  }

  @override
  Future<UpdateCheck> latest() async {
    asked += 1;
    return answer;
  }
}

/// An installer that answers instead of replacing anything.
///
/// The same seam argument as [ScriptedUpdateChecker], and a stronger one: the
/// real installer downloads a build from the internet, replaces the folder the
/// test is running from and then ends the process the test is running in. So a
/// test hands in what should happen and keeps its files.
///
/// [supported] defaults to false, which is what a platform that cannot replace
/// itself answers — and what every test that is not about installing wants,
/// because it is the state in which the offer is left off the card entirely.
///
/// ```dart
/// final installer = ScriptedUpdateInstaller.replace(supported: true);
/// await press(tester, l10n.aboutUpdateInstall);
/// expect(installer.askedFor.single.version, '9.9.9');
/// ```
class ScriptedUpdateInstaller implements UpdateInstaller {
  /// Answers [prepared] from [prepare] after reporting [progress], or fails
  /// with [failure] when there is nothing ready.
  ScriptedUpdateInstaller({
    this.supported = false,
    this.progress = const [],
    this.prepared,
    this.failure,
    this.leftOver,
    this.hold,
  });

  /// Whether this stand-in says it can replace the build it is running in.
  @override
  final bool supported;

  /// What is reported to the caller before the answer.
  final List<UpdateInstallProgress> progress;

  /// What [prepare] answers with, or null to fail with [failure].
  final PreparedUpdate? prepared;

  /// What [prepare] fails with when it has nothing ready.
  final UpdateInstallFailure? failure;

  /// What [previousFailure] answers.
  final UpdateInstallFailure? leftOver;

  /// When set, [prepare] reports [progress] and then waits for this to complete
  /// instead of answering — a download that is still running, which is the only
  /// way a test can look at the middle of one.
  final Completer<UpdatePrepareResult>? hold;

  /// Every answer the installer was handed, in order.
  final List<UpdateCheck> askedFor = [];

  /// Every update [apply] was handed, in order.
  final List<PreparedUpdate> applied = [];

  /// Installs a scripted installer in place of the real one.
  ///
  /// Registers [UpdateInstallResolution.reset] with `addTearDown` itself, like
  /// [ScriptedUpdateChecker]: a static resolution left pointing at a stand-in
  /// would silently answer for the next test in the file.
  static ScriptedUpdateInstaller replace({
    bool supported = false,
    List<UpdateInstallProgress> progress = const [],
    PreparedUpdate? prepared,
    UpdateInstallFailure? failure,
    UpdateInstallFailure? leftOver,
    Completer<UpdatePrepareResult>? hold,
  }) {
    final installer = ScriptedUpdateInstaller(
      supported: supported,
      progress: progress,
      prepared: prepared,
      failure: failure,
      leftOver: leftOver,
      hold: hold,
    );
    UpdateInstallResolution.installer = installer;
    addTearDown(UpdateInstallResolution.reset);
    return installer;
  }

  @override
  UpdateInstallFailure? previousFailure() => leftOver;

  @override
  Future<UpdatePrepareResult> prepare(
    UpdateCheck check, {
    required void Function(UpdateInstallProgress progress) onProgress,
  }) async {
    askedFor.add(check);
    for (final step in progress) {
      onProgress(step);
    }
    final waiting = hold;
    if (waiting != null) return waiting.future;
    final ready = prepared;
    if (ready != null) return UpdatePrepareResult.ready(ready);
    return UpdatePrepareResult.failed(failure ?? UpdateInstallFailure.download);
  }

  @override
  Future<void> apply(
    PreparedUpdate update, {
    required void Function(UpdateInstallProgress progress) onProgress,
  }) async {
    applied.add(update);
    // What the real one reports before it ends the process: the last thing the
    // old build gets to say.
    onProgress(const UpdateInstallProgress(UpdateInstallStage.handingOver));
  }
}

/// A [LinkOpener] that records the addresses it was asked to open.
///
/// The same seam argument as [ScriptedRevealer]: the real opener hands the
/// address to the operating system's shell, so a test that drove it would open
/// a browser window on the machine running the suite — and a `<cmd>` that has
/// been started never returns to the test body, so the failure would be a hang
/// rather than a report.
///
/// ```dart
/// final links = ScriptedLinkOpener.install();
/// await tester.tap(updateEntry(windowA));
/// expect(links.opened.single, updateReleasesPage);
/// ```
class ScriptedLinkOpener implements LinkOpener {
  ScriptedLinkOpener._();

  /// Installs a scripted opener in place of the system one.
  ///
  /// Registers [LinkResolution.reset] with `addTearDown` itself: a static
  /// resolution left pointing at a stand-in would silently answer for the next
  /// test in the file, and the only way to make that impossible is to not rely
  /// on the test remembering.
  static ScriptedLinkOpener install() {
    final opener = ScriptedLinkOpener._();
    LinkResolution.opener = opener;
    addTearDown(LinkResolution.reset);
    return opener;
  }

  /// Every address the app asked to open, in order.
  final List<String> opened = [];

  /// What the next call answers — false stands in for a machine with no
  /// browser, which is what the caller's own reporting exists for.
  bool answers = true;

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return answers;
  }
}

/// A host that writes down what it was told instead of doing it.
///
/// Passed to a Device the way the real one is, rather than installed as a
/// global: the host is a constructor argument, so a test that wants to see what
/// the app told the window simply holds the object it handed in —
/// `device.hostShell`. The install-and-reset dance the other scripted seams
/// need is only for the ones that replace a global.
///
/// It is deliberately *not* an emulator of the Windows runner. It holds one
/// bool of state, which is the same amount the registry entry holds, and the
/// point of it is that the app reads that state back rather than trusting what
/// it asked for — see `LocalTransferController.setAutostart`, which is the
/// behaviour these two fields exist to check.
class ScriptedHostShell implements HostShell {
  /// Starts with the app's own default: not starting with the system.
  ScriptedHostShell({this.autostart = false});

  /// Whether this host says it starts with the system. Set directly by a test
  /// to stand in for a user who changed it outside the app.
  bool autostart;

  /// When true, [setAutostart] records the request and leaves [autostart] where
  /// it was — a registry write that was denied, or an entry something else puts
  /// back. It is the only way to see the difference between the app reporting
  /// what it asked for and the app reporting what is there.
  bool refusesAutostartWrites = false;

  /// Every value the app has asked for, oldest first.
  final List<bool> autostartRequests = [];

  /// Every close-button value the app has pushed, oldest first.
  ///
  /// A list rather than the last value because "it was told the same thing
  /// twice" and "it was told once" are different bugs, and only a list can tell
  /// them apart.
  final List<bool> closeToTray = [];

  /// What the app last asked the close button to do, or null for never.
  bool? get closeToTrayNow => closeToTray.isEmpty ? null : closeToTray.last;

  @override
  Future<void> setCloseToTray(bool value) async => closeToTray.add(value);

  @override
  Future<bool> autostartEnabled() async => autostart;

  @override
  Future<void> setAutostart(bool enabled) async {
    autostartRequests.add(enabled);
    if (refusesAutostartWrites) return;
    autostart = enabled;
  }
}

/// A one-pixel PNG, for the tests that need the clipboard to hold a picture.
///
/// The smallest real PNG there is, so `imageExtensionOf` sees the signature it
/// is looking for rather than a handful of made-up bytes: a test fixture that
/// only looks like an image would pass a check the real thing could fail.
final Uint8List onePixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR, 13 bytes
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1 x 1
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, // 8-bit RGBA
  0x89,
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT, 10 bytes
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05,
  0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND
  0xAE, 0x42, 0x60, 0x82,
]);

/// Presses Ctrl+V in [window]'s composer.
///
/// A real key event rather than a call to the handler, so the test covers the
/// shortcut table as well as what the shortcut does.
Future<void> sendCtrlV(WidgetTester tester, TestWindow window) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

/// Right-clicks [matching], the way a user opens a context menu.
///
/// A secondary *mouse* button rather than a `tester.tap`: `onSecondaryTapDown`
/// only fires for the secondary button, so a plain tap would satisfy a finder
/// and still leave the menu shut — a test that passed while the feature it named
/// did nothing. The gesture is held from `down` so the button is reported for
/// the whole press, which is what the recognizer keys on.
Future<void> rightClick(WidgetTester tester, Finder matching) async {
  final gesture = await tester.startGesture(
    tester.getCenter(matching),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Moves a mouse pointer onto [matching], the way a hover is made.
///
/// A real pointer rather than a call to whatever the widget does on hover: a
/// tooltip is shown by a `MouseRegion` seeing an enter event, so a test that
/// asserted on the widget's own message property would pass while nothing a
/// user could see ever appeared. The pointer has to *be added* before it moves,
/// because moving a pointer the binding has never heard of is an event about
/// nothing.
///
/// The two pumps are the tooltip's own timing rather than padding: `Tooltip`
/// shows immediately for a mouse (`waitDuration` defaults to zero) and fades in
/// over 150ms, so one frame is not enough for the text to be in the tree. Well
/// under the 1500ms it stays up for, which is the other edge to stay clear of.
Future<void> hoverOver(WidgetTester tester, Finder matching) async {
  final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await pointer.addPointer(location: Offset.zero);
  addTearDown(pointer.removePointer);
  await tester.pump();
  await pointer.moveTo(tester.getCenter(matching));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

/// A real PNG of [width] × [height] pixels, written to [file].
///
/// Encoded by the engine rather than written out as a byte literal, so the
/// fixture is a picture the decoder will really accept at the size it claims:
/// an image message reads its shape from the decoded picture, and a fixture
/// that only looked like a PNG would exercise the "cannot read it" fallback
/// instead of the preview.
///
/// The colour is irrelevant — only the dimensions are read back.
Future<void> writePng(
  WidgetTester tester,
  File file, {
  required int width,
  required int height,
}) async {
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF3366CC),
    );
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        file.writeAsBytesSync(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  });
}

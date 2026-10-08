import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/app/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/ui/controller_scope.dart';
import 'package:local_transfer/ui/home_shell.dart';
import 'package:local_transfer/ui/pages/conversation_page.dart';
import 'package:local_transfer/ui/seams.dart';

import '../support/ui_harness.dart';

void main() {
  // This suite exists because every other widget test builds the shell the
  // harness's way — a ControllerScope wrapped around the whole MaterialApp —
  // and that tree cannot see the difference that matters: the application
  // wrapped only its `home`. A route pushed onto the root navigator builds in
  // the navigator's overlay, which is a sibling of `home`, so the two trees
  // disagree about exactly the thing such a route cares about. The
  // conversation page is the one pushed route, and on a release build the
  // disagreement was a grey window.
  //
  // So these tests pump `LocalTransferApp` itself — the tree `main` builds,
  // with no harness scaffolding around it — and push the way `_PeerCard`
  // does, from a context inside the shell. The full two-window flow, pairing
  // over real sockets included, stays in the E2E suite; its harness cannot
  // catch this class of bug, and this one exists precisely to close that gap.
  group('the app as main builds it', () {
    testWidgets('a route pushed from the shell can read the controller', (
      tester,
    ) async {
      final seams = PlatformSeams(
        store: MemoryProfileStore(),
        profilePath: null,
        beacon: MemoryBeaconHub().a,
        clipboard: MemorySystemClipboard(),
        platform: DevicePlatform.windows,
        defaultIncomingDirectory: null,
      );
      // Two clocks have to be driven at once, which is the whole difficulty of
      // testing this widget. `LocalTransferApp._open` binds a real
      // `ServerSocket`, and a `testWidgets` body runs on a fake clock: awaiting
      // that future under the fake clock alone deadlocks, and pumping alone
      // never lets the bind finish. So each round yields to the real event loop
      // (`runAsync`) and then advances the fake clock to build the frame the
      // resulting `setState` schedules. This is `startUiDevice`'s pattern,
      // applied to the app's own controller rather than the harness's.
      await tester.runAsync(
        () => tester.pumpWidget(LocalTransferApp(seams: seams)),
      );
      for (var i = 0; i < 400; i++) {
        if (find.byType(HomeShell).evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        find.byType(HomeShell),
        findsOneWidget,
        reason: 'the application should have come up',
      );
      // The controller the app made for itself, so the test can put it down
      // again the way the harness puts its own devices down.
      LocalTransferController? app;
      addTearDown(() async {
        final controller = app;
        if (controller == null) return;
        await controller.close().timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      });
      app = ControllerScope.of(tester.element(find.byType(HomeShell)));

      // Push the conversation the way `_PeerCard._openConversation` does for a
      // caller with no shell to ask: onto the root navigator, from a context
      // inside the shell. The peer here is this Device itself, which the page
      // tolerates — what is under test is the build, not the conversation's
      // contents.
      //
      // The navigator is kept from here rather than looked up again later:
      // once the conversation is on top, the shell below it is no longer
      // reachable as an element, so a second `find.byType(HomeShell)` would
      // come back empty.
      final navigator = Navigator.of(tester.element(find.byType(HomeShell)));
      final pushed = navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ConversationPage(peer: app!.self.fingerprint),
        ),
      );
      unawaited(pushed);
      await settleRoute(tester);

      // The assertion the old tree could not pass: the conversation builds
      // without an exception, and its pieces are actually on screen. With the
      // scope below the navigator this threw
      // `no ControllerScope above this widget` — a grey window on a release
      // build — which is what the report showed.
      final thrown = tester.takeException();
      expect(
        thrown,
        isNull,
        reason: 'opening a conversation must not throw: $thrown',
      );
      expect(find.byType(ConversationPage), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(l10n.conversationEmpty), findsOneWidget);

      // And the route goes back down again cleanly, because a page that
      // cannot build is also a page whose back button cannot be trusted.
      // Popped through the navigator rather than `pageBack`: that helper
      // looks for a platform-specific back button widget, and this test
      // deliberately pumps the app with the test binding's default platform
      // rather than Windows, so the button it looks for is not the one the
      // AppBar builds.
      expect(navigator.canPop(), isTrue);
      navigator.pop();
      await settleRoute(tester);
      expect(find.byType(ConversationPage), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
    });
  });
}

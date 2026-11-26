import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/pages/ai_routing_page.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

void main() {
  late Directory directory;
  late AiRuntime runtime;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ai-routing-test');
    runtime = await AiRuntime.open(directory.path);
  });

  tearDown(() async {
    await runtime.dispose();
    // Windows releases the just-written config files a beat after close;
    // a locked temp dir is litter, not a failure.
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // ignored: temp-dir cleanup is best-effort
    }
  });

  testWidgets('draws only the provider nodes a request has used', (
    tester,
  ) async {
    // The config is read once, up front, on the real event loop; the page
    // then gets it from memory — its own disk read could not complete
    // under the fake-async test clock.
    final config = await tester.runAsync(() => runtime.load());
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: AiRoutingView(
              runtime: runtime,
              configLoader: () async => config!,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final l10n = lookupAppLocalizations(appLocale);

    // No request yet: agent and gateway only. The seeded providers exist
    // but earn their nodes by being asked — a long catalogue must not have
    // to fit.
    expect(find.text('OpenCode Zen'), findsNothing);
    expect(find.text('Kilo'), findsNothing);
    expect(find.text(l10n.aiRoutingSource), findsOneWidget);
    expect(find.text(l10n.aiRoutingGateway), findsOneWidget);

    // A request to one provider puts its node up — and only its node.
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.served,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('OpenCode Zen'), findsOneWidget);
    expect(find.text('Kilo'), findsNothing);
  });

  testWidgets('tapping a provider node reports its id', (tester) async {
    // The enlarged nodes need ~1174px of canvas; widen the test surface
    // so the provider column is on screen rather than scrolled off.
    tester.view.physicalSize = const Size(1600, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final config = await tester.runAsync(() => runtime.load());
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: AiRoutingView(
              runtime: runtime,
              configLoader: () async => config!,
              onProviderTap: (id) => tapped = id,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.served,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.text('OpenCode Zen'));
    await tester.pump();
    expect(tapped, 'opencode-zen');
  });

  testWidgets('concurrent requests fly leaves in different shades', (
    tester,
  ) async {
    final config = await tester.runAsync(() => runtime.load());
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: AiRoutingView(
              runtime: runtime,
              configLoader: () async => config!,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Two in-flight requests: leaves must be tellable apart, and a
    // failover's second member (same callId) keeps the first member's
    // shade — same request, same colour.
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.failed,
      'opencode-zen/mimo-v2.6-flash-free',
      '',
      true,
    );
    // Same callId, next failover member: same request, same shade.
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.attempt,
      'kilo/kilo-auto/free',
    );
    // A second, unrelated call gets its own shade.
    runtime.router.emitRouteEventForTest(
      2,
      AiRoutePhase.attempt,
      'opencode-zen/deepseek-v4.1-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Each in-flight leaf is an Icons.eco glyph keyed 'leaf-out' /
    // 'leaf-back'; the Icon carries the per-callId shade.
    Set<Color?> leafColors() => tester
        .widgetList<Icon>(
          find.byWidgetPredicate(
            (w) =>
                w is Icon &&
                w.icon == Icons.eco &&
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('leaf-'),
          ),
        )
        .map((icon) => icon.color)
        .toSet();

    // Three leaves across two callIds: the two callId-1 leaves share a
    // shade, callId-2's differs — exactly two distinct colours.
    expect(leafColors().length, 2);
  });

  testWidgets('a leaf flies out solid and comes back with a hollow bead', (
    tester,
  ) async {
    final config = await tester.runAsync(() => runtime.load());
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: AiRoutingView(
              runtime: runtime,
              configLoader: () async => config!,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The leaf keys double as state markers: 'leaf-out' outbound,
    // 'leaf-back' (hollow bead) on the way home.
    int leaves(String state) =>
        find.byKey(ValueKey('leaf-$state')).evaluate().length;

    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    // The broadcast event lands a microtask later, and a leaf's ticker
    // needs frames to establish its baseline before elapsed time counts
    // — three pumps carry it well into its outbound leg. (The leaf
    // renders at any progress, but the return leg only exists once
    // value > 0.)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(leaves('out'), 1);
    expect(leaves('back'), 0);

    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.served,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    // Mid-return the leaf still exists and now shows its hollow bead;
    // the reverse leg is proportional to remaining progress, so a short
    // pump keeps it on screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(leaves('back'), 1);
    expect(leaves('out'), 0);
  });

  testWidgets('an in-flight request marks its provider node as answering', (
    tester,
  ) async {
    final config = await tester.runAsync(() => runtime.load());
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: AiRoutingView(
              runtime: runtime,
              configLoader: () async => config!,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final l10n = lookupAppLocalizations(appLocale);
    expect(find.text(l10n.aiRoutingAnswering), findsNothing);

    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Outbound leg: the request is on its way, the mark is already up.
    expect(find.text(l10n.aiRoutingAnswering), findsOneWidget);

    // Parked at the provider mid-stream: still answering.
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text(l10n.aiRoutingAnswering), findsOneWidget);

    // Content flowing: the mark gains live numbers on the 15fps clock.
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.progress,
      'opencode-zen/mimo-v2.6-flash-free',
      '',
      false,
      1234,
    );
    await tester.pump(const Duration(milliseconds: 70));
    expect(find.textContaining('1.2K'), findsOneWidget);
    expect(find.text(l10n.aiRoutingAnswering), findsNothing);

    // Served and heading home: the reply already arrived, mark lifts.
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.served,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text(l10n.aiRoutingAnswering), findsNothing);
  });

  testWidgets('a dashed wire means a leaf is on that leg right now', (
    tester,
  ) async {
    final config = await tester.runAsync(() => runtime.load());
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: AiRoutingView(
              runtime: runtime,
              configLoader: () async => config!,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The wire painter's segments are private to the page; read the flags
    // back through dynamic. Segment 0 is agent→gateway, segment 1 is
    // gateway→the one provider node on screen.
    ({bool agentDashed, bool agentRev, bool providerDashed, bool providerRev})
    wireState() {
      final painter = tester
          .widgetList<CustomPaint>(
            find.byWidgetPredicate(
              (w) =>
                  w is CustomPaint &&
                  w.painter.toString().contains('_WirePainter'),
            ),
          )
          .single
          .painter;
      final segments = (painter as dynamic).segments as List;
      return (
        agentDashed: segments[0].dashed as bool,
        agentRev: segments[0].reverse as bool,
        providerDashed: segments[1].dashed as bool,
        providerRev: segments[1].reverse as bool,
      );
    }

    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    // Let the leaf finish its outbound leg and park at the provider: the
    // whole route stays lit — both wires dashed and flowing forward for
    // as long as the request is out, held stretch included.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1100));
    var state = wireState();
    expect(state.agentDashed, isTrue);
    expect(state.agentRev, isFalse);
    expect(state.providerDashed, isTrue);
    expect(state.providerRev, isFalse);

    // On the way home both wires march backwards — the whole route, not
    // just the leg the leaf is on.
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.served,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    state = wireState();
    expect(state.providerDashed, isTrue);
    expect(state.providerRev, isTrue);
    expect(state.agentDashed, isTrue);
    expect(state.agentRev, isTrue);

    // Late in the return the route is still lit — both wires dashed,
    // both flowing backwards — until the leaf docks and the flight is
    // dismissed.
    await tester.pump(const Duration(milliseconds: 400));
    state = wireState();
    expect(state.agentDashed, isTrue);
    expect(state.agentRev, isTrue);
    expect(state.providerDashed, isTrue);
    expect(state.providerRev, isTrue);
  });

  testWidgets('a serial request queues behind the homeward leaf', (
    tester,
  ) async {
    final config = await tester.runAsync(() => runtime.load());
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: AiRoutingView(
              runtime: runtime,
              configLoader: () async => config!,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    int leaves(String state) =>
        find.byKey(ValueKey('leaf-$state')).evaluate().length;

    // Request 1 flies out and parks at the provider.
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1100));

    // It is served and its leaf turns for home; mid-return it is the
    // loaded leaf on the provider leg.
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.served,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(leaves('back'), 1);

    // The next serial request arrives while the first leaf is still
    // flying home. It must queue: a serial caller should see one round
    // trip at a time, not a homeward leaf overlapping a fresh departure
    // in the opposite direction.
    runtime.router.emitRouteEventForTest(
      2,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(leaves('back'), 1);
    expect(leaves('out'), 0);

    // Once the homeward leaf docks, the queued request departs.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(leaves('out'), 1);
  });

  testWidgets('a request that ends while queued never flies', (tester) async {
    final config = await tester.runAsync(() => runtime.load());
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: AiRoutingView(
              runtime: runtime,
              configLoader: () async => config!,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    int leaves(String state) =>
        find.byKey(ValueKey('leaf-$state')).evaluate().length;

    // Request 1 out and back; mid-return request 2 queues.
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1100));
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.served,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    runtime.router.emitRouteEventForTest(
      2,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Request 2 finishes before its leaf ever launched — the queued
    // attempt must be dropped, or it would fly out and park at the
    // provider forever with no end event left to bring it home.
    runtime.router.emitRouteEventForTest(
      2,
      AiRoutePhase.served,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(leaves('out'), 0);
    expect(leaves('back'), 0);
  });
}

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

    // Each in-flight cart is a CustomPaint whose painter carries the
    // per-callId shade; read it back through dynamic since the painter
    // type is private to the page.
    Set<Color> cartColors() => tester
        .widgetList<CustomPaint>(
          find.byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                w.painter.toString().contains('RouteCartPainter'),
          ),
        )
        .map((cp) => (cp.painter as dynamic).color as Color)
        .toSet();

    // Three carts across two callIds: the two callId-1 carts share a
    // shade, callId-2's differs — exactly two distinct colours.
    expect(cartColors().length, 2);
  });

  testWidgets('the cart runs empty out and comes back loaded', (tester) async {
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

    // The cart keys double as state markers: 'cart-empty' outbound,
    // 'cart-loaded' (sacks in the bed) on the way home.
    int carts(String state) =>
        find.byKey(ValueKey('cart-$state')).evaluate().length;

    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    // The broadcast event lands a microtask later, and a cart's ticker
    // needs frames to establish its baseline before elapsed time counts
    // — three pumps carry it well into its outbound leg. (The cart renders
    // at any progress, but the return leg only exists once value > 0.)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(carts('empty'), 1);
    expect(carts('loaded'), 0);

    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.served,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    // Mid-return the cart still exists and now shows its load — sacks
    // in the bed; the reverse leg is proportional to remaining progress,
    // so a short pump keeps it on screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(carts('loaded'), 1);
    expect(carts('empty'), 0);
  });

  testWidgets('a dashed wire means a cart is on that leg right now', (
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
    // Let the cart finish its outbound leg: parked at the provider, only
    // the gateway→provider wire may be dashed — the agent→gateway wire
    // must be solid because no cart is on it.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1100));
    var state = wireState();
    expect(state.agentDashed, isFalse);
    expect(state.providerDashed, isTrue);
    expect(state.providerRev, isFalse);

    // On the way home the provider-leg dash must flow backwards.
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
    expect(state.agentDashed, isFalse);

    // Late in the return the cart crosses onto the agent→gateway leg,
    // and that wire takes over — still flowing backwards.
    await tester.pump(const Duration(milliseconds: 400));
    state = wireState();
    expect(state.agentDashed, isTrue);
    expect(state.agentRev, isTrue);
    expect(state.providerDashed, isFalse);
  });

  testWidgets('a serial request queues behind the homeward cart', (
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

    int carts(String state) =>
        find.byKey(ValueKey('cart-$state')).evaluate().length;

    // Request 1 flies out and parks at the provider.
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1100));

    // It is served and its cart turns for home; mid-return it is the
    // loaded cart on the provider leg.
    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.served,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(carts('loaded'), 1);

    // The next serial request arrives while the first cart is still
    // flying home. It must queue: a serial caller should see one round
    // trip at a time, not a homeward cart overlapping a fresh departure
    // in the opposite direction.
    runtime.router.emitRouteEventForTest(
      2,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(carts('loaded'), 1);
    expect(carts('empty'), 0);

    // Once the homeward cart docks, the queued request departs.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(carts('empty'), 1);
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

    int carts(String state) =>
        find.byKey(ValueKey('cart-$state')).evaluate().length;

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

    // Request 2 finishes before its cart ever launched — the queued
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
    expect(carts('empty'), 0);
    expect(carts('loaded'), 0);
  });
}

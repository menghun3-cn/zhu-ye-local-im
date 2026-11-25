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

    final leafColors = tester
        .widgetList<Icon>(
          find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.eco),
        )
        .map((icon) => icon.color)
        .toSet();
    // Gateway node + three leaves across two callIds: the two callId-1
    // leaves share a shade, callId-2's differs — three distinct colours.
    expect(leafColors.length, greaterThanOrEqualTo(3));
  });

  testWidgets('a leaf carries a solid bead out and a hollow one back', (
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

    // The 7px cargo bead: filled decoration on the way out, a bare ring
    // on the way back — magpie's solid-out / hollow-home convention.
    int beads({required bool hollow}) => tester
        .widgetList<Container>(
          find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).shape == BoxShape.circle,
          ),
        )
        .where(
          (c) => ((c.decoration! as BoxDecoration).color == null) == hollow,
        )
        .length;

    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.attempt,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    // The broadcast event lands a microtask later, and a leaf's ticker
    // needs a frame to establish its baseline before elapsed time counts
    // — three pumps carry it well into its outbound leg. (The bead renders
    // at any progress, but the return leg only exists once value > 0.)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(beads(hollow: false), 1);
    expect(beads(hollow: true), 0);

    runtime.router.emitRouteEventForTest(
      1,
      AiRoutePhase.served,
      'opencode-zen/mimo-v2.6-flash-free',
    );
    // Mid-return the leaf still exists and now carries the hollow bead;
    // the reverse leg is proportional to remaining progress, so a short
    // pump keeps it on screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(beads(hollow: true), 1);
    expect(beads(hollow: false), 0);
  });
}

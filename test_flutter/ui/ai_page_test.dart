import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/l10n/generated/app_localizations.dart';
import 'package:local_transfer/ui/pages/ai_page.dart';
import 'package:local_transfer/ui/seams.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

import '../support/ui_harness.dart';

void main() {
  late Directory directory;
  late AiRuntime runtime;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ai-page-test');
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

  testWidgets('lands on the routing tab and switches to providers', (
    tester,
  ) async {
    // The config is read once, up front, on the real event loop; the page
    // then gets it from memory — its own disk read could not complete
    // under the fake-async test clock.
    final config = await tester.runAsync(() => runtime.load());
    final seams = PlatformSeams(
      store: MemoryProfileStore(),
      profilePath: null,
      messageStore: MemoryMessageStore(),
      messagePath: null,
      beacon: MemoryBeaconHub().a,
      clipboard: MemorySystemClipboard(),
      platform: DevicePlatform.windows,
      defaultIncomingDirectory: null,
      hostShell: ScriptedHostShell(),
      controlsWindow: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: WeChat.theme(WeChatColors.light),
        locale: appLocale,
        supportedLocales: appLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: AiPage(
            runtime: runtime,
            seams: seams,
            configLoader: () async => config!,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final l10n = lookupAppLocalizations(appLocale);

    // All four sub-pages exist as tabs.
    expect(find.text(l10n.aiRoutingTitle), findsOneWidget);
    expect(find.text(l10n.aiSectionProviders), findsOneWidget);
    expect(find.text(l10n.aiNavGateway), findsOneWidget);
    expect(find.text(l10n.aiSectionGroups), findsOneWidget);

    // The default tab is routing: the canvas's source node is on screen
    // and the provider list is not.
    expect(find.text(l10n.aiRoutingSource), findsOneWidget);
    expect(find.text('OpenCode Zen'), findsNothing);

    // Switching to providers shows the configured catalogue.
    await tester.tap(find.text(l10n.aiSectionProviders));
    await tester.pumpAndSettle();
    expect(find.text('OpenCode Zen'), findsOneWidget);
    expect(find.text('Kilo'), findsOneWidget);
    expect(find.text(l10n.aiAddProvider), findsOneWidget);
  });
}

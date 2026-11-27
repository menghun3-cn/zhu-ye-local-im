import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/ui/app.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/ai_provider_mark.dart';
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

    // All four sub-pages exist as tabs. The gateway tab's label collides
    // with the routing canvas's gateway node ("网关"/"Gateway"), so tabs
    // are found inside Tab widgets rather than as bare text.
    expect(find.text(l10n.aiRoutingTitle), findsOneWidget);
    expect(find.widgetWithText(Tab, l10n.aiSectionProviders), findsOneWidget);
    expect(find.widgetWithText(Tab, l10n.aiNavGateway), findsOneWidget);
    expect(find.widgetWithText(Tab, l10n.aiSectionGroups), findsOneWidget);

    // The default tab is routing: the canvas's source node is on screen
    // and the provider list is not.
    expect(find.text(l10n.aiRoutingSource), findsOneWidget);
    expect(find.text('OpenCode Zen'), findsNothing);

    // Switching to providers shows the configured catalogue.
    await tester.tap(find.widgetWithText(Tab, l10n.aiSectionProviders));
    await tester.pumpAndSettle();
    expect(find.text('OpenCode Zen'), findsOneWidget);
    expect(find.text('Kilo'), findsOneWidget);
    expect(find.text(l10n.aiAddProvider), findsOneWidget);
  });

  testWidgets('a gateway key stays masked until its eye is tapped', (
    tester,
  ) async {
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

    await tester.tap(find.widgetWithText(Tab, l10n.aiNavGateway));
    await tester.pumpAndSettle();
    // The keyring and request log load from real files in two awaits; each
    // needs a real event-loop turn the fake-async clock cannot give it.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final loadedKeys = await tester.runAsync(() => runtime.keys.load());
    expect(loadedKeys, hasLength(1));
    expect(find.text(l10n.aiGatewayKeys), findsOneWidget);
    expect(find.text(l10n.aiGatewayKeyAdd), findsOneWidget);
    // The seeded default key is masked — one dot per secret character —
    // and its eye toggle reveals the secret.
    final mask = '•' * loadedKeys!.single.secret.length;
    expect(find.text(mask), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(find.text(mask), findsNothing);
    expect(find.textContaining('sk-'), findsWidgets);
  });

  testWidgets('the add-provider dialog shows a brand mark per preset', (
    tester,
  ) async {
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

    await tester.tap(find.widgetWithText(Tab, l10n.aiSectionProviders));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aiAddProvider));
    await tester.pumpAndSettle();
    // SVG bytes resolve through the real asset bundle; each load needs a
    // real event-loop turn the fake-async clock cannot give it.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsNWidgets(aiProviderPresets.length));
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text(l10n.aiProviderCustom), findsOneWidget);
    // The picker is grouped: cloud header, local header, custom header.
    expect(find.text(l10n.aiProviderGroupCloud), findsOneWidget);
    expect(find.text(l10n.aiProviderGroupLocal), findsOneWidget);
    expect(find.text(l10n.aiProviderGroupCustom), findsOneWidget);
  });

  testWidgets('a new provider draft is titled as an add, not an edit', (
    tester,
  ) async {
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

    await tester.tap(find.widgetWithText(Tab, l10n.aiSectionProviders));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aiAddProvider));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anthropic'));
    await tester.pumpAndSettle();

    // The dialog's own title says "add" — the same words the button behind
    // it uses, so scope the finder to the dialog.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.aiAddProvider),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.aiEditProvider),
      ),
      findsNothing,
    );
  });

  testWidgets('the member dropdown survives picking a member', (tester) async {
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

    await tester.tap(find.widgetWithText(Tab, l10n.aiSectionGroups));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aiAddGroup));
    await tester.pumpAndSettle();

    // Picking a member used to leave the dropdown holding a value that had
    // just left its item list — the "value must be in items" assertion.
    // Enter a name first so the form is valid, then add a member.
    await tester.enterText(
      find.widgetWithText(TextField, l10n.aiGroupName),
      'failover',
    );
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    final firstItem = find.byType(DropdownMenuItem<String>).first;
    final ref = tester.widget<DropdownMenuItem<String>>(firstItem).value!;
    await tester.tap(firstItem);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(ref), findsOneWidget);
  });

  testWidgets('a gateway key needs a name and asks before deleting', (
    tester,
  ) async {
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

    await tester.tap(find.widgetWithText(Tab, l10n.aiNavGateway));
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.aiGatewayKeyAdd));
    await tester.pumpAndSettle();

    // Create stays disabled until the name field has content — an empty
    // name used to make the button a silent no-op.
    final createButton = find.widgetWithText(
      FilledButton,
      l10n.aiGatewayKeyCreate,
    );
    expect(tester.widget<FilledButton>(createButton).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, l10n.aiGatewayKeyNameHint),
      'laptop',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(createButton).onPressed, isNotNull);
    await tester.tap(createButton);
    // The save and the keyring reload are real file IO the fake-async
    // clock cannot advance — wait until the new row is actually on screen
    // (and the add form has closed, so 'laptop' cannot be the text field).
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (find.text('laptop').evaluate().isNotEmpty &&
          find.text(l10n.aiGatewayKeyAdd).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(find.text('laptop'), findsOneWidget);

    // Deleting a key asks first — it revokes a client's credential. The
    // row can sit below the fold of the gateway card's list, so scroll it
    // into view before tapping.
    await tester.ensureVisible(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.aiDeleteKeyTitle), findsOneWidget);
    await tester.tap(find.text(l10n.deleteMessage));
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (find.text('laptop').evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(find.text('laptop'), findsNothing);
  });

  testWidgets('a provider mark ignores an iconAsset that is not bundled', (
    tester,
  ) async {
    AiProvider provider(String? asset) => AiProvider(
      id: 'x',
      name: 'X',
      kind: AiProviderKind.custom,
      iconAsset: asset,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AiProviderMark(provider: provider(null), color: Colors.black),
              // providers.json is user-editable: a path that names no
              // bundled preset mark must fall back, not throw in build.
              AiProviderMark(
                provider: provider('assets/ai_providers/nope.svg'),
                color: Colors.black,
              ),
              AiProviderMark(
                provider: provider('assets/ai_providers/deepseek.svg'),
                color: Colors.black,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.dns_outlined), findsNWidgets(2));
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to LAN scope asks before widening the bind', (
    tester,
  ) async {
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

    await tester.tap(find.widgetWithText(Tab, l10n.aiNavGateway));
    await tester.pumpAndSettle();

    // Picking LAN opens the warning dialog instead of applying at once.
    await tester.tap(find.text(l10n.aiGatewayScopeLan));
    await tester.pumpAndSettle();
    expect(find.text(l10n.aiGatewayLanConfirmTitle), findsOneWidget);

    // Cancelling leaves the scope where it was.
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    var stored = await tester.runAsync(() => runtime.load());
    expect(stored!.gateway.scope, AiGatewayScope.loopback);

    // Confirming applies it — the save and rebind are real file/socket IO
    // the fake-async clock cannot advance. The config file flips before
    // the bind finishes, so wait on the runtime's gateway, not the file.
    await tester.tap(find.text(l10n.aiGatewayScopeLan));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aiGatewayLanConfirmAction));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (runtime.gateway?.scope == AiGatewayScope.lan) break;
    }
    await tester.pumpAndSettle();
    stored = await tester.runAsync(() => runtime.load());
    expect(stored!.gateway.scope, AiGatewayScope.lan);
    expect(runtime.gateway?.scope, AiGatewayScope.lan);

    // The rebind left a real HttpServer — and its idle-timeout timer —
    // alive inside the fake-async zone. Release it before the widget
    // tree's invariant check; tearDown's dispose() is then a no-op.
    await tester.runAsync(() => runtime.dispose());
    await tester.pump();
  });

  testWidgets('a corrupt keyring is reported instead of silently emptied', (
    tester,
  ) async {
    // Corrupt the file after open() seeded it — the next load must surface
    // the damage rather than read as "zero keys". Real file IO needs
    // runAsync: the fake-async clock cannot advance it.
    await tester.runAsync(
      () =>
          File('${directory.path}/gateway_keys.json')
              .writeAsString('{not json'),
    );
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

    await tester.tap(find.widgetWithText(Tab, l10n.aiNavGateway));
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text(l10n.aiGatewayKeysCorrupt), findsOneWidget);
  });
}

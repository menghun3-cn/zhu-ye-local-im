import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app.dart';
import 'controller_scope.dart';
import 'feedback.dart';
import 'home_shell.dart';
import 'l10n/generated/app_localizations.dart';
import 'seams.dart';
import 'wechat/theme.dart';

/// The languages this application speaks, in **fallback order**.
///
/// The order is [appLocale] first so that the fallback and the default agree:
/// Flutter falls back to the *first* entry of this list when the platform asks
/// for a language that is in neither, and the generated
/// [AppLocalizations.supportedLocales] is alphabetical (en, zh) — relying on it
/// would make the fallback English.
const List<Locale> appLocales = [Locale('zh'), Locale('en')];

/// The language this build opens in.
///
/// Chinese, fixed rather than resolved from the platform. There is no language
/// setting on screen to change it with, so following the platform would make
/// the language depend on a Windows setting nobody chose for this app — and
/// English strings are kept complete and generated, so the alternative stays
/// real. Setting this to null is the one-line change that hands the decision
/// back to the platform, at which point [appLocales]' order is what decides
/// the default.
const Locale appLocale = Locale('zh');

/// The application: one controller over the platform seams, and the shell.
///
/// The controller is created here rather than in `main`, so a failure to bring
/// the layers up is a screen instead of a stack trace before the first frame.
class LocalTransferApp extends StatefulWidget {
  /// Runs [seams], which the caller has already opened.
  const LocalTransferApp({super.key, required this.seams});

  /// What this platform provides.
  final PlatformSeams seams;

  @override
  State<LocalTransferApp> createState() => _LocalTransferAppState();
}

class _LocalTransferAppState extends State<LocalTransferApp> {
  LocalTransferController? _controller;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final seams = widget.seams;
    final controller = LocalTransferController(
      store: seams.store,
      beaconTransport: seams.beacon,
      clipboard: seams.clipboard,
      platform: seams.platform,
    );
    try {
      await controller.start();
    } on Object catch (error) {
      // A profile that cannot be read or minted leaves nothing to run on. The
      // controller is closed rather than leaked and the reason is shown: the
      // one thing that must not happen is a window that looks like it works.
      await controller.close();
      if (mounted) setState(() => _failure = error);
      return;
    }
    if (!mounted) {
      await controller.close();
      return;
    }
    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    // The seams are not closed with it: this widget was handed them and does
    // not own them.
    unawaited(_controller?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final app = MaterialApp(
      // The window and task-switcher title is a string like any other, so it is
      // read from the localizations rather than fixed here.
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: appLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: appLocales,
      // The one theme the whole app runs on. Not seeded from a colour: a seeded
      // scheme invents its own greens, and the conversation surfaces are held
      // to WeChat's specific `#07C160`.
      theme: WeChat.theme(),
      // A `Builder`, because this widget's own context sits *above* the
      // MaterialApp and therefore above the localizations it installs:
      // everything below reads its strings off this inner context instead.
      home: Builder(builder: (context) => _screenFor(context)),
    );

    // The scope wraps the whole `MaterialApp`, not just the shell inside
    // `home`.
    //
    // A pushed route does not build below `home`: it builds in the root
    // navigator's overlay, which is a *sibling* of `home` rather than a
    // descendant of it. A scope around the shell alone therefore does not
    // reach the conversation — `ControllerScope.of` throws
    // `no ControllerScope above this widget`, and a release build draws that
    // as a grey window. Wrapping the `MaterialApp` puts the scope above the
    // navigator and so above `home` and every route pushed on top of it.
    //
    // Above rather than inside via `MaterialApp.builder` because the
    // navigator is created by the `MaterialApp` itself and cannot be handed
    // in: `builder` only decorates the navigator it made, so a scope there
    // wraps a child that is not the routes. `home` also has to stay the shell
    // — replacing it with a placeholder leaves the navigator with no route at
    // all, which renders as an empty window.
    //
    // The scope is only installed once there is a controller to put in it.
    // Before that (and after a failure) there is nothing below that could read
    // one: the tree is the startup screen, which reads only its own strings.
    return controller == null
        ? app
        : ControllerScope(controller: controller, child: app);
  }

  /// The screen under the navigator: the shell, a startup failure, or a wait.
  ///
  /// The controller arrives asynchronously and can fail, so all three states
  /// live here rather than this widget's `build` — `home` is the only place a
  /// route can come from.
  Widget _screenFor(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return HomeShell(seams: widget.seams);
    }
    final failure = _failure;
    if (failure != null) {
      final l10n = AppLocalizations.of(context);
      return StartupFailureScreen(
        title: l10n.startupFailureTitle,
        message: describeFailure(failure, l10n),
      );
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// What the user sees when the app cannot even open its seams.
///
/// Losing the discovery socket is the case this exists for — a second copy of
/// the app on one host binds nothing — and a window that silently lists no
/// Devices would be a worse answer than one that says why.
class StartupFailureApp extends StatelessWidget {
  /// Shows [message] instead of the application.
  const StartupFailureApp({super.key, required this.message});

  /// What went wrong, as a sentence. Already text rather than an exception:
  /// this screen is built from `main`, which has no localized context to read
  /// a refusal off, and the failure it reports is a platform channel's own.
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: appLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: appLocales,
      // The same theme as the running app: a failure screen drawn in a
      // different scheme would look like a different program, and the moment a
      // user most needs to trust what they are reading is the moment it broke.
      theme: WeChat.theme(),
      home: Builder(
        builder: (context) => StartupFailureScreen(
          title: AppLocalizations.of(context).startupFailureTitle,
          message: message,
        ),
      ),
    );
  }
}

/// A failure that happened before there was any application to show it in.
class StartupFailureScreen extends StatelessWidget {
  /// Shows [title] and [message].
  const StartupFailureScreen({
    super.key,
    required this.title,
    required this.message,
  });

  /// The headline.
  final String title;

  /// The detail.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                SelectableText(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

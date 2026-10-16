import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import 'app.dart';
import 'l10n/generated/app_localizations.dart';
import 'labels.dart';
import 'update_install.dart';
import 'wechat/theme.dart';

/// The window a build shows while it finishes an update.
///
/// The window that is up when this one appears belongs to the build being
/// replaced, which is on its way out: Windows holds a program's files open until
/// the process running them has ended, so the replacement cannot be done from
/// inside it. What happens instead is what this class is the visible half of —
/// the download was unpacked into a folder of its own, this build — the newer
/// one — was started with the two folder names it needs, and it waits for the
/// old one to go before copying itself into place.
///
/// The window is not decoration. Between the old window closing and the new one
/// opening there is a copy of a whole application and a restart, and a machine
/// that showed nothing for that long would read as having crashed. It is also
/// the only place the failure of that copy can be reported: by then the old
/// build is gone and the new one is not in place yet.
class UpdateHandoffApp extends StatelessWidget {
  /// Finishes [handoff].
  const UpdateHandoffApp({super.key, required this.handoff});

  /// What this build was told to put where.
  final UpdateHandoff handoff;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: appLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: appLocales,
      // The same two themes as the application it is standing in for: a window
      // drawn in a different scheme would look like a different program, and
      // this one is on screen for exactly as long as the user has no other way
      // to tell what is happening.
      theme: WeChat.theme(WeChatColors.light),
      darkTheme: WeChat.theme(WeChatColors.dark),
      themeMode: ThemeMode.system,
      home: UpdateHandoffScreen(handoff: handoff),
    );
  }
}

/// What the hand-over window is showing.
class UpdateHandoffScreen extends StatefulWidget {
  /// Reports the progress of [handoff].
  const UpdateHandoffScreen({super.key, required this.handoff});

  /// What this build was told to put where.
  final UpdateHandoff handoff;

  @override
  State<UpdateHandoffScreen> createState() => _UpdateHandoffScreenState();
}

class _UpdateHandoffScreenState extends State<UpdateHandoffScreen> {
  /// The reason the copy did not happen, or null while it is happening.
  Object? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_finish());
  }

  Future<void> _finish() async {
    try {
      // On an isolate of its own rather than here: this is a copy of a whole
      // application — tens of megabytes, thousands of files — and doing it on
      // the frame's own thread would freeze the progress that is the one thing
      // telling the user this is not a crash.
      final executable = await Isolate.run(widget.handoff.putInPlace);
      // The new process must actually exist before the old one goes away:
      // exiting early can leave the update finished but nobody restarted.
      await startDetached(executable);
      // The build that was just started is the window the user asked for. This
      // one has nothing left to do and must not stay in front of it.
      exit(0);
    } on Object catch (error) {
      // Left where the application looks on its next start, because this window
      // may be read and closed by somebody who will not be here to remember it.
      writeHandoverReport(
        File(
          '${widget.handoff.target}${Platform.pathSeparator}$handoverReportName',
        ),
        error,
      );
      if (mounted) setState(() => _failure = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final failure = _failure;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: failure == null
                  ? const [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      _HandoverMessage(),
                    ]
                  : [
                      Icon(
                        Icons.error_outline,
                        size: 40,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.aboutUpdateFailedTitle,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        describeUpdateInstallFailure(
                          UpdateInstallFailure.handover,
                          l10n,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      // The window does not close on its own — the copy it is
                      // reporting on must not be interrupted by a click — so
                      // this is the way out once it has failed.
                      TextButton(
                        onPressed: () => exit(1),
                        child: Text(l10n.close),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The line under the spinner.
///
/// A widget of its own only because the string it shows comes from the
/// localizations, which the widget above cannot read before there is a
/// `BuildContext` to read them off — the same shape [StartupFailureScreen] uses
/// for its title.
class _HandoverMessage extends StatelessWidget {
  /// Shows the sentence for this step.
  const _HandoverMessage();

  @override
  Widget build(BuildContext context) => Text(
    AppLocalizations.of(context).aboutUpdateHandingOver,
    textAlign: TextAlign.center,
  );
}

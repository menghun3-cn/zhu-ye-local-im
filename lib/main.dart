import 'dart:async';

import 'package:flutter/material.dart';

import 'ui/app.dart';
import 'ui/seams.dart';
import 'ui/update_handoff.dart';
import 'ui/update_install.dart';

/// Starts the application.
///
/// The seams are opened before the first frame because discovery binds a
/// well-known UDP port: a second copy of the app on one host cannot have it,
/// and a window that silently lists no Devices would be a worse answer than
/// one that says why. Everything else the app does is a screen.
///
/// A build started with [applyUpdateFlag] is not the application at all: see
/// `update_install.dart` for why an update needs a second process, and
/// `update_handoff.dart` for what that process puts on the screen. It opens no
/// seams, binds no port and asks the platform for nothing — which is the point,
/// because the build it is replacing still holds the discovery port.
Future<void> main(List<String> arguments) async {
  // The platform channels are asked for a directory before any widget exists,
  // so the binding has to be up first.
  WidgetsFlutterBinding.ensureInitialized();

  final handoff = UpdateHandoff.parse(arguments);
  if (handoff != null) {
    runApp(UpdateHandoffApp(handoff: handoff));
    return;
  }

  // What earlier hand-overs left in the temporary directory. Started rather
  // than awaited — it is housekeeping, and the first frame must not wait behind
  // a folder holding the previous build.
  unawaited(Future<void>(clearStaleUpdateStages));

  try {
    final seams = await openPlatformSeams();
    runApp(LocalTransferApp(seams: seams));
  } on Object catch (error) {
    runApp(StartupFailureApp(message: '$error'));
  }
}

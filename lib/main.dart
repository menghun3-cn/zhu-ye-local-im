import 'package:flutter/material.dart';

import 'ui/app.dart';
import 'ui/seams.dart';

/// Starts the application.
///
/// The seams are opened before the first frame because discovery binds a
/// well-known UDP port: a second copy of the app on one host cannot have it,
/// and a window that silently lists no Devices would be a worse answer than
/// one that says why. Everything else the app does is a screen.
Future<void> main() async {
  // The platform channels are asked for a directory before any widget exists,
  // so the binding has to be up first.
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final seams = await openPlatformSeams();
    runApp(LocalTransferApp(seams: seams));
  } on Object catch (error) {
    runApp(StartupFailureApp(message: '$error'));
  }
}

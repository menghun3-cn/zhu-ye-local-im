/// The application layer: plain Dart orchestration over `lib/core`.
///
/// [LocalTransferController] owns discovery, pairing, Sessions, Transfers and
/// the clipboard mirror, and answers the questions a user interface asks. The
/// widget tree above it draws what this reports and nothing else.
///
/// **Nothing under `lib/app` may import `package:flutter`.** That is the whole
/// point of the split: the application — every flow a user goes through, over
/// real sockets — can be driven and accepted from `dart test`, with no widget
/// tree and no rendering engine. `test/app/plain_dart_test.dart` is the gate
/// that keeps the claim true.
library;

export 'app_controller.dart';
export 'app_version.dart';
export 'views.dart';

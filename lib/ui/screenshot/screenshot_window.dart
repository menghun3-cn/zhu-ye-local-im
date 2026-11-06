import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';

/// The four kinds of window the screenshot feature opens besides the main
/// one, carried in `WindowConfiguration.arguments` as a small JSON object.
///
/// The arguments are the *only* thing a new engine is told: each window
/// reads its kind, the library and pins directories, and — for the editor
/// and the pin — which record it is about. Everything else each window
/// needs it reads from those directories itself, which is also what lets a
/// pin window survive being opened by the restore pass and by a fresh
/// capture identically.
enum ScreenshotWindowKind { capture, history, editor, pin }

/// What a screenshot window was asked to be.
final class ScreenshotWindowArgs {
  const ScreenshotWindowArgs({
    required this.kind,
    this.libraryPath,
    this.pinPath,
    this.entryId,
    this.pinId,
    this.pinKind,
  });

  /// Which window to run.
  final ScreenshotWindowKind kind;

  /// The screenshot history directory, or null when there is nowhere to
  /// write — the feature still runs, it just forgets on exit.
  final String? libraryPath;

  /// The pins directory.
  final String? pinPath;

  /// The history entry the editor is marking up.
  final String? entryId;

  /// The pin the pin window or editor is about.
  final String? pinId;

  /// Whether [entryId] refers to a history entry (`history`) or, unused
  /// today, something else — kept explicit so a future source does not
  /// overload [entryId].
  final String? pinKind;

  /// The arguments for the main window, which carries no payload.
  static const main = ScreenshotWindowArgs(kind: ScreenshotWindowKind.capture);

  Map<String, Object?> toJson() => {
    't': switch (kind) {
      ScreenshotWindowKind.capture => 'capture',
      ScreenshotWindowKind.history => 'history',
      ScreenshotWindowKind.editor => 'editor',
      ScreenshotWindowKind.pin => 'pin',
    },
    if (libraryPath != null) 'lib': libraryPath,
    if (pinPath != null) 'pins': pinPath,
    if (entryId != null) 'id': entryId,
    if (pinId != null) 'pin': pinId,
    if (pinKind != null) 'pk': pinKind,
  };

  String encode() => jsonEncode(toJson());

  /// Reads the arguments of the engine this isolate is running in.
  ///
  /// The main window's arguments are the empty string — the runner created
  /// it before any `WindowConfiguration` existed — which decodes as "no
  /// screenshot window", i.e. the ordinary application.
  static Future<ScreenshotWindowArgs?> current() async {
    final controller = await WindowController.fromCurrentEngine();
    final raw = controller.arguments;
    if (raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return fromJson(json.cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  static ScreenshotWindowArgs? fromJson(Map<String, Object?> json) {
    final type = json['t'];
    final kind = switch (type) {
      'capture' => ScreenshotWindowKind.capture,
      'history' => ScreenshotWindowKind.history,
      'editor' => ScreenshotWindowKind.editor,
      'pin' => ScreenshotWindowKind.pin,
      _ => null,
    };
    if (kind == null) return null;
    return ScreenshotWindowArgs(
      kind: kind,
      libraryPath: json['lib'] as String?,
      pinPath: json['pins'] as String?,
      entryId: json['id'] as String?,
      pinId: json['pin'] as String?,
      pinKind: json['pk'] as String?,
    );
  }
}

/// Opens a screenshot window of [args.kind], or focuses the one already
/// open — Snipaste's rule that a second press of the hotkey brings the
/// history back rather than stacking a second copy.
Future<WindowController> openScreenshotWindow(
  ScreenshotWindowKind kind, {
  String? libraryPath,
  String? pinPath,
  String? entryId,
  String? pinId,
}) async {
  final wanted = ScreenshotWindowArgs(
    kind: kind,
    libraryPath: libraryPath,
    pinPath: pinPath,
    entryId: entryId,
    pinId: pinId,
  );
  for (final controller in await WindowController.getAll()) {
    final args = ScreenshotWindowArgs.fromJson(
      (jsonDecode(controller.arguments) as Map).cast<String, Object?>(),
    );
    if (args?.kind == kind &&
        args?.entryId == entryId &&
        args?.pinId == pinId) {
      await controller.show();
      return controller;
    }
  }
  final created = await WindowController.create(
    WindowConfiguration(arguments: wanted.encode()),
  );
  await created.show();
  return created;
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_transfer/core/core.dart';
import 'package:local_transfer/ui/wechat/theme.dart';

/// The fonts a captured window needs, and where they are on this machine.
///
/// A widget test renders with whatever the test binding has, which is not the
/// machine's font set: Chinese characters come out as empty boxes and the
/// Material glyphs come out as nothing at all. Both are loaded by hand here,
/// and both are named the way the theme names them — the theme asks for
/// `Microsoft YaHei UI` by name, so a font registered under any other name is
/// a font the tree never asks for.
///
/// The paths are the ones on the machine that runs the capture, and the loader
/// skips a file that is not there rather than failing: a missing font is a
/// picture that looks wrong, and a capture that cannot run at all is worse.
class ScreenshotFonts {
  const ScreenshotFonts._();

  /// The family the theme asks for, and the one the tree must name.
  static const String cjkFamily = 'Microsoft YaHei UI';

  /// The family a style that names no family at all falls back to.
  ///
  /// The theme's own text styles carry [cjkFamily], but the styles the
  /// Material components build for themselves — a button's label, a list
  /// tile's subtitle — name no family, and the engine then asks for the
  /// platform's default one. On a test machine that default is a face with
  /// no Chinese in it, so those labels come out as empty boxes. Registering
  /// the same face under that name gives every label in the picture a glyph.
  static const String defaultFamily = 'FlutterTest';

  /// Where the Chinese face lives on a Windows machine.
  static const String cjkPath = r'C:\Windows\Fonts\msyh.ttc';

  /// The family the symbol glyphs come from.
  ///
  /// The Chinese face has no `☺` in it, so a face the tree asks for as a
  /// fallback is what gives the composer its emoji button a glyph.
  static const String symbolFamily = 'Segoe UI Symbol';

  /// Where that face lives on a Windows machine.
  static const String symbolPath = r'C:\Windows\Fonts\seguisym.ttf';

  /// Where the Material icons live inside a Flutter checkout.
  static const String iconsPath =
      r'D:\tools\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf';

  /// Whether the fonts have been loaded into this process.
  static bool _loaded = false;

  /// Loads the Chinese face and the Material icons, once per process.
  ///
  /// A family is only usable when something names it, so loading is not
  /// enough: the theme's own `fontFamily` has to match, which is why the
  /// family here is the theme's family and not a convenient one.
  ///
  /// The whole fallback chain is loaded, not just the first face: a style
  /// naming the theme's family asks the chain for the glyphs that face does
  /// not have, and a chain that stops at the Chinese face leaves the
  /// composer's `☺` as a box.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    await _loadFamily(cjkFamily, cjkPath);
    await _loadFamily(defaultFamily, cjkPath);
    for (final family in WeChat.fontFamilyFallback) {
      if (family == cjkFamily) continue;
      await _loadFamily(family, _pathFor(family));
    }
    await _loadFamily('MaterialIcons', iconsPath);
  }

  /// Where the face behind [family] lives on this machine.
  ///
  /// The chain mixes Chinese faces and symbol faces, and a symbol glyph asked
  /// of a Chinese face is a box — so each family is paired with the file that
  /// actually has its glyphs.
  static String _pathFor(String family) => switch (family) {
    'Segoe UI Symbol' => symbolPath,
    _ => cjkPath,
  };

  static Future<void> _loadFamily(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  /// Loads the Chinese face under one more family name.
  ///
  /// Public so a probe can find out which family a widget that names none
  /// ends up asking for.
  static Future<void> loadFamily(String family) => _loadFamily(family, cjkPath);

  /// Loads [path] under [family].
  ///
  /// The face behind a family is not always the Chinese one: a symbol glyph
  /// needs a symbol face, and asking the Chinese face for one gives a box.
  static Future<void> loadFamilyAt(String family, String path) =>
      _loadFamily(family, path);
}

/// Writes the current window out as a PNG.
///
/// The picture comes from the render tree's own layer rather than from a
/// picture recorded separately, so what lands on disk is exactly what the
/// tree drew.
///
/// The capture has to happen inside [WidgetTester.runAsync]: the engine's
/// image pipeline needs the real event loop, and a test body that only has
/// the fake clock waits for it forever.
Future<void> captureWindow(WidgetTester tester, File file) async {
  await tester.runAsync(() async {
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    final image = await layer.toImage(renderView.paintBounds);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

/// A picture the conversation can draw, with a caption on it.
///
/// A flat block of colour would be enough to prove the plumbing, and would
/// also make the picture in the README a rectangle. The shot is meant to be
/// looked at, so it is drawn: a sky, a horizon, and a label, at the size a
/// photograph would be.
Future<void> writePicture(
  WidgetTester tester,
  File file, {
  required int width,
  required int height,
  String caption = '',
}) async {
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final size = ui.Size(width.toDouble(), height.toDouble());
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size.width, size.height),
      ui.Paint()..color = const ui.Color(0xFF8FC3EC),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, size.height * 0.62, size.width, size.height * 0.38),
      ui.Paint()..color = const ui.Color(0xFF6E8F6E),
    );
    canvas.drawCircle(
      ui.Offset(size.width * 0.78, size.height * 0.22),
      size.height * 0.11,
      ui.Paint()..color = const ui.Color(0xFFFFF3C4),
    );
    if (caption.isNotEmpty) {
      final painter = TextPainter(
        text: TextSpan(
          text: caption,
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 28,
            fontWeight: FontWeight.w600,
            fontFamily: ScreenshotFonts.cjkFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(24, size.height - 52));
    }
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  });
}

/// A beacon transport that reports a chosen address for what it hears.
///
/// The in-memory hub every Device in a test shares reports every peer at
/// `127.0.0.1`, because that is where the loopback socket it speaks over
/// lives. A picture is not a test: it is what a reader of the README sees,
/// and a loopback address in a picture of a LAN tool is a lie about the one
/// fact the picture exists to show.
///
/// Only the address changes. The datagrams are the ones the hub carries, so
/// discovery, the beacon format and the auto-connect are all still the
/// shipping ones.
final class AddressedBeaconTransport implements BeaconTransport {
  AddressedBeaconTransport(this._inner, this.address) {
    _subscription = _inner.received.listen((datagram) {
      if (_received.isClosed) return;
      _received.add(
        BeaconDatagram(
          beacon: datagram.beacon,
          address: address,
          port: datagram.port,
        ),
      );
    });
  }

  final BeaconTransport _inner;

  /// The address every peer is reported at.
  final InternetAddress address;

  late final StreamSubscription<BeaconDatagram> _subscription;
  final StreamController<BeaconDatagram> _received =
      StreamController<BeaconDatagram>.broadcast();

  @override
  Stream<BeaconDatagram> get received => _received.stream;

  @override
  void send(
    List<int> datagram, {
    required InternetAddress address,
    required int port,
  }) => _inner.send(datagram, address: address, port: port);

  @override
  void broadcast(List<int> datagram) => _inner.broadcast(datagram);

  @override
  Future<void> close() async {
    await _subscription.cancel();
    if (!_received.isClosed) await _received.close();
    await _inner.close();
  }
}

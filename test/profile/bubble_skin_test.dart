import 'package:local_transfer/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('BubbleSkinInk', () {
    test('round-trips through its wire name', () {
      for (final ink in BubbleSkinInk.values) {
        expect(BubbleSkinInk.fromWireName(ink.wireName), ink);
      }
    });

    test('an unknown name resolves to null rather than throwing', () {
      expect(BubbleSkinInk.fromWireName('sepia'), isNull);
      expect(BubbleSkinInk.fromWireName(null), isNull);
    });
  });

  group('GradientBubbleSkin', () {
    test('round-trips through JSON', () {
      final skin = GradientBubbleSkin(
        colors: [0xFFA9DDBB, 0xFF4E9A6E],
        direction: BubbleGradientDirection.vertical,
        ink: BubbleSkinInk.dark,
      );
      final decoded = BubbleSkin.fromJson(skin.toJson());
      expect(decoded, skin);
    });

    test('keeps explicit stops and even spacing apart', () {
      final even = GradientBubbleSkin(
        colors: [0xFF000000, 0xFFFFFFFF],
        ink: BubbleSkinInk.light,
      );
      final stepped = GradientBubbleSkin(
        colors: [0xFF000000, 0xFF333333, 0xFFFFFFFF],
        stops: [0.0, 0.7, 1.0],
        ink: BubbleSkinInk.light,
      );
      expect(even.stops, isEmpty);
      expect(stepped.stops, [0.0, 0.7, 1.0]);
      expect(BubbleSkin.fromJson(stepped.toJson()), stepped);
    });

    test('refuses a colour count outside two to four', () {
      expect(
        () => GradientBubbleSkin(colors: [0xFF000000], ink: BubbleSkinInk.dark),
        throwsArgumentError,
      );
      expect(
        () => GradientBubbleSkin(
          colors: [for (var i = 0; i < 5; i++) 0xFF000000 | i],
          ink: BubbleSkinInk.dark,
        ),
        throwsArgumentError,
      );
    });

    test('refuses stops that do not match the colour count', () {
      expect(
        () => GradientBubbleSkin(
          colors: [0xFF000000, 0xFFFFFFFF],
          stops: [0.0, 0.5, 1.0],
          ink: BubbleSkinInk.dark,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ImageBubbleSkin', () {
    test('round-trips an asset skin through JSON', () {
      final skin = ImageBubbleSkin(
        source: BubbleSkinImageSource.asset,
        name: 'mint.png',
        scrim: 0.4,
        ink: BubbleSkinInk.dark,
      );
      expect(BubbleSkin.fromJson(skin.toJson()), skin);
    });

    test('round-trips a file skin through JSON', () {
      final skin = ImageBubbleSkin(
        source: BubbleSkinImageSource.file,
        name: '/data/user/0/app/files/bubble_skins/skin-1-a.png',
        ink: BubbleSkinInk.light,
      );
      expect(BubbleSkin.fromJson(skin.toJson()), skin);
      // The default scrim is written, not omitted: a reader that predates
      // the field sees a complete skin rather than half of one.
      expect(skin.toJson()['scrim'], BubbleSkin.defaultScrim);
    });

    test('refuses an empty name and an out-of-range scrim', () {
      expect(
        () => ImageBubbleSkin(
          source: BubbleSkinImageSource.asset,
          name: '',
          ink: BubbleSkinInk.dark,
        ),
        throwsArgumentError,
      );
      expect(
        () => ImageBubbleSkin(
          source: BubbleSkinImageSource.asset,
          name: 'mint.png',
          scrim: BubbleSkin.maxScrim + 0.1,
          ink: BubbleSkinInk.dark,
        ),
        throwsArgumentError,
      );
    });
  });

  group('BubbleSkin.fromJson', () {
    test('answers null for everything it cannot fully decode', () {
      for (final bad in [
        null,
        'gradient',
        42,
        <String, Object?>{},
        {'kind': 'plasma', 'ink': 'dark'},
        {
          'kind': 'gradient',
          'ink': 'sepia',
          'colors': ['#000000', '#ffffff'],
        },
        {
          'kind': 'gradient',
          'ink': 'dark',
          'colors': ['#000000'],
        },
        {
          'kind': 'gradient',
          'ink': 'dark',
          'colors': ['#000000', 'not-a-colour'],
        },
        {
          'kind': 'gradient',
          'ink': 'dark',
          'colors': ['#000000', '#ffffff'],
          'stops': [0.0, 1.5],
        },
        {'kind': 'image', 'ink': 'dark'},
        {'kind': 'image', 'ink': 'dark', 'source': 'url', 'name': 'x.png'},
        {
          'kind': 'image',
          'ink': 'dark',
          'source': 'file',
          'name': 'x.png',
          'scrim': 9.0,
        },
      ]) {
        expect(BubbleSkin.fromJson(bad), isNull, reason: '$bad');
      }
    });

    test('reads #RRGGBB colours as opaque and #AARRGGBB as given', () {
      final skin =
          BubbleSkin.fromJson({
                'kind': 'gradient',
                'ink': 'dark',
                'colors': ['#A9DDBB', '#804E9A6E'],
              })!
              as GradientBubbleSkin;
      expect(skin.colors, [0xFFA9DDBB, 0x804E9A6E]);
      expect(skin.direction, BubbleGradientDirection.horizontal);
    });

    test('an unknown direction falls back to horizontal', () {
      final skin =
          BubbleSkin.fromJson({
                'kind': 'gradient',
                'ink': 'dark',
                'direction': 'spiral',
                'colors': ['#000000', '#ffffff'],
              })!
              as GradientBubbleSkin;
      expect(skin.direction, BubbleGradientDirection.horizontal);
    });
  });

  group('withInk', () {
    test('changes only the ink, whatever the fill', () {
      final gradient = GradientBubbleSkin(
        colors: [0xFF000000, 0xFFFFFFFF],
        ink: BubbleSkinInk.dark,
      );
      final image = ImageBubbleSkin(
        source: BubbleSkinImageSource.asset,
        name: 'mint.png',
        ink: BubbleSkinInk.dark,
      );
      expect(gradient.withInk(BubbleSkinInk.light).ink, BubbleSkinInk.light);
      expect(image.withInk(BubbleSkinInk.light).ink, BubbleSkinInk.light);
      expect(
        (gradient.withInk(BubbleSkinInk.light) as GradientBubbleSkin).colors,
        gradient.colors,
      );
    });
  });
}

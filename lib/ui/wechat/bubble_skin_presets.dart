import '../../core/core.dart';

/// A bubble skin the picker offers as a ready-made choice.
///
/// [id] is the preset's name — a stable key the picker maps to a localized
/// label, so renaming a preset never rewrites a stored profile: the skin
/// itself is what gets persisted, and two presets that share a look are two
/// entries here rather than one shared object.
final class BubbleSkinPreset {
  /// A preset called [id], painting with [skin].
  const BubbleSkinPreset({required this.id, required this.skin});

  /// The preset's stable name, e.g. `'mint'`.
  final String id;

  /// What choosing it stores in the profile.
  final BubbleSkin skin;
}

/// The gradient skins offered under 「渐变」.
///
/// Each is a designed pair (or trio) rather than a colour the user picked:
/// the stops, direction and ink are part of the preset, which is what keeps
/// a preset readable on both themes — a gradient has no theme-aware version
/// of itself, so the ink is chosen once, for the gradient, not per theme.
final List<BubbleSkinPreset> gradientSkinPresets = [
  BubbleSkinPreset(
    id: 'bamboo',
    skin: GradientBubbleSkin(
      colors: [0xFFA9DDBB, 0xFF4E9A6E],
      direction: BubbleGradientDirection.vertical,
      ink: BubbleSkinInk.dark,
    ),
  ),
  BubbleSkinPreset(
    id: 'aurora',
    skin: GradientBubbleSkin(
      colors: [0xFFBFE3F0, 0xFF7FB6D9],
      direction: BubbleGradientDirection.horizontal,
      ink: BubbleSkinInk.dark,
    ),
  ),
  BubbleSkinPreset(
    id: 'sakura',
    skin: GradientBubbleSkin(
      colors: [0xFFF6C6D9, 0xFFE58BB1],
      direction: BubbleGradientDirection.diagonal,
      ink: BubbleSkinInk.dark,
    ),
  ),
  BubbleSkinPreset(
    id: 'honey',
    skin: GradientBubbleSkin(
      colors: [0xFFF9DFA0, 0xFFF0A860],
      direction: BubbleGradientDirection.horizontal,
      ink: BubbleSkinInk.dark,
    ),
  ),
  BubbleSkinPreset(
    id: 'meadow',
    skin: GradientBubbleSkin(
      colors: [0xFFCDEBA0, 0xFF7CC46B],
      direction: BubbleGradientDirection.diagonal,
      ink: BubbleSkinInk.dark,
    ),
  ),
  BubbleSkinPreset(
    id: 'dusk',
    skin: GradientBubbleSkin(
      colors: [0xFF8E7CC3, 0xFF4E3F78],
      direction: BubbleGradientDirection.diagonal,
      ink: BubbleSkinInk.light,
    ),
  ),
];

/// The picture skins bundled with the application, offered under 「内置图片」.
///
/// The files live in `assets/bubble_skins/` and are registered in
/// `pubspec.yaml`; [ImageBubbleSkin.name] is the file name inside that
/// directory. Each carries the scrim and ink that were designed for it —
/// the user can still change the ink afterwards through the same picker,
/// because the stored skin is just data.
final List<BubbleSkinPreset> imageSkinPresets = [
  BubbleSkinPreset(
    id: 'mint',
    skin: ImageBubbleSkin(
      source: BubbleSkinImageSource.asset,
      name: 'mint.png',
      ink: BubbleSkinInk.dark,
    ),
  ),
  BubbleSkinPreset(
    id: 'duskPhoto',
    skin: ImageBubbleSkin(
      source: BubbleSkinImageSource.asset,
      name: 'dusk.png',
      ink: BubbleSkinInk.light,
    ),
  ),
  BubbleSkinPreset(
    id: 'ocean',
    skin: ImageBubbleSkin(
      source: BubbleSkinImageSource.asset,
      name: 'ocean.png',
      ink: BubbleSkinInk.dark,
    ),
  ),
  BubbleSkinPreset(
    id: 'graphite',
    skin: ImageBubbleSkin(
      source: BubbleSkinImageSource.asset,
      name: 'graphite.png',
      ink: BubbleSkinInk.light,
    ),
  ),
  BubbleSkinPreset(
    id: 'apricot',
    skin: ImageBubbleSkin(
      source: BubbleSkinImageSource.asset,
      name: 'apricot.png',
      ink: BubbleSkinInk.dark,
    ),
  ),
  BubbleSkinPreset(
    id: 'lilac',
    skin: ImageBubbleSkin(
      source: BubbleSkinImageSource.asset,
      name: 'lilac.png',
      ink: BubbleSkinInk.dark,
    ),
  ),
];

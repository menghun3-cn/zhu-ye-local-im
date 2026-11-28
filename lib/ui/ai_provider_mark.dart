import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/core.dart';

/// The leading mark of an AI provider — a provider-list row, a picker
/// option's fallback, a routing-canvas node: the bundled brand SVG when the
/// provider carries one, the generic glyph otherwise.
///
/// It lives outside `ai_page.dart` because the routing canvas draws the same
/// mark, and the page already imports the canvas — a shared widget in the
/// page would make the import circular.
class AiProviderMark extends StatelessWidget {
  /// Shows [provider]'s brand mark, or the fallback glyph, in [color].
  const AiProviderMark({
    super.key,
    required this.provider,
    required this.color,
    this.size = 20,
  });

  final AiProvider provider;
  final Color color;
  final double size;

  /// `providers.json` is a user-editable file: an `iconAsset` that does not
  /// name a bundled preset mark would make `SvgPicture.asset` throw inside
  /// build. Only paths the presets actually ship are honoured.
  static final Set<String> _bundled = {
    for (final preset in aiProviderPresets)
      if (preset.iconAsset != null) preset.iconAsset!,
  };

  @override
  Widget build(BuildContext context) {
    final asset = provider.iconAsset;
    if (asset == null || !_bundled.contains(asset)) {
      return Icon(Icons.dns_outlined, size: size, color: color);
    }
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

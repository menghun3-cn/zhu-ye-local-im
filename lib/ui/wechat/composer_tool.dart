import 'package:flutter/material.dart';

import 'theme.dart';

/// One tool in the composer's row of tools: a bare line-drawn glyph.
///
/// Not a button with a border. WeChat's input area has a row of tools, and
/// they read as tools precisely because none of them is framed — a row of
/// little squares would read as a form.
///
/// The glyph is drawn at [WeChat.composerIconSize] inside a
/// [WeChat.composerIconBox] tap area, and the colour changes on press rather
/// than the glyph being swapped for another one: the same tool is being held
/// down, not a different tool being shown.
class ComposerTool extends StatelessWidget {
  /// Builds the tool over [onPressed].
  const ComposerTool({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  /// What the tool does, on hover.
  final String tooltip;

  /// The glyph that names the tool.
  final IconData icon;

  /// Null when the tool cannot be used — there is nobody to send to.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: WeChat.composerIconBox,
        height: WeChat.composerIconBox,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: WeChat.composerIconSize),
          // The framework's own IconButton padding is 8 on every side and
          // its minimum size is 40 — together they squash a 22pt glyph down
          // to 12pt inside a 28pt box. The glyph is what the reference
          // measures, so it is given the whole box and the padding is
          // nothing at all.
          padding: EdgeInsets.zero,
          // No splash and no ink: a ripple under a line-drawn tool draws a
          // filled disc that the glyph then sits on top of, which is not what
          // pressing a tool in WeChat looks like.
          splashRadius: WeChat.composerIconSize,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          // The pressed colour is the whole of the pressed state, so the
          // button itself draws nothing.
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(
              Size(WeChat.composerIconBox, WeChat.composerIconBox),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return colors.disabledText;
              }
              if (states.contains(WidgetState.pressed)) {
                return colors.composerIconActive;
              }
              return colors.composerIcon;
            }),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(WeChat.controlRadius),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

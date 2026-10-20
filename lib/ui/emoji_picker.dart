import 'package:flutter/material.dart';

import '../core/core.dart';
import 'l10n/generated/app_localizations.dart';
import 'wechat/theme.dart';

/// The button that opens the emoticon picker, and the picker it opens.
///
/// The picker appears above the composer as a floating panel, the way WeChat's
/// desktop client does instead of taking over the bottom half of the window.
/// It is anchored to the button that opened it, so the eye that found the 表情
/// glyph lands on the faces nearest to it.
///
/// Picking a face puts it **into the composer**, it does not send it. A face
/// is a character the user chose, and it goes out with whatever else is in
/// the box, when 发送 is pressed — the same way a face typed with the keyboard
/// goes out. Sending it on the tap would have made the face a message of its
/// own, which is a different thing: a person who picks a face and then wants
/// to write a word next to it would have to send twice.
class EmojiPickerButton extends StatelessWidget {
  /// Builds the button over [onPick].
  const EmojiPickerButton({
    super.key,
    required this.onPick,
    this.enabled = true,
    this.recent = const [],
  });

  /// Called with the face the user chose.
  final ValueChanged<String> onPick;

  /// False when there is no peer to send to; the button is then inert, the
  /// same way the file button is.
  final bool enabled;

  /// The faces to draw first, newest first.
  final List<String> recent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return Tooltip(
      message: l10n.menuSendEmoji,
      child: SizedBox(
        width: WeChat.composerControl,
        height: WeChat.composerControl,
        child: OutlinedButton(
          onPressed: enabled ? () => _open(context) : null,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.hovered)
                  ? colors.listHover
                  : Colors.transparent;
            }),
            foregroundColor: WidgetStatePropertyAll(colors.bubbleText),
            side: WidgetStateProperty.resolveWith((states) {
              return BorderSide(
                color: states.contains(WidgetState.hovered)
                    ? colors.disabledText
                    : colors.borderStrong,
              );
            }),
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(WeChat.controlRadius),
                ),
              ),
            ),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: const WidgetStatePropertyAll(
              Size(WeChat.composerControl, WeChat.composerControl),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('☺', style: TextStyle(fontSize: 16)),
        ),
      ),
    );
  }

  /// Where the whole panel lives while it is open.
  void _open(BuildContext context) {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final button = context.findRenderObject();
    if (button is! RenderBox) return;
    final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
    // A composer button sits at the bottom of the window, so a panel that
    // opens below it usually has to be clamped back up — and clamping is a
    // panel half off its anchoring. Prefer opening *above* the button when
    // there is room; the menu's own clamping still catches the corner cases.
    final above = origin.dy >= EmojiPanel.estimatedHeight;
    final anchor = Rect.fromLTWH(
      origin.dx,
      above
          ? origin.dy - EmojiPanel.estimatedHeight
          : origin.dy + button.size.height,
      button.size.width,
      button.size.height,
    );
    showMenu<void>(
      context: context,
      // The button's rect in overlay coordinates, which is where the panel is
      // anchored. Anchoring to the button (rather than a corner of the window)
      // is what keeps the panel on whichever side of the warp the button is
      // on, and `showMenu` still clamps it into the window.
      position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
      items: [_EmojiPanelEntry(recent: recent, onPick: onPick)],
    );
  }
}

/// The popup entry that holds the picker's body.
///
/// It is an entry of its own rather than a [PopupMenuItem] because of what
/// that widget does with a panel. A menu item is a *choice*, so it is drawn
/// as one: the entry's own text goes to the label colour, and — when the item
/// is disabled — the whole of it is dimmed, text and icons alike. The way to
/// put a panel in a menu is to make the item disabled, since an enabled item
/// pops the menu the moment it is tapped, and a panel is not a choice.
///
/// That left the faces behind a veil: the panel's own text took the disabled
/// colour and the icons lost 38% of their opacity, so the panel read as a
/// sheet of frosted glass laid over the faces rather than as the faces
/// themselves.
///
/// Drawing the panel here instead draws it as a panel — no disabled state, no
/// menu-item padding, no tint — and the entry is not a choice, so it does not
/// close the menu when the panel is tapped. The panel closes itself, by
/// popping the route, once a face has been picked.
class _EmojiPanelEntry extends PopupMenuEntry<void> {
  const _EmojiPanelEntry({required this.recent, required this.onPick});

  /// The faces to draw first, newest first.
  final List<String> recent;

  /// Called with the face the user chose.
  final ValueChanged<String> onPick;

  @override
  double get height => double.infinity;

  @override
  bool represents(void value) => false;

  @override
  State<_EmojiPanelEntry> createState() => _EmojiPanelEntryState();
}

/// The state of the picker's popup entry.
class _EmojiPanelEntryState extends State<_EmojiPanelEntry> {
  @override
  Widget build(BuildContext context) {
    return EmojiPanel(recent: widget.recent, onPick: widget.onPick);
  }
}

/// The picker's body: a Recent row and the full grid.
class EmojiPanel extends StatelessWidget {
  /// How tall the panel is, for choosing which side of the button it opens on.
  ///
  /// Approximate on purpose: `showMenu` clamps the result into the window
  /// anyway, so this only decides *which* side is tried first. A number that
  /// is off by a row flips the preference for a corner case, never loses a
  /// panel off-screen.
  static const double estimatedHeight = 360;

  /// Builds the panel over [recent] and [onPick].
  const EmojiPanel({super.key, required this.recent, required this.onPick});

  /// The faces to draw first, newest first.
  final List<String> recent;

  /// Called with the face the user chose.
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    final grid = Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        for (final entry in emojiTable)
          _EmojiTile(
            emoji: entry.emoji,
            name: entry.name,
            onTap: () => _choose(context, entry.emoji),
          ),
      ],
    );
    return Container(
      width: 8 * WeChat.emojiTileSide + 7 * 2,
      padding: const EdgeInsets.all(10),
      // The panel draws its own surface. The popup it lives in has one too,
      // but a menu entry is a menu *item* and the framework draws those with
      // the menu's own padding and colour; giving the panel a surface of its
      // own is what makes the faces sit on a clean sheet rather than on a
      // tinted item that reads as a layer over them.
      color: colors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EmojiSectionTitle(text: l10n.emojiRecent),
          const SizedBox(height: 6),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '—',
                style: TextStyle(
                  fontSize: WeChat.fontSizeMeta,
                  color: colors.disabledText,
                ),
              ),
            )
          else
            Wrap(
              spacing: 2,
              runSpacing: 2,
              children: [
                for (final face in recent)
                  _EmojiTile(emoji: face, onTap: () => _choose(context, face)),
              ],
            ),
          const SizedBox(height: 10),
          _EmojiSectionTitle(text: l10n.kindEmoji),
          const SizedBox(height: 6),
          Flexible(child: SingleChildScrollView(child: grid)),
        ],
      ),
    );
  }

  /// Pops the menu from [panelContext] and hands [face] to the caller.
  void _choose(BuildContext panelContext, String face) {
    // The panel is a descendant of the menu route, so popping with its own
    // context closes the menu; the composer's context would dismiss the
    // conversation underneath instead.
    Navigator.of(panelContext).pop();
    onPick(face);
  }
}

/// One selectable face in the panel.
class _EmojiTile extends StatelessWidget {
  const _EmojiTile({required this.emoji, required this.onTap, this.name});

  final String emoji;
  final VoidCallback onTap;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    final face = Text(
      emoji,
      style: TextStyle(fontSize: WeChat.emojiTileFontSize),
    );
    return Tooltip(
      message: name ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        hoverColor: colors.listHover,
        child: SizedBox(
          width: WeChat.emojiTileSide,
          height: WeChat.emojiTileSide,
          child: Center(child: face),
        ),
      ),
    );
  }
}

/// A section heading inside the panel.
class _EmojiSectionTitle extends StatelessWidget {
  const _EmojiSectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: WeChat.fontSizeMeta,
        fontWeight: FontWeight.w600,
        color: colors.secondaryText,
      ),
    );
  }
}

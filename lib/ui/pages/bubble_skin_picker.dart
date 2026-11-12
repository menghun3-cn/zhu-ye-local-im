import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../l10n/generated/app_localizations.dart';
import '../pickers.dart';
import '../wechat/bubble.dart';
import '../wechat/bubble_paint.dart';
import '../wechat/bubble_skin_presets.dart';
import '../wechat/theme.dart';

/// The localized name of a preset, by its stable [BubbleSkinPreset.id].
String bubbleSkinPresetName(AppLocalizations l10n, String id) => switch (id) {
  'bamboo' => l10n.bubbleSkinPresetBamboo,
  'aurora' => l10n.bubbleSkinPresetAurora,
  'sakura' => l10n.bubbleSkinPresetSakura,
  'honey' => l10n.bubbleSkinPresetHoney,
  'meadow' => l10n.bubbleSkinPresetMeadow,
  'dusk' => l10n.bubbleSkinPresetDusk,
  'mint' => l10n.bubbleSkinPresetMint,
  'duskPhoto' => l10n.bubbleSkinPresetDuskPhoto,
  'ocean' => l10n.bubbleSkinPresetOcean,
  'graphite' => l10n.bubbleSkinPresetGraphite,
  'apricot' => l10n.bubbleSkinPresetApricot,
  'lilac' => l10n.bubbleSkinPresetLilac,
  _ => id,
};

/// What a stored skin is called on the settings row.
///
/// A preset gets its name; anything else — a custom gradient, a picture the
/// user chose — is 「自定义」, because the row's job is recognition, not
/// description.
String bubbleSkinLabel(AppLocalizations l10n, BubbleSkin? skin) {
  if (skin == null) return l10n.bubbleSkinCurrentDefault;
  for (final preset in [...gradientSkinPresets, ...imageSkinPresets]) {
    if (preset.skin == skin) return bubbleSkinPresetName(l10n, preset.id);
  }
  return l10n.bubbleSkinCustomLabel;
}

/// Picks the bubble skin for one side of the conversation.
///
/// Opened from the Settings surface's 「消息气泡」 rows, once for the
/// outgoing side and once for the incoming one — the two are independent,
/// which is why [outgoing] is a constructor argument rather than something
/// the dialog works out: it decides both which profile slot is read and
/// which one is written when 「完成」 is pressed.
///
/// Selections are a *draft* until 完成: a gradient being edited colour by
/// colour should not repaint every bubble in the conversation on each
/// slider tick. The preview bubble at the top is where the draft is seen
/// working before it is kept.
class BubbleSkinPicker extends StatefulWidget {
  /// The picker for [outgoing]'s side — true for the bubbles this Device
  /// sends, false for the ones it receives.
  const BubbleSkinPicker({
    super.key,
    required this.outgoing,
    required this.controller,
  });

  /// Which side of the conversation this picker styles.
  final bool outgoing;

  /// The controller the choice is saved through.
  final LocalTransferController controller;

  @override
  State<BubbleSkinPicker> createState() => _BubbleSkinPickerState();
}

class _BubbleSkinPickerState extends State<BubbleSkinPicker> {
  /// The skin currently being tried out, or null for the theme's colours.
  late BubbleSkin? _draft;

  /// The picture the user just picked, waiting for its confirm card — the
  /// picker path, not yet copied into the app's directory.
  String? _pickedImage;

  /// What the confirm card's ink and scrim choices currently are.
  BubbleSkinInk _imageInk = BubbleSkinInk.dark;
  double _imageScrim = BubbleSkin.defaultScrim;

  /// Whether the picked file was refused for its format, so the card can
  /// say why instead of silently doing nothing.
  bool _badFormat = false;

  /// Whether the last import attempt failed — the copy into the app's
  /// directory is the one step that can.
  bool _importFailed = false;

  /// The custom gradient being edited, or null while the section is closed.
  _CustomGradient? _custom;

  @override
  void initState() {
    super.initState();
    _draft = widget.outgoing
        ? widget.controller.outgoingBubbleSkin
        : widget.controller.incomingBubbleSkin;
  }

  /// Applies [_draft] and closes.
  Future<void> _done() async {
    await widget.controller.setBubbleSkin(
      outgoing: widget.outgoing,
      skin: _draft,
    );
    if (mounted) Navigator.of(context).pop();
  }

  /// Offers the platform's file dialog for a skin picture.
  ///
  /// One dialog for everything, as everywhere else in the app: what the
  /// answer *means* is decided here — first file only, and only if its
  /// extension is one a bubble can wear.
  Future<void> _choosePicture() async {
    final files = await PickerResolution.picker.files();
    if (files.isEmpty || !mounted) return;
    final path = files.first.path;
    var tooLarge = false;
    if (looksLikeBubbleSkinImage(path)) {
      try {
        tooLarge = await File(path).length() > bubbleSkinMaxImageBytes;
      } on Object {
        tooLarge = true;
      }
    }
    if (!mounted) return;
    if (!looksLikeBubbleSkinImage(path) || tooLarge) {
      setState(() {
        _pickedImage = null;
        _badFormat = true;
        _importFailed = false;
      });
      return;
    }
    setState(() {
      _pickedImage = path;
      _badFormat = false;
      _importFailed = false;
      _imageInk = BubbleSkinInk.dark;
      _imageScrim = BubbleSkin.defaultScrim;
    });
  }

  /// Copies the picked picture into the app's directory and makes it the
  /// draft. The copy — not the picker path — is what the profile stores,
  /// which is the whole reason [LocalTransferController.importBubbleSkinImage]
  /// exists.
  Future<void> _usePickedImage() async {
    final path = _pickedImage;
    if (path == null) return;
    final stored = await widget.controller.importBubbleSkinImage(path);
    if (!mounted) return;
    if (stored == null) {
      setState(() => _importFailed = true);
      return;
    }
    setState(() {
      _draft = ImageBubbleSkin(
        source: BubbleSkinImageSource.file,
        name: stored,
        scrim: _imageScrim,
        ink: _imageInk,
      );
      _pickedImage = null;
      _importFailed = false;
    });
  }

  /// The paint the preview bubble is drawn with — the draft resolved exactly
  /// as a real bubble on this side would be.
  BubblePaint get _previewPaint {
    final colors = WeChatColors.of(context);
    return bubblePaintFor(
      colors: colors,
      outgoing: widget.outgoing,
      skin: _draft,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return AlertDialog(
      title: Text(l10n.bubbleSkinPickerTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PreviewBubble(paint: _previewPaint, outgoing: widget.outgoing),
              const SizedBox(height: 16),
              _sectionLabel(l10n.bubbleSkinSectionDefault),
              _DefaultTile(
                selected: _draft == null,
                onTap: () => setState(() => _draft = null),
              ),
              const SizedBox(height: 8),
              _sectionLabel(l10n.bubbleSkinSectionGradients),
              _PresetGrid(
                presets: gradientSkinPresets,
                draft: _draft,
                outgoing: widget.outgoing,
                onPick: (skin) => setState(() => _draft = skin),
              ),
              _CustomGradientTile(
                custom: _custom,
                draft: _draft,
                onChanged: (custom, skin) => setState(() {
                  _custom = custom;
                  if (skin != null) _draft = skin;
                }),
              ),
              const SizedBox(height: 8),
              _sectionLabel(l10n.bubbleSkinSectionPictures),
              _PresetGrid(
                presets: imageSkinPresets,
                draft: _draft,
                outgoing: widget.outgoing,
                onPick: (skin) => setState(() => _draft = skin),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => unawaited(_choosePicture()),
                icon: const Icon(Icons.image_outlined, size: 18),
                label: Text(l10n.bubbleSkinChoosePicture),
              ),
              if (_badFormat)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.bubbleSkinBadFormat,
                    style: TextStyle(
                      fontSize: WeChat.fontSizeMeta,
                      color: colors.danger,
                    ),
                  ),
                ),
              if (_pickedImage != null)
                _PickedImageCard(
                  path: _pickedImage!,
                  ink: _imageInk,
                  scrim: _imageScrim,
                  importFailed: _importFailed,
                  onInk: (ink) => setState(() => _imageInk = ink),
                  onScrim: (scrim) => setState(() => _imageScrim = scrim),
                  onUse: () => unawaited(_usePickedImage()),
                  onCancel: () => setState(() {
                    _pickedImage = null;
                    _importFailed = false;
                  }),
                ),
              const SizedBox(height: 12),
              _InkToggle(
                ink: _draft?.ink ?? BubbleSkinInk.dark,
                enabled: _draft != null,
                onChanged: (ink) =>
                    setState(() => _draft = _draft?.withInk(ink)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => unawaited(_done()),
          child: Text(l10n.bubbleSkinDone),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: WeChat.fontSizePreview,
        color: WeChatColors.of(context).secondaryText,
      ),
    ),
  );
}

/// The sample bubble at the top of the picker: the draft drawn exactly as a
/// real message on this side would be — same paint resolution, same side.
class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({required this.paint, required this.outgoing});

  final BubblePaint paint;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: WeChatColors.of(context).conversationBackground,
        borderRadius: BorderRadius.circular(WeChat.bubbleRadius),
      ),
      child: Align(
        alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: MessageBubbleShape(
          paint: paint,
          outgoing: outgoing,
          child: Text(
            l10n.bubbleSkinSampleMessage,
            style: TextStyle(
              fontSize: WeChat.fontSizeBody,
              height: WeChat.lineHeightBody,
              color: paint.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// The 「默认」 row: back to the theme's own colours.
class _DefaultTile extends StatelessWidget {
  const _DefaultTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WeChat.controlRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(WeChat.controlRadius),
          border: Border.all(
            color: selected ? colors.brandStrong : colors.divider,
          ),
        ),
        child: Row(
          children: [
            // The theme's own incoming fill as the swatch: 「默认」 means
            // "whatever the theme would have drawn", which on this side is
            // one specific colour, not a pattern.
            Container(
              width: 40,
              height: 28,
              decoration: BoxDecoration(
                color: colors.bubbleIn,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.divider),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.bubbleSkinSectionDefault)),
            if (selected)
              Icon(Icons.check, size: 18, color: colors.brandStrong),
          ],
        ),
      ),
    );
  }
}

/// A wrapping grid of preset thumbnails; tapping one makes it the draft.
class _PresetGrid extends StatelessWidget {
  const _PresetGrid({
    required this.presets,
    required this.draft,
    required this.outgoing,
    required this.onPick,
  });

  final List<BubbleSkinPreset> presets;
  final BubbleSkin? draft;
  final bool outgoing;
  final ValueChanged<BubbleSkin> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in presets)
          _PresetTile(
            preset: preset,
            selected: draft == preset.skin,
            outgoing: outgoing,
            borderColor: colors.divider,
            onTap: () => onPick(preset.skin),
          ),
      ],
    );
  }
}

/// One preset: its thumbnail, its name underneath, a check when chosen.
class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.selected,
    required this.outgoing,
    required this.borderColor,
    required this.onTap,
  });

  final BubbleSkinPreset preset;
  final bool selected;
  final bool outgoing;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    final paint = bubblePaintFor(
      colors: colors,
      outgoing: outgoing,
      skin: preset.skin,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WeChat.controlRadius),
      child: Container(
        width: 76,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(WeChat.controlRadius),
          border: Border.all(
            color: selected ? colors.brandStrong : borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 44,
                width: double.infinity,
                decoration: paint.decoration.copyWith(
                  borderRadius: BorderRadius.circular(6),
                ),
                // The scrim a picture skin carries is part of its look, so
                // the thumbnail shows it too — a thumbnail that skipped it
                // would advertise a brighter bubble than the one delivered.
                foregroundDecoration: paint.scrim == null
                    ? null
                    : BoxDecoration(
                        color: paint.scrim,
                        borderRadius: BorderRadius.circular(6),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              bubbleSkinPresetName(l10n, preset.id),
              style: const TextStyle(fontSize: WeChat.fontSizeMeta),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// The 「自定义渐变」 row: closed it is one line, open it is the editor.
///
/// [onChanged] reports the editor's new state — null custom when the row is
/// tapped shut, in which case [GradientBubbleSkin] is null too and the
/// draft is left alone: closing the editor is not un-choosing the gradient
/// it produced. While open, every edit reports both the mutable editor
/// state and the immutable skin it currently describes, so the picker's
/// draft and the editor's colours can never disagree.
class _CustomGradientTile extends StatelessWidget {
  const _CustomGradientTile({
    required this.custom,
    required this.draft,
    required this.onChanged,
  });

  /// The editor's state, or null while it is closed.
  final _CustomGradient? custom;

  /// The picker's current draft, used to tell whether the custom gradient is
  /// the chosen skin and to seed the editor when it opens.
  final BubbleSkin? draft;

  /// Reports `(editor, skin)`: editor null closes the section, skin null
  /// leaves the draft untouched.
  final void Function(_CustomGradient? custom, GradientBubbleSkin? skin)
  onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    final open = custom != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            if (open) {
              onChanged(null, null);
              return;
            }
            // Opening is a choice: the editor seeds from the draft when it
            // already is a custom gradient, and its skin becomes the draft
            // straight away — a gradient the user opened the editor for is
            // a gradient they are trying.
            final editor = _CustomGradient()..seedFrom(draft);
            onChanged(editor, editor.skin());
          },
          borderRadius: BorderRadius.circular(WeChat.controlRadius),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WeChat.controlRadius),
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: colors.secondaryText,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.bubbleSkinCustomGradient)),
                if (!open && _isCustomGradient(draft))
                  Icon(Icons.check, size: 16, color: colors.brandStrong),
              ],
            ),
          ),
        ),
        if (open)
          _CustomGradientEditor(
            custom: custom!,
            onChanged: (editor, skin) => onChanged(editor, skin),
          ),
      ],
    );
  }

  /// Whether [skin] is a gradient that is not one of the bundled presets —
  /// the only kind the custom row's check mark belongs to.
  bool _isCustomGradient(BubbleSkin? skin) =>
      skin is GradientBubbleSkin &&
      !gradientSkinPresets.any((preset) => preset.skin == skin);
}

/// The mutable state of the custom-gradient editor.
///
/// Mutable rather than immutable because it is edited a colour at a time;
/// the [GradientBubbleSkin] it produces is the immutable value that gets
/// stored. [seedFrom] starts it from whatever the draft already is, so
/// reopening the editor does not lose the gradient being edited.
class _CustomGradient {
  /// Two starting colours — the minimum a gradient can have.
  final List<Color> colors = [const Color(0xFF8FD3F4), const Color(0xFFF4B8D0)];

  BubbleGradientDirection direction = BubbleGradientDirection.horizontal;
  BubbleSkinInk ink = BubbleSkinInk.dark;

  /// Starts the editor from [skin] when it is a non-preset gradient, so the
  /// editor reopens on what was being edited rather than on the defaults.
  void seedFrom(BubbleSkin? skin) {
    if (skin is! GradientBubbleSkin ||
        gradientSkinPresets.any((preset) => preset.skin == skin)) {
      return;
    }
    colors
      ..clear()
      ..addAll([for (final color in skin.colors) Color(color)]);
    direction = skin.direction;
    ink = skin.ink;
  }

  /// The immutable skin the editor currently describes.
  GradientBubbleSkin skin() => GradientBubbleSkin(
    colors: [for (final color in colors) color.toARGB32()],
    direction: direction,
    ink: ink,
  );
}

/// The open custom-gradient editor: colour swatches, direction, and the
/// add/remove controls a two-to-four-colour gradient needs.
class _CustomGradientEditor extends StatelessWidget {
  const _CustomGradientEditor({required this.custom, required this.onChanged});

  final _CustomGradient custom;
  final void Function(_CustomGradient custom, GradientBubbleSkin skin)
  onChanged;

  void _emit() => onChanged(custom, custom.skin());

  Future<void> _pickColour(BuildContext context, int index) async {
    final picked = await _colourDialog(context, custom.colors[index]);
    if (picked == null) return;
    custom.colors[index] = picked;
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(WeChat.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < custom.colors.length; i++)
                _ColourSwatch(
                  color: custom.colors[i],
                  removable: custom.colors.length > 2,
                  onTap: () => unawaited(_pickColour(context, i)),
                  onRemove: () {
                    custom.colors.removeAt(i);
                    _emit();
                  },
                ),
              if (custom.colors.length < 4)
                IconButton(
                  tooltip: l10n.bubbleSkinAddColour,
                  onPressed: () {
                    // A new stop starts as a blend of its neighbours rather
                    // than a random colour: the gradient stays pleasant
                    // while the user decides what it should become.
                    final at = custom.colors.length ~/ 2;
                    custom.colors.insert(
                      at,
                      Color.lerp(
                            custom.colors[at - 1],
                            custom.colors[at],
                            0.5,
                          ) ??
                          custom.colors[at],
                    );
                    _emit();
                  },
                  icon: const Icon(Icons.add, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<BubbleGradientDirection>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: BubbleGradientDirection.horizontal,
                label: Text(l10n.bubbleSkinDirectionHorizontal),
              ),
              ButtonSegment(
                value: BubbleGradientDirection.vertical,
                label: Text(l10n.bubbleSkinDirectionVertical),
              ),
              ButtonSegment(
                value: BubbleGradientDirection.diagonal,
                label: Text(l10n.bubbleSkinDirectionDiagonal),
              ),
            ],
            selected: {custom.direction},
            onSelectionChanged: (selection) {
              custom.direction = selection.first;
              _emit();
            },
          ),
        ],
      ),
    );
  }
}

/// One editable colour stop: the colour, a remove badge when there are more
/// than two, and a tap that opens the colour picker.
class _ColourSwatch extends StatelessWidget {
  const _ColourSwatch({
    required this.color,
    required this.removable,
    required this.onTap,
    required this.onRemove,
  });

  final Color color;
  final bool removable;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: WeChatColors.of(context).divider),
            ),
          ),
        ),
        if (removable)
          Positioned(
            top: -4,
            right: -4,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(10),
              child: Tooltip(
                message: l10n.bubbleSkinRemoveColour,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: WeChatColors.of(context).surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: WeChatColors.of(context).divider),
                  ),
                  child: const Icon(Icons.close, size: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The picked picture's confirm card: preview, the image rules, ink and
/// scrim choices, and the button that actually adopts it.
class _PickedImageCard extends StatelessWidget {
  const _PickedImageCard({
    required this.path,
    required this.ink,
    required this.scrim,
    required this.importFailed,
    required this.onInk,
    required this.onScrim,
    required this.onUse,
    required this.onCancel,
  });

  /// The picker path being confirmed — not yet the app's copy.
  final String path;
  final BubbleSkinInk ink;
  final double scrim;
  final bool importFailed;
  final ValueChanged<BubbleSkinInk> onInk;
  final ValueChanged<double> onScrim;
  final VoidCallback onUse;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = WeChatColors.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(WeChat.controlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(WeChat.imageRadius),
            child: Image.file(
              File(path),
              height: 96,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Container(
                height: 96,
                color: colors.surface,
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: colors.secondaryText,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.bubbleSkinImageRules,
            style: TextStyle(
              fontSize: WeChat.fontSizeMeta,
              height: 1.5,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          _InkToggle(ink: ink, enabled: true, onChanged: onInk),
          const SizedBox(height: 8),
          _ScrimToggle(scrim: scrim, onChanged: onScrim),
          if (importFailed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.bubbleSkinImportFailed,
                style: TextStyle(
                  fontSize: WeChat.fontSizeMeta,
                  color: colors.danger,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onCancel, child: Text(l10n.cancel)),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onUse,
                child: Text(l10n.bubbleSkinUseThis),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The 深色文字 / 浅色文字 choice, shared by the draft row and the picture
/// card. Disabled while there is no skin for it to apply to.
class _InkToggle extends StatelessWidget {
  const _InkToggle({
    required this.ink,
    required this.enabled,
    required this.onChanged,
  });

  final BubbleSkinInk ink;
  final bool enabled;
  final ValueChanged<BubbleSkinInk> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedButton<BubbleSkinInk>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: BubbleSkinInk.dark,
          label: Text(l10n.bubbleSkinInkDark),
        ),
        ButtonSegment(
          value: BubbleSkinInk.light,
          label: Text(l10n.bubbleSkinInkLight),
        ),
      ],
      selected: {ink},
      onSelectionChanged: enabled
          ? (selection) => onChanged(selection.first)
          : null,
    );
  }
}

/// The 不压暗 / 轻度 / 重度 scrim choice for a picked picture.
class _ScrimToggle extends StatelessWidget {
  const _ScrimToggle({required this.scrim, required this.onChanged});

  final double scrim;
  final ValueChanged<double> onChanged;

  /// The three stops the segmented control offers, mapped to scrim values.
  static const _stops = [0.0, BubbleSkin.defaultScrim, BubbleSkin.maxScrim];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = [
      l10n.bubbleSkinScrimNone,
      l10n.bubbleSkinScrimLight,
      l10n.bubbleSkinScrimHeavy,
    ];
    return SegmentedButton<double>(
      showSelectedIcon: false,
      segments: [
        for (var i = 0; i < _stops.length; i++)
          ButtonSegment(value: _stops[i], label: Text(labels[i])),
      ],
      selected: {_nearest(scrim)},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }

  double _nearest(double scrim) {
    var best = _stops.first;
    for (final stop in _stops) {
      if ((stop - scrim).abs() < (best - scrim).abs()) best = stop;
    }
    return best;
  }
}

/// Asks for a colour and answers it, or null on cancel.
///
/// [flutter_colorpicker]'s `ColorPicker` reports every drag tick through
/// `onColorChanged`; the dialog keeps the latest in a [StatefulBuilder] and
/// only hands it back when 「选择」 is pressed, so cancelling leaves the
/// swatch untouched.
Future<Color?> _colourDialog(BuildContext context, Color current) {
  var picked = current;
  final l10n = AppLocalizations.of(context);
  return showDialog<Color>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(l10n.bubbleSkinCustomGradient),
        content: SizedBox(
          width: 320,
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (color) => setState(() => picked = color),
            enableAlpha: false,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(picked),
            child: Text(l10n.bubbleSkinUseThis),
          ),
        ],
      ),
    ),
  );
}

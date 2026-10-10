import 'dart:io';

import 'package:flutter/material.dart';

import 'theme.dart';

/// An image message: a thumbnail on its own, full size when clicked.
///
/// **Not drawn inside a bubble.** WeChat puts a picture into a conversation as
/// a picture — a rounded thumbnail with no fill behind it and no tail — and a
/// picture wrapped in a green rectangle reads as a file that happens to have a
/// preview rather than as a picture that was sent. The conversation skips
/// `MessageBubbleShape` for this widget and nothing else; see `MessageBubble`.
///
/// The bytes are read from disk rather than held in memory. A conversation is a
/// list that is rebuilt on every progress tick of every live Transfer, so an
/// image cached in a widget field would be re-decoded many times a second while
/// something else is transferring; resolving through [FileImage] keeps the
/// decode in Flutter's own cache, keyed on the file's path and the display's
/// pixel ratio.
///
/// The thumbnail keeps the picture's own shape. Its size is read once from the
/// decoded image and the box is then made that shape, bounded by
/// [WeChat.imageMaxSide] on both sides — a wide screenshot comes out wide and
/// short, a portrait photograph tall and narrow, and neither is cut down to a
/// square. A fixed square with `BoxFit.cover` would show the middle of every
/// picture and nothing else, which is a preview of the picture's centre rather
/// than of the picture.
///
/// A picture that cannot be read — deleted between the message arriving and the
/// user scrolling to it, or a format the platform's decoder does not know —
/// falls back to its name rather than to an exception. A chat history is not a
/// place where one bad file should take the screen down.
class ImageBubble extends StatefulWidget {
  /// Draws the image at [path].
  const ImageBubble({
    super.key,
    required this.path,
    required this.name,
    this.onOpen,
  });

  /// Where the bytes are.
  final String path;

  /// What to call it when it cannot be shown.
  final String name;

  /// Opens the full-size view. Null when there is nothing to open into.
  final VoidCallback? onOpen;

  @override
  State<ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<ImageBubble> {
  /// What is drawn between the message appearing and the picture being ready.
  ///
  /// Roughly a landscape photograph's shape, so that the common case grows only
  /// a little when the real size arrives. The alternative — a zero-sized box —
  /// makes the message collapse and spring back, which reads as a glitch rather
  /// than as loading.
  static const Size _placeholder = Size(
    WeChat.imageMaxSide,
    WeChat.imageMaxSide * 0.66,
  );

  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// The thumbnail's size once the picture has been decoded, else null.
  Size? _thumbnail;

  /// Whether the picture could not be read at all.
  bool _unreadable = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // In `didChangeDependencies` rather than `initState`: the pixel ratio the
    // decode is keyed on comes from the [ImageConfiguration], which is only
    // available once the widget is in a tree.
    _follow(widget.path);
  }

  @override
  void didUpdateWidget(ImageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _follow(widget.path);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  /// Stops following the picture currently being resolved.
  void _detach() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
    _stream = null;
  }

  /// Starts following the picture at [path], if it is not already following it.
  void _follow(String path) {
    final stream = FileImage(File(path))
        .resolve(createLocalImageConfiguration(context));
    // The same provider resolves to the same stream, and re-adding a listener
    // to it would be pointless work on every dependency change.
    if (stream.key == _stream?.key) return;
    _detach();
    _stream = stream;
    _thumbnail = null;
    _unreadable = false;
    _listener = ImageStreamListener(_onImage, onError: (_, _) => _onError());
    stream.addListener(_listener!);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    if (!mounted) return;
    final size = Size(
      info.image.width / info.scale,
      info.image.height / info.scale,
    );
    final thumbnail = _fitWithin(size);
    // A cached picture is handed over *during* `addListener`, which is to say
    // during `didChangeDependencies` — a phase where `setState` is an error.
    // There is a build immediately after, so writing the field is enough.
    if (synchronousCall) {
      _thumbnail = thumbnail;
      _unreadable = false;
      return;
    }
    if (_thumbnail == thumbnail && !_unreadable) return;
    setState(() {
      _thumbnail = thumbnail;
      _unreadable = false;
    });
  }

  void _onError() {
    if (!mounted || _unreadable) return;
    setState(() => _unreadable = true);
  }

  /// [size] scaled down to fit [WeChat.imageMaxSide] on both sides — never up.
  ///
  /// A small picture stays small: blowing a 32-pixel icon up to 200 would be a
  /// preview of the decoder's guesswork rather than of the file.
  static Size _fitWithin(Size size) {
    const bound = WeChat.imageMaxSide;
    if (size.width <= 0 || size.height <= 0) return _placeholder;
    final fit = (size.width <= bound && size.height <= bound)
        ? 1.0
        : (bound / size.width < bound / size.height
              ? bound / size.width
              : bound / size.height);
    return Size(size.width * fit, size.height * fit);
  }

  @override
  Widget build(BuildContext context) {
    final picture = ClipRRect(
      borderRadius: BorderRadius.circular(WeChat.imageRadius),
      child: _picture(),
    );
    // Nothing to open into when the picture could not be read, so the bubble is
    // not made to look clickable either.
    final open = widget.onOpen;
    if (open == null || _unreadable) return picture;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: open, child: picture),
    );
  }

  Widget _picture() {
    if (_unreadable) return _unreadableBox();
    final thumbnail = _thumbnail;
    if (thumbnail == null) return _placeholderBox();
    return SizedBox(
      width: thumbnail.width,
      height: thumbnail.height,
      // `cover` against a box of exactly this shape crops nothing; it only
      // rules out the hairline the layout would otherwise leave when rounding
      // the fitted size to a whole number of pixels.
      child: Image(
        image: FileImage(File(widget.path)),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _unreadableBox(),
      ),
    );
  }

  /// What is drawn while the picture is being read.
  ///
  /// [WeChatColors.pageBackground] rather than [WeChatColors.surface], because
  /// there is no longer a bubble around this box: a thumbnail stands on the
  /// conversation's own panel, and a box in that panel's colour would be an
  /// invisible one. The page colour is what the rest of the interface uses for
  /// "a surface below the panel", so a hole waiting to be filled by a picture
  /// reads as one — on either page.
  Widget _placeholderBox() {
    return Container(
      width: _placeholder.width,
      height: _placeholder.height,
      color: WeChatColors.of(context).pageBackground,
    );
  }

  /// What an image that cannot be decoded shows instead.
  ///
  /// Grey for the same reason as [_placeholderBox]: it has to stand out
  /// against the conversation behind it, and there is no fill there to read a
  /// white box as a hole in.
  Widget _unreadableBox() {
    return Container(
      width: WeChat.imageMaxSide,
      height: WeChat.imageMaxSide,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      color: WeChatColors.of(context).pageBackground,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: WeChatColors.of(context).secondaryText,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            widget.name,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: TextStyle(
              fontSize: WeChat.fontSizeMeta,
              color: WeChatColors.of(context).secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows [path] full size over the conversation.
///
/// A dialog rather than a route: the conversation behind it is the context the
/// picture is being read in, and a push would take that away for a look that is
/// meant to be a glance.
Future<void> showImagePreview(
  BuildContext context, {
  required String path,
  required String name,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => GestureDetector(
      // Anywhere outside the picture closes it, which is what a lightbox does
      // on every desktop platform.
      onTap: () => Navigator.of(context).pop(),
      child: Semantics(
        label: name,
        image: true,
        child: Center(
          child: InteractiveViewer(
            maxScale: 8,
            child: Image.file(
              File(path),
              errorBuilder: (_, _, _) =>
                  Text(name, style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ),
    ),
  );
}

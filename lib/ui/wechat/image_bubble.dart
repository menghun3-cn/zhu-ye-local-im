import 'dart:io';

import 'package:flutter/material.dart';

import 'theme.dart';

/// An image message: a thumbnail in the bubble, full size when clicked.
///
/// The bytes are read from disk rather than held in memory. A conversation is a
/// list that is rebuilt on every progress tick of every live Transfer, so an
/// image cached in a widget field would be re-decoded many times a second while
/// something else is transferring; [Image.file] decodes once and keeps its own
/// cache keyed on the file's path, mtime and size.
///
/// A picture that cannot be read — deleted between the message arriving and the
/// user scrolling to it, or a format the platform's decoder does not know —
/// falls back to its name rather than to an exception. A chat history is not a
/// place where one bad file should take the screen down.
class ImageBubble extends StatelessWidget {
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

  /// The largest a thumbnail is allowed to be, on either side.
  ///
  /// A square bound rather than a width: a portrait photograph at a fixed
  /// width would be a column of pixels taller than the window, and WeChat
  /// bounds both sides for exactly that reason.
  static const double _maxSide = 200;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(WeChat.bubbleRadius),
      child: Image.file(
        File(path),
        width: _maxSide,
        fit: BoxFit.cover,
        // Bounded on both sides: without a height the layout has to resolve
        // through the decode, which makes a tall image push the conversation
        // around as it loads.
        height: _maxSide,
        errorBuilder: (_, _, _) => _unreadable(),
      ),
    );
    if (onOpen == null) return image;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onOpen, child: image),
    );
  }

  /// What an image that cannot be decoded shows instead.
  Widget _unreadable() {
    return Container(
      width: _maxSide,
      height: _maxSide,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      color: WeChat.pageBackground,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: WeChat.secondaryText,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: const TextStyle(
              fontSize: WeChat.fontSizeMeta,
              color: WeChat.secondaryText,
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

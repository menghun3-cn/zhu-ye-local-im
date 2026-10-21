import 'dart:async';

import 'package:flutter/material.dart';

import 'wechat/theme.dart';

/// A message that drops in at the **top** of the window and fades away.
///
/// The opposite of a [SnackBar], which rises from the bottom. The reason is
/// positional: a [SnackBar] appears where the input area is, so a message
/// about a message that could not be sent would land on top of the thing the
/// user is looking at. A toast at the top is out of the way of the
/// conversation and of the keyboard.
///
/// It is drawn over the app rather than inside it: an [Overlay] entry, so it
/// floats above whatever surface it is shown over — a dialog, a pushed
/// conversation, the shell's pane.
class TopToast {
  /// Shows [message] at the top of the window for [duration].
  ///
  /// The [context] is read for its overlay **now**, not later: the caller
  /// usually has something to await first, and the widget that asked for the
  /// toast may be gone by the time it is ready to show it. That is why the
  /// overlay is taken here and passed on rather than looked up at the far end.
  ///
  /// Returns once the toast is on screen — not once it has gone. The toast
  /// removes itself when its time is up.
  static Future<void> show(
    BuildContext context,
    String message, {
    Duration duration = WeChat.toastDuration,
  }) async {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    await showIn(overlay, message, duration: duration);
  }

  /// Shows [message] over [overlay], for [duration].
  ///
  /// The overload for a caller that already holds the overlay — see [show] for
  /// why that is worth having.
  static Future<void> showIn(
    OverlayState overlay,
    String message, {
    Duration duration = WeChat.toastDuration,
  }) async {
    // Only one toast at a time: two of them would land on the same pixels,
    // and the second would hide the first rather than follow it.
    _current?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _TopToast(
        message: message,
        duration: duration,
        onDone: () {
          if (entry.mounted) entry.remove();
          if (identical(_current, entry)) _current = null;
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  /// The toast that is on screen, if any.
  static OverlayEntry? _current;
}

/// The toast's own body: a dark bar with the message on it.
class _TopToast extends StatefulWidget {
  const _TopToast({
    required this.message,
    required this.duration,
    required this.onDone,
  });

  final String message;

  /// How long the toast stays up before it leaves.
  final Duration duration;

  /// Called when the toast has finished leaving.
  final VoidCallback onDone;

  @override
  State<_TopToast> createState() => _TopToastState();
}

/// The state of the toast, which owns its entrance and its exit.
class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 140),
  );

  /// The toast's own clock, so that it leaves on time and is cancelled with
  /// the widget rather than outliving it.
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(widget.duration, _leave);
  }

  @override
  void dispose() {
    _timer.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Fades the toast out and then takes it off the screen.
  Future<void> _leave() async {
    await _controller.reverse();
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return Positioned(
      top: WeChat.toastTopMargin,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _controller,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, -0.4),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: _controller, curve: Curves.easeOut),
                  ),
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: WeChat.toastMaxWidth,
                ),
                margin: const EdgeInsets.symmetric(
                  horizontal: WeChat.toastHPadding,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: WeChat.toastHPadding,
                  vertical: WeChat.toastVPadding,
                ),
                decoration: BoxDecoration(
                  // The inverse surface: a toast is the one thing on screen
                  // that is *about* the interface rather than part of it, so
                  // it is drawn against the page rather than on it.
                  color: colors.inverseSurface,
                  borderRadius: BorderRadius.circular(WeChat.controlRadius),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: WeChat.toastFontSize,
                    color: colors.onInverseSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

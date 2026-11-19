import 'package:flutter/material.dart';

import 'wechat/theme.dart';

/// The small pieces the surfaces share.
///
/// Three widgets rather than a design system: a titled divider, a label/value
/// line, and a quiet line where a list would be. They exist because several
/// pages need them and that many copies would drift.
///
/// They read their colours from [WeChatColors] rather than from the
/// `ColorScheme`, even though the scheme carries the same values: a widget that
/// says `WeChatColors.of(context).secondaryText` states which grey it means,
/// *and* takes the one the running theme actually chose, which a colour read
/// off the scheme by role would leave to Material's judgement.

/// The header shown above a sub-page, with a back button.
///
/// Shared by the My page's card sub-pages and the Transfers page's share
/// sub-view: both are "a surface inside a surface" and owe the same way out.
class SubPageHeader extends StatelessWidget {
  /// Titles a sub-page and offers the way back to its parent.
  const SubPageHeader({super.key, required this.title, required this.onBack});

  /// The sub-page's name.
  final String title;

  /// Returns to the parent surface.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.pageBackground,
        border: Border(bottom: BorderSide(color: colors.divider, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
            tooltip: 'Back',
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.bubbleText,
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled divider between the groups of a page, with an optional action.
class SectionHeader extends StatelessWidget {
  /// Titles a group of content.
  const SectionHeader({super.key, required this.title, this.trailing});

  /// The group's name.
  final String title;

  /// An action belonging to the group, shown at its end.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    final trailing = this.trailing;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              // The quiet grey heading the desktop client puts above a group.
              // Deliberately not `titleSmall`: that slot is the *content*
              // title, and a section heading and a file's name are two
              // different ranks that must not share one size.
              style: TextStyle(
                fontSize: WeChat.fontSizePreview,
                color: colors.secondaryText,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One line of a fact list: a label, and a value that can be selected.
class FactLine extends StatelessWidget {
  /// Shows [value] under [label].
  const FactLine(this.label, this.value, {super.key});

  /// What the value is.
  final String label;

  /// The value, in the user's own hands — a Fingerprint is meant to be copied.
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: WeChat.fontSizePreview,
                color: WeChatColors.of(context).secondaryText,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

/// A quiet line where a list would be.
class HintText extends StatelessWidget {
  /// Shows [message].
  const HintText(this.message, {super.key});

  /// What to say about the empty space.
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = WeChatColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        style: TextStyle(
          fontSize: WeChat.fontSizePreview,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}

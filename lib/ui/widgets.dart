import 'package:flutter/material.dart';

/// The small pieces the four surfaces share.
///
/// Three widgets rather than a design system: a titled divider, a label/value
/// line, and a quiet line where a list would be. They exist because all four
/// pages need them and four copies would drift.

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
    final trailing = this.trailing;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

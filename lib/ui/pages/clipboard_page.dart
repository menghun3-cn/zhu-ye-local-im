import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../core/core.dart';
import '../controller_scope.dart';
import '../feedback.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../widgets.dart';

/// How the clipboard is treated, and what is waiting in it.
class ClipboardPage extends StatefulWidget {
  /// Builds the Clipboard surface.
  const ClipboardPage({super.key});

  @override
  State<ClipboardPage> createState() => _ClipboardPageState();
}

class _ClipboardPageState extends State<ClipboardPage> {
  /// Entries that reached this Device's system clipboard since the page was
  /// built, newest first.
  ///
  /// Held here rather than in the controller: the controller reports what it
  /// applied, and only a screen cares about the last twenty of them. Bounded
  /// because it is a history scroll-back, not a log.
  final List<ClipboardEntry> _applied = [];
  StreamSubscription<ClipboardEntry>? _appliedWatch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in initState: an inherited widget cannot be looked
    // up before the first didChangeDependencies, and this page outlives every
    // rebuild the scope above it does.
    _appliedWatch ??= ControllerScope.of(context).applied.listen(_remember);
  }

  @override
  void dispose() {
    unawaited(_appliedWatch?.cancel());
    super.dispose();
  }

  void _remember(ClipboardEntry entry) {
    setState(() {
      _applied.insert(0, entry);
      if (_applied.length > 20) _applied.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    final capability = controller.self.capability;
    final staged = controller.stagedEntries;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionHeader(title: l10n.clipboardSyncHeader),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<ClipboardMode>(
                  segments: [
                    for (final mode in ClipboardMode.values)
                      ButtonSegment<ClipboardMode>(
                        value: mode,
                        label: Text(labelForClipboardMode(mode, l10n)),
                        // A mode this platform cannot honour is shown and
                        // disabled rather than hidden: "why can I not mirror"
                        // is answered by the mode being visible and grey.
                        enabled: _isUsable(mode, capability),
                      ),
                  ],
                  selected: {controller.clipboardMode},
                  onSelectionChanged: (selection) =>
                      controller.setClipboardMode(selection.first),
                ),
                const SizedBox(height: 12),
                Text(describeClipboardMode(controller.clipboardMode, l10n)),
                const SizedBox(height: 8),
                Text(
                  _capabilityNote(capability, l10n),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        if (!controller.isPaired) ...[
          const SizedBox(height: 12),
          HintText(l10n.clipboardNeedsGroup),
        ],
        const SizedBox(height: 20),
        SectionHeader(title: l10n.clipboardWaitingHeader),
        if (staged.isEmpty)
          HintText(l10n.clipboardNothingStaged)
        else
          for (final entry in staged)
            _EntryCard(entry: entry, controller: controller),
        const SizedBox(height: 20),
        SectionHeader(title: l10n.clipboardAppliedHeader),
        if (_applied.isEmpty)
          HintText(l10n.clipboardNothingApplied)
        else
          for (final entry in _applied)
            _EntryCard(entry: entry, controller: null),
      ],
    );
  }

  /// Whether a mode can be honoured on this platform.
  static bool _isUsable(ClipboardMode mode, ClipboardCapability capability) =>
      switch (mode) {
        ClipboardMode.off => true,
        // Staging still needs one of the two directions to be possible, or the
        // setting would be a switch that changes nothing.
        ClipboardMode.stage => capability.canApply || capability.canOriginate,
        ClipboardMode.mirror => capability.canApply,
      };

  /// What this platform lets the clipboard do, in a sentence.
  static String _capabilityNote(
    ClipboardCapability capability,
    AppLocalizations l10n,
  ) {
    if (capability.canOriginate && capability.canApply) {
      return l10n.clipboardNoteBoth;
    }
    if (!capability.canOriginate && capability.canApply) {
      return l10n.clipboardNoteApplyOnly;
    }
    if (capability.canOriginate) return l10n.clipboardNoteOriginateOnly;
    return l10n.clipboardNoteNone;
  }
}

/// One clipboard entry, either waiting to be applied or already applied.
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.controller});

  final ClipboardEntry entry;

  /// The controller, when this entry can still be applied; null for one that
  /// has already been applied.
  final LocalTransferController? controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = this.controller;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          controller == null ? Icons.check_circle_outline : Icons.content_paste,
        ),
        title: Text(_preview(entry.text)),
        subtitle: Text(
          l10n.entryFrom(
            entry.origin.short(),
            describeLastSeen(entry.capturedAt, l10n),
          ),
          style: theme.textTheme.bodySmall,
        ),
        isThreeLine: true,
        trailing: controller == null
            ? null
            : FilledButton(
                onPressed: () => unawaited(
                  guarded(context, () => controller.applyStaged(entry)),
                ),
                child: Text(l10n.apply),
              ),
      ),
    );
  }
}

/// The start of an entry's text, which is all a list row can show.
String _preview(String text) {
  final firstLine = text.split('\n').first;
  return firstLine.length <= 120
      ? firstLine
      : '${firstLine.substring(0, 120)}…';
}

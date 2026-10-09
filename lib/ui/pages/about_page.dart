import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../external_links.dart';
import '../l10n/generated/app_localizations.dart';
import '../labels.dart';
import '../update_check.dart';
import '../wechat/theme.dart';
import '../widgets.dart';

/// What this build is, and how to get a newer one.
///
/// A surface of its own rather than a section of Settings: it is the one page
/// whose content is about the *program* rather than about this Device or this
/// network, and it is the only one that ever talks to the outside world.
///
/// Nothing here is asked until the user presses 检查更新. That is the whole
/// reason the button exists rather than the check running on arrival: this
/// application's promise is that it stays inside the local network, and a page
/// that reached out on being opened would break that promise for a fact nobody
/// had asked for yet.
class AboutPage extends StatefulWidget {
  /// Shows what this build is.
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  /// The last answer, or null while none has been asked for.
  UpdateCheck? _answer;

  /// Whether a question is out. The button is inert while it is, because a
  /// second press would only ask the same thing again.
  bool _asking = false;

  Future<void> _check() async {
    setState(() => _asking = true);
    // The checker never throws — every failure is an [UpdateOutcome] — so there
    // is nothing to guard here but the widget's own lifetime.
    final answer = await UpdateResolution.checker.latest();
    if (!mounted) return;
    setState(() {
      _answer = answer;
      _asking = false;
    });
  }

  /// Where a newer build can be fetched, when one has been found.
  String? get _downloadUrl {
    final answer = _answer;
    if (answer == null || answer.outcome != UpdateOutcome.available)
      return null;
    return answer.url ?? updateReleasesPage;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final answer = _answer;
    final url = _downloadUrl;

    return ListView(
      padding: WeChat.pagePadding,
      children: [
        SectionHeader(title: l10n.tabAbout),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(WeChat.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(l10n.appTitle, style: theme.textTheme.titleMedium),
                    const SizedBox(width: 8),
                    Text(
                      l10n.aboutVersion(appVersion),
                      style: const TextStyle(
                        fontSize: WeChat.fontSizeMeta,
                        color: WeChat.secondaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(l10n.aboutDescription),
                const Divider(height: 24),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _asking ? null : () => unawaited(_check()),
                      icon: const Icon(Icons.system_update_alt, size: 18),
                      label: Text(
                        _asking
                            ? l10n.aboutChecking
                            : l10n.aboutCheckForUpdates,
                      ),
                    ),
                    if (url != null)
                      TextButton.icon(
                        onPressed: () => unawaited(openInBrowser(url)),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(l10n.aboutOpenDownload),
                      ),
                  ],
                ),
                if (answer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      describeUpdateCheck(answer, l10n),
                      style: TextStyle(
                        fontSize: WeChat.fontSizePreview,
                        color: answer.outcome == UpdateOutcome.available
                            ? WeChat.brand
                            : WeChat.secondaryText,
                      ),
                    ),
                  ),
                // The address stays on screen even when the browser could not
                // be opened — a machine with no default handler is exactly the
                // machine that has to have somewhere to copy it from.
                if (url != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      url,
                      style: const TextStyle(
                        fontSize: WeChat.fontSizeMeta,
                        color: WeChat.secondaryText,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                HintText(l10n.aboutHowToUpgrade),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

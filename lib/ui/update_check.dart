import 'dart:convert';
import 'dart:io';

import '../app/app_version.dart';

/// Where a newer build is looked for.
///
/// A repository rather than a server of our own: this application ships no
/// backend by design (see the About text it shows), so the one place a release
/// can be published to is the place its source already lives.
const String updateRepository = 'menghun3-cn/zhu-ye-local-im';

/// The page a download link opens on. Kept here beside the API URL so the two
/// cannot be pointed at different repositories.
const String updateReleasesPage =
    'https://github.com/$updateRepository/releases/latest';

/// What a look for a newer build came back with.
///
/// A closed set of names rather than a sentence: turning an outcome into words
/// belongs to the UI, which is the only layer that knows what language the user
/// reads. [unreachable] and [noRelease] are separate because they are different
/// things to tell somebody — "check your network" and "there is nothing to
/// check against yet" — and a single "it failed" would say neither.
enum UpdateOutcome {
  /// The published version is the one running.
  upToDate,

  /// There is something newer to fetch.
  available,

  /// Nothing has been published, so there is nothing to compare against.
  noRelease,

  /// The question could not be asked.
  unreachable,
}

/// The answer to "is there a newer build", as data.
final class UpdateCheck {
  /// The answer [outcome], naming [version] and [url] when it has them.
  const UpdateCheck(this.outcome, {this.version, this.url});

  /// What came back.
  final UpdateOutcome outcome;

  /// The newer version, when [outcome] is [UpdateOutcome.available].
  final String? version;

  /// Where to get it, when [outcome] is [UpdateOutcome.available].
  final String? url;

  /// The answer to a question that could not be asked.
  static const UpdateCheck unreachable = UpdateCheck(UpdateOutcome.unreachable);
}

/// Asks whether a newer build than this one has been published.
///
/// An interface because the only real implementation talks to the network, and
/// a widget test may not: a test builds an answer and hands it in, which is
/// also the only way to exercise the "there is a newer version" screen honestly.
abstract interface class UpdateChecker {
  /// The published version, compared against [appVersion].
  Future<UpdateCheck> latest();
}

/// Asks GitHub what the latest release is.
///
/// Asked only when the user presses the button — never at startup, and never on
/// a timer. This application's promise is that it does not talk to anything
/// outside the network unless it was asked to, and a build that quietly polled
/// GitHub on launch would break that promise for a convenience nobody asked
/// for.
final class GitHubUpdateChecker implements UpdateChecker {
  /// Asks [repository], giving up after [timeout].
  ///
  /// The timeout is short on purpose: this runs with a person watching a button
  /// they just pressed, and a machine with no route out would otherwise sit
  /// there for the platform's own minute-long default.
  const GitHubUpdateChecker({
    this.repository = updateRepository,
    this.timeout = const Duration(seconds: 8),
  });

  /// The repository to ask, as `owner/name`.
  final String repository;

  /// How long any one step of the request may take.
  final Duration timeout;

  @override
  Future<UpdateCheck> latest() async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(
            Uri.parse(
              'https://api.github.com/repos/$repository/releases/latest',
            ),
          )
          .timeout(timeout);
      // GitHub rejects a request with no User-Agent, and answers a different
      // shape without the versioned Accept header.
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'zhuye-local-transfer');
      final response = await request.close().timeout(timeout);
      // A repository with no releases has no `latest` to answer with, and that
      // is a 404 rather than an empty body.
      if (response.statusCode == HttpStatus.notFound) {
        return const UpdateCheck(UpdateOutcome.noRelease);
      }
      if (response.statusCode != HttpStatus.ok) {
        return UpdateCheck.unreachable;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) return UpdateCheck.unreachable;
      final tag = decoded['tag_name'];
      if (tag is! String || tag.isEmpty) {
        return const UpdateCheck(UpdateOutcome.noRelease);
      }
      if (!isNewerVersion(tag, appVersion)) {
        return const UpdateCheck(UpdateOutcome.upToDate);
      }
      final page = decoded['html_url'];
      return UpdateCheck(
        UpdateOutcome.available,
        version: tag,
        url: page is String && page.isNotEmpty ? page : updateReleasesPage,
      );
    } on Object {
      // Every failure is the same answer to the user: the question did not get
      // through. Which exception it was is a detail of the platform — a
      // timeout, a DNS failure, a proxy refusing the CONNECT — and none of them
      // changes what there is to do about it.
      return UpdateCheck.unreachable;
    } finally {
      client.close(force: true);
    }
  }
}

/// Which checker the About surface uses.
///
/// A single mutable field rather than a parameter threaded down, in the same
/// shape as `PickerResolution`: this is a seam, and it is named like one.
abstract final class UpdateResolution {
  /// The checker in force. Set by a test; never by the application.
  static UpdateChecker checker = const GitHubUpdateChecker();

  /// Restores the real checker. Called from a `tearDown`.
  static void reset() => checker = const GitHubUpdateChecker();
}

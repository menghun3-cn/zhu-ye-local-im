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

/// Where the release API answers.
///
/// A field rather than a constant in the request so that a test can point the
/// checker at a server of its own — the same reason `repository` is one. The
/// two together are the whole of the address, and both default to the real
/// thing.
const String updateApiHost = 'https://api.github.com';

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

/// One file a release carries.
///
/// [digest] is the checksum GitHub publishes for an uploaded asset, spelled
/// `sha256:<hex>`. It is the only one this application can check a download
/// against without fetching a second address: the versioned artifact carries no
/// `.sha256` sidecar of its own — only the fixed-name alias does — so a build
/// that verified against the sidecar would have to fetch the alias and could
/// then not be sure the two came from the same release. Null for an asset
/// uploaded before GitHub published digests, which is a good enough reason not
/// to download it automatically at all.
final class UpdateAsset {
  /// Names the file [name] at [url], [size] bytes long, checked by [digest],
  /// and also served at [apiUrl].
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    this.apiUrl,
    this.digest,
  });

  /// What the release calls it, version and all.
  final String name;

  /// Where it is served from: the address the download button on the release
  /// page itself points at.
  final String url;

  /// The same file at the release API's own address, or null when the answer
  /// did not name one.
  ///
  /// One file, two addresses, because they are two hosts and a network can
  /// reach one and not the other. [url] is on `github.com`; this one is on
  /// `api.github.com` — the host this application has *already* reached in
  /// order to be holding this answer at all. Asking for it with
  /// `Accept: application/octet-stream` returns the bytes rather than a
  /// description of them.
  ///
  /// Which of the two is the blocked one depends on where the machine is: the
  /// development network answers on `api.github.com` and times out on
  /// `github.com`, and a network that filters by name the other way round is
  /// no harder to imagine. So neither is a fallback — both are tried, and the
  /// first that delivers the file is the one that works. See
  /// `update_install.dart`.
  final String? apiUrl;

  /// How many bytes it is, as the release states. Zero when it did not say.
  final int size;

  /// The published checksum, or null when there is none.
  final String? digest;

  /// The checksum as bare lowercase hex, or null when there is none.
  String? get sha256 {
    final published = digest;
    if (published == null) return null;
    const prefix = 'sha256:';
    final hex = published.startsWith(prefix)
        ? published.substring(prefix.length)
        : published;
    return hex.isEmpty ? null : hex.toLowerCase();
  }
}

/// The answer to "is there a newer build", as data.
final class UpdateCheck {
  /// The answer [outcome], naming [version] and [url] when it has them.
  const UpdateCheck(
    this.outcome, {
    this.version,
    this.url,
    this.notes,
    this.assets = const [],
  });

  /// What came back.
  final UpdateOutcome outcome;

  /// The newer version, when [outcome] is [UpdateOutcome.available].
  final String? version;

  /// Where to get it, when [outcome] is [UpdateOutcome.available].
  final String? url;

  /// What the release itself says it changes, when [outcome] is
  /// [UpdateOutcome.available] and the release carried any.
  ///
  /// Markdown, as the release pipeline writes it: the body is the version's own
  /// `CHANGELOG.md` section, so it is a couple of `###` headings over `- …`
  /// items and nothing more exotic. Reading it into something a card can draw
  /// belongs to the card — see `update_notes.dart` — and this class only
  /// carries it, the same way it carries [version] rather than a sentence about
  /// it.
  final String? notes;

  /// Every file the release carries, when [outcome] is
  /// [UpdateOutcome.available]. Empty for the other three.
  final List<UpdateAsset> assets;

  /// The answer to a question that could not be asked.
  static const UpdateCheck unreachable = UpdateCheck(UpdateOutcome.unreachable);
}

/// The release API's answer, read into an [UpdateCheck].
///
/// Split out of [GitHubUpdateChecker] so that the shape of the JSON can be
/// tested without a network. What the checker adds over this is the request;
/// the two were one function only while there was nothing else to do with the
/// body.
///
/// The four outcomes are unchanged, including the one the older versions of
/// this file had: a repository with no releases answers with no `tag_name`, and
/// that is [UpdateOutcome.noRelease] rather than a failure.
UpdateCheck parseRelease(
  Object? decoded, {
  required String currentVersion,
  required String fallbackUrl,
}) {
  if (decoded is! Map<String, Object?>) return UpdateCheck.unreachable;
  final tag = decoded['tag_name'];
  if (tag is! String || tag.isEmpty) {
    return const UpdateCheck(UpdateOutcome.noRelease);
  }
  if (!isNewerVersion(tag, currentVersion)) {
    return const UpdateCheck(UpdateOutcome.upToDate);
  }
  final page = decoded['html_url'];
  final body = decoded['body'];
  return UpdateCheck(
    UpdateOutcome.available,
    version: tag,
    url: page is String && page.isNotEmpty ? page : fallbackUrl,
    // A release published without notes — `--generate-notes` writes some of its
    // own, and somebody filling in the web form may write none — is a release
    // whose changes cannot be shown. Null rather than an empty string, so the
    // card has one thing to ask rather than two.
    notes: body is String && body.trim().isNotEmpty ? body : null,
    assets: parseAssets(decoded['assets']),
  );
}

/// The release's files, as far as they can be read from an answer.
///
/// Anything unreadable is dropped rather than reported: an asset with no name
/// or no address cannot be downloaded, and one missing digest cannot be
/// checked — and both facts are already visible where they matter, which is the
/// decision to install by hand instead. A release whose `assets` is not a list
/// at all yields none, which reads downstream as "this release does not carry
/// the file this copy needs".
List<UpdateAsset> parseAssets(Object? raw) {
  if (raw is! List) return const [];
  final assets = <UpdateAsset>[];
  for (final entry in raw) {
    if (entry is! Map<String, Object?>) continue;
    final name = entry['name'];
    final url = entry['browser_download_url'];
    if (name is! String || name.isEmpty || url is! String || url.isEmpty) {
      continue;
    }
    final size = entry['size'];
    final digest = entry['digest'];
    final apiUrl = entry['url'];
    assets.add(
      UpdateAsset(
        name: name,
        url: url,
        size: size is int && size >= 0 ? size : 0,
        apiUrl: apiUrl is String && apiUrl.isNotEmpty ? apiUrl : null,
        digest: digest is String && digest.isNotEmpty ? digest : null,
      ),
    );
  }
  return assets;
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
/// Asked twice, and never more often: once as the application comes up — see
/// `UpdateNotice`, which is what the rail's update entry reads — and again each
/// time the About surface's button is pressed. Never on a timer, and never from
/// a page being opened. This application's promise is that it does not talk to
/// anything outside the local network unless it was asked to, and the one
/// request it makes on its own is deliberate, happens once per run, carries
/// nothing about this Device, and is named in the About text for exactly that
/// reason. A build that polled GitHub on a schedule, or on every visit to a
/// page, would be breaking that promise quietly instead.
final class GitHubUpdateChecker implements UpdateChecker {
  /// Asks [repository], giving up after [timeout].
  ///
  /// The timeout is short on purpose: this runs with a person watching a button
  /// they just pressed, and a machine with no route out would otherwise sit
  /// there for the platform's own minute-long default.
  const GitHubUpdateChecker({
    this.repository = updateRepository,
    this.apiHost = updateApiHost,
    this.timeout = const Duration(seconds: 8),
  });

  /// The repository to ask, as `owner/name`.
  final String repository;

  /// The host the release API answers on. A test points this at a server of its
  /// own; nothing in the application ever changes it.
  final String apiHost;

  /// How long any one step of the request may take.
  final Duration timeout;

  @override
  Future<UpdateCheck> latest() async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('$apiHost/repos/$repository/releases/latest'))
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
      return parseRelease(
        jsonDecode(body),
        currentVersion: appVersion,
        fallbackUrl: updateReleasesPage,
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

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'update_check.dart';

/// Fetching a newer build and putting it where this one is.
///
/// Two shapes, because the two ways this application is distributed differ in
/// who is allowed to touch the files. A copy that was *installed* is owned by
/// its installer: the honest upgrade is to run the new installer quietly and
/// let it replace, repair and relaunch — it also keeps the uninstall entry's
/// version true, which replacing the files by hand would leave behind. A copy
/// that was *unpacked* has no installer and nobody to ask, so it replaces
/// itself.
///
/// ## Why replacing itself needs a second process
///
/// Windows will not let a running program overwrite its own executable, and a
/// Flutter build is not one file: `local_transfer.exe`, `flutter_windows.dll`
/// and `data\app.so` are all open while the process runs, and the platform
/// holds them until it ends. So the copy that does the replacing cannot be the
/// copy being replaced. It also cannot be a shell script or an encoder of one —
/// this application ships no interpreter and would rather not start one.
///
/// What it is instead is the build that was just downloaded. It is unpacked
/// into a folder of its own, started with [applyUpdateFlag] and the two paths
/// it needs, and it waits — see [dropStagedTree] — for the old one to go. That
/// it is *newer* than the process it replaces is the point rather than a
/// coincidence: the code that finishes an update is the code that was written
/// most recently, so a fix to this machinery reaches the machines that need it
/// with the update that carries it.

/// The file an installed copy has and an unpacked one does not.
///
/// A fact about this repository's packaging rather than about Windows, and one
/// worth keeping on this side: `packaging/local_transfer.iss` is what copies it
/// in, `scripts/pack-windows-portable.ps1` is what does not. The alternative
/// would be reading the uninstall registry key through the native side, which
/// is more machinery for a question a file already answers.
const String installedCopyMarker = '安装说明.txt';

/// What a file is called while a hand-over puts it in place.
///
/// Every byte of the new build is written under this suffix first and renamed
/// into position afterwards, so that the folder between the two phases still
/// holds the build that is there now — see [dropStagedTree].
const String droppedInSuffix = '.ltnew';

/// Where a hand-over that did not finish says why.
const String handoverReportName = '.update-failed.txt';

/// The flag that turns a start into the last step of an update.
///
/// Read by `windows/runner/main.cpp` before the single-instance check, and
/// spelled there exactly as it is here: a build finishing an update is not a
/// second copy of this application — the copy it is replacing is still running,
/// and handing the work to it would be handing it to the process that is on its
/// way out.
const String applyUpdateFlag = '--apply-update';

/// The flag naming the folder a hand-over takes the new build from.
const String stagedArgument = '--staged';

/// The flag naming the folder a hand-over puts it in.
const String targetArgument = '--target';

/// How many times a rename waits for the build that is being replaced to go.
const int _renameAttempts = 40;

/// How long it waits in between.
const Duration _renameInterval = Duration(milliseconds: 250);

/// How long a download may sit without receiving anything.
const Duration _idleTimeout = Duration(seconds: 30);

/// How long any one step of a request may take.
const Duration _requestTimeout = Duration(seconds: 15);

/// The executable, as every packaging step here spells it.
const String _executableName = 'local_transfer.exe';

/// Which of a release's files a copy of this shape needs.
enum UpdatePayload {
  /// The zip an unpacked copy replaces itself from.
  portablePackage,

  /// The installer an installed copy hands the job to.
  installer,
}

/// What the release calls the file [payload] needs, tagged [tag].
///
/// Built rather than matched by suffix on purpose, even though both shapes end
/// in a suffix of their own: the release also carries a fixed-name alias of this
/// very file, whose name ends in exactly the same suffix, and picking by suffix
/// would make "which of the two" depend on the order the API listed them in.
String updateAssetName({required String tag, required UpdatePayload payload}) {
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  return switch (payload) {
    UpdatePayload.portablePackage =>
      'LocalTransfer-$version-windows-x64-portable.zip',
    UpdatePayload.installer => 'LocalTransfer-$version-windows-x64-setup.exe',
  };
}

/// The file [check] names for [payload], or null when it does not carry it.
UpdateAsset? updateAssetFor(UpdateCheck check, UpdatePayload payload) {
  final tag = check.version;
  if (tag == null) return null;
  final wanted = updateAssetName(tag: tag, payload: payload);
  for (final asset in check.assets) {
    if (asset.name == wanted) return asset;
  }
  return null;
}

/// How far an update has got.
enum UpdateInstallStage {
  /// Nothing is in flight.
  idle,

  /// The new build is on its way down.
  downloading,

  /// What arrived is being checked against what the release published.
  verifying,

  /// The package is being unpacked for the copy that will put it in place.
  staging,

  /// The new build has been started and is waiting to take over.
  handingOver,

  /// It did not work, and an [UpdateInstallFailure] says how.
  failed,
}

/// Why an update did not happen, as a name.
///
/// A closed set rather than a sentence for the same reason [UpdateOutcome] is
/// one: turning an outcome into words belongs to the layer that knows what
/// language the user reads.
enum UpdateInstallFailure {
  /// This platform cannot replace itself.
  unsupported,

  /// The release does not carry the file this shape of copy needs.
  noAsset,

  /// The release does not publish a checksum for it.
  noDigest,

  /// The folder holding this copy cannot be written to.
  notWritable,

  /// The download did not arrive.
  download,

  /// What arrived is not what the release published.
  checksum,

  /// The package arrived but could not be unpacked.
  unpack,

  /// A hand-over was started and never finished.
  handover,
}

/// How far along a download is.
final class UpdateInstallProgress {
  /// Reports [stage], with the bytes counted so far when it is a download.
  const UpdateInstallProgress(this.stage, {this.received = 0, this.total = 0});

  /// What is happening.
  final UpdateInstallStage stage;

  /// Bytes received so far.
  final int received;

  /// Bytes expected, or zero when the answer did not say.
  final int total;

  /// How much of the download is down, or null when the length is unknown.
  double? get fraction {
    if (total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }
}

/// What an attempt to install an update ended as.
final class UpdateInstallResult {
  /// The hand-over was started and this process is about to end.
  const UpdateInstallResult.handedOver() : failure = null;

  /// It did not happen, and [failure] says why.
  const UpdateInstallResult.failed(UpdateInstallFailure this.failure);

  /// Why it did not happen, or null when it did.
  final UpdateInstallFailure? failure;

  /// Whether a newer build is on its way in.
  bool get handedOver => failure == null;
}

/// Replacing this build with the one a release names.
///
/// An interface because the real thing replaces the application that is running
/// and then ends it, which is not something a test may do to the machine it runs
/// on: a test hands in an answer and keeps its files.
abstract interface class UpdateInstaller {
  /// Whether this build can put a newer one in place by itself.
  ///
  /// False on every platform but the one whose packaging this knows, and it is
  /// known before anything is awaited, so a surface can leave the offer out
  /// rather than show a button that always fails.
  bool get supported;

  /// The last hand-over that did not finish, or null when the last one did.
  ///
  /// Consumed by the reading: the report a hand-over leaves says what to tell
  /// the user once, and a line that stayed for ever would be a line about a
  /// failure the user has already dealt with.
  UpdateInstallFailure? previousFailure();

  /// Downloads [check], checks it, and hands over to it.
  ///
  /// [onProgress] is called before each step and while the bytes arrive. This
  /// does not return when the hand-over starts: on success the process it is
  /// running in has to end, because that process is what holds the files being
  /// replaced. The caller therefore sees a return only on failure — or, in a
  /// test, from a stand-in that cannot end anything.
  Future<UpdateInstallResult> install(
    UpdateCheck check, {
    required void Function(UpdateInstallProgress progress) onProgress,
  });
}

/// Replacing this build with the one a release names, on the platform that can.
final class PlatformUpdateInstaller implements UpdateInstaller {
  /// Hands over, and ends the process, through [leave].
  const PlatformUpdateInstaller({this.leave = _leaveProcess});

  /// What happens when a hand-over has started. A test replaces it; nothing in
  /// the application does.
  final void Function() leave;

  @override
  bool get supported => Platform.isWindows;

  @override
  UpdateInstallFailure? previousFailure() => readHandoverReport(
    File(_within(applicationDirectory().path, handoverReportName)),
  );

  @override
  Future<UpdateInstallResult> install(
    UpdateCheck check, {
    required void Function(UpdateInstallProgress progress) onProgress,
  }) async {
    if (!supported) {
      return const UpdateInstallResult.failed(UpdateInstallFailure.unsupported);
    }
    final application = applicationDirectory();
    final installed = File(_within(application.path, installedCopyMarker))
        .existsSync();
    final payload = installed
        ? UpdatePayload.installer
        : UpdatePayload.portablePackage;
    final asset = updateAssetFor(check, payload);
    if (asset == null) {
      return const UpdateInstallResult.failed(UpdateInstallFailure.noAsset);
    }
    final expected = asset.sha256;
    if (expected == null) {
      return const UpdateInstallResult.failed(UpdateInstallFailure.noDigest);
    }
    if (!_isWritable(application)) {
      return const UpdateInstallResult.failed(UpdateInstallFailure.notWritable);
    }

    final stage = newUpdateStage();
    final downloaded = File(_within(stage.path, _fileName(asset.name)));
    onProgress(const UpdateInstallProgress(UpdateInstallStage.downloading));
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    try {
      await _download(
        client,
        Uri.parse(asset.url),
        downloaded,
        asset.size,
        onProgress,
      );
    } on Object {
      return const UpdateInstallResult.failed(UpdateInstallFailure.download);
    } finally {
      client.close(force: true);
    }

    onProgress(const UpdateInstallProgress(UpdateInstallStage.verifying));
    if (!await _matchesDigest(downloaded, expected)) {
      return const UpdateInstallResult.failed(UpdateInstallFailure.checksum);
    }

    if (payload == UpdatePayload.installer) {
      // Inno replaces the files and puts the application back — see the second
      // `[Run]` entry in `packaging/local_transfer.iss`, which runs under
      // `/SILENT` only when `/update` is among the arguments, and that is what
      // this spelling of it is for: a silent install somebody else started
      // should install and nothing more. Whatever the installer does not do,
      // this process must not: its files are open until it ends and it has
      // seconds before the unpacker reaches them.
      await Process.start(downloaded.path, const [
        '/SILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/update',
      ], mode: ProcessStartMode.detached);
      return _handOver(onProgress);
    }

    onProgress(const UpdateInstallProgress(UpdateInstallStage.staging));
    if (!await _unpack(downloaded, stage) || !isAPackage(stage)) {
      return const UpdateInstallResult.failed(UpdateInstallFailure.unpack);
    }

    // The build in the stage folder is the one that can replace this one: every
    // file of this build is open until this process ends, and that one has
    // nothing open in the folder it is about to fill.
    await Process.start(_within(stage.path, _executableName), [
      applyUpdateFlag,
      stagedArgument,
      stage.path,
      targetArgument,
      application.path,
    ], mode: ProcessStartMode.detached);
    return _handOver(onProgress);
  }

  /// Says that a hand-over has started, and ends the process it was started
  /// from.
  Future<UpdateInstallResult> _handOver(
    void Function(UpdateInstallProgress progress) onProgress,
  ) async {
    onProgress(const UpdateInstallProgress(UpdateInstallStage.handingOver));
    // The sentence that says the application is restarting has to be on the
    // screen before the screen goes away, and a frame is not painted in the
    // same turn the state was set in.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    leave();
    return const UpdateInstallResult.handedOver();
  }
}

/// Which installer a surface uses.
///
/// A second resolution class rather than a second field on `UpdateResolution`:
/// the two seams live in two files — asking is in `update_check.dart` and
/// replacing is here — and folding them together would mean one of those files
/// importing the other for no reason but the name.
abstract final class UpdateInstallResolution {
  /// The installer in force. Set by a test; never by the application.
  static UpdateInstaller installer = const PlatformUpdateInstaller();

  /// Restores the real installer. Called from a `tearDown`.
  static void reset() => installer = const PlatformUpdateInstaller();
}

/// The folder this build runs from.
Directory applicationDirectory() => File(Platform.resolvedExecutable).parent;

/// A folder to fetch an update into, besides the one being replaced.
///
/// The system's own temporary directory: it is the one place a program may
/// write without asking, and the folder holding the application may be anywhere
/// at all — including somewhere the user cannot write, which is a question
/// [PlatformUpdateInstaller] asks before it downloads anything.
Directory newUpdateStage() =>
    Directory.systemTemp.createTempSync('local_transfer_update_');

/// Deletes what hand-overs left in the temporary directory.
///
/// A hand-over unpacks a whole build somewhere temporary and then *runs from
/// there*, so the build cannot delete the folder it is running in. The next
/// start of the application is what clears it up, and it only touches folders
/// old enough not to belong to a hand-over still in progress.
void clearStaleUpdateStages({
  Duration olderThan = const Duration(hours: 1),
  DateTime? now,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(olderThan);
  List<FileSystemEntity> entries;
  try {
    entries = Directory.systemTemp.listSync();
  } on Object {
    return;
  }
  for (final entry in entries) {
    if (entry is! Directory) continue;
    if (!_fileName(entry.path).startsWith('local_transfer_update_')) continue;
    try {
      if (entry.statSync().modified.isAfter(cutoff)) continue;
      entry.deleteSync(recursive: true);
    } on Object {
      // Somebody else's, or still busy: leaving it is always an option.
    }
  }
}

/// Reads the report a hand-over leaves, and takes it away.
///
/// Null when there is none, which covers both "the last hand-over finished" and
/// "nothing has ever tried" — the two are the same thing to a surface that only
/// has to decide whether to say something.
UpdateInstallFailure? readHandoverReport(File report) {
  if (!report.existsSync()) return null;
  try {
    report.deleteSync();
  } on Object {
    // Best effort: the sentence is what matters, and it is about to be said.
  }
  return UpdateInstallFailure.handover;
}

/// Writes why a hand-over could not be finished, where the application looks.
void writeHandoverReport(File report, Object error) {
  try {
    report.writeAsStringSync(
      '${DateTime.now().toIso8601String()}$lineSeparator$error$lineSeparator',
      flush: true,
    );
  } on Object {
    // Nowhere to say it. The application will notice the update did not happen
    // by being the version it was.
  }
}

/// Every file under [staged], as paths relative to it.
List<String> stagedFiles(Directory staged) {
  final files = <String>[];
  for (final entity in staged.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = relativePath(root: staged.path, path: entity.path);
    if (relative.isEmpty) continue;
    // A rename that did not happen leaves its `.ltnew` behind, and it is not
    // part of any build.
    if (relative.endsWith(droppedInSuffix)) continue;
    files.add(relative);
  }
  files.sort();
  return files;
}

/// Whether [staged] looks like a build rather than like a download that went
/// wrong somewhere [dropStagedTree] cannot see.
///
/// The check that matters is not that every file arrived — [dropStagedTree]
/// copies what is there — but that what arrived can run: an executable, the
/// Dart code, and the assets it reads.
bool isAPackage(Directory staged) {
  if (!File(_within(staged.path, _executableName)).existsSync()) return false;
  final data = Directory(_within(staged.path, 'data'));
  if (!File(_within(data.path, 'app.so')).existsSync()) return false;
  final assets = Directory(_within(data.path, 'flutter_assets'));
  if (!assets.existsSync()) return false;
  try {
    return assets.listSync().isNotEmpty;
  } on Object {
    return false;
  }
}

/// Puts every file of [staged] into [target].
///
/// In two phases, and that is the whole point of it. While the bytes are still
/// being copied nothing in [target] has been touched — each file lands under
/// [droppedInSuffix] beside the one it will replace — so a failure in the copy
/// phase (a full disk, a folder that turned out not to be writable after all)
/// leaves the build that is running now exactly as it was, and the caller can
/// say so in the same breath. Only the renames that follow can leave the folder
/// holding a mixture, and a rename carries no bytes: it is the shortest window
/// this can be done in without a second directory and a restart in between.
///
/// Renames are retried, because the copy this one is replacing has only just
/// been asked to stop and Windows keeps a program's files open until the
/// process that is running them has gone.
void dropStagedTree({required Directory staged, required Directory target}) {
  final files = stagedFiles(staged);
  final dropped = <String>[];
  try {
    for (final relative in files) {
      final destination = File(_within(target.path, relative));
      destination.parent.createSync(recursive: true);
      final landing = File('${destination.path}$droppedInSuffix');
      File(_within(staged.path, relative)).copySync(landing.path);
      dropped.add(landing.path);
    }
  } on Object {
    for (final path in dropped) {
      try {
        File(path).deleteSync();
      } on Object {
        // Best effort: the point is not to leave litter, not to be perfect.
      }
    }
    rethrow;
  }
  for (final path in dropped) {
    final destination = path.substring(0, path.length - droppedInSuffix.length);
    _renameOver(File(path), destination);
  }
}

/// Renames [file] onto [destination], waiting out the process being replaced.
void _renameOver(File file, String destination) {
  for (var attempt = 0; ; attempt++) {
    try {
      file.renameSync(destination);
      return;
    } on FileSystemException {
      if (attempt >= _renameAttempts) rethrow;
      sleep(_renameInterval);
    }
  }
}

/// What a build that was started to finish an update was told.
final class UpdateHandoff {
  /// Names the two folders a hand-over works between.
  const UpdateHandoff({required this.staged, required this.target});

  /// The folder the new build was unpacked into.
  final String staged;

  /// The folder the application runs from, and the one being replaced.
  final String target;

  /// Reads a hand-over out of a command line, or null for an ordinary start.
  ///
  /// A command line that names the flag but not the folders is still a
  /// hand-over — it is a start with nowhere to put anything — so it comes back
  /// with what it has and lets [putInPlace] refuse it. Reading it as an
  /// ordinary start would be the one answer that cannot be right: the folders
  /// this build is running from are in the middle of being replaced.
  static UpdateHandoff? parse(List<String> arguments) {
    if (!arguments.contains(applyUpdateFlag)) return null;
    return UpdateHandoff(
      staged: _argumentAfter(arguments, stagedArgument) ?? '',
      target: _argumentAfter(arguments, targetArgument) ?? '',
    );
  }

  /// Puts [staged] in place under [target] and answers what to start.
  ///
  /// Throws when either folder is missing, which is the only way a hand-over
  /// can be malformed: the caller is the entry point of a build that was
  /// started with [applyUpdateFlag], and it reports what it caught.
  String putInPlace() {
    if (staged.isEmpty || target.isEmpty) {
      throw ArgumentError('a hand-over needs both folders: $staged, $target');
    }
    final stagedDirectory = Directory(staged);
    if (!stagedDirectory.existsSync()) {
      throw FileSystemException('the new build is not there', staged);
    }
    final targetDirectory = Directory(target);
    if (!targetDirectory.existsSync()) {
      throw FileSystemException('the application is not there', target);
    }
    dropStagedTree(staged: stagedDirectory, target: targetDirectory);
    return _within(targetDirectory.path, _executableName);
  }
}

/// Starts [executable] with no arguments, detached from this process.
void startDetached(String executable) {
  Process.start(executable, const [], mode: ProcessStartMode.detached);
}

/// [path], with [root] taken off the front and `/` as the separator.
String relativePath({required String root, required String path}) {
  var relative = path;
  if (relative.startsWith(root)) relative = relative.substring(root.length);
  relative = relative.replaceAll('\\', '/');
  while (relative.startsWith('/')) {
    relative = relative.substring(1);
  }
  return relative;
}

/// [relative] under [directory], with this platform's separator.
String _within(String directory, String relative) =>
    '$directory${Platform.pathSeparator}'
    '${relative.replaceAll('/', Platform.pathSeparator)}';

/// The last segment of a path, whichever separator the path uses.
String _fileName(String path) {
  final cut = path.replaceAll('\\', '/').lastIndexOf('/');
  return cut < 0 ? path : path.substring(cut + 1);
}

/// The platform's line separator, for the report a hand-over leaves.
const String lineSeparator = '\r\n';

/// The value of [name] on a command line, or null when it is not there.
String? _argumentAfter(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}

/// Whether a file can be created and removed in [directory].
bool _isWritable(Directory directory) {
  final probe = File(
    '${directory.path}${Platform.pathSeparator}.local_transfer_write_check',
  );
  try {
    probe.writeAsStringSync('', flush: true);
    probe.deleteSync();
    return true;
  } on Object {
    return false;
  }
}

/// Whether [file] is [expected] — a lowercase hex sha256 — as a stream.
Future<bool> _matchesDigest(File file, String expected) async {
  try {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == expected;
  } on Object {
    return false;
  }
}

/// Reads [url] into [destination], counting the bytes for [onProgress].
Future<void> _download(
  HttpClient client,
  Uri url,
  File destination,
  int expectedBytes,
  void Function(UpdateInstallProgress progress) onProgress,
) async {
  final request = await client.getUrl(url).timeout(_requestTimeout);
  request.headers.set(HttpHeaders.userAgentHeader, 'zhuye-local-transfer');
  final response = await request.close().timeout(_requestTimeout);
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('HTTP ${response.statusCode}', uri: url);
  }
  final total = response.contentLength > 0
      ? response.contentLength
      : expectedBytes;
  final sink = destination.openWrite();
  var received = 0;
  try {
    await for (final chunk in response.timeout(_idleTimeout)) {
      sink.add(chunk);
      received += chunk.length;
      onProgress(
        UpdateInstallProgress(
          UpdateInstallStage.downloading,
          received: received,
          total: total,
        ),
      );
    }
  } finally {
    await sink.close();
  }
}

/// Unpacks [package] into [into], answering whether it worked.
///
/// `tar` rather than a package of our own: the archive is a zip, Windows has
/// been able to open one from the command line since 1803 — the version this
/// application already requires — and a zip reader in Dart would be a few
/// hundred lines of code to read a file this machine can already read.
Future<bool> _unpack(File package, Directory into) async {
  try {
    final result = await Process.run('tar', [
      '-xf',
      package.path,
      '-C',
      into.path,
    ]);
    return result.exitCode == 0;
  } on Object {
    return false;
  }
}

/// Ends this process, handing the machine to whatever was started.
void _leaveProcess() => exit(0);

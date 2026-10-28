import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../app/app_version.dart';
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
/// it needs, and it waits — see [dropStagedTree] — for the old one to go. The
/// step that finishes the update runs in that newer build, without a window of
/// its own; the updated build is the window the user asked for. That it is
/// *newer* than the process it replaces is the point rather than a
/// coincidence: the code that finishes an update is the code that was written
/// most recently, so a fix to this machinery reaches the machines that need it
/// with the update that carries it.
///
/// ## Where the package is fetched to
///
/// A folder of the application's own, called `update`: not the root of that
/// folder, which holds the build itself — a download sitting beside the
/// executable reads as part of the program — and not the system's temporary
/// directory either, which is the one place a program may write without asking
/// and also the one place a user never looks. The package stays there between
/// attempts, which is what makes a retry after a cancelled one cheap, and the
/// next start of the version it carries takes it away — see
/// [clearFetchedUpdate]. The unpacked build beside it is the transient part,
/// and it lives where transient things live.
///
/// ## Two steps, and a question between them
///
/// Everything that can be done while this build still runs — fetching the
/// package, checking it against the checksum the release published, unpacking
/// it — is one call, [UpdateInstaller.prepare]. What is left ends the process,
/// because the files it replaces are open until it does, and that is a second
/// call, [UpdateInstaller.apply]. Between the two the user is asked: the last
/// thing this build does before its window goes away is close itself on
/// purpose, and a program that did that without a word would be a program that
/// disappeared. See `about_page.dart` for the question.

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

/// What a partially fetched package is called while it fills up.
///
/// The suffix is a second, invisible marker that a file in the update folder
/// is *in flight*: without it, a retry would hand a crashed attempt's
/// half-written file to the digest check. That is safe for the digest's sake,
/// but it costs the ability to resume from the bytes that already arrived.
const String updatePartialSuffix = '.part';

/// How many network steps one address of a download is allowed.
///
/// A step that fails is retried against the same address, resuming from the
/// offset the previous one reached; only after all three does the next address
/// get its own steps.
const int _attemptsPerAddress = 3;

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

  /// The APK an Android copy hands to the system package installer.
  androidPackage,
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
    UpdatePayload.androidPackage => 'LocalTransfer-$version-android.apk',
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

  /// Android is handing the checked APK to the system package installer.
  installing,

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

  /// Android has not been allowed to install apps from this one.
  permission,

  /// Android could not open the system package installer.
  installer,
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

/// A newer build, fetched and checked, waiting for the word that puts it in
/// place.
///
/// What [UpdateInstaller.prepare] answers with and [UpdateInstaller.apply]
/// needs. Everything the second call does is start a process and end this one,
/// so which of the two it starts is decided here rather than worked out again
/// from the same facts a second time.
final class PreparedUpdate {
  /// The installer an installed copy hands the job to, already checked.
  const PreparedUpdate.installer(this.package)
    : payload = UpdatePayload.installer,
      staged = null;

  /// The unpacked build an unpacked copy replaces itself from.
  const PreparedUpdate.portable({required this.package, required this.staged})
    : payload = UpdatePayload.portablePackage;

  /// The checked APK an Android copy hands to the system installer.
  const PreparedUpdate.android(this.package)
    : payload = UpdatePayload.androidPackage,
      staged = null;

  /// Which of the two shapes of copy this is for.
  final UpdatePayload payload;

  /// The file that was fetched and checked, under the update folder.
  final String package;

  /// The folder the new build was unpacked into, or null for an installer —
  /// which is run exactly as it arrived and unpacks nothing.
  final String? staged;
}

/// What an attempt to fetch and stage an update ended as.
final class UpdatePrepareResult {
  /// There is something to put in place, and [prepared] says what.
  const UpdatePrepareResult.ready(PreparedUpdate this.prepared)
    : failure = null;

  /// It did not happen, and [failure] says why.
  const UpdatePrepareResult.failed(UpdateInstallFailure this.failure)
    : prepared = null;

  /// What is waiting to be put in place, or null when nothing is.
  final PreparedUpdate? prepared;

  /// Why nothing is, or null when something is.
  final UpdateInstallFailure? failure;

  /// Whether there is something to put in place.
  bool get isReady => prepared != null;
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

  /// Whether applying an update ends this process and starts it again.
  ///
  /// Windows replaces the running build or hands the job to an installer that
  /// relaunches it. Android opens the system package installer instead, which
  /// may ask for permission and returns here after it has been opened. The
  /// surface uses this to choose between "update and restart" and "install".
  bool get restartsApplication;

  /// The last hand-over that did not finish, or null when the last one did.
  ///
  /// Consumed by the reading: the report a hand-over leaves says what to tell
  /// the user once, and a line that stayed for ever would be a line about a
  /// failure the user has already dealt with.
  UpdateInstallFailure? previousFailure();

  /// Fetches [check] and stages it: everything that can be done while this
  /// build is still running.
  ///
  /// Answers what is ready, or why nothing is. Nothing here ends the process or
  /// touches the folder this build runs from — the package lands in the update
  /// folder and the unpacked build in a folder of its own — so a caller that
  /// stops here leaves the application exactly as it was. That is what a user
  /// answering "not now" to the question in `about_page.dart` amounts to.
  Future<UpdatePrepareResult> prepare(
    UpdateCheck check, {
    required void Function(UpdateInstallProgress progress) onProgress,
  });

  /// Puts what [prepare] readied in place, and ends this process.
  ///
  /// Does not return in the application: the files being replaced are open
  /// until the process holding them ends, so this one has to. What the user
  /// sees after it is the updated application, reopened by the build that was
  /// just started or by the installer's second `[Run]` entry. [onProgress] is
  /// called before the end, which is the last thing the old build gets to say.
  Future<void> apply(
    PreparedUpdate prepared, {
    required void Function(UpdateInstallProgress progress) onProgress,
  });
}

/// How the Android side answered a request to open its package installer.
enum AndroidInstallOutcome {
  /// The app must first be allowed to install unknown apps.
  permission,

  /// The system installer was opened.
  started,
}

/// A failure applying an update that the page can show verbatim.
///
/// The platform side is allowed to throw; turning that into a closed failure
/// belongs here, before the UI has to inspect an exception chain.
final class UpdateInstallException implements Exception {
  /// Reports [failure].
  const UpdateInstallException(this.failure, [this.cause]);

  /// What the user can act on.
  final UpdateInstallFailure failure;

  /// The underlying error, for diagnostics and tests.
  final Object? cause;

  @override
  String toString() => 'UpdateInstallException($failure, $cause)';
}

/// Which platform's packaging [PlatformUpdateInstaller] should follow.
///
/// Separate from `DevicePlatform` so this file can be exercised by `dart test`
/// without importing the Flutter-facing UI layer. [main.dart] maps the real
/// platform onto it.
enum UpdateInstallPlatform { windows, android, other }

/// Replacing this build with the one a release names, on the platform that can.
final class PlatformUpdateInstaller implements UpdateInstaller {
  /// Hands over, and ends the process, through [leave]. Fetches into
  /// [application], which a test points at a folder of its own.
  const PlatformUpdateInstaller({
    this.leave = _leaveProcess,
    this.application,
    this.platform,
    this.androidInstall,
  });

  /// What happens when a hand-over has started. A test replaces it; nothing in
  /// the application does.
  final void Function() leave;

  /// The folder this build runs from, or null for the real one.
  ///
  /// A seam for the same reason `GitHubUpdateChecker.apiHost` is one: the
  /// installer writes into the folder it runs from, and a test that ran the
  /// real thing would be writing into the folder the suite itself runs from.
  final String? application;

  /// What platform this instance follows. Null for the running one.
  final UpdateInstallPlatform? platform;

  /// Opens Android's package installer for the checked APK at a path.
  ///
  /// Supplied by `main.dart` through a Flutter method channel. Kept as a
  /// function rather than imported here so this file stays runnable under
  /// `dart test`, where no Flutter engine exists.
  final Future<AndroidInstallOutcome> Function(String path)? androidInstall;

  /// The folder this build runs from, seam and all.
  String get _root => application ?? applicationDirectory().path;

  UpdateInstallPlatform get _platform =>
      platform ??
      (Platform.isWindows
          ? UpdateInstallPlatform.windows
          : Platform.isAndroid
          ? UpdateInstallPlatform.android
          : UpdateInstallPlatform.other);

  @override
  bool get supported =>
      _platform == UpdateInstallPlatform.windows ||
      _platform == UpdateInstallPlatform.android;

  @override
  bool get restartsApplication => _platform == UpdateInstallPlatform.windows;

  @override
  UpdateInstallFailure? previousFailure() =>
      _platform == UpdateInstallPlatform.windows
      ? readHandoverReport(File(_within(_root, handoverReportName)))
      : null;

  @override
  Future<UpdatePrepareResult> prepare(
    UpdateCheck check, {
    required void Function(UpdateInstallProgress progress) onProgress,
  }) async {
    if (!supported) {
      return const UpdatePrepareResult.failed(UpdateInstallFailure.unsupported);
    }
    if (_platform == UpdateInstallPlatform.android) {
      return _prepareAndroid(check, onProgress: onProgress);
    }
    final installed = File(_within(_root, installedCopyMarker)).existsSync();
    final payload = installed
        ? UpdatePayload.installer
        : UpdatePayload.portablePackage;
    final asset = updateAssetFor(check, payload);
    if (asset == null) {
      return const UpdatePrepareResult.failed(UpdateInstallFailure.noAsset);
    }
    final expected = asset.sha256;
    if (expected == null) {
      return const UpdatePrepareResult.failed(UpdateInstallFailure.noDigest);
    }
    // The hand-over drops its files into the folder being replaced, so that
    // folder has to be writable; and the update folder beside it is where the
    // download lands, which is the same question asked of the same place.
    if (!_isWritable(Directory(_root))) {
      return const UpdatePrepareResult.failed(UpdateInstallFailure.notWritable);
    }
    final Directory update;
    try {
      update = updateDirectory(_root);
    } on Object {
      return const UpdatePrepareResult.failed(UpdateInstallFailure.notWritable);
    }
    final wanted = _fileName(asset.name);
    final downloaded = File(_within(update.path, wanted));
    // One package at a time. A folder holding last week's download beside this
    // one is a folder nobody can read, and a package that was superseded is
    // superseded the moment a newer release was asked about. The partial file
    // is this same package's own in-flight name, so it is kept beside it.
    _keepOnly(update, [wanted, '$wanted$updatePartialSuffix']);

    onProgress(const UpdateInstallProgress(UpdateInstallStage.downloading));
    // The bytes may already be here: an attempt that was cancelled after the
    // download leaves the package in place, and fetching it again would be
    // twenty megabytes for a file that is already the right one.
    if (!await _matchesDigest(downloaded, expected)) {
      try {
        await _download(asset, downloaded, onProgress);
      } on Object {
        _discard(downloaded);
        return const UpdatePrepareResult.failed(UpdateInstallFailure.download);
      }
    }

    onProgress(const UpdateInstallProgress(UpdateInstallStage.verifying));
    if (!await _matchesDigest(downloaded, expected)) {
      // What arrived is not what the release published, and the sentence the
      // user is about to read says it has been thrown away — so it has.
      _discard(downloaded);
      return const UpdatePrepareResult.failed(UpdateInstallFailure.checksum);
    }

    if (payload == UpdatePayload.installer) {
      return UpdatePrepareResult.ready(
        PreparedUpdate.installer(downloaded.path),
      );
    }

    onProgress(const UpdateInstallProgress(UpdateInstallStage.staging));
    final stage = newUpdateStage();
    if (!await _unpack(downloaded, stage) || !isAPackage(stage)) {
      // The package is not what failed — it checked out — so it stays where it
      // is, and a retry starts from it rather than from the network.
      return const UpdatePrepareResult.failed(UpdateInstallFailure.unpack);
    }
    return UpdatePrepareResult.ready(
      PreparedUpdate.portable(package: downloaded.path, staged: stage.path),
    );
  }

  /// Fetches and checks the APK without unpacking it.
  ///
  /// The system package installer reads an APK in place. The private app data
  /// directory is writable without storage permission, and the FileProvider in
  /// the Android runner is the only thing granted access to it.
  Future<UpdatePrepareResult> _prepareAndroid(
    UpdateCheck check, {
    required void Function(UpdateInstallProgress progress) onProgress,
  }) async {
    final asset = updateAssetFor(check, UpdatePayload.androidPackage);
    if (asset == null) {
      return const UpdatePrepareResult.failed(UpdateInstallFailure.noAsset);
    }
    final expected = asset.sha256;
    if (expected == null) {
      return const UpdatePrepareResult.failed(UpdateInstallFailure.noDigest);
    }
    if (!_isWritable(Directory(_root))) {
      return const UpdatePrepareResult.failed(UpdateInstallFailure.notWritable);
    }
    final Directory update;
    try {
      update = updateDirectory(_root);
    } on Object {
      return const UpdatePrepareResult.failed(UpdateInstallFailure.notWritable);
    }
    final wanted = _fileName(asset.name);
    final downloaded = File(_within(update.path, wanted));
    _keepOnly(update, [wanted, '$wanted$updatePartialSuffix']);

    onProgress(const UpdateInstallProgress(UpdateInstallStage.downloading));
    if (!await _matchesDigest(downloaded, expected)) {
      try {
        await _download(asset, downloaded, onProgress);
      } on Object {
        _discard(downloaded);
        return const UpdatePrepareResult.failed(UpdateInstallFailure.download);
      }
    }

    onProgress(const UpdateInstallProgress(UpdateInstallStage.verifying));
    if (!await _matchesDigest(downloaded, expected)) {
      _discard(downloaded);
      return const UpdatePrepareResult.failed(UpdateInstallFailure.checksum);
    }
    return UpdatePrepareResult.ready(PreparedUpdate.android(downloaded.path));
  }

  @override
  Future<void> apply(
    PreparedUpdate prepared, {
    required void Function(UpdateInstallProgress progress) onProgress,
  }) async {
    if (prepared.payload == UpdatePayload.androidPackage) {
      onProgress(const UpdateInstallProgress(UpdateInstallStage.installing));
      final install = androidInstall;
      if (install == null) {
        throw const UpdateInstallException(UpdateInstallFailure.installer);
      }
      try {
        final outcome = await install(prepared.package);
        if (outcome == AndroidInstallOutcome.permission) {
          throw const UpdateInstallException(UpdateInstallFailure.permission);
        }
      } on UpdateInstallException {
        rethrow;
      } on Object catch (error) {
        throw UpdateInstallException(UpdateInstallFailure.installer, error);
      }
      return;
    }
    if (prepared.payload == UpdatePayload.installer) {
      // Inno replaces the files and puts the application back — see the second
      // `[Run]` entry in `packaging/local_transfer.iss`, which runs only when
      // `/update` is among the arguments. `/VERYSILENT` is the whole point of
      // an in-app update: the user has already said yes to the restart, so the
      // installer must not show a window of its own either. Whatever the
      // installer does not do, this process must not: its files are open until
      // it ends and it has seconds before the unpacker reaches them.
      await Process.start(prepared.package, const [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/update',
      ], mode: ProcessStartMode.detached);
    } else {
      // The build in the stage folder is the one that can replace this one:
      // every file of this build is open until this process ends, and that one
      // has nothing open in the folder it is about to fill. A portable payload
      // is only ever readied with a folder to run from, so there is nothing to
      // do without one. The staged build is started detached and finishes the
      // update in place; until this process goes, its files are still open.
      final staged = prepared.staged;
      if (staged == null) return;
      try {
        await Process.start(_within(staged, _executableName), [
          applyUpdateFlag,
          stagedArgument,
          staged,
          targetArgument,
          _root,
        ], mode: ProcessStartMode.detached);
      } on Object catch (error) {
        // Where the old build can still say it: the next start reads this.
        writeHandoverReport(File(_within(_root, handoverReportName)), error);
      }
    }
    await _handOver(onProgress);
  }

  /// Says that a hand-over has started, and ends the process it was started
  /// from. Nothing is drawn in between — the updated build is the window the
  /// user asked for, and a gap would read as a crash only to a user who had
  /// not already answered the question that said the app was about to restart.
  Future<void> _handOver(
    void Function(UpdateInstallProgress progress) onProgress,
  ) async {
    leave();
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

/// What the folder an update is fetched into is called, under the
/// application's own.
///
/// Not the root of that folder, which holds the build itself: a download
/// sitting beside the executable reads as part of the program, and a user who
/// looks for one should not have to tell the two apart. Not the system's
/// temporary directory either, which is the one place a program may write
/// without asking and also the one place a user never looks.
const String updateDirectoryName = 'update';

/// The folder an update is fetched into, under [root].
///
/// Created if it is not there — a first update has nothing to fetch into — and
/// throws when it cannot be, which the caller reads as "this folder cannot be
/// written to": the question of whether it can be created is the writability
/// question the caller has already asked about the folder above it.
Directory updateDirectory(String root) =>
    Directory(_within(root, updateDirectoryName))..createSync(recursive: true);

/// A folder to unpack an update into, besides the one being replaced.
///
/// The system's own temporary directory: the unpacked build is the transient
/// part — it exists to be run once, from a folder of its own, and it is taken
/// away by [clearStaleUpdateStages] — so it belongs where transient things
/// live rather than beside the package that outlives it.
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

/// Takes away the package of an update that has been applied.
///
/// The only trace that says an update happened is the name: the package for the
/// version this build now *is* is the one that was just installed, and it is
/// twenty megabytes of nothing now. A package for any other version is one
/// whose update was cancelled or failed — it stays, because it is what a retry
/// starts from. Called from `main.dart` on an ordinary start, beside
/// [clearStaleUpdateStages].
void clearFetchedUpdate({String? root}) {
  final update = Directory(
    _within(root ?? applicationDirectory().path, updateDirectoryName),
  );
  if (!update.existsSync()) return;
  for (final payload in UpdatePayload.values) {
    final package = File(
      _within(
        update.path,
        updateAssetName(tag: 'v$appVersion', payload: payload),
      ),
    );
    try {
      if (package.existsSync()) package.deleteSync();
    } on Object {
      // Best effort. The version still matches on the next start, so a package
      // that could not be deleted yet is tried for again; and one that outlives
      // its version is taken away by the next update's own housekeeping.
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

  /// Finishes an update from a build that was started with [applyUpdateFlag].
  ///
  /// Replaces the folder on an isolate of its own (a whole application is
  /// copied, and the caller's thread must not freeze while it is), starts the
  /// updated build, and exits when it is on its way. A failure is written
  /// where the application looks on its next start, because there is no window
  /// of this build to report it. Answers the exit code the caller must leave
  /// with: 0 when the updated build is on its way, non-zero otherwise.
  Future<int> run() async {
    try {
      final executable = await Isolate.run(putInPlace);
      // The new process must actually exist before this one goes away: exiting
      // early can leave the update finished but nobody restarted.
      await startDetached(executable);
      return 0;
    } on Object catch (error) {
      writeHandoverReport(
        File('$target${Platform.pathSeparator}$handoverReportName'),
        error,
      );
      return 1;
    }
  }
}

/// Starts [executable] with no arguments, detached from this process.
///
/// The await is the point rather than a nicety: the caller is the replacement
/// build, which hands control back by exiting the instant the new window is on
/// its way. Exiting before [Process.start] has actually created the process
/// would let the old build disappear without the new one ever coming up.
Future<void> startDetached(String executable) async {
  await Process.start(executable, const [], mode: ProcessStartMode.detached);
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

/// Deletes every file in [update] but the ones named [keep].
void _keepOnly(Directory update, List<String> keep) {
  List<FileSystemEntity> entries;
  try {
    entries = update.listSync();
  } on Object {
    return;
  }
  for (final entry in entries) {
    // Folders are not this function's business: what a hand-over unpacks is
    // somewhere else entirely, and anything else a folder might hold is
    // somebody else's.
    if (entry is! File) continue;
    if (keep.contains(_fileName(entry.path))) continue;
    try {
      entry.deleteSync();
    } on Object {
      // Somebody else's, or still busy: leaving it is always an option.
    }
  }
}

/// Takes a fetched file away, best effort.
void _discard(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
    final partial = File(_partialFileOf(file));
    if (partial.existsSync()) partial.deleteSync();
  } on Object {
    // Nothing to be done about it: the sentence the user reads is about the
    // attempt, not about the litter.
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

/// The addresses [asset] can be fetched from, best first.
///
/// Two of them, because the two live on different hosts and a network can reach
/// one and not the other — the release API's own address is on
/// `api.github.com`, which is the host this application has already reached to
/// be asked this question at all, and the address the release page's download
/// button points at is on `github.com`. Measured on the development machine:
/// `api.github.com` answers and `github.com` times out, so a build that only
/// knew the second one could check for an update and never install it. Neither
/// is a fallback in the "unlikely" sense; both are tried, in the order that puts
/// the host already proven reachable first.
///
/// Duplicates are dropped: a release could hand back the same address twice in
/// the two fields, and fetching it twice would only be slower.
List<String> downloadAddresses(UpdateAsset asset) {
  final addresses = <String>[];
  final apiUrl = asset.apiUrl;
  if (apiUrl != null && apiUrl.isNotEmpty) addresses.add(apiUrl);
  if (asset.url.isNotEmpty && !addresses.contains(asset.url)) {
    addresses.add(asset.url);
  }
  return addresses;
}

/// What one network step of a download ended with.
final class _DownloadFailure {
  const _DownloadFailure(this.attempt, this.position);

  /// Which address attempt this was, starting from zero.
  final int attempt;

  /// How many bytes the failed step had already put down.
  final int position;
}

/// The in-flight bytes an interrupted fetch leaves beside [destination].
///
/// Bytes are only ever *the package* once a step that received every one of
/// them renames the file into place ([updatePartialSuffix] comes off then),
/// so a leftover is safe to adopt — and expensive to throw away.
final class _Recovered {
  const _Recovered(this.destination);

  /// The package the bytes are heading for, under the update folder.
  final File destination;
}

/// The leftover a new step starts from, or null when there is none.
///
/// When [destination] is empty and a partial file sits beside it, that partial
/// is the work of an earlier attempt: the current one adopts it for its first
/// step, which is what turns byte-for-byte failure into a cheap resume instead
/// of another whole download. A partial that coexists with a non-empty
/// destination can only be stale — the package it was fetching is the one
/// already named — so it is dropped.
Future<_Recovered?> _recoverPartial(File destination) async {
  final partial = File(_partialFileOf(destination));
  if (!partial.existsSync() || _existingLength(destination) > 0) {
    if (partial.existsSync() && _existingLength(destination) > 0) {
      try {
        partial.deleteSync();
      } on Object {
        // Best effort; the fetch below starts from zero regardless.
      }
    }
    return null;
  }
  return _Recovered(destination);
}

/// Fetches [asset] to [destination], trying each of its addresses.
///
/// Every address is allowed up to [_attemptsPerAddress] network steps, and a
/// step resumes the file where the previous one stopped instead of fetching
/// the whole thing again: when a connection drops a few hundred kilobytes
/// short of the end, the reconnect saves the part that already arrived.
///
/// Resuming is only possible while the server supports ranges; an answer that
/// is a whole-file 200 switches the receiver back to a fresh download at the
/// start. Nothing here decides whether the bytes are right — the digest check
/// after the fetch is the only judge of that.
///
/// Throws when no address delivers the whole file, which is what the caller
/// reports as "the download did not arrive" — an answer that has not changed,
/// and one the user can act on by trying again.
Future<void> _download(
  UpdateAsset asset,
  File destination,
  void Function(UpdateInstallProgress progress) onProgress,
) async {
  final failures = <_DownloadFailure>[];
  for (final address in downloadAddresses(asset)) {
    // A new client per attempt: a connection that failed during its CONNECT
    // leaves the pool of the one that held it in a state worth not reusing, and
    // the second host is a different one anyway.
    for (var attempt = 0; attempt < _attemptsPerAddress; attempt++) {
      final client = HttpClient()..connectionTimeout = _requestTimeout;
      try {
        final recovered = await _recoverPartial(destination);
        // The partial of an earlier attempt is the work this step resumes: it
        // gets the range, and a step that reaches the end renames those very
        // bytes into the package's own name.
        // The partial file of whatever is being fetched: a recovered one from
        // an earlier attempt, or the new one this step is about to open.
        final resumeFrom = _existingLength(
          File(_partialFileOf(recovered?.destination ?? destination)),
        );
        final received = await _fetch(
          client,
          Uri.parse(address),
          destination,
          asset.size,
          resumeFrom: resumeFrom,
          onProgress: onProgress,
        );
        // Short of the bytes the release published is not a download that
        // arrived, and finding that out here is what gives the next step a
        // chance: an interception that answers with a page of its own returns
        // 200 and the whole wrong file, which the checksum below would catch —
        // but only after every address and step had been given up on.
        if (asset.size > 0 && received != asset.size) {
          throw HttpException(
            '$received of ${asset.size} bytes',
            uri: Uri.parse(address),
          );
        }
        // The arrival is complete; the bytes were only ever the package's once
        // they carry its name. A rename is atomic here, so a crash can leave
        // the old package or the new one, never a file that looks whole.
        await File(_partialFileOf(destination)).rename(destination.path);
        return;
      } on Object {
        failures.add(
          _DownloadFailure(
            attempt,
            _existingLength(File(_partialFileOf(destination))),
          ),
        );
        // Re-running the same address after several of these would only be
        // waiting on the same wall; the next address is what is new to try.
        if (attempt + 1 >= _attemptsPerAddress) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      } finally {
        client.close(force: true);
      }
    }
  }
  throw StateError(
    failures.isEmpty ? 'no address to download from' : failures.join('; '),
  );
}

/// How many bytes [file] already holds, or zero when it cannot be read.
int _existingLength(File file) {
  try {
    return file.lengthSync();
  } on Object {
    return 0;
  }
}

/// Reads [url] into a partial file, answering how many bytes arrived.
///
/// [destined] is the package the bytes are heading for; nothing here writes
/// that name. What is written is the bytes under [updatePartialSuffix] from
/// [resumeFrom] on, and [destined] only appears again — with the whole file —
/// when the caller renames the partial into place.
///
/// One step begins at [resumeFrom]: when the partial file already holds bytes,
/// the request asks for them to be skipped ([HttpHeaders.rangeHeader]) and the
/// sink resumes where they end. A server that does not understand ranges
/// answers 200 with the whole file and the receiver falls back to a fresh
/// download at the start — the same guard the partial file of a crashed
/// attempt needs, since its bytes may end anywhere.
Future<int> _fetch(
  HttpClient client,
  Uri url,
  File destined,
  int expectedBytes, {
  required int resumeFrom,
  required void Function(UpdateInstallProgress progress) onProgress,
}) async {
  final request = await client.getUrl(url).timeout(_requestTimeout);
  request.headers.set(HttpHeaders.userAgentHeader, 'zhuye-local-transfer');
  // What turns the API's address from a description of a file into the file
  // itself. The download address ignores it, so one header serves both.
  request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
  final resuming = resumeFrom > 0;
  if (resuming) {
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeFrom-');
  }
  final response = await request.close().timeout(_requestTimeout);
  final resumed = resuming && response.statusCode == HttpStatus.partialContent;
  final whole = response.statusCode == HttpStatus.ok;
  if (!resumed && !whole) {
    throw HttpException('HTTP ${response.statusCode}', uri: url);
  }
  // A 200 to a ranged request means the server does not serve ranges: the
  // bytes it sends start at zero, not at the offset the file already holds.
  final writeFrom = resumed ? resumeFrom : 0;
  final total = response.contentLength > 0
      ? response.contentLength
      : expectedBytes;
  final sink = File(_partialFileOf(destined)).openWrite(mode: FileMode.append);
  var received = writeFrom;
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
  return received;
}

/// The file that is filling up for [file], reached by [updatePartialSuffix].
///
/// One name, this platform's separator, so both the fetch and the takeover
/// agree on where the bytes are.
String _partialFileOf(File file) => '${file.path}$updatePartialSuffix';

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

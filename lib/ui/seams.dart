import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/core.dart';

/// The platform seams, as Flutter provides them.
///
/// `lib/core` and `lib/app` talk to a [ProfileStore], a [MessageStore], a
/// [BeaconTransport] and a [SystemClipboard], and never ask what they are
/// running on. This file is where those four get their real answers, and it is
/// the only place in the application that reaches for the Flutter platform
/// channels.

/// The system clipboard of the running app.
///
/// Flutter's own [Clipboard] is the read and the write. What it does not offer
/// is a change notification, so [changes] polls — see
/// [PollingClipboardWatcher], which holds the whole of that policy and is
/// where its consequences are written down.
final class FlutterSystemClipboard implements SystemClipboard {
  /// Reads and writes through Flutter, watching with [interval] polls.
  FlutterSystemClipboard({this.interval = const Duration(milliseconds: 700)})
    : _watcher = PollingClipboardWatcher(
        // The static rather than the instance method: an initializer cannot
        // reach an instance member, and the read this watcher polls is exactly
        // the read the rest of the app calls.
        read: _readClipboard,
        interval: interval,
      );

  /// How often the clipboard is read to notice a change.
  final Duration interval;

  final PollingClipboardWatcher _watcher;

  static Future<String?> _readClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    // An empty clipboard and a clipboard holding an image are the same thing
    // here: nothing this product can carry. A platform that will not answer —
    // Android without window focus — also arrives as null.
    return (text == null || text.isEmpty) ? null : text;
  }

  @override
  Future<String?> read() => _readClipboard();

  @override
  Future<void> write(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Stream<String> get changes => _watcher.changes;
}

/// Everything the application needs from the platform it runs on.
final class PlatformSeams {
  const PlatformSeams({
    required this.store,
    required this.profilePath,
    required this.messageStore,
    required this.messagePath,
    required this.beacon,
    required this.clipboard,
    required this.platform,
    required this.defaultIncomingDirectory,
  });

  /// Where this Device's identity is kept, or an in-memory stand-in.
  final ProfileStore store;

  /// The file [store] writes to, or null when nothing is persisted.
  final String? profilePath;

  /// Where this Device's conversations are kept, or an in-memory stand-in.
  ///
  /// Separate from [store] rather than folded into it: the two are written at
  /// very different rates, and a conversation that filled the profile file with
  /// itself would be a conversation that could cost a Device its identity.
  final MessageStore messageStore;

  /// The file [messageStore] writes to, or null when nothing is persisted.
  final String? messagePath;

  /// How Discovery sends and receives.
  final BeaconTransport beacon;

  /// The system clipboard.
  final SystemClipboard clipboard;

  /// The platform, as the clipboard model understands it.
  final DevicePlatform platform;

  /// Where a Transfer lands when the user has not said otherwise.
  final String? defaultIncomingDirectory;
}

/// The platform this binary is running on.
///
/// Anything that is neither Windows nor Android is [DevicePlatform.other],
/// which the clipboard model treats as the most restrictive case rather than
/// as something that behaves like a supported platform.
DevicePlatform currentPlatform() {
  if (Platform.isWindows) return DevicePlatform.windows;
  if (Platform.isAndroid) return DevicePlatform.android;
  return DevicePlatform.other;
}

/// The app's own data directory channel.
///
/// The app ships no plugins, so the one platform fact Dart cannot read for
/// itself — Android's private files directory — comes through a channel this
/// project implements in its own [MainActivity]. A platform that has not
/// implemented it throws [MissingPluginException], which is handled as
/// "nowhere to write" rather than as a failure.
const MethodChannel defaultPathsChannel = MethodChannel(
  'cn.hnasct.local_transfer/paths',
);

/// The method [defaultPathsChannel] is asked for.
const String appDataDirectoryMethod = 'appDataDirectory';

/// Brings up the seams the application runs on.
///
/// [beacon] binds the discovery port, so this is where two copies of the app
/// on one host collide: the second one gets a [SocketException] from here, and
/// the caller is expected to show that rather than to swallow it.
///
/// The four optional parameters are test seams, and they exist because this
/// product's platforms cannot otherwise all be exercised from one machine.
/// [platform] and [environment] let a test ask what the Android and Windows
/// rules resolve to without being on Android, or without reading the real
/// `%APPDATA%`; [pathsChannel] lets a test answer the Android directory
/// question with a stand-in for the Kotlin side; [beacon] lets a test hand over
/// an in-memory transport so that what this function decides — which store it
/// picks, and where — can be checked without binding the well-known discovery
/// port, which only one process on a host may hold. Production passes none of
/// them, and then every answer comes from the running host.
Future<PlatformSeams> openPlatformSeams({
  DevicePlatform? platform,
  Map<String, String>? environment,
  MethodChannel pathsChannel = defaultPathsChannel,
  BeaconTransport? beacon,
}) async {
  final running = platform ?? currentPlatform();
  final appDataDirectory = running == DevicePlatform.android
      ? await _readAppDataDirectory(pathsChannel)
      : null;
  final host = environment ?? Platform.environment;
  final path = profileFilePath(
    platform: running,
    environment: host,
    appDataDirectory: appDataDirectory,
  );
  final conversationPath = messageFilePath(
    platform: running,
    environment: host,
    appDataDirectory: appDataDirectory,
  );
  return PlatformSeams(
    // A Device with nowhere to write runs with its identity in memory: it
    // still pairs and transfers, and it has to be paired again after a
    // restart. Saying so beats pretending the file was saved.
    store: path == null ? MemoryProfileStore() : FileProfileStore(path),
    profilePath: path,
    // The same rule for the conversation, resolved from the same directory:
    // nowhere to write means it is kept until the process ends.
    messageStore: conversationPath == null
        ? MemoryMessageStore()
        : FileMessageStore(conversationPath),
    messagePath: conversationPath,
    beacon: beacon ?? await UdpBeaconTransport.bind(),
    clipboard: FlutterSystemClipboard(),
    platform: running,
    defaultIncomingDirectory: defaultIncomingDirectory(
      platform: running,
      environment: host,
      appDataDirectory: appDataDirectory,
    ),
  );
}

/// The private directory this app may write to, when the platform has one and
/// this app can reach it.
///
/// Asked only on Android: asking on Windows would throw a
/// [MissingPluginException] for a fact `%APPDATA%` already states. Both ways of
/// not being answerable — a platform that never registered the channel and one
/// that registered it but failed — mean the same thing here: nowhere durable to
/// write, which the caller turns into an in-memory profile rather than an
/// error.
Future<String?> _readAppDataDirectory(MethodChannel channel) async {
  try {
    return await channel.invokeMethod<String>(appDataDirectoryMethod);
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

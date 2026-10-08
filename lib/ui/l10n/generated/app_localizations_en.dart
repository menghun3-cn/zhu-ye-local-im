// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Local Transfer';

  @override
  String get startupFailureTitle => 'Local Transfer could not start';

  @override
  String get tabDevices => 'Devices';

  @override
  String get tabTransfers => 'Transfers';

  @override
  String get tabClipboard => 'Clipboard';

  @override
  String get tabSettings => 'Settings';

  @override
  String get notPairedYet => 'Not paired with any Device yet';

  @override
  String failureUnreachable(String detail) {
    return 'Could not reach the Device: $detail';
  }

  @override
  String failurePairing(String detail) {
    return 'Pairing failed: $detail';
  }

  @override
  String failureCannotReach(String detail) {
    return 'Could not reach the other Device: $detail. Check that it is running, that both machines are on the same network, and that its firewall allows incoming TCP 47656.';
  }

  @override
  String refusalSessionAlreadyOpen(String peer) {
    return 'A Session with $peer is already open.';
  }

  @override
  String refusalPeerAddressUnknown(String peer) {
    return 'Nothing is known about where $peer is. Wait until this Device has discovered it, then try again.';
  }

  @override
  String get refusalNoAddressGiven => 'No address was given.';

  @override
  String refusalPortNotAPort(String value) {
    return '$value is not a port.';
  }

  @override
  String get refusalOfferAlreadyAnswered =>
      'This offer has already been answered.';

  @override
  String get refusalNoPeerConnected => 'No Device is connected.';

  @override
  String refusalNoSessionOpen(String peer) {
    return 'No Session is open with $peer.';
  }

  @override
  String get refusalSeveralPeersConnected =>
      'More than one Device is connected; name the one to send to.';

  @override
  String get refusalNotPaired =>
      'This Device is not paired, so it accepts no Sessions.';

  @override
  String refusalNoFreeFileName(String name) {
    return 'No free name is left for \"$name\" in that folder.';
  }

  @override
  String get kindText => 'Text';

  @override
  String get kindFiles => 'Files';

  @override
  String get kindClipboard => 'Clipboard';

  @override
  String get stateAwaitingDecision => 'Waiting for an answer';

  @override
  String get stateTransferring => 'Transferring';

  @override
  String get stateVerifying => 'Checking';

  @override
  String get stateCompleted => 'Done';

  @override
  String get stateRejected => 'Refused';

  @override
  String get stateCancelled => 'Cancelled';

  @override
  String get stateFailed => 'Failed';

  @override
  String get clipboardModeOff => 'Off';

  @override
  String get clipboardModeStage => 'Ask me';

  @override
  String get clipboardModeMirror => 'Mirror';

  @override
  String get clipboardModeOffMeans =>
      'Nothing is captured, and nothing arrives.';

  @override
  String get clipboardModeStageMeans =>
      'A copy here travels to the group. Incoming copies wait for you.';

  @override
  String get clipboardModeMirrorMeans =>
      'A copy here travels to the group, and incoming copies replace this clipboard on their own.';

  @override
  String get yes => 'yes';

  @override
  String get no => 'no';

  @override
  String get neverSeen => 'Never seen';

  @override
  String peerNotAccepting(String address) {
    return '$address, not accepting Sessions';
  }

  @override
  String get timeNever => 'never';

  @override
  String get timeJustNow => 'just now';

  @override
  String get timeAMinuteAgo => 'a minute ago';

  @override
  String timeMinutesAgo(int count) {
    return '$count minutes ago';
  }

  @override
  String get timeAnHourAgo => 'an hour ago';

  @override
  String timeHoursAgo(int count) {
    return '$count hours ago';
  }

  @override
  String get timeYesterday => 'yesterday';

  @override
  String timeDaysAgo(int count) {
    return '$count days ago';
  }

  @override
  String get byAddress => 'By address';

  @override
  String get devicesEmptyHint =>
      'Nothing has been discovered yet. Devices running this app on the same network appear here; one Discovery cannot reach can still be dialled by address.';

  @override
  String get rename => 'Rename';

  @override
  String get factPlatform => 'Platform';

  @override
  String get factOwnerGroup => 'Owner Group';

  @override
  String get factSessions => 'Sessions';

  @override
  String get factListening => 'Listening';

  @override
  String clipboardCanOriginate(String value) {
    return 'can originate: $value';
  }

  @override
  String clipboardCanApply(String value) {
    return 'can apply: $value';
  }

  @override
  String groupDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Devices',
      one: '1 Device',
    );
    return '$_temp0';
  }

  @override
  String sessionsOpen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open',
      one: '1 open',
    );
    return '$_temp0';
  }

  @override
  String get notAcceptingSessions => 'not accepting Sessions';

  @override
  String onPort(int port) {
    return 'on port $port';
  }

  @override
  String get pairingCardPairedTitle => 'Pair another Device';

  @override
  String get pairingCardUnpairedTitle => 'Pair this Device to send anything';

  @override
  String get pairingCardPairedBody =>
      'Devices in one Owner Group can open Sessions with each other. Pairing adds one, and is also what lets a clipboard be shared.';

  @override
  String get pairingCardUnpairedBody =>
      'Pairing is a one-time step: on the other Device, tap Pair beside this one in its list, and this Device will ask you to allow it. Allowing it is the whole of it. After that, sending files and messages needs nothing further.';

  @override
  String get acceptPairingRequests => 'Answer pairing requests';

  @override
  String get pairingListening => 'Answering requests from other Devices';

  @override
  String get pairingNotListening => 'Not answering requests';

  @override
  String get factPairingRequests => 'Pairing requests';

  @override
  String get peerNameNotAnnounced => 'name not announced yet';

  @override
  String get sessionOpen => 'Session open';

  @override
  String lastSeen(String when) {
    return 'last seen $when';
  }

  @override
  String get notInOwnerGroup => 'not in this Owner Group';

  @override
  String get trusted => 'trusted';

  @override
  String get menuSendFile => 'Send a file';

  @override
  String get trustDevice => 'Trust this Device';

  @override
  String get stopTrustingDevice => 'Stop trusting this Device';

  @override
  String get openSession => 'Open a Session';

  @override
  String get pairWithThisDevice => 'Pair with this Device';

  @override
  String get nothingToDialYet =>
      'Nothing to dial yet: this Device has not been seen';

  @override
  String get nothingKnownAboutPeer =>
      'Nothing known about where this Device is';

  @override
  String get pair => 'Pair';

  @override
  String get connect => 'Connect';

  @override
  String get transfersEmptyHint => 'Nothing has been sent or received yet.';

  @override
  String transferTo(String peer) {
    return 'To $peer';
  }

  @override
  String transferFrom(String peer) {
    return 'From $peer';
  }

  @override
  String andMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'and $count more',
      one: 'and 1 more',
    );
    return '$_temp0';
  }

  @override
  String bytesOf(String transferred, String total) {
    return '$transferred of $total';
  }

  @override
  String get accept => 'Accept';

  @override
  String get refuse => 'Refuse';

  @override
  String get whereShouldFilesLand => 'Where should these files land?';

  @override
  String get whereShouldThisArrive => 'Where should this arrive?';

  @override
  String get clipboardSyncHeader => 'Clipboard sync';

  @override
  String get clipboardWaitingHeader => 'Waiting for you';

  @override
  String get clipboardAppliedHeader => 'Put on this clipboard';

  @override
  String get clipboardNothingStaged => 'Nothing is waiting to be applied.';

  @override
  String get clipboardNothingApplied =>
      'Nothing has reached this clipboard yet.';

  @override
  String get clipboardNeedsGroup =>
      'Clipboard sync happens inside an Owner Group, and this Device is not in one yet. Pairing is on the Devices surface.';

  @override
  String get clipboardNoteBoth =>
      'Copies made here travel to the group, and copies from the group replace this clipboard.';

  @override
  String get clipboardNoteApplyOnly =>
      'This platform only lets an app read its clipboard while its window is on screen, so copies made here travel only while this window is focused. Copies from the group are applied at any time.';

  @override
  String get clipboardNoteOriginateOnly =>
      'Copies made here travel to the group. This platform cannot apply a copy that arrives.';

  @override
  String get clipboardNoteNone =>
      'This platform lets this app do nothing with its clipboard, in either direction.';

  @override
  String entryFrom(String origin, String when) {
    return 'from $origin · $when';
  }

  @override
  String get apply => 'Apply';

  @override
  String get settingsThisDevice => 'This Device';

  @override
  String get settingsWhereThingsGo => 'Where things go';

  @override
  String get settingsNotices => 'Notices';

  @override
  String get factAlias => 'Alias';

  @override
  String get factFingerprint => 'Fingerprint';

  @override
  String get renameThisDevice => 'Rename this Device';

  @override
  String get factIdentity => 'Identity';

  @override
  String get notStoredOnThisDevice => 'not stored on this Device';

  @override
  String get noIdentityHint =>
      'This Device has nowhere to keep its identity, so it runs in memory: it works, and it has to be paired again after every restart.';

  @override
  String get factReceivedFiles => 'Received files';

  @override
  String get noDefaultFolder => 'no default folder';

  @override
  String get nothingWentWrong => 'Nothing has gone wrong.';

  @override
  String get settingsAbout =>
      'Local Transfer moves text, files and clipboard entries between your own Devices over the local network. There is no server, no account and no cloud: everything above stays inside this network.';

  @override
  String get aliasHelper => 'What other Devices show for this one';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get pairingRequestTitle => 'Pairing request';

  @override
  String pairingRequestFrom(String alias) {
    return '$alias wants to pair with this Device.';
  }

  @override
  String get pairingRequestUnnamed => 'a Device with no name yet';

  @override
  String get pairingRequestClaimHint =>
      'The name is the caller\'s own claim and nothing here can check it. Allowing it adds that Device to your Owner Group, and the two of you can then send each other things.';

  @override
  String get pairingCompleting => 'Finishing the Pairing…';

  @override
  String get acceptPairing => 'Allow';

  @override
  String connectToPeerTitle(String peer) {
    return 'Connect to $peer';
  }

  @override
  String get reachingOtherDevice =>
      'Reaching the other Device, waiting for its user to allow it…';

  @override
  String get manualAddressTitle => 'Reach a Device by address';

  @override
  String get fieldAddress => 'Address';

  @override
  String get addressHelper => 'For a Device Discovery cannot find';

  @override
  String get fieldPort => 'Port';

  @override
  String get portIsANumber => 'A port is a number.';

  @override
  String get manualAddressNote =>
      'Nothing is known about this Device beforehand, so the Session is what proves it belongs in your Owner Group. A Device in a different group is refused.';

  @override
  String get openConversation => 'Open conversation';

  @override
  String get conversationEmpty =>
      'Nothing has been sent or received here yet. Text arrives straight away; a file waits for the other Device to accept it.';

  @override
  String get messageHint => 'Type a message';

  @override
  String get send => 'Send';

  @override
  String get tabConversation => 'Conversations';

  @override
  String get conversationListEmpty =>
      'No conversations yet. Connect a Device from Devices and it will show up here.';

  @override
  String get conversationPickOne =>
      'Pick a conversation on the left, or connect a Device from Devices first.';

  @override
  String get conversationDisconnected => 'Session closed';

  @override
  String sendFileTitle(String peer) {
    return 'Send a file to $peer';
  }

  @override
  String get fieldPath => 'Path';

  @override
  String get pathHelper => 'Copy a path, or type one';

  @override
  String get noFileBrowserNote =>
      'This build has no file browser: it ships no plugins, and a native dialog for each platform is its own change. A path is what it takes for now.';

  @override
  String noSuchFile(String path) {
    return 'There is no file at \"$path\".';
  }

  @override
  String get fieldFolder => 'Folder';

  @override
  String get folderHelper => 'Created if it does not exist';

  @override
  String get folderRequired =>
      'A folder is needed: a name from the peer must not be allowed to choose one.';

  @override
  String get folderNote =>
      'A name that arrives with the Transfer is untrusted: it can name a file inside this folder and nothing else.';

  @override
  String get acceptIntoFolder => 'Accept into this folder';
}

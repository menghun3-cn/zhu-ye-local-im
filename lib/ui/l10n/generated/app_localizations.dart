import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Local Transfer'**
  String get appTitle;

  /// No description provided for @startupFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Local Transfer could not start'**
  String get startupFailureTitle;

  /// No description provided for @tabDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get tabDevices;

  /// No description provided for @tabTransfers.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get tabTransfers;

  /// No description provided for @tabClipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get tabClipboard;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @notPairedYet.
  ///
  /// In en, this message translates to:
  /// **'Not paired with any Device yet'**
  String get notPairedYet;

  /// No description provided for @failureUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the Device: {detail}'**
  String failureUnreachable(String detail);

  /// No description provided for @failurePairing.
  ///
  /// In en, this message translates to:
  /// **'Pairing failed: {detail}'**
  String failurePairing(String detail);

  /// No description provided for @failureCannotReach.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the other Device: {detail}. Check that it is running, that both machines are on the same network, and that its firewall allows incoming TCP 47656.'**
  String failureCannotReach(String detail);

  /// No description provided for @refusalSessionAlreadyOpen.
  ///
  /// In en, this message translates to:
  /// **'A Session with {peer} is already open.'**
  String refusalSessionAlreadyOpen(String peer);

  /// No description provided for @refusalPeerAddressUnknown.
  ///
  /// In en, this message translates to:
  /// **'Nothing is known about where {peer} is. Wait until this Device has discovered it, then try again.'**
  String refusalPeerAddressUnknown(String peer);

  /// No description provided for @refusalNoAddressGiven.
  ///
  /// In en, this message translates to:
  /// **'No address was given.'**
  String get refusalNoAddressGiven;

  /// No description provided for @refusalPortNotAPort.
  ///
  /// In en, this message translates to:
  /// **'{value} is not a port.'**
  String refusalPortNotAPort(String value);

  /// No description provided for @refusalOfferAlreadyAnswered.
  ///
  /// In en, this message translates to:
  /// **'This offer has already been answered.'**
  String get refusalOfferAlreadyAnswered;

  /// No description provided for @refusalNoPeerConnected.
  ///
  /// In en, this message translates to:
  /// **'No Device is connected.'**
  String get refusalNoPeerConnected;

  /// No description provided for @refusalNoSessionOpen.
  ///
  /// In en, this message translates to:
  /// **'No Session is open with {peer}.'**
  String refusalNoSessionOpen(String peer);

  /// No description provided for @refusalSeveralPeersConnected.
  ///
  /// In en, this message translates to:
  /// **'More than one Device is connected; name the one to send to.'**
  String get refusalSeveralPeersConnected;

  /// No description provided for @refusalNotPaired.
  ///
  /// In en, this message translates to:
  /// **'This Device is not paired, so it accepts no Sessions.'**
  String get refusalNotPaired;

  /// No description provided for @refusalNoFreeFileName.
  ///
  /// In en, this message translates to:
  /// **'No free name is left for \"{name}\" in that folder.'**
  String refusalNoFreeFileName(String name);

  /// No description provided for @kindText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get kindText;

  /// No description provided for @kindFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get kindFiles;

  /// No description provided for @kindImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get kindImages;

  /// No description provided for @kindClipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get kindClipboard;

  /// No description provided for @stateAwaitingDecision.
  ///
  /// In en, this message translates to:
  /// **'Waiting for an answer'**
  String get stateAwaitingDecision;

  /// No description provided for @stateTransferring.
  ///
  /// In en, this message translates to:
  /// **'Transferring'**
  String get stateTransferring;

  /// No description provided for @stateVerifying.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get stateVerifying;

  /// No description provided for @stateCompleted.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get stateCompleted;

  /// No description provided for @stateRejected.
  ///
  /// In en, this message translates to:
  /// **'Refused'**
  String get stateRejected;

  /// No description provided for @stateCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get stateCancelled;

  /// No description provided for @stateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get stateFailed;

  /// No description provided for @clipboardModeOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get clipboardModeOff;

  /// No description provided for @clipboardModeStage.
  ///
  /// In en, this message translates to:
  /// **'Ask me'**
  String get clipboardModeStage;

  /// No description provided for @clipboardModeMirror.
  ///
  /// In en, this message translates to:
  /// **'Mirror'**
  String get clipboardModeMirror;

  /// No description provided for @clipboardModeOffMeans.
  ///
  /// In en, this message translates to:
  /// **'Nothing is captured, and nothing arrives.'**
  String get clipboardModeOffMeans;

  /// No description provided for @clipboardModeStageMeans.
  ///
  /// In en, this message translates to:
  /// **'A copy here travels to the group. Incoming copies wait for you.'**
  String get clipboardModeStageMeans;

  /// No description provided for @clipboardModeMirrorMeans.
  ///
  /// In en, this message translates to:
  /// **'A copy here travels to the group, and incoming copies replace this clipboard on their own.'**
  String get clipboardModeMirrorMeans;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'no'**
  String get no;

  /// No description provided for @neverSeen.
  ///
  /// In en, this message translates to:
  /// **'Never seen'**
  String get neverSeen;

  /// No description provided for @peerNotAccepting.
  ///
  /// In en, this message translates to:
  /// **'{address}, not accepting Sessions'**
  String peerNotAccepting(String address);

  /// No description provided for @timeNever.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get timeNever;

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get timeJustNow;

  /// No description provided for @timeAMinuteAgo.
  ///
  /// In en, this message translates to:
  /// **'a minute ago'**
  String get timeAMinuteAgo;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes ago'**
  String timeMinutesAgo(int count);

  /// No description provided for @timeAnHourAgo.
  ///
  /// In en, this message translates to:
  /// **'an hour ago'**
  String get timeAnHourAgo;

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} hours ago'**
  String timeHoursAgo(int count);

  /// No description provided for @timeYesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get timeYesterday;

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String timeDaysAgo(int count);

  /// No description provided for @byAddress.
  ///
  /// In en, this message translates to:
  /// **'By address'**
  String get byAddress;

  /// No description provided for @devicesEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been discovered yet. Devices running this app on the same network appear here; one Discovery cannot reach can still be dialled by address.'**
  String get devicesEmptyHint;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @factPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get factPlatform;

  /// No description provided for @factOwnerGroup.
  ///
  /// In en, this message translates to:
  /// **'Owner Group'**
  String get factOwnerGroup;

  /// No description provided for @factSessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get factSessions;

  /// No description provided for @factListening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get factListening;

  /// No description provided for @clipboardCanOriginate.
  ///
  /// In en, this message translates to:
  /// **'can originate: {value}'**
  String clipboardCanOriginate(String value);

  /// No description provided for @clipboardCanApply.
  ///
  /// In en, this message translates to:
  /// **'can apply: {value}'**
  String clipboardCanApply(String value);

  /// No description provided for @groupDevices.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Device} other{{count} Devices}}'**
  String groupDevices(int count);

  /// No description provided for @sessionsOpen.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 open} other{{count} open}}'**
  String sessionsOpen(int count);

  /// No description provided for @notAcceptingSessions.
  ///
  /// In en, this message translates to:
  /// **'not accepting Sessions'**
  String get notAcceptingSessions;

  /// No description provided for @onPort.
  ///
  /// In en, this message translates to:
  /// **'on port {port}'**
  String onPort(int port);

  /// No description provided for @pairingCardPairedTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair another Device'**
  String get pairingCardPairedTitle;

  /// No description provided for @pairingCardUnpairedTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair this Device to send anything'**
  String get pairingCardUnpairedTitle;

  /// No description provided for @pairingCardPairedBody.
  ///
  /// In en, this message translates to:
  /// **'Devices in one Owner Group can open Sessions with each other. Pairing adds one, and is also what lets a clipboard be shared.'**
  String get pairingCardPairedBody;

  /// No description provided for @pairingCardUnpairedBody.
  ///
  /// In en, this message translates to:
  /// **'Pairing is a one-time step: on the other Device, tap Pair beside this one in its list, and this Device will ask you to allow it. Allowing it is the whole of it. After that, sending files and messages needs nothing further.'**
  String get pairingCardUnpairedBody;

  /// No description provided for @acceptPairingRequests.
  ///
  /// In en, this message translates to:
  /// **'Answer pairing requests'**
  String get acceptPairingRequests;

  /// No description provided for @pairingListening.
  ///
  /// In en, this message translates to:
  /// **'Answering requests from other Devices'**
  String get pairingListening;

  /// No description provided for @pairingNotListening.
  ///
  /// In en, this message translates to:
  /// **'Not answering requests'**
  String get pairingNotListening;

  /// No description provided for @factPairingRequests.
  ///
  /// In en, this message translates to:
  /// **'Pairing requests'**
  String get factPairingRequests;

  /// No description provided for @peerNameNotAnnounced.
  ///
  /// In en, this message translates to:
  /// **'name not announced yet'**
  String get peerNameNotAnnounced;

  /// No description provided for @sessionOpen.
  ///
  /// In en, this message translates to:
  /// **'Session open'**
  String get sessionOpen;

  /// No description provided for @lastSeen.
  ///
  /// In en, this message translates to:
  /// **'last seen {when}'**
  String lastSeen(String when);

  /// No description provided for @notInOwnerGroup.
  ///
  /// In en, this message translates to:
  /// **'not in this Owner Group'**
  String get notInOwnerGroup;

  /// No description provided for @trusted.
  ///
  /// In en, this message translates to:
  /// **'trusted'**
  String get trusted;

  /// No description provided for @menuSendFile.
  ///
  /// In en, this message translates to:
  /// **'Send a file'**
  String get menuSendFile;

  /// No description provided for @menuSendImage.
  ///
  /// In en, this message translates to:
  /// **'Send an image'**
  String get menuSendImage;

  /// No description provided for @dropToSend.
  ///
  /// In en, this message translates to:
  /// **'Let go to send'**
  String get dropToSend;

  /// No description provided for @trustDevice.
  ///
  /// In en, this message translates to:
  /// **'Trust this Device'**
  String get trustDevice;

  /// No description provided for @stopTrustingDevice.
  ///
  /// In en, this message translates to:
  /// **'Stop trusting this Device'**
  String get stopTrustingDevice;

  /// No description provided for @openSession.
  ///
  /// In en, this message translates to:
  /// **'Open a Session'**
  String get openSession;

  /// No description provided for @pairWithThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Pair with this Device'**
  String get pairWithThisDevice;

  /// No description provided for @nothingToDialYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing to dial yet: this Device has not been seen'**
  String get nothingToDialYet;

  /// No description provided for @nothingKnownAboutPeer.
  ///
  /// In en, this message translates to:
  /// **'Nothing known about where this Device is'**
  String get nothingKnownAboutPeer;

  /// No description provided for @pair.
  ///
  /// In en, this message translates to:
  /// **'Pair'**
  String get pair;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @transfersEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'No files have been transferred yet. Text messages live in their conversations, not here.'**
  String get transfersEmptyHint;

  /// No description provided for @transferTo.
  ///
  /// In en, this message translates to:
  /// **'To {peer}'**
  String transferTo(String peer);

  /// No description provided for @transferFrom.
  ///
  /// In en, this message translates to:
  /// **'From {peer}'**
  String transferFrom(String peer);

  /// No description provided for @andMore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{and 1 more} other{and {count} more}}'**
  String andMore(int count);

  /// No description provided for @bytesOf.
  ///
  /// In en, this message translates to:
  /// **'{transferred} of {total}'**
  String bytesOf(String transferred, String total);

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @refuse.
  ///
  /// In en, this message translates to:
  /// **'Refuse'**
  String get refuse;

  /// No description provided for @whereShouldFilesLand.
  ///
  /// In en, this message translates to:
  /// **'Where should these files land?'**
  String get whereShouldFilesLand;

  /// No description provided for @whereShouldThisArrive.
  ///
  /// In en, this message translates to:
  /// **'Where should this arrive?'**
  String get whereShouldThisArrive;

  /// No description provided for @clipboardSyncHeader.
  ///
  /// In en, this message translates to:
  /// **'Clipboard sync'**
  String get clipboardSyncHeader;

  /// No description provided for @clipboardWaitingHeader.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you'**
  String get clipboardWaitingHeader;

  /// No description provided for @clipboardAppliedHeader.
  ///
  /// In en, this message translates to:
  /// **'Put on this clipboard'**
  String get clipboardAppliedHeader;

  /// No description provided for @clipboardNothingStaged.
  ///
  /// In en, this message translates to:
  /// **'Nothing is waiting to be applied.'**
  String get clipboardNothingStaged;

  /// No description provided for @clipboardNothingApplied.
  ///
  /// In en, this message translates to:
  /// **'Nothing has reached this clipboard yet.'**
  String get clipboardNothingApplied;

  /// No description provided for @clipboardNeedsGroup.
  ///
  /// In en, this message translates to:
  /// **'Clipboard sync happens inside an Owner Group, and this Device is not in one yet.'**
  String get clipboardNeedsGroup;

  /// No description provided for @clipboardPeersHeader.
  ///
  /// In en, this message translates to:
  /// **'Devices that may share the clipboard'**
  String get clipboardPeersHeader;

  /// No description provided for @clipboardPeersHint.
  ///
  /// In en, this message translates to:
  /// **'Only the devices ticked below receive what this Device copies, and only their entries are applied here.'**
  String get clipboardPeersHint;

  /// No description provided for @clipboardPeersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No paired devices yet; pair one from the conversation list first, then come back to tick it for clipboard sharing.'**
  String get clipboardPeersEmpty;

  /// No description provided for @clipboardNoteBoth.
  ///
  /// In en, this message translates to:
  /// **'Copies made here travel to the group, and copies from the group replace this clipboard.'**
  String get clipboardNoteBoth;

  /// No description provided for @clipboardNoteApplyOnly.
  ///
  /// In en, this message translates to:
  /// **'This platform only lets an app read its clipboard while its window is on screen, so copies made here travel only while this window is focused. Copies from the group are applied at any time.'**
  String get clipboardNoteApplyOnly;

  /// No description provided for @clipboardNoteOriginateOnly.
  ///
  /// In en, this message translates to:
  /// **'Copies made here travel to the group. This platform cannot apply a copy that arrives.'**
  String get clipboardNoteOriginateOnly;

  /// No description provided for @clipboardNoteNone.
  ///
  /// In en, this message translates to:
  /// **'This platform lets this app do nothing with its clipboard, in either direction.'**
  String get clipboardNoteNone;

  /// No description provided for @entryFrom.
  ///
  /// In en, this message translates to:
  /// **'from {origin} · {when}'**
  String entryFrom(String origin, String when);

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @settingsThisDevice.
  ///
  /// In en, this message translates to:
  /// **'This Device'**
  String get settingsThisDevice;

  /// No description provided for @settingsWhereThingsGo.
  ///
  /// In en, this message translates to:
  /// **'Where things go'**
  String get settingsWhereThingsGo;

  /// No description provided for @settingsNotices.
  ///
  /// In en, this message translates to:
  /// **'Notices'**
  String get settingsNotices;

  /// No description provided for @factAlias.
  ///
  /// In en, this message translates to:
  /// **'Alias'**
  String get factAlias;

  /// No description provided for @factFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint'**
  String get factFingerprint;

  /// No description provided for @renameThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Rename this Device'**
  String get renameThisDevice;

  /// No description provided for @factIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get factIdentity;

  /// No description provided for @notStoredOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'not stored on this Device'**
  String get notStoredOnThisDevice;

  /// No description provided for @noIdentityHint.
  ///
  /// In en, this message translates to:
  /// **'This Device has nowhere to keep its identity, so it runs in memory: it works, and it has to be paired again after every restart.'**
  String get noIdentityHint;

  /// No description provided for @factReceivedFiles.
  ///
  /// In en, this message translates to:
  /// **'Received files'**
  String get factReceivedFiles;

  /// No description provided for @noDefaultFolder.
  ///
  /// In en, this message translates to:
  /// **'no default folder'**
  String get noDefaultFolder;

  /// No description provided for @nothingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Nothing has gone wrong.'**
  String get nothingWentWrong;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'Local Transfer moves text, files and clipboard entries between your own Devices over the local network. There is no server, no account and no cloud: everything above stays inside this network.'**
  String get settingsAbout;

  /// No description provided for @aliasHelper.
  ///
  /// In en, this message translates to:
  /// **'What other Devices show for this one'**
  String get aliasHelper;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @pairingRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Pairing request'**
  String get pairingRequestTitle;

  /// No description provided for @pairingRequestFrom.
  ///
  /// In en, this message translates to:
  /// **'{alias} wants to pair with this Device.'**
  String pairingRequestFrom(String alias);

  /// No description provided for @pairingRequestUnnamed.
  ///
  /// In en, this message translates to:
  /// **'a Device with no name yet'**
  String get pairingRequestUnnamed;

  /// No description provided for @pairingRequestClaimHint.
  ///
  /// In en, this message translates to:
  /// **'The name is the caller\'s own claim and nothing here can check it. Allowing it adds that Device to your Owner Group, and the two of you can then send each other things.'**
  String get pairingRequestClaimHint;

  /// No description provided for @pairingCompleting.
  ///
  /// In en, this message translates to:
  /// **'Finishing the Pairing…'**
  String get pairingCompleting;

  /// No description provided for @acceptPairing.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get acceptPairing;

  /// No description provided for @connectToPeerTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to {peer}'**
  String connectToPeerTitle(String peer);

  /// No description provided for @reachingOtherDevice.
  ///
  /// In en, this message translates to:
  /// **'Reaching the other Device, waiting for its user to allow it…'**
  String get reachingOtherDevice;

  /// No description provided for @manualAddressTitle.
  ///
  /// In en, this message translates to:
  /// **'Reach a Device by address'**
  String get manualAddressTitle;

  /// No description provided for @fieldAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get fieldAddress;

  /// No description provided for @addressHelper.
  ///
  /// In en, this message translates to:
  /// **'For a Device Discovery cannot find'**
  String get addressHelper;

  /// No description provided for @fieldPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get fieldPort;

  /// No description provided for @portIsANumber.
  ///
  /// In en, this message translates to:
  /// **'A port is a number.'**
  String get portIsANumber;

  /// No description provided for @manualAddressNote.
  ///
  /// In en, this message translates to:
  /// **'Nothing is known about this Device beforehand, so the Session is what proves it belongs in your Owner Group. A Device in a different group is refused.'**
  String get manualAddressNote;

  /// No description provided for @openConversation.
  ///
  /// In en, this message translates to:
  /// **'Open conversation'**
  String get openConversation;

  /// No description provided for @conversationEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been sent or received here yet. Text arrives straight away; a file waits for the other Device to accept it.'**
  String get conversationEmpty;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message'**
  String get messageHint;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @tabConversation.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get tabConversation;

  /// No description provided for @conversationListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet. A Device this one finds shows up here on its own, ready to connect.'**
  String get conversationListEmpty;

  /// No description provided for @conversationPickOne.
  ///
  /// In en, this message translates to:
  /// **'Pick a conversation on the left, or connect a Device first.'**
  String get conversationPickOne;

  /// No description provided for @conversationDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Session closed'**
  String get conversationDisconnected;

  /// No description provided for @sendFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Send a file to {peer}'**
  String sendFileTitle(String peer);

  /// No description provided for @fieldPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get fieldPath;

  /// No description provided for @pathHelper.
  ///
  /// In en, this message translates to:
  /// **'Copy a path, or type one'**
  String get pathHelper;

  /// No description provided for @noFileBrowserNote.
  ///
  /// In en, this message translates to:
  /// **'This build has no file browser: it ships no plugins, and a native dialog for each platform is its own change. A path is what it takes for now.'**
  String get noFileBrowserNote;

  /// No description provided for @noSuchFile.
  ///
  /// In en, this message translates to:
  /// **'There is no file at \"{path}\".'**
  String noSuchFile(String path);

  /// No description provided for @fieldFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get fieldFolder;

  /// No description provided for @folderHelper.
  ///
  /// In en, this message translates to:
  /// **'Created if it does not exist'**
  String get folderHelper;

  /// No description provided for @folderRequired.
  ///
  /// In en, this message translates to:
  /// **'A folder is needed: a name from the peer must not be allowed to choose one.'**
  String get folderRequired;

  /// No description provided for @folderNote.
  ///
  /// In en, this message translates to:
  /// **'A name that arrives with the Transfer is untrusted: it can name a file inside this folder and nothing else.'**
  String get folderNote;

  /// No description provided for @acceptIntoFolder.
  ///
  /// In en, this message translates to:
  /// **'Accept into this folder'**
  String get acceptIntoFolder;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

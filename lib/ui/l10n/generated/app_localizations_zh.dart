// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '竹叶局域网传输';

  @override
  String get startupFailureTitle => '竹叶局域网传输无法启动';

  @override
  String get tabDevices => '设备';

  @override
  String get tabTransfers => '传输';

  @override
  String get tabClipboard => '剪贴板';

  @override
  String get tabSettings => '设置';

  @override
  String get tabAbout => '关于';

  @override
  String failureUnreachable(String detail) {
    return '无法连接到该设备：$detail';
  }

  @override
  String failurePairing(String detail) {
    return '自动连接失败：$detail';
  }

  @override
  String failureCannotReach(String detail) {
    return '连不上对方设备：$detail。请确认对方程序正在运行、两台机器在同一网络，并在对方的防火墙里允许本程序接受连接（默认入站 TCP 47656）。';
  }

  @override
  String refusalSessionAlreadyOpen(String peer) {
    return '与 $peer 的连接已经打开了。';
  }

  @override
  String refusalPeerAddressUnknown(String peer) {
    return '还不知道 $peer 在哪里。请等本机发现它之后再试。';
  }

  @override
  String get refusalNoAddressGiven => '没有填写地址。';

  @override
  String refusalPortNotAPort(String value) {
    return '$value 不是合法的端口号。';
  }

  @override
  String get refusalOfferAlreadyAnswered => '这个传输请求已经处理过了。';

  @override
  String get refusalNoPeerConnected => '当前没有已连接的设备。';

  @override
  String refusalNoSessionOpen(String peer) {
    return '与 $peer 之间没有打开的连接。';
  }

  @override
  String get refusalSeveralPeersConnected => '当前连接了多台设备，需要指明发给哪一台。';

  @override
  String get refusalNotPaired => '本机还没有加入设备组，不接受任何连接。';

  @override
  String refusalNoFreeFileName(String name) {
    return '在那个文件夹里已经找不到 \"$name\" 可用的名字了。';
  }

  @override
  String get kindText => '文本';

  @override
  String get kindFiles => '文件';

  @override
  String get kindImages => '图片';

  @override
  String get kindClipboard => '剪贴板';

  @override
  String get kindEmoji => '表情';

  @override
  String get stateAwaitingDecision => '等待对方确认';

  @override
  String get stateTransferring => '传输中';

  @override
  String get stateVerifying => '校验中';

  @override
  String get stateCompleted => '已完成';

  @override
  String get stateRejected => '被拒绝';

  @override
  String get stateCancelled => '已取消';

  @override
  String get stateFailed => '失败';

  @override
  String transferElapsed(String duration) {
    return '已用 $duration';
  }

  @override
  String transferTook(String duration) {
    return '用时 $duration';
  }

  @override
  String durationSeconds(int seconds) {
    return '$seconds 秒';
  }

  @override
  String durationMinutes(int minutes, int seconds) {
    return '$minutes 分 $seconds 秒';
  }

  @override
  String durationHours(int hours, int minutes) {
    return '$hours 小时 $minutes 分';
  }

  @override
  String get clipboardModeOff => '关闭';

  @override
  String get clipboardModeStage => '问我';

  @override
  String get clipboardModeMirror => '镜像';

  @override
  String get clipboardModeOffMeans => '不采集本机剪贴板，也不接收组内内容。';

  @override
  String get clipboardModeStageMeans => '在本机复制会发给组内设备；组内发来的内容会先等你确认，再写入剪贴板。';

  @override
  String get clipboardModeMirrorMeans => '在本机复制会发给组内设备；组内发来的内容会自动替换本机剪贴板。';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get neverSeen => '从未出现';

  @override
  String peerNotAccepting(String address) {
    return '$address，不接受连接';
  }

  @override
  String get timeNever => '从未';

  @override
  String get timeJustNow => '刚刚';

  @override
  String get timeAMinuteAgo => '1 分钟前';

  @override
  String timeMinutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String get timeAnHourAgo => '1 小时前';

  @override
  String timeHoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String get timeYesterday => '昨天';

  @override
  String timeDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get byAddress => '按地址连接';

  @override
  String get devicesEmptyHint =>
      '还没有发现任何设备。同一网络里运行本程序的设备会显示在这里；自动发现不到的设备，也可以按地址直接连接。';

  @override
  String get localIpAddress => '本机 IP';

  @override
  String get localIpUnavailable => '暂时读不到本机地址';

  @override
  String get rename => '重命名';

  @override
  String get factPlatform => '平台';

  @override
  String get factOwnerGroup => '设备组';

  @override
  String get factSessions => '连接数';

  @override
  String get factListening => '监听';

  @override
  String clipboardCanOriginate(String value) {
    return '可发出：$value';
  }

  @override
  String clipboardCanApply(String value) {
    return '可接收：$value';
  }

  @override
  String groupDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 台设备',
    );
    return '$_temp0';
  }

  @override
  String sessionsOpen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个已打开',
    );
    return '$_temp0';
  }

  @override
  String get sessionsAutoConnectPending => '正在自动建立连接';

  @override
  String get connectionNotReady => '连接通道暂未就绪';

  @override
  String onPort(int port) {
    return '端口 $port';
  }

  @override
  String get automaticConnectionsTitle => '自动连接';

  @override
  String get automaticConnectionsBody =>
      '同一局域网内运行本程序的设备被发现后会自动建立连接。无需配对或接受请求，即可直接发送文字、图片、文件和表情。';

  @override
  String get automaticConnectionsReady => '已就绪：发现设备后自动连接';

  @override
  String get automaticConnectionsUnavailable => '本机当前无法接受自动连接；仍可主动连接其他设备。';

  @override
  String get factAutomaticConnections => '自动连接';

  @override
  String get peerNameNotAnnounced => '对方还没广播名称';

  @override
  String get sessionOpen => '已连接';

  @override
  String lastSeen(String when) {
    return '最后出现于 $when';
  }

  @override
  String get notInOwnerGroup => '不在本设备组中';

  @override
  String get trusted => '已信任';

  @override
  String get menuSendFile => '发送文件';

  @override
  String get menuSendEmoji => '发送表情';

  @override
  String get emojiRecent => '最近使用';

  @override
  String get dropToSend => '松手即发送';

  @override
  String get trustDevice => '信任这台设备';

  @override
  String get stopTrustingDevice => '不再信任这台设备';

  @override
  String get openSession => '建立连接';

  @override
  String get nothingToDialYet => '暂时无法连接：还没有发现这台设备';

  @override
  String get nothingKnownAboutPeer => '不知道这台设备在哪里';

  @override
  String get connect => '连接';

  @override
  String get connectingAutomatically => '正在自动连接';

  @override
  String get autoReconnectPending => '会自动重新连接';

  @override
  String get autoConnectingSoon => '正在等待对方可连接';

  @override
  String get transfersEmptyHint => '还没有传输过文件。文字内容在对话里，不在这里显示。';

  @override
  String transferTo(String peer) {
    return '发给 $peer';
  }

  @override
  String transferFrom(String peer) {
    return '来自 $peer';
  }

  @override
  String andMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '还有 $count 项',
    );
    return '$_temp0';
  }

  @override
  String bytesOf(String transferred, String total) {
    return '$transferred / $total';
  }

  @override
  String get accept => '接收';

  @override
  String get refuse => '拒绝';

  @override
  String get cancelSend => '取消发送';

  @override
  String get whereShouldFilesLand => '这些文件保存到哪个文件夹？';

  @override
  String get whereShouldThisArrive => '保存到哪个文件夹？';

  @override
  String get openContainingFolder => '打开所在目录';

  @override
  String get cannotOpenFolder => '没能打开那个文件夹。';

  @override
  String get copyImage => '复制图片';

  @override
  String get cannotCopyImage => '没能复制这张图片。';

  @override
  String get copyText => '复制文字';

  @override
  String get cannotCopyText => '没能复制这段文字。';

  @override
  String get copySelection => '复制';

  @override
  String get deleteMessage => '删除';

  @override
  String get clipboardSyncHeader => '剪贴板同步';

  @override
  String get clipboardWaitingHeader => '等待你处理';

  @override
  String get clipboardAppliedHeader => '已写入本机剪贴板';

  @override
  String get clipboardNothingStaged => '没有等待处理的内容。';

  @override
  String get clipboardNothingApplied => '还没有内容写入本机剪贴板。';

  @override
  String get clipboardNeedsGroup => '剪贴板同步只在设备组内进行，本机还没有加入任何设备组。';

  @override
  String get clipboardPeersHeader => '可共享剪贴板的设备';

  @override
  String get clipboardPeersHint => '只有勾选的设备会收到本机复制的内容，本机也只会应用它们发来的内容。';

  @override
  String get clipboardPeersEmpty => '还没有已连接的设备；等附近设备自动出现后，再回来勾选要共享剪贴板的设备。';

  @override
  String get clipboardNoteBoth => '在本机复制的内容会发给组内设备，组内发来的内容会替换本机剪贴板。';

  @override
  String get clipboardNoteApplyOnly =>
      '这个平台只允许应用在窗口显示时读取剪贴板，所以本机复制的内容只有在窗口处于前台时才会发出；组内发来的内容随时可以写入。';

  @override
  String get clipboardNoteOriginateOnly => '在本机复制的内容会发给组内设备；这个平台无法把收到的内容写入剪贴板。';

  @override
  String get clipboardNoteNone => '这个平台不允许本应用读写剪贴板，两个方向都不行。';

  @override
  String entryFrom(String origin, String when) {
    return '来自 $origin · $when';
  }

  @override
  String get apply => '写入剪贴板';

  @override
  String get settingsThisDevice => '本机';

  @override
  String get settingsWhereThingsGo => '存放位置';

  @override
  String get settingsNotices => '提示';

  @override
  String get settingsWindowAndStartup => '窗口与启动';

  @override
  String get settingsStartWithWindows => '开机自启动';

  @override
  String get settingsStartWithWindowsOn => '登录系统后自动运行。';

  @override
  String get settingsStartWithWindowsOff => '需要手动启动。';

  @override
  String get settingsCloseButton => '点击关闭按钮时';

  @override
  String get settingsCloseToTray => '最小化到托盘';

  @override
  String get settingsCloseQuit => '直接退出';

  @override
  String get settingsCloseToTrayHint => '窗口隐藏，程序继续在后台运行，仍能接收内容。';

  @override
  String get settingsCloseQuitHint => '关闭窗口就结束程序。';

  @override
  String get settingsUpdate => '更新检查';

  @override
  String get settingsPeriodicUpdateTitle => '后台定期检查更新';

  @override
  String get settingsPeriodicUpdateOn => '程序会自己询问是否有更新版本。';

  @override
  String get settingsPeriodicUpdateOff => '只在手动点「检查更新」时询问。';

  @override
  String get settingsUpdateFrequency => '检查频率';

  @override
  String get settingsUpdateHint =>
      '每次检查仅向 GitHub 询问发布版本，不发送本机任何内容；关闭后仍保留启动时的一次检查。';

  @override
  String get updateIntervalHourly => '每 1 小时';

  @override
  String get updateIntervalSixHours => '每 6 小时';

  @override
  String get updateIntervalDaily => '每天';

  @override
  String get updateIntervalThreeDays => '每 3 天';

  @override
  String get factAlias => '名称';

  @override
  String get factFingerprint => '指纹';

  @override
  String get renameThisDevice => '重命名本机';

  @override
  String get factIdentity => '身份';

  @override
  String get notStoredOnThisDevice => '未保存在本机';

  @override
  String get noIdentityHint =>
      '本机没有可保存身份的位置，因此身份只存在于内存中：功能可用，但重启后需要重新发现其他设备并自动建立连接。';

  @override
  String get factReceivedFiles => '接收的文件';

  @override
  String get noDefaultFolder => '没有默认文件夹';

  @override
  String get nothingWentWrong => '一切正常。';

  @override
  String get aboutDescription =>
      '竹叶局域网传输在你自己的设备之间，通过局域网传送文本、文件和剪贴板内容。没有服务器、没有账号、也没有云端：所有传送都只在本网络内。唯一与外界通信的是向 GitHub 询问发布版本（启动时一次，之后按你在设置里选择的频率），不发送任何内容。';

  @override
  String aboutVersion(String version) {
    return '版本 $version';
  }

  @override
  String get aboutCheckForUpdates => '检查更新';

  @override
  String get aboutChecking => '正在检查…';

  @override
  String get aboutUpToDate => '已是最新版本。';

  @override
  String aboutUpdateAvailable(String version) {
    return '有新版本 $version。';
  }

  @override
  String get aboutUpdateNotes => '更新日志';

  @override
  String get aboutOpenDownload => '打开下载页';

  @override
  String get aboutNoRelease => '还没有发布过任何版本，暂时无从比较本机这版。';

  @override
  String get aboutUnreachable => '连不上更新服务器。请检查网络，或手动下载新版本。';

  @override
  String get aboutHowToUpgrade =>
      '升级方式：退出程序，下载新版压缩包，解压后覆盖本目录即可。程序只在这个文件夹和 %APPDATA%\\LocalTransfer（本机身份，不要动）里留东西。';

  @override
  String get aboutUpdate => '更新';

  @override
  String get aboutUpdateDownloading => '正在下载';

  @override
  String get aboutUpdateVerifying => '正在校验下载内容…';

  @override
  String get aboutUpdateStaging => '正在解压…';

  @override
  String get aboutUpdateHandingOver => '正在替换本目录并重启…';

  @override
  String get aboutUpdateInstalling => '正在打开系统安装器…';

  @override
  String get aboutUpdateFailedTitle => '更新没有完成';

  @override
  String get aboutUpdateInstallHint =>
      '点「更新」就行：程序把更新包取到本目录下的 update 文件夹、按发布方公布的校验值核一遍，然后问一句「更新并重启」——确认后程序先关闭，更新完成自动重新打开。做不了的时候，旁边那个按钮会打开手动下载的页面。';

  @override
  String get aboutUpdateInstallHintAndroid =>
      '点「更新」：程序把 APK 下载到应用自己的目录，按发布方公布的校验值核一遍，然后问一句「安装更新」——确认后会打开系统安装器。第一次安装时，系统可能会先让你允许本应用安装未知应用。';

  @override
  String get aboutUpdateConfirmTitle => '更新并重启？';

  @override
  String aboutUpdateConfirmBody(String version) {
    return '新版本 $version 已经下载完成，并核对过发布方公布的校验值。点「更新并重启」：程序先关闭，更新完成后自动重新打开。';
  }

  @override
  String get aboutUpdateConfirmApply => '更新并重启';

  @override
  String get aboutUpdateConfirmTitleAndroid => '安装更新？';

  @override
  String aboutUpdateConfirmBodyAndroid(String version) {
    return '新版本 $version 已经下载完成，并核对过发布方公布的校验值。点「打开安装器」：系统会接管安装，完成后可以重新打开本应用。';
  }

  @override
  String get aboutUpdateConfirmApplyAndroid => '打开安装器';

  @override
  String get aboutUpdateReady => '更新包已就绪。再点一次「更新」即可安装，不用重新下载。';

  @override
  String get aboutUpdateReadyAndroid => '安装包已就绪。再点一次「更新」即可打开系统安装器，不用重新下载。';

  @override
  String get aboutHowToUpgradeAndroid =>
      '升级方式：点「更新」获取并校验 APK，再交给系统安装器；也可以打开下载页手动下载。';

  @override
  String get updateFailureUnsupported => '这个平台不能自己替换，请手动下载新版本。';

  @override
  String get updateFailureNoAsset => '这个版本没有带本机需要的那个文件，请手动下载。';

  @override
  String get updateFailureNoDigest => '这个版本没有公布校验值，装上之前没法核对，请手动下载。';

  @override
  String get updateFailureNotWritable => '程序所在的目录不可写。请手动下载新版本，解压后覆盖本目录。';

  @override
  String get updateFailureDownload => '下载没有完成。请检查网络后重试。';

  @override
  String get updateFailureChecksum => '下载到的内容与发布方公布的不一致，已经丢弃。';

  @override
  String get updateFailureUnpack => '下载到了，但解压失败。可以重试，或手动下载新版本。';

  @override
  String get updateFailureHandover => '上一次替换没有完成。请手动下载新版本，解压后覆盖本目录。';

  @override
  String get updateFailurePermission =>
      '还没有获得「安装未知应用」权限。请在系统设置里允许本应用安装未知应用，然后回来再点一次。';

  @override
  String get updateFailureInstaller => '系统安装器没有打开。请重试，或打开下载页手动安装 APK。';

  @override
  String get railUpdate => '更新';

  @override
  String get aliasHelper => '其他设备上显示的名称';

  @override
  String get cancel => '取消';

  @override
  String get close => '关闭';

  @override
  String get save => '保存';

  @override
  String get manualAddressTitle => '按地址连接设备';

  @override
  String get fieldAddress => '地址';

  @override
  String get addressHelper => '用于自动发现不到的设备';

  @override
  String get fieldPort => '端口';

  @override
  String get portIsANumber => '端口必须是数字。';

  @override
  String get manualAddressNote =>
      '事先并不知道这台设备的任何信息，因此要靠连接握手来证明它属于同一个设备组；属于其他设备组的会被拒绝。';

  @override
  String get openConversation => '打开会话';

  @override
  String get conversationEmpty => '还没有收发过内容。文字和图片会直接送达，文件需要对方确认后才会接收。';

  @override
  String get messageHint => '输入要发送的文字';

  @override
  String get send => '发送';

  @override
  String get removeAttachment => '移除';

  @override
  String get tabConversation => '对话';

  @override
  String get conversationListEmpty => '还没有对话。附近运行本程序的设备被发现后，会自动建立连接并出现在这里。';

  @override
  String get searchConversations => '搜索对话内容';

  @override
  String get conversationSearchEmpty => '没有找到匹配的对话或消息。';

  @override
  String get clearSearch => '清除搜索';

  @override
  String get clearConversation => '清空聊天记录';

  @override
  String get clearConversationConfirmTitle => '清空聊天记录？';

  @override
  String get clearConversationConfirmBody =>
      '这个对话里的文字、文件和图片记录都会从本机清除，无法撤销。剪贴板记录不受影响。';

  @override
  String get clearConversationConfirmAction => '清空';

  @override
  String get conversationPickOne => '从左边选一个对话，或等待附近设备自动连接。';

  @override
  String get conversationDisconnected => '离线';

  @override
  String conversationUnread(int count) {
    return '[$count]';
  }

  @override
  String sendFileTitle(String peer) {
    return '发送文件给 $peer';
  }

  @override
  String get fieldPath => '路径';

  @override
  String get pathHelper => '粘贴或输入一个文件路径';

  @override
  String get noFileBrowserNote =>
      '这个版本还没有文件选择器：它不带任何插件，而为每个平台各写一个原生对话框是另一件事。目前只能用路径。';

  @override
  String noSuchFile(String path) {
    return '\"$path\" 这里没有文件。';
  }

  @override
  String get fieldFolder => '文件夹';

  @override
  String get folderHelper => '不存在时会自动创建';

  @override
  String get folderRequired => '必须指定一个文件夹：不能让随传输过来的文件名替我们决定保存到哪里。';

  @override
  String get folderNote => '随传输一起过来的文件名不能信任：它只能命名这个文件夹里的文件，跳不出去。';

  @override
  String get acceptIntoFolder => '接收并保存到此文件夹';

  @override
  String get browseFolder => '选择文件夹…';

  @override
  String get changeIncomingFolder => '更改…';

  @override
  String get incomingFolderHint => '以后收到的文件默认保存在这里；每次接收时仍然可以另选一个文件夹。';

  @override
  String get incomingFolderUnset => '每次接收时都会问你保存在哪里。';

  @override
  String get folderNotSaved => '未保存 —— 按回车，或点开别处，就会记下这个文件夹。';
}

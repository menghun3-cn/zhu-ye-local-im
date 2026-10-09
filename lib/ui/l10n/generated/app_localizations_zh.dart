// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '局域网传输';

  @override
  String get startupFailureTitle => '局域网传输无法启动';

  @override
  String get tabDevices => '设备';

  @override
  String get tabTransfers => '传输';

  @override
  String get tabClipboard => '剪贴板';

  @override
  String get tabSettings => '设置';

  @override
  String get notPairedYet => '还没有和任何设备配对';

  @override
  String failureUnreachable(String detail) {
    return '无法连接到该设备：$detail';
  }

  @override
  String failurePairing(String detail) {
    return '配对失败：$detail';
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
  String get refusalNotPaired => '本机还没有配对，不接受任何连接。';

  @override
  String refusalNoFreeFileName(String name) {
    return '在那个文件夹里已经找不到 \"$name\" 可用的名字了。';
  }

  @override
  String get kindText => '文本';

  @override
  String get kindFiles => '文件';

  @override
  String get kindClipboard => '剪贴板';

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
  String get notAcceptingSessions => '不接受连接';

  @override
  String onPort(int port) {
    return '端口 $port';
  }

  @override
  String get pairingCardPairedTitle => '再配对其他设备';

  @override
  String get pairingCardUnpairedTitle => '先配对，才能发送内容';

  @override
  String get pairingCardPairedBody =>
      '同一个设备组里的设备可以互相建立连接。配对就是把这台设备加进组里，也是共享剪贴板的前提。';

  @override
  String get pairingCardUnpairedBody =>
      '配对只做一次：在另一台设备上点本机旁边的「配对」，本机就会弹出请求；你点「接受」就完成了。之后互相发文件、发消息都不再需要任何操作。';

  @override
  String get acceptPairingRequests => '应答配对请求';

  @override
  String get pairingListening => '正在应答其他设备的配对请求';

  @override
  String get pairingNotListening => '不再应答配对请求';

  @override
  String get factPairingRequests => '配对请求';

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
  String get trustDevice => '信任这台设备';

  @override
  String get stopTrustingDevice => '不再信任这台设备';

  @override
  String get openSession => '建立连接';

  @override
  String get pairWithThisDevice => '与这台设备配对';

  @override
  String get nothingToDialYet => '暂时无法连接：还没有发现这台设备';

  @override
  String get nothingKnownAboutPeer => '不知道这台设备在哪里';

  @override
  String get pair => '配对';

  @override
  String get connect => '连接';

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
  String get whereShouldFilesLand => '这些文件保存到哪个文件夹？';

  @override
  String get whereShouldThisArrive => '保存到哪个文件夹？';

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
  String get clipboardPeersEmpty => '还没有已配对的设备；先在对话列表里配对，再回来勾选要共享剪贴板的设备。';

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
  String get noIdentityHint => '本机没有可保存身份的位置，因此身份只存在于内存中：功能可用，但每次重启后都需要重新配对。';

  @override
  String get factReceivedFiles => '接收的文件';

  @override
  String get noDefaultFolder => '没有默认文件夹';

  @override
  String get nothingWentWrong => '一切正常。';

  @override
  String get settingsAbout =>
      '局域网传输在你自己的设备之间，通过局域网传送文本、文件和剪贴板内容。没有服务器、没有账号、也没有云端：以上一切都只在本网络内。';

  @override
  String get aliasHelper => '其他设备上显示的名称';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get pairingRequestTitle => '配对请求';

  @override
  String pairingRequestFrom(String alias) {
    return '$alias 想与这台设备配对。';
  }

  @override
  String get pairingRequestUnnamed => '一台还没报上名字的设备';

  @override
  String get pairingRequestClaimHint =>
      '名字是对方自称的，本机无法核实。点「接受」就是把对方加入你的设备组，之后双方可以互相发送内容。';

  @override
  String get pairingCompleting => '正在完成配对…';

  @override
  String get acceptPairing => '接受';

  @override
  String connectToPeerTitle(String peer) {
    return '连接到 $peer';
  }

  @override
  String get reachingOtherDevice => '正在连接对方设备，等待对方点「接受」…';

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
  String get conversationEmpty => '还没有收发过内容。文字会直接送达，文件需要对方确认后才会接收。';

  @override
  String get messageHint => '输入要发送的文字';

  @override
  String get send => '发送';

  @override
  String get tabConversation => '对话';

  @override
  String get conversationListEmpty => '还没有对话。只要扫描到设备，它就会自动出现在这里，可以直接连接。';

  @override
  String get conversationPickOne => '从左边选一个对话，或者先连接一台设备。';

  @override
  String get conversationDisconnected => '连接已断开';

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
}

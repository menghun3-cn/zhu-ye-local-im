# Agent Note: The application is a plain-Dart layer, not a widget tree

Status: implemented

English | [中文](2026-09-30-app-layer-plain-dart-orchestration.zh.md)

## Problem

让产品运转的每一层都已存在——[设备发现](../../architecture/2026-09-29-lan-discovery-by-broadcast.md)、
[身份](../../architecture/2026-09-30-owner-identity-key-pair-and-device-profile.md)、
[配对](../../architecture/2026-09-30-pairing-by-typed-code.md)、
[Session](../../architecture/2026-09-30-link-manager-owns-the-sockets.md)、
[传输](../../architecture/2026-09-29-transfer-engine-over-a-session.md) 与
[剪贴板镜像](../../architecture/2026-09-29-clipboard-mirroring-within-an-owner-group.md)——
却没有任何东西把它们组合起来。`lib/main.dart` 只是一个写着「No devices discovered yet」的
占位页面，而唯一把两层接起来过的代码是测试套件，且每个测试只接自己用到的那一小部分。

于是缺了两样东西，其中第二样才是要害：

**1. 没有一条能跑通的流程。** 用户无法发现设备、无法配对、无法发送任何东西、也无法打开
剪贴板同步。把已有的零件按任何顺序摆一遍，都造不出一个可用的产品。

**2. 编排决策无处安放。** 设备什么时候开始接受 Session？一次发送该走哪条 Session？收到的
报价要不要自动应答？收到的文件落在哪里？这些都是决策而非管道，而在没有承载它们的层时，
每一条都会由最先需要它的那个界面临时决定——恰好决定在最难测试的地方。

是开发机决定了该先做哪一层。本机 `flutter test` 根本无法启动：运行器报
`Unable to connect to flutter_tester process: Invalid WebSocket upgrade request`，
因为这台主机上的零信任客户端剥掉了 loopback WebSocket 升级所需的逐跳头——这一发现记录在
[dart test 门禁笔记](../testing/2026-09-29-dart-test-as-the-core-gate.md) 里。
因此，一个长得像「界面」的第一步，会是一个在本机无法验证的步骤。

## Decision

**`lib/app` 是 `lib/core` 与 widget 树之间的新一层，而且是纯 Dart。**
`LocalTransferController` 持有 `DiscoveryService`、`PairingService`、`LinkManager`、
每条 Session 一个 `TransferEngine`，以及 `ClipboardMirror`，并回答一个用户界面会问的问题：
这台设备自称什么（[SelfView](../../../../lib/app/views.dart)）、周围有哪些设备
（[PeerView](../../../../lib/app/views.dart)）、正在传什么
（[TransferView](../../../../lib/app/views.dart)），以及启动各条流程的方法。

这条主张是被机器检查的，而不是口头声明：`test/app/plain_dart_test.dart` 会遍历
`lib/core` 与 `lib/app` 下每一个 `.dart` 文件，只要有谁 import 了 `package:flutter` 就失败。
它还会在扫描到的文件少于二十个时失败，这样一次搬错目录或写错根的 glob 无法让它以错误的
理由通过。

**平台接缝一律注入，从不自行创建。** 控制器接收 `ProfileStore`、`BeaconTransport` 与
`SystemClipboard`。App 传入真实的实现；测试传入内存实现，并在一个进程里通过真实的
`ServerSocket` 跑起两台完整设备。两者之间没有任何分支。

这一层持有的策略，按一台设备遇到它们的顺序：

- **只有持有群秘密之后才提供 Session。** 没有秘密就没有任何人能被它认证，因此它不绑定端口、
  也不宣告端口——未配对设备可见但不可拨号。让它可达的是配对，而不是启动 App。
- **每条 Session 一个 `TransferEngine`**，Session 建立时创建、丢失时关闭，剪贴板镜像在同一
  时刻挂接到同一条 Session 上。
- **应用从不代答报价。** 传入的传输会出现在 `incoming` 上，并出现在 `transfers` 里且带
  `offer` 字段；只有用户调用的 `acceptInto` 或 `reject` 才能让它落定。
- **收到的文件名是不可信输入。** `sanitiseIncomingName` 剥掉所有分隔符以及 Windows 会拒绝的
  字符，`incomingPathFor` 在重名时编号而**不**覆盖；唯一要紧的不变量——路径留在所选目录之内
  ——被直接断言。
- **发送要么有明确对象，要么被拒绝，绝不猜。** 只有一条 Session 时发送无需指定对端；有多条时，
  调用方会被告知要指名哪一台。
- **profile 变化会重建会话层。** 配对与改名都会改变这台设备宣告的内容，而对端锁定的内容里
  包含它曾宣告的描述符，所以一个新名字意味着新的 `LinkManager` 与全新的 Session。群秘密不受
  影响，因此改名之后不需要重新配对。

## Alternatives considered

**先做界面，让每个界面自己去组合各层。** 否决：编排恰恰是决策所在，这么做就是把每一条决策
放在无法测试的地方——而且本机上 widget 测试根本跑不起来，所以结果既不可验证又会重复。三个
界面会各自需要一份「这次发送到底走哪条 Session」的答案。

**把控制器放进 `lib/core`。** 否决：`lib/core` 的规则是「产品中不依赖 Flutter 的那一部分」，
这条规则两种放法下都仍然成立——但 core 的词汇是字节、Session 与 Owner，「用户选了哪台对端」
并不是一个协议事实。把 `lib/app` 分开，才能让那条缝保持诚实，而不是被稀释。

**让控制器一开始就建好 `LinkManager`，未配对时先用一个随机占位秘密。** 否决：那样它会绑定并
宣告一个监听端口，未配对设备于是在列表里显得可拨号，而每一次拨号都会握手失败。一个提供「连不
上的连接」的对端列表，比一个显示该设备暂不接受会话的列表更糟。

**对收藏（Favorite）对端的报价不提问、直接接受。** 暂予否决，尽管 profile 里已经有这个概念，
且 `DeviceProfile.canMirrorTo` 说明收藏本就是用来跳过逐次传输确认的。接受文件需要有地方存放，
而这一层里并没有下载目录——用一个对端提供的文件名悄悄发明一个，不是赢得这项权限的正确方式。
收藏这项授权已经存在于 profile 中但尚未使用，这是一笔有意留下的债。

**让 widget 树直接持有控制器的各个流**——每个字段一条流，谁想要谁订阅。否决：一条「有东西变了」
的粗粒度通知只触发一次重建，在调用点更省事且不会产生竞态；而 views 是廉价的值对象，界面可以
直接 diff。

## Consequences

- 整个应用可以被无头驱动、也可以被无头验收：`test/app/app_controller_test.dart` 在真实的
  loopback TCP 上跑 15 个用例——用输入码配对两台设备、双方确认、发现把彼此放到位、建立一条
  Session、一次文本传输在两侧落定为完成、一个 200 KiB 文件跨多个分片逐字节抵达、一次被拒的
  报价被回报给发送方，以及剪贴板在 `mirror` 下传递、在 `stage` 下等待、在 `off` 下什么都不做。
  `test/app` 合计 28 个用例；全套测试从 313 增至 341。
- 逐笔读取 `Transfer.updates` 是让进度可见的手段；每个订阅都在其传输落定时被取消，所以长期
  运行的应用不会按传输数量累积订阅。
- 这一层遇到的两个运行期故障值得点名，因为两者都不是编译错误。流的 `onError` 必须接受
  `Object`，所以传一个 `void Function(String)` 只在真有错误到达时才抛。以及
  `Fingerprint`/描述符只有在相应类型声明了按值比较时才按值比较——这正是本层比较自己构造的
  键的原因。
- 改名会付出所有已打开 Session 的代价。这是「对端锁定了什么」的诚实后果，不是疏漏；也正因
  如此，界面里无法在一条 Session 内部修改别名。
- 本次改动不含任何 widget：`lib/main.dart` 仍然启动到占位页面。界面所需的那一层现在已经就位，
  界面是下一步的改动。

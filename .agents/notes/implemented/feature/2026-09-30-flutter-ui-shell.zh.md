# Agent Note: The application has a screen

Status: implemented

[English](2026-09-30-flutter-ui-shell.md) | 中文

## Problem

产品的每一层都能工作，却没有一层能被触达。`lib/main.dart` 是一句占位的
“No devices discovered yet”，而那个把设备发现、配对、Session、传输与剪贴板镜像
组装起来的[应用层](2026-09-30-app-layer-plain-dart-orchestration.md) —— 一个已
经有 15 个用例跑在真实 loopback TCP 上的层 —— 在应用内部没有任何调用者。用户无
法配对设备、无法发送文件、无法打开剪贴板同步：这个产品是一个前面摆着窗口的测试
套件。

两个约束决定了这个界面能是什么样。第一，这台机器上 `flutter test` 根本起不来
（零信任客户端会剥掉 loopback WebSocket 升级所需的头），所以任何值得测试的东西
都不能写在 widget 里。第二，这个项目不发布任何插件，于是桌面应用通常从插件拿的三
样东西 —— 文件选择器、剪贴板变更通知、Android 上的应用数据目录 —— 只能用 Dart
与平台通道已有的能力自己搭出来，或者干脆不做并把这件事说清楚。

## Decision

**`lib/ui` 是 `LocalTransferController` 的一次渲染，本身不持有任何协议状态。**
它调用 controller，并画出 controller 报告的内容；四个界面是设备、传输、剪贴板
与设置，每一个都是在应用层已经产出的视图对象之上的一个 `ListView`。

把它撑起来的东西：

- **`LocalTransferApp`** 在 `openPlatformSeams` 解析出的接缝之上创建 controller
  并调用 `start()`。这一步失败会得到一个写着原因的页面，而绝不会是第一帧之前
  的一串堆栈：一个“看起来在工作”的窗口是唯一不能出现的结果。
- **`ControllerScope`** —— 一个包着 controller 的 `InheritedWidget`，由 controller
  那个粗粒度的 `changes` 信号触发重建 —— 是页面触达应用层的唯一方式。每次变
  化在根部重建一次，页面没有订阅可泄漏，也没有逐字段的流让两个 widget 去抢。
- **`HomeShell`** 把四个界面放在窗口够宽时的 `NavigationRail` 或不够宽时的
  `NavigationBar` 上，并给等待答复的传输加一个角标 —— 那是唯一值得打断的事。
- **`FlutterSystemClipboard`** 用 Flutter 的 `Clipboard` 读写，靠轮询来监听：
  剪贴板变更通知需要这个项目在没有插件时开不出来的原生窗口。轮询循环是
  `lib/core` 里的 `PollingClipboardWatcher`，因此它报告什么、忽略什么、什么时候
  停下，全部由 `dart test` 覆盖。
- **身份文件放在哪里** 由 `lib/core` 里的平台事实决定（`profileFilePath`）：
  Windows 上是 `%APPDATA%\LocalTransfer`，Android 上是通过本项目在
  `MainActivity.kt` 里实现的通道拿到的应用私有目录；而当没有可持久写入的位置时
  返回 null —— 在内存里运行、身份只活到应用退出，并在设置界面上说明这一点。
  `defaultIncomingDirectory` 同一形状：Windows 是下载目录，Android 是应用自己的
  目录。
- **手动地址可达**，为此新增了一个应用层调用：
  `LocalTransferController.connectTo({address, port})`。它拨号时不钉住
  Fingerprint，因为用户敲的是一个地址而不是选中了一台设备。握手仍然证明对端持有
  群秘密，来自另一个 Owner Group 的设备仍然会被拒绝。
- **无论本机是否已在某个群中，配对都可发起。** 加入第三台设备是配对服务支持的
  流程 —— 持有秘密的设备会把该秘密交出去，来自两个不同群的设备会被拒绝 —— 所以
  界面不把它藏在“首次运行”状态后面。
- **Android 的 `INTERNET` 权限声明在主 manifest 里。** Flutter 模板只把它放在
  debug manifest 里供工具自身使用；缺了它，release 包一个 socket 都开不出来，
  而整个产品就是一堆 socket。

各界面展示什么，按用户遇到的顺序：设备界面展示本机对自己的说法、配对的两个方向、
以及带“连接 / 发送 / 信任”的对端列表；传输界面展示每一笔传输及其进度，并为待答复
的报价给出一个落地文件夹；剪贴板界面展示模式 —— 平台无法兑现的模式会被显示并置
灰，而不是隐藏 —— 等待应用的条目，以及已经应用过的内容；设置界面展示身份、完整的
Fingerprint、身份文件的位置，以及下层报告上来的提示。

## Alternatives considered

**两个平台各自的原生文件选择器。** 本次否决。选择器要么是插件 —— 本项目不发布
插件 —— 要么是两份这台机器无法验证的原生实现：Android 上一个 intent 加
`onActivityResult`，Windows 上在 C++ runner 里调 `GetOpenFileName`。因此发送文件
走输入路径的方式（手敲或粘贴），对话框说明原因，而不是摆一个按了没反应的“浏览”
按钮。

**引入路由，每个流程一个页面。** 否决。整个应用就是四个界面加三个对话框；路由表
会变成第五个需要与 controller 状态保持同步的东西，而没有任何收益 —— 决定哪个页
面才对的状态本来就在 controller 里，而且它本来就会重建整棵树。

**把 widget 放在 controller 旁边，即 `lib/app` 里。** 否决；这条边界有自己的决策
记录，见[把 Flutter 限制在 `lib/ui` 的笔记](../architecture/2026-09-30-flutter-confined-to-lib-ui.md)。

**隐藏平台无法兑现的剪贴板模式。** 否决：“这里为什么不能镜像”是界面应该回答的问
题，方式是显示该模式、置灰它，并在旁边写出平台层面的原因。

**对 Favorite 自动答复报价。** 否决，与下一层一致。接受一笔传输需要落地文件夹，
而一台用对端提供的名字凭空造出文件夹的设备，是在花用户从未给出的授权。信任开关已
经在对端列表上，目前不对任何东西生效 —— 这是有意留下的欠账。

**让每个页面各自订阅它需要的流。** 除一种情况外否决：剪贴板界面记着镜像最近应用
的二十条，因为那是一次回看、且只有界面关心它。其余一切都从重建后的视图里读取，这
正是重建一开始就设计成粗粒度的原因。

## Consequences

- `dart test` 共 366 个用例，其中 25 个由本次改动带来：轮询监听器（5）、身份文件
  与下载目录的去向（8）、视图与格式化辅助函数（7）、真实 loopback TCP 上的手动
  地址（3），以及强制 `lib/ui` 边界的两个用例。`flutter analyze` 无任何问题，
  `flutter build windows --debug` 链接出了 `local_transfer.exe`。
- **这里没有验证的东西，也不应当被读作已验证。** 没有跑过 widget 测试：这台机器
  上 `flutter test` 起不来，所以 widget 树由静态分析和一次构建覆盖，而不是由驱动
  它来覆盖。窗口没有被打开过，因此“第一帧能渲染”尚未被证明。Android 通道是未经验
  证的代码 —— 本次会话没有尝试 Android 构建 —— 而其 Dart 一侧写成在通道缺失时退
  化为“无处可写”。
- 有意留下并已点名的缺口：没有文件选择器；无法“忘记”一台设备（那需要核心层目前
  没有的 Owner Group 操作）；Android 上收到的文件落在应用自己的目录里，而不是下载
  目录或相册，那需要一步 media-store；`ACCESS_LOCAL_NETWORK` 未声明也未申请，
  而 Android 17 会要求它（事实见
  [docs/android-background-constraints.md](../../../../docs/android-background-constraints.md)）。
- 设备发现用的 socket 在第一帧之前就绑定，并且只在进程结束时才释放，因此同一台主
  机上开第二份应用会看到失败页面而不是应用本身。这是对一个众所周知的广播端口的诚
  实呈现；把发现端口改成每实例一个，才是消除它的那步改动。
- 改名仍会终止所有已打开的 Session —— 这是下一层的决定，这个界面继承了它：改名入
  口放在设备界面上，在那里这个代价是看得见的，而不是放在 Session 里面让它看不见。

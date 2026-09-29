# Agent Note: Find peers by UDP broadcast, unauthenticated and subnet-local

Status: implemented

[English](2026-09-29-lan-discovery-by-broadcast.md) | 中文

## Problem

两台 Device 在能传任何东西之前，得先找到彼此；而这个产品没有服务端、没有账号、没有云端、也不要求用户配置。于是发现必须能在一条没人描述过的链路上冷启动：没有会合主机可问，没有主机名可解析，也没有用户愿意手输的东西。

三条平台事实约束了机制的选择，都记在本仓库的平台笔记里：

- **Android 17（API 37）默认阻断本地网络访问**，需要 `ACCESS_LOCAL_NETWORK` 运行时权限。Dart socket 无法弹出权限对话框，因此缺权限时任何 socket 使用都会以 `SocketException` 失败（见 `docs/android-background-constraints.md`）。
- **在 Android 上接收多播需要 `WifiManager.MulticastLock`** 加 `CHANGE_WIFI_MULTICAST_STATE`。那是平台 API，而本项目不引入任何插件 —— 开发机甚至构建不了插件，因为非管理员会话建不出 Flutter 插件机制所需的符号链接。
- `InterfaceAddress.broadcast` 能在不需要用户提供掩码的前提下，按接口给出定向广播地址（见 `docs/dart-networking-capabilities.md`）。

还有一条安全约束塑造了整个设计：发现发生在任何信任建立**之前**。它携带什么，就等于告诉链路上的所有人什么。

## Decision

发现机制是固定端口上的 UDP 广播，位于 `lib/core/discovery/`：

- `beacon.dart` —— 数据报格式：`{v, k, n, device}`，其中 `v` 是 `beaconVersion`（1），`k` 为 `probe` 或 `announce`，`n` 是每台 Device 各有其随机值的 Nonce，`device` 就是握手所携带的同一个 `DeviceDescriptor`。
- `peer_registry.dart` —— 以 Fingerprint 为键、带 TTL 的对等表。
- `beacon_transport.dart` —— 接缝，以及测试用的内存集线器。
- `udp_beacon_transport.dart` —— 真实 socket，绑定 `discoveryPort`（47654）并开启 `broadcastEnabled`。
- `discovery_service.dart` —— 策略：启动即 probe、每三秒 announce、收到 probe 直接作答、十秒无音信即过期。

线上刻意**不做认证**。任何主机都能发信标、任何主机都能读信标；信标的任何内容都不构成对其发送者的证明。它是存在性通告，不是身份。

## What a beacon carries, and what it must never carry

信标只携带陌生人本就能靠观察链路推断出来的东西：某台 Device 存在、它自称什么、什么平台、剪贴板能力如何、以及该去哪个 TCP 端口开 Session。它**不携带 Pairing Secret、不携带 Owner 身份，也不携带由二者派生的任何东西** —— 这些只在能证明持有 secret 的握手之内离开 Device。有测试断言编码后的键集合，并断言其中不出现任何形似密钥的字符串，于是这条边界是被钉住的，而不是靠自觉。

随之而来的后果要记牢：**存在不等于信任。** 列表里出现一个对端，只意味着那里有东西，不意味着它是「我们的人」。在握手成功且用户比对过 SAS 之前，列表里每一台 Device 都是陌生人。UI 不得模糊这条界线。

## Why broadcast, not multicast

多播是教科书答案，而且**如果**发现需要跨子网，它就是正确答案。这一版不需要，而多播在 Android 上要付出一把这个项目不引入插件就拿不到的平台锁。它还意味着要挑选、记录并长期维护一个组播地址 —— 一项持久的线上承诺 —— 来换取这一版并不需要的可达性。

按接口的定向广播加上受限广播，无需配置、无需 Android 17 之外的新权限，就能触达本地链路的所有 Device。两者都发：有些 AP 只转发其中一种，而重复的代价只是每个通告多一个小数据报。

## The seam

`BeaconTransport`（`received`、`send`、`broadcast`、`close`）与 `ByteTransport` 同构，理由也一样：上文的策略既能跑在真实 socket 上、也能纯内存运行，而代码路径毫无差异。其中两点是刻意为之：

- **解不开的数据报被丢弃，而不是作为错误向上传播。** 陌生人随时可以发畸形包；为一个坏包把接收循环搞停，等于把一个骚扰升级为对发现的拒绝服务，而上面那层根本无能为力。畸形输入的拒绝点是 `Beacon.decode`，它也为此被直接测试。
- **内存传输会丢弃无人监听时到达的数据报**，而不是缓冲。尚未启动的 Device 还不在链路上，而「这台 Device 到底听没听到？」必须只有一个答案，否则测试的先后顺序就变成了偶然。真实 socket 会缓冲；差异在传输层，而被测的是策略层。

## Alternatives considered

**多播，mDNS 那一套。** 常规的局域网发现机制，也是 LocalSend 自己发现所用的方式。本版否决理由：在 Android 上需要 `WifiManager.MulticastLock`，不引入插件就够不到；而它的主要优势 —— 配合反射器时能跨子网 —— 不是本版要解决的问题。

**DNS-SD/mDNS 插件（`nsd`、`bonsoir`、`multicast_dns`）。** 可以白得服务注册与浏览，且用平台原生实现。否决理由：引入第一个含 Windows 实现的插件，被一个已知的机器限制卡住（非管理员会话建不出 Flutter 所需的符号链接）；而且它会把可达性交给一个原生库而不是 `dart:io`，与「核心层保持纯 Dart、可无头测试」的决定相冲突。

**让用户输地址 —— 手打 IP，或扫一个带地址的二维码。** 实现起来微不足道，也完全不需要发现协议。否决理由（作为**唯一**机制）：它让常见情形退化为手工操作，而且根本回答不了「谁在这儿？」。作为**兜底**并未否决 —— 配对本来就用二维码承载 secret，所以让二维码顺带承载地址，是广播被过滤的网络里顺理成章的后续补充。

**子网扫描 —— 对前缀内每个地址做 TCP connect。** 只用 `InterfaceAddress.prefixLength`，不需要任何新协议，还能发现屏蔽广播的设备。否决理由（作为唯一机制）：一个 `/24` 每轮刷新就是 254 次连接尝试，慢，而且在任何网络监控看来都像扫描，且同样需要那条 Android 权限。

**把信标放到 TCP 监听端口上。** 只开一个端口、只配一条防火墙。否决理由：不接受 Session 的 Device 同样希望自己是可见的 —— 一台只能被应用剪贴板的 Device 也应当可被发现 —— 而 TCP 监听加 UDP 监听正是为此而生的常规拆分。

**云端或局域网会合服务。** 能一举解决跨子网发现。否决理由：本产品的立身之本就是无服务端、无账号、无云端。把它记在这里，因为它是那条诱人的捷径，也是「跨子网发现是一等目标」会不断招来的那个替代方案。

## Consequences

- 发现只回答「这条链路上有谁」，仅此而已。跨子网发现 —— 本产品存在的两个理由之一（见 [build-from-scratch-not-fork-localsend](2026-09-29-build-from-scratch-not-fork-localsend.zh.md)）—— **尚未实现**。广播不跨路由器边界，因此一台连在蜂窝邻近 Wi-Fi 上的手机和一台接以太网的笔记本互相看不见。这是被点名的缺口，不是疏漏。
- 信标是一种线上格式，因而现在带版本（`beaconVersion`）。未知版本被直接拒绝，而不是被半懂不懂地解析，于是未来对发现的改动不可能与这一版静默互通。
- 链路上每台 Device 都能看到其他每台 Device 的 Alias 与平台，并且可以伪造其中任何一项。这是无认证发现的固有性质；应对方式不是让发现变得可信，而是让它保持不可信 —— UI 的职责，是在 SAS 比对确认之前，一直把对端显示为未验证。
- Android 还差两块本增量未做的平台层工作：在任何 socket 打开前请求 `ACCESS_LOCAL_NETWORK` 权限；以及决定发现是否只在前台运行。两者都属于 Android 层，且都是「发现在 Android 上能否工作」的前置条件。
- 广播天性话多：每台 Device 每三秒一个小数据报，且进程每次启动都要从零重建对等表。这就是没有服务端要付的代价。

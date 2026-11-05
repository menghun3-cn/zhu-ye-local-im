# Agent Note: 从会话搜索按 IP 连接

Status: implemented

[English](2026-11-05-connect-by-ip-from-conversation-search.md) | 中文

## Problem

广播发现无法覆盖所有仍在同一局域网里的设备：对端可能在广播到不了的子网、被 AP
过滤广播的网络里，或者只是错过了 announce 窗口。设备页已有“按地址连接”，但它直接
拨会话端口，因此只适用于已经在 Owner Group 内的设备。真正用来开始对话的会话页
却没有任何填写地址的入口。

## Decision

会话搜索框在清除按钮旁固定一个 `+` 操作，打开只填写一个 IP 地址的对话框，并调用
`LocalTransferController.connectByAddress`。

`connectByAddress` 把输入的地址当作“去哪里找”，而不是身份证明。它先复用该地址上
已有的 Discovery 记录；没有时调用 `DiscoveryService.probeHost`，向固定 Discovery
端口发送单播探测并等待匹配的 announce。应答仍是普通 `DiscoveredPeer`：Fingerprint
和端口在握手证明之前都只是对端自述。

信任判断不变。已在 Owner Group 内且广播了会话端口的对端，会用 `expectedFingerprint`
固定为探测到的设备后拨号。组外设备必须完成与广播发现相同的开放配对，之后由
`connectAfterPairing` 建立会话。无人应答的探测，或既没有配对端口也没有可用会话端口
的设备，会被拒绝，而不是盲拨。

`LocalTransferController` 保留 `addressProbe` 测试缝：生产路径使用
`DiscoveryService.probeHost`，测试则可以不模拟所有广播域就回答这次单播探测。
设备页的手动地址对话框不变，仍是已知会话端口的高级入口。

## Alternatives considered

**在搜索 `+` 上复用 `connectTo`。** 否决：`connectTo` 直接拨会话端口、没有先探测，
因此无法得知未配对设备的配对端口，也不能先配对。它对设备页仍然正确，因为那里预期
用户知道端口。

**再广播一次探测并按地址过滤。** 否决：用户已经回答了“在哪里”。单播探测直接到达
输入的地址，能跨过促成此功能的广播边界，也不会让链路上每台设备都回答一个只问了
其中一台的问题。

**探测后盲拨配对端口。** 否决：探测已经返回了对端广播的端口。信任仍来自配对握手，
但没有理由去猜一个设备刚刚宣布过的端口。

**让输入的地址直接准入设备。** 否决：地址是不可信输入。成员关系仍要求 Owner Group
密钥，会话仍要求对端证明它知道该密钥；只应答探测却无法完成配对或会话握手的陌生
设备会被拒绝。

## Consequences

- 用户可以在会话搜索框输入 IP 开始对话，包括自动发现没有放置的设备。
- 同一条单播探测路径也能配对那些 unicast TCP/UDP 可达、但广播发现看不到的设备。
- 手动 IP 不是后门：它执行 Discovery，然后沿用与自动连接相同的已认证配对和会话规则。
- `DiscoveryService.probeHost` 发送一次探测并等待匹配 announce；该 announce 与其他
  目击一样被记录，因此对端进入正常设备列表。
- `test/discovery/discovery_service_test.dart` 覆盖单播探测应答，
  `test/app/app_controller_test.dart` 覆盖非法输入、无人应答、同组拨号以及按 IP
  先配对再建会话。
- `test_flutter/ui/pages_test.dart` 覆盖 `+` 操作和非法 IP 拒绝。

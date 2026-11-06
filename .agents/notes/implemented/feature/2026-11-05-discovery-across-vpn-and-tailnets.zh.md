# Agent Note: 通过单播探测跨越 VPN 与 tailnet 的发现

Status: implemented

[English](2026-11-05-discovery-across-vpn-and-tailnets.md) | 中文

## Problem

[基于广播的发现](../../implemented/architecture/2026-09-29-lan-discovery-by-broadcast.zh.md)
回答的是「谁在这条链路上」，仅此而已：beacon 是广播报文，广播在第一个路由
边界就停下了。两台被 VPN 或 Tailscale tailnet 连在一起的 Device，在用户看来
属于同一个私有网络，在协议看来却分属不同的广播域，因此互相看不见。那篇笔记
里记录的 named gap——跨子网发现——正是本次改动要解决的，且不引入服务端、账
号或云端汇合点。

三件事让这个问题无需新基础设施即可解：

- 单播 UDP 报文能跨过广播到不了的任何边界，前提是发送方知道一个地址。
  `DiscoveryService.probeHost` 已经验证过这条回路：探测一个地址，收到它的
  announce。
- 本机遇到过的 Device 已经存下了它被到达时的地址——`KnownDevice.lastAddress`，
  当初就是为「不经 Discovery 的重拨」保留的。
- tailscaled 把对端表暴露在回环 local API 上，同一 tailnet 里每台 Device 的
  地址都能在无配置的情况下读到。

## Decision

发现机制在广播之外增加了第二条单播探测路径，都在 `lib/core/discovery/`：

- `DiscoveryService` 接受可选的 `unicastTargets` 提供者——一个
  `Future<List<InternetAddress>> Function()`——并每 `unicastProbeInterval`
  （五秒，刻意短于十秒的 peer TTL，保证只靠单播被发现的 peer 不会在两轮之间
  过期）向返回的每个地址发一次探测。目标去重、每轮上限
  `maxUnicastTargets`。提供者抛错会被忽略，广播路径不受影响。
- `TailscaleDirectory`（`tailscale_directory.dart`）最多每三十秒轮询一次
  `GET http://127.0.0.1:41112/localapi/v0/status`，返回 `Peer` 表中在线
  节点的 `TailscaleIPs`，仅取 IPv4。请求走回环、默认安装下无需凭据、两秒
  超时；所有失败形态——没有守护进程、非 200、报文无法解析——都等价于
  「没有 tailnet」，且上一次成功的结果会跨过短暂抖动保留。
- `LocalTransferController` 负责提供目标列表：所有 `KnownDevice.lastAddress`
  与 `TailscaleDirectory` 报告的全部地址之并集。下游完全不变——隧道上应答
  的 announce 就是一个普通的 `DiscoveredPeer`，后续交给现有的自动 Pairing
  与 Session 机制。

`PeerRegistry` 现在记录 peer 被听到过的**每一个地址**及其各自的时间戳，而不
再只留最近一次。既走 LAN 又走 VPN 可达的 Device 会在每条链路上各被听到一次；
每个 sighting 独立老化，因此 peer 会收敛到仍然应答的地址，而不是在每次
announce 时于两个地址之间来回翻转。`DiscoveredPeer.address` 保留——它是最新
的 sighting——`DiscoveredPeer.addresses` 携带完整集合。事件只在地址**集合**
变化时触发，而不是最新地址易主时，因此双归属的 peer 不会每隔几秒就推一次
变更。

beacon 格式不变（`beaconVersion` 仍为 1）：单播只是传输层差异，不是协议差异。

## Alternatives considered

**子网扫描——探测每个接口前缀里的所有地址。** 否决理由与广播笔记中否决它
作为唯一机制时相同，而且在这里更糟：Tailscale 地址位于
`100.64.0.0/10`，规模根本无法扫描；对任何 VPN 前缀的扫描在沿途每个防火墙
看来都像扫描流量。对模拟局域网的子网型 VPN，子网定向广播已经覆盖；点对点
链路根本没有可发送的广播地址。

**组播或 mDNS。** 再次否决，理由沿用已记录的：组播在 Android 上需要本项目
无法在不发布插件的情况下获得的 MulticastLock，而且组播与组播广播都跨不过
Tailscale 或点对点 VPN。

**云端或局域网汇合服务。** 依然否决：产品定位是无服务端、无账号、无云端。
本次改动刻意是同一思路的无汇合版本——tailnet 自己的目录和本机自己的记忆就
是汇合点。

**以子进程方式调用 `tailscale status`。** 否决：每次刷新都拉起进程比一次
回环 HTTP 请求更重、更脆弱，而 local API 才是文档化的机器接口。CLI 仍可
作为 local API 缺失平台的备选，但 Android 的 Tailscale 应用两者都不暴露，
在那里它也换不来任何东西。

**持久化 peer 曾经出现过的全部地址。** 考虑过并部分否决：
`KnownDevice.lastAddress` 保持单值，因为 profile 记录的是 Device 上次被**到
达**的位置，而多地址的实时事实已经由 `PeerRegistry` 承载。永远记住过期地址
会无限期探测死端点；tailnet 目录和新鲜会话足以让目标列表保持诚实。

## Consequences

- 同一 tailnet 上的两台 Device 在双方都运行本版本时无需任何配置即可互相发
  现——包括冷启动，因为 Tailscale 目录不需要任何先前接触。只要相遇过一次
  的 Device 还能在任何单播可达的网络（不限于 VPN）上通过记住的地址重新发
  现彼此。
- 该功能按设计是非对称的：只有运行本版本的一侧会发起探测。旧版本的 peer
  同样受益——它的 beacon 套接字会应答单播探测、从报文源地址记下探测方的
  隧道地址，而它普通的 announce 应答会完成整个交换。
- 在 Android 上 Tailscale 应用不暴露 local API，因此那里的
  `TailscaleDirectory` 恒为空；记住的地址仍然有效，也就是说 Android Device
  只有在与对端相遇过一次（手动地址、二维码或同一 LAN）之后才能在 tailnet
  上发现它。
- 在两条链路上都被听到的 peer 持有两个 sighting。拨号仍使用最新鲜的地址；
  某条链路断开时其 sighting 按普通 TTL 过期，peer 会收敛回可达地址，不需要
  任何专门的故障转移逻辑。
- 单播探测是发往目录或记忆所指地址的未认证 beacon——与广播同样的信任姿态：
  存在不等于可信，每个 peer 在握手证明之前都是陌生人。
- 一个拥有大量 peer 的 tailnet 每五秒一轮最多产生 `maxUnicastTargets` 个
  小报文——有上界，远低于任何网络监控会标记的流量。
- `test/discovery/peer_registry_test.dart` 覆盖多地址 sighting 与逐地址
  过期；`test/discovery/discovery_service_test.dart` 覆盖单播节奏、去重、
  每轮上限、提供者失败与应答式探测；
  `test/discovery/tailscale_directory_test.dart` 覆盖状态解析、缓存与失败
  容忍。

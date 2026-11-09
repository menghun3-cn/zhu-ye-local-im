# Agent Note: 分享链接使用对端可达的地址

Status: implemented

[English](2026-11-09-share-link-picks-a-reachable-address.md) | 中文

## Problem

`LinkTransferServer._getLocalIp` 返回的是 `NetworkInterface.list` 枚举到的
第一个非 loopback IPv4 地址。在同时存在多个网卡的机器上——路由器局域网加
VPN 或 tailnet，再加上虚拟化软件和容器附带的虚拟网卡——排在第一个的地址
和「对端真正能到达的那块网卡」一样可能属于任何一个，于是生成的
`http://<ip>:<port>/download/<token>` 链接一开始就是死链。

## Decision

选择逻辑移入一个可独立测试的纯函数
`lib/core/link_transfer/share_address.dart` 里的 `chooseShareAddress`，
输入有二：本机候选地址（地址加网卡名）和最近从各 Device 处听到的地址。

存在对端地址时，胜出者是与其中任意一个前缀重合最长的本机地址——对端
自己的地址说明了收件人在哪条链路上，因此路由器局域网场景和 Tailscale
场景是同一条规则。匹配要求至少共享一个首字节；低于此值的「匹配」只是
巧合。打平时回落到下面的排序。

没有可用的对端提示时——还没有发现任何设备，或只剩过期记录——排序偏好
局域网收件人有理由够到的地址：link-local 与 loopback 直接排除，RFC1918
私网段优先于运营商级 NAT（Tailscale 使用的 100.64.0.0/10）和其他公网
地址段；网卡名看起来像虚拟适配器的——`vEthernet`、VPN 客户端、
`tun`/`tap`/`ppp`、WSL、Docker、VMware、VirtualBox、Hyper-V、蜂窝网络
——排在物理网卡之后。最后的决胜是地址本身，因此结果不依赖枚举顺序。

提示来自 `LocalTransferController.discoveredPeers`——一个新 getter，
原样暴露 Discovery 的对等列表，不做合并；`peers` 会混入 Owner Group、
Known Devices 和在线 Session，这些都说明不了收件人在哪条链路上。两处
分享链接入口（`ShareByLinkPage` 和会话菜单里的 `shareByLink`）都通过
`shareAddressHints` 把每个 sighting 按新鲜度排序后拍平，作为
`peerAddresses` 传给 `LinkTransfer.createLink`。

## Consequences

- 在 `192.168.x.x` 被听到的对端会拿到本机 `192.168.x.x` 地址的链接，
  即使 Tailscale 或虚拟化网卡排在枚举最前；在 `100.x` tailnet 地址被
  听到的对端拿到的是 tailnet 地址。
- 完全没有对端时，链接优先选择物理 RFC1918 网卡而非 VPN、WSL 等虚拟
  适配器——正是 bug 报告描述的常见情形。
- 只有 VPN 地址的机器依然能为 tailnet 收件人生成可用链接：排序是降级，
  不是排除。
- 选择是按链路而非按对端的：当对端同时分处两张互不相通的网上时，前缀
  重合最长者胜出，另一张网的收件人拿到的链接可能不可达。一个 URL 无法
  同时写两个地址；对端最新的 sighting 让选择偏向正在使用的那条链路。

## Alternatives considered

**让操作系统判断到某对端走哪个接口（UDP connect 技巧）。** 否决：
`RawDatagramSocket` 没有 `connect`，而向对端会话端口发起 TCP 探测会建
立一条 Session 层必须察觉并丢弃的真实连接。前缀匹配用 Discovery 已有的
数据回答同一个问题，不产生流量也没有副作用。

**为每个本机地址各生成一条链接。** 暂不采用：它能彻底解决多网络歧义，
但会让 UI 面翻倍——分享页要列多条链接、菜单要复制其中一条——而为一个
罕见场景（对端同时分处两张互不相通的网）付出这个代价不值。hints 机制
给将来留了口子。

**保留首地址规则，只跳过已知的虚拟网卡名。** 否决：只靠名字无法区分
需要 `100.x` 地址的 Tailscale 收件人和局域网收件人，而且所有网卡都是
虚拟时它无能为力。它只作为兜底排序的最后决胜输入保留。

**通过平台通道读取默认路由接口。** 否决：默认路由指向面向互联网的网
卡，说明不了某个收件人在哪个私网里，而且要在两个平台上各加一条平台通
道，得到的答案反而更弱。

## Testing

`test/link_transfer/share_address_test.dart` 覆盖纯函数：局域网对端胜过
VPN 与虚拟化候选、tailnet 对端选中 tailnet 地址、不可用提示被忽略、无
对端时兜底偏好物理私网接口、只有 VPN 地址的机器仍能作答、打平结果确定。
`_getLocalIp` 里 `dart:io` 的枚举只是它的薄适配层；HTTP 服务路径未改动。

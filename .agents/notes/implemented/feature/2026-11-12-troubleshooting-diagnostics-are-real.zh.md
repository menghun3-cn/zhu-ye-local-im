# Agent Note: 故障排查页给出真实结果，并能自己放开防火墙

Status: implemented

[English](2026-11-12-troubleshooting-diagnostics-are-real.md) | 中文

## Problem

故障排查页的每一行都渲染着字面量 `unknown`——硬编码的英文状态串，展示给
以中文用户为主的用户群，什么也回答不了。这个页面是个占位符，看起来像诊断，
实际不是。

它的四个问题里有两个不需要任何新平台代码就能回答：各监听器实际绑定在哪些
端口（controller 已经暴露），以及 Windows 防火墙有没有覆盖对端所需端口的
入站放行规则。第三个——「直接让应用通过防火墙」——是自然的后续动作，也是
Windows 坚持要 UAC 弹窗的那一处。

## Decision

四项诊断现在都报告真实状态，判定逻辑放在 `lib/core`，让 `dart test` 覆盖，
平台侧只剩进程调用：

* **端口**——对 controller 报告的实际端口（`listenPort`、`pairingPort`）做
  纯函数判定。绑定在默认端口上是 `ok`，退到备用端口是 `warning`（Discovery
  仍能找到这台设备；按裸地址拨 47655 则不行），Session 无监听是 `error`，
  Pairing 无监听是 `warning`——与 controller 自身把缺失的 Pairing 监听视为
  「降级」而非「损坏」的态度一致。UDP 发现端口不需要探测：绑不上 47654 的
  设备根本走不到这个页面。
* **网络**——非回环 IPv4 接口计数；为零即 `error`。
* **VPN**——接口名匹配隧道/VPN 特征词（`tap`、`tun`、`wireguard`、
  `openvpn`、`ppp`、`vpn` 等）。`tailscale` 故意不在其中：本应用对
  Tailscale 有一等支持，它的适配器是特性而非干扰。结果是带适配器名的
  `warning`，因为名字启发式永远只能是提示。
* **防火墙**——一次 PowerShell 查询（`Get-NetFirewallRule` 加端口与程序
  过滤器、当前 `NetworkCategory`、profile 的 `Enabled`），无需提权即可
  读取，输出 JSON 解析。一个端口只有在同时满足以下条件时才算被覆盖：存在
  一条已启用的入站允许规则，协议、端口匹配，且规则要么不限定程序、要么
  限定于 `Platform.resolvedExecutable`，并且其 profile 与当前网络类别
  匹配。程序作用域是最容易判错的部分：Windows 自己的「允许此应用」弹窗
  写的正是按程序限定的规则，只看端口会把「其实挡着本应用」的防火墙误判成
  「已放行」。

「放开防火墙端口」按钮只在 Windows 显示，位于它所对应的端口检查项旁边，
并且在探测报告 `blocked` 之前保持禁用——端口已放行或问题无从判定时，
它没有可做的事。它不可能无声完成——加规则需要
管理员——所以一次点击收集一次 UAC 授权，然后执行两条 `New-NetFirewallRule`，
都用 `-Program` 限定到当前可执行文件：TCP `47655,47656` 与 UDP `47654`。
提权的那半段以 `-EncodedCommand`（UTF-16LE 的 Base64，在 Dart 侧编码，因为
`dart:convert` 没有 UTF-16 编解码器）传给 PowerShell，而不是嵌套引号参数——
这是唯一能完好穿过 `Start-Process -ArgumentList` 的编码方式。每次执行先
删除名为 `LocalTransfer` / `LocalTransfer Discovery` 的旧规则，因此应用
挪了位置后重跑是更新规则而不是留下过期规则。退出码映射为已添加 / 已取消
（拒绝 UAC）/ 失败，页面随后无论哪种结果都会重新探测。

所有状态词与明细行都是本地化字符串；旧代码把英文单词 `unknown` 直接画在
界面上，这正是页面读起来「翻译了一半」的原因。

## Consequences

* `lib/core/diagnostics/troubleshooting.dart` 是纯 Dart，带两个缝：
  `ProcessRunner` 负责 PowerShell 调用，接口枚举负责网络检查。解析与判定
  逻辑由 `test/diagnostics/troubleshooting_test.dart` 完整覆盖。
* 探测要枚举所有已启用的入站允许规则，每条规则一次 CIM 查询——规则多的
  机器上会花一点时间。它每次进页面跑一次、按需再跑，正好是诊断页的节奏。
* 防火墙判定的准确度取决于规则数据：第三方防火墙、探测后新增的规则、或
  Windows 防火墙之外的过滤，都会读成「已放行」或「未知」而非确定结论。
  代码里把这条启发式写明了。
* 添加的规则按程序限定、profile 不限（`Profile` 保持默认 `Any`），所以在
  Public 网络下同样生效——这是有意为之：否则这个功能在最需要它的网络上
  会静默失效。
* Android 显示端口、网络、VPN 三行，隐藏防火墙按钮；防火墙行本身报
  `unsupported`。

## Alternatives considered

**绑定端口来测试。** 已否决：应用自己占着全部三个端口，bind 探测永远
无法区分「我们的监听」和「别的进程占坑」，而页面要回答的问题——「对端
能否连到我」——是关于我们已经知道的监听器，不是关于空闲端口。

**用 `netsh advfirewall` 做探测和修复。** 修复上已否决：`netsh` 不能把规则
限定到程序，会把端口对机器上所有进程放开。探测上它可行，但 PowerShell
对象模型直接返回结构化字段（协议、端口表达式、profile、程序），而 `netsh`
输出需要文本解析，会被本地化和格式变化打破。

**在 `windows/runner` 里加 MethodChannel 做防火墙操作。** 已否决：现有
host 通道是为 runner 自己的窗口与托盘事实服务的。调 PowerShell 不需要
原生代码，逻辑留在可测试的 Dart 里，UAC 边界本来就是操作系统的而不是
我们的——加通道只是多一块 C++ 表面，没有能力上的收益。

**拨自己的局域网地址测连通性。** 已否决：经过 Windows 防火墙的回环行为
不稳定，回环拨号绕过的恰恰是被测的过滤器，而且自拨失败无法区分「防火墙」
和「地址不对」。规则检查回答的才是那个真正可操作的问题。

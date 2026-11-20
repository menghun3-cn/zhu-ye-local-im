# Agent Note: 防火墙例外在安装时尝试、在首次运行时提供一次

Status: implemented

[English](2026-11-20-firewall-exception-at-install-and-startup.md) | 中文

## Problem

打开防火墙端口此前只有手动修复一条路：用户得先怀疑是防火墙问题，找到
故障排查页再点按钮——而官网却让每个新用户「装完记得放行防火墙」。绿色
包用户根本没有安装环节，安装时的方案永远覆盖不到他们，也不会有人去读
一个局域网小工具的 README。

这条例外本身值得「写一次就不再问」：规则按程序限定、升级后依然有效，
产品的职责是在有安装器的地方安装时写一次、在没有的地方首次运行时提供
一次，然后永远不再提起。

## Decision

两条路径写同一对规则：`LocalTransfer`（TCP `47655-47657`，按程序限定）
与 `LocalTransfer Discovery`（UDP `47654`，按程序限定），与
[故障排查那篇笔记](../feature/2026-11-12-troubleshooting-diagnostics-are-real.zh.md)
判定所用的端口口径一致。

**安装时**（`packaging/local_transfer.iss`）：文件就位后
（`ssPostInstall`），非静默安装用 `ShellExec` 的 `runas` 动词拉起一次提
权的 `netsh.exe -f <脚本>`。命令经 `{tmp}` 下的脚本文件传入而非内联参数，
「删旧建新」四条扁平命令只弹**一次** UAC，而不是四次。`program=` 把规则
限定到 `{app}\local_transfer.exe`；旧笔记中「netsh 不能按程序限定规则」
的说法是错的，已在那篇笔记里更正。UAC 被拒不算安装失败——返回值被故意
丢弃，运行时的提供是第二次机会。静默安装（`/SILENT`，含应用内更新）整
体跳过：更新中途弹 UAC 是惊吓，且按程序限定的规则在文件替换后依然有
效。卸载（`usUninstall`，非静默）删除同样两个规则名，不留指向已删 exe
的残留。

**运行时**（`lib/ui/dialogs.dart`、`lib/ui/home_shell.dart`）：每个安装
只此一次，首帧之后外壳用已有的 `probeHostFirewall` 接缝探测防火墙。
`blocked` 才弹对话框，列出未覆盖的端口，按钮为「允许入站连接」/「暂
不」；任一答案——以及任何非 blocked 的判定——都会落定
`DeviceProfile.firewallCheckDone`，与其他一次性偏好一样持久化。「允许」
走已有的 `openFirewallPorts` UAC 流程，结果以 `TopToast` 提示，复用故
障排查页的同一组文案。`unknown` 不置位，探测答不出时下次启动再试，而不
是永远不提供。非 Windows 平台在探测前直接返回。

手动故障排查页不变，仍是所有选了「暂不」的人的回头路。

## Alternatives considered

**安装包整体要求管理员（`PrivilegesRequired=admin`）。** 否：与 `.iss`
开头论证过的每用户免 UAC 安装哲学直接冲突，且会让每个安装用户为一条
多数人根本用不上的规则付一次 UAC。提权子进程写的是同一条规则，提示只
在真正需要的地方出现。

**安装脚本里也用 PowerShell `New-NetFirewallRule`。** 否在引号而非能力：
同样的命令要在 Inno Pascal 里接 `-EncodedCommand` 的 Base64 管道，而
`netsh -f` 吃的是扁平行。运行时保留 PowerShell 是因为那边已有幂等脚本
和测试缝；两边靠规则名收敛，而探测、重装与卸载认的都是这两个名字。

**随包附带一个调 `INetFwPolicy2` 的小 exe。** 否：一条防火墙规则不值得
在已验证的包里多养一个二进制，而 COM API 正是 `netsh` 已经封装的东西。

**仍被阻止时每次启动都问。** 否：选了「暂不」或拒绝 UAC 的人已经答过；
每次启动都问是纠缠，故障排查页才是回头的诚实位置。`unknown` 是唯一例
外——它什么都没落定。

**对话框一弹出就记为已提供。** 否：对话框与答案之间崩溃会烧掉唯一一
次机会。标志只在真实结果上写——一个判定或一个答案。

## Consequences

- 安装版用户在设置时最多弹一次 UAC 就拿到规则；绿色包用户首次运行获
  得同样的一次提供。两边收敛到同一对规则名，先跑哪条都不冲突。
- `DeviceProfile` 新增 `firewallCheckDone`（默认 false，宽容读取）；
  `LocalTransferController` 暴露 `firewallCheckDone` /
  `markFirewallCheckDone()`。
- 安装脚本的 UAC 步骤无法被 `dart test` 覆盖；它由打包脚本编译 `.iss`
  验证，被拒的提示也只会留下一个能正常用的安装。运行时一半由 profile
  往返测试与已有的 `ProcessRunner`/通道接缝覆盖。
- 安装时写的规则只覆盖首选短链端口 47657；动态回退端口仍由服务器绑定
  时运行时那条脚本补上——与手动按钮一直以来的覆盖面相同。

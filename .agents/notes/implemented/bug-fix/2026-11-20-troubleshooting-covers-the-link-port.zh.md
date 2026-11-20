# Agent Note: 故障排查诊断并修复短链分享端口，含动态回退端口

Status: implemented

[English](2026-11-20-troubleshooting-covers-the-link-port.md) | 中文

## Problem

一台机器上生成的分享链接在另一台机器上打不开，而「故障排查」页对此没有任
何可说的：它的端口检查只列出会话、配对和发现三个端口，防火墙检查也只按这
三个端口判定入站规则。真正承载 `/s/` 与 `/f/` 的短链 HTTP 服务对两项检查
都不可见。

「不可见」不等于「无关」，因为这个端口并不固定。
[LinkTransferServer](../../../../lib/core/link_transfer/link_server.dart)
在首次分享时才惰性绑定，优先使用 `defaultLinkTransferPort`（47657），被占
用时回退到随机端口——此后生成的所有链接都指向这个回退端口。只认 47657 的
防火墙判定会在「链接实际使用的端口被墙」时仍报「已放行」，而「放开端口」
的修复动作写出的规则同样覆盖不到它。

## Decision

诊断现在端到端携带短链端口，绑定值优先于偏好值。

- **`linkPortLevel`** 与 `sessionPortLevel`/`pairingPortLevel` 并列。`null`
  —— 服务尚未启动，即首次分享前的常态 —— 判 `ok`；绑定端口不是 47657 时
  判 `warning`，与会话、配对回退同一结论。
- **`requiredInboundPortsFor({linkPort})`** 把 `('TCP', linkPort)` 追加进
  防火墙判定的必需端口集合，并与基础端口去重。`evaluateFirewallRules` 与
  `firewallReportFromSnapshot` 把该端口作为可选参数接收，不传时行为与以
  前完全一致。
- **页面传入有效端口**：服务运行时取 `LinkTransfer.instance.port`——即链
  接实际指向的动态回退端口；未启动时取 `defaultLinkTransferPort`，这是当
  前能给出的最好答案，因为会发现另一个回退端口的分享尚不存在。端口检查的
  明细行新增 `Link TCP` 一项，回退时附带点名实际端口的说明，未启动时附
  「待启动」说明。
- **修复两端都覆盖。** `firewallOpenScript` 始终把偏好端口 47657 写进
  TCP 规则——本次回退的服务下次运行很可能又会拿到它——绑定端口不同时再
  追加，于是规则形如 `47657,47655,47656,51234`。`openFirewallPorts` 与
  `probeHostFirewall` 同样透传该参数，检测与修复口径一致。

## Alternatives considered

**在诊断时启动短链服务。** 否决：绑定监听是页面不需要的副作用——新端口
上第一次监听恰恰是触发 Windows 防火墙提示的时刻，一个「检查」入口不应成
为提示弹出的原因。空闲时报告偏好端口回答的是同一个问题，且不必绑定。

**只判定 47657。** 否决：这正是本次要修的缺陷。服务一旦回退，链接指向的
是回退端口，只认 47657 的判定与规则描述的都是一个没有人监听的端口。

**改放行程序的整个 TCP 端口段。** 否决：`LocalPort Any` 或临时端口段规则
能覆盖今后一切回退，但也让本应用在它从不监听的端口上接受入站——比问题
本身更宽，而这条规则还是应用代用户写入的。

**把短链端口并入 `PortReport`。** 否决，属多余：该类承载的是控制器启动时
上报的已绑定端口，而短链服务惰性绑定、需要从 `LinkTransfer.instance` 实
时读取——它没有可加入的启动快照。

## Consequences

- 端口检查现在展示四个端口，短链回退时会告警；防火墙检查在无规则覆盖时
  会把 `TCP <短链端口>` 列入缺失项，「放开端口」按钮写出的规则同时覆盖偏
  好端口与当前绑定端口。
- `requiredInboundPorts` 仍是三个常驻端口；短链端口经 `linkPort` 显式传入
  才生效，既有调用方与测试在不传时保持旧行为。
- 动态回退只在进程生命周期内有效：下次重启可能重新绑上 47657，所以修复
  写入两个端口，而不是只写当前绑定的那一个。

## Testing

- `test/diagnostics/troubleshooting_test.dart` 覆盖 `linkPortLevel`（未启
  动/偏好/回退）、快照中偏好短链端口已覆盖与动态 `51234` 未覆盖两种情形
  ——断言缺失列表点名 `TCP 51234` 而非 `TCP 47657`——以及 `linkPort:
  51234` 时提权脚本包含 `47657,47655,47656,51234`。

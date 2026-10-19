# Agent Note: 按用户选择的时间间隔定期检查更新

Status: implemented

[English](2026-10-19-periodic-update-checks-on-a-cadence.md) | 中文

## Problem

侧栏「更新」入口只知道应用启动时问过一次的结果。一个被打开、配对好、然后在托盘里
放好多天的应用，恰恰最需要知道「程序没在看窗口的这段时间里发布了新版本」——但它要
等到下次重启才听说。

That one check was deliberately a once-per-run action (the About text named it
「the one exception」). Turning it into a recurring action needs a setting the
user can see and switch off: a silent polling loop is a different thing entirely,
and one that never appeared in Settings was never agreed to exist.

## Decision

**Profile 里存一个每 Device 的选择，默认一小时。** `UpdateCheckInterval` 枚举放在
`lib/core`（纯 Dart，`test/` 可测），以 `updateCheckInterval` 持久化在
`DeviceProfile` 中，wire 名固定为 `off / hourly / six-hours / daily /
three-days`。该键出现前的旧 profile、或本版本不认识的取值，都按默认值解码——与
`acceptPairingRequests` 的同一条宽容规则。

**设置页负责这个选择。** 设置页新增「更新检查」区：一个开关（后台定期检查开/关），
打开时再给一个 `SegmentedButton` 列四种频率。改任一都会经控制器 `_persist()`
持久化并通知监听者，区域立刻重画。

**`UpdateNotice` 按 profile 的时间间隔重挂一个 `Timer.periodic`。**
`attach(controller)` 在控制器启动后被调用；notice 监听控制器的变更流，间隔变化时
重挂定时器，`off` 则取消。定时器归 `lib/ui`（它本来就持有 `UpdateResolution.checker`），
About 文案把「启动时一次」和「按设置选择的时间间隔」都写成对「只在局域网内通信」的
两条刻意例外。

## Alternatives considered

**不加设置项、内部固定一个定时器。** 否决：一个用户看不见也关不掉的后台探测，恰恰是
这个产品在网络承诺上最在意的东西，About 文案还得再添一条关不掉的例外。

**用 `shared_preferences` 存间隔。** 否决：这是和 `closeBehaviour` 一样的本机偏好，
profile 本来就是这类偏好存放、持久化、启动时读取的同一处地方。

**每种频率一个开关。** 否决：用户选择的是「多久一次」，不是「哪几个检查」；一个开关加
一行分节按钮，两个控件就说清楚了。

**不做定期，只靠手动检查。** 否决：整个意义就在于托盘图标合上的期间发布了新版，用户
不必重启或手动点一下也能看到入口。

## Consequences

- 新增 `lib/core/update/update_check_interval.dart`；`DeviceProfile`、
  `LocalTransferController`、`UpdateNotice`、`lib/ui/app.dart` 与设置页都接上了
  这个间隔。
- About 页描述把「按设置选择的时间间隔」作为对外请求的例外写了出来。
- widget 测试覆盖设置区与定时器节奏；profile 测试覆盖默认值、宽容解码、往返与
  wire 名。
- 默认按时一小时，是刻意选的低频；用户可选 6 小时、每天、每 3 天或关闭。

# Agent Note: 截图默认开启，遮罩内快捷键可自定义

Status: implemented

[English](2026-11-06-screenshot-on-by-default-and-overlay-keys.md) | 中文

## Problem

[2026-11-20-windows-screenshot-tools](2026-11-20-windows-screenshot-tools.zh.md)
把截图遮罩做成了纯鼠标操作，并把整个功能放在一个**默认关闭**的开关后面，理由是能截屏的全局快捷键是这个应用能做的最具侵入性的事。实际使用暴露出两个后果：

* 没人找得到的功能等于没有功能。呼出快捷键只有在打开开关后才存在，而「我的 → 截图」页面之外没有任何地方提示这个功能的存在。
* 遮罩打开后独占整个屏幕和键盘，但每个动作——切模式、完成、钉图、取消——都要瞄准工具栏按钮。作为参照的 Snipaste 是键盘优先的。

## Decision

**新设备默认开启，已有安装不动。** `DeviceProfile.screenshotEnabled`
的构造默认值翻转为 `true`；`fromJson` 对缺失键仍解析为 `false`。自
功能上线以来写出的 profile 都显式带这个键，所以翻转恰好只覆盖「从未回答
过这个问题」的安装——旧 profile 不被追溯改动，也不需要「用户是否动过
这个开关」的标记位。

**六个绑定，每个遮罩动作一个。** 新增 `CaptureAction` 枚举
（`region`、`window`、`full`、`copy`、`pin`、`cancel`），默认值
`q`/`w`/`e`/`enter`/`ctrl+enter`/`escape`，以 `captureKeys` 存入
profile——动作 wire 名到规范化 `modifier+key` 字符串的映射。文法是
`isScreenshotHotkey` 的姊妹而非复用：`isCaptureHotkey` 允许**裸键**
（遮罩打开时没有别的应用的快捷键需要避让），并接受 `enter`、
`escape`、`space`、`tab`、方向键等截图工具赖以生存的命名键。所有绑定
都过 `normalizeCaptureHotkey`，因此 `shift+ctrl+a` 与 `ctrl+shift+a`
是同一个存储字符串。

**遮罩自己匹配按键。** 遮罩内容上方的 `Focus(autofocus: true)` 把每个
`KeyDownEvent`——修饰键从 `HardwareKeyboard` 读，因为事件只报下去的
那个键——翻译成同一套规范字符串并分发动作。返回 `handled` 让
`Enter` 不会同时点中获得焦点的工具栏按钮；`_capturing` 守卫让按住
按键只触发一次截图。绑定通过新增的 `ScreenshotWindowArgs.overlayKeys`
字段送达遮罩所在的独立引擎——窗口参数是截图窗口通往 profile 的唯一
链路。

**设置页列出全部绑定。** 「我的 → 截图」新增「截图内快捷键」卡片：每
个动作一行录制器，各自带录制控件和恢复默认按钮。
`DeviceProfile.setCaptureKey` 拒绝非法绑定和与其他动作重复的绑定
——两个动作共用一个键会让遮罩的分发变成抛硬币。controller 再补一条
profile 看不见的拒绝：与呼出快捷键相同的绑定会让每次按键都重新唤出
遮罩。`ScreenshotService.captureKeys` 随每次 profile 同步推送，改完
的键下一个遮罩即生效，不必重启。

## Consequences

* 新装现在在首次运行就注册 `ctrl+shift+a`。对从不打开设置页的安装者
  这是行为变化——刻意接受，一键即可还原。
* 裸键绑定意味着遮罩打开期间会吞掉普通字母键。这正是目的——遮罩是模
  态的——但也意味着 `q` 这类绑定在遮罩外不生效，设置页文案已说明
  （「截图遮罩打开时生效」）。
* 本版本写出的 profile 带 `captureKeys`；旧版本读取时忽略未知键，与
  快捷键字符串原有的宽容一致。
* 按键名桥接（`lib/ui/screenshot/capture_key_names.dart`）由录制器和
  遮罩共用是刻意的：页面接受的绑定必须是遮罩能拼写的那一个。

## Alternatives considered

**让已有用户也默认开启。** 否决：存储的 `false` 无法与「从未问过」区
分，诚实地区分需要一个「用户碰过开关」标记位来做一次性迁移。只覆盖
新装是被要求的范围，也是它的诚实版本。

**遮罩绑定复用 `isScreenshotHotkey`。** 否决：它要求带修饰键且排除所
有命名键，恰好禁掉了功能预期要带的 `enter`/`escape`。两套文法形状与
修饰键名相同，但规则不同。

**遮罩按键也走 `hotkey_manager` 全局注册。** 否决：遮罩是独立引擎里的
独立窗口，第二轮全局注册会在应用任何位置触发，而不是只在遮罩打开时
生效。在获得焦点的遮罩窗口内用 Flutter 按键事件才是正确的作用域。

**每个动作一个 profile 字段。** 否决：六个字段要六段序列化分支，且加
第七个动作仍要改格式；以 wire 名为键的映射可以逐条降级容错，这正是
本 profile 已有的做法。

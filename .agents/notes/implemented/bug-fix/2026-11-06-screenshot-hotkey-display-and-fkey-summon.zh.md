# Agent Note: 快捷键可读显示与裸 F 键呼出

Status: implemented

[English](2026-11-06-screenshot-hotkey-display-and-fkey-summon.md) | 中文

## Problem

「我的 → 截图」页的快捷键行同时暴露两个缺陷：

* 该行渲染的是 hotkey_manager 的 `HotKeyRecorder`，其内置
  `HotKeyVirtualView` 通过 `PhysicalKeyboardKey.keyLabel` 取键名——
  该 getter 落到包自带的符号表，产出 `⌃`、`⇧`、`⊞`。于是
  `ctrl+shift+a` 显示成三个键帽：「^」、一个向上的箭头和「A」。
  绑定本身能用，只是读不出来。
* `isScreenshotHotkey` 强制要求至少一个修饰键，用户真正想要的唯一
  无和弦绑定——裸按 `F1`——在设置页被拒绝，尽管
  `hotkey_manager` 注册它毫无问题。

## Decision

**页面自己录键、自己标键。** `screenshot_page.dart` 里的
`_HotkeyEditor` 改为 `StatefulWidget`，像被替换的录制器一样通过
`HardwareKeyboard.instance` 监听，与被替换的录制器一样——但要先点
击该行才进入监听：所有行共用同一个物理键盘，常开监听会让一次按键
录进全部七行，静态 `_armed` 槽位保证同一时刻只有一行在听。纯修饰
键按下被忽略（它们是和弦的前半段而非绑定），其余 `KeyDownEvent`
由 `captureKeyName` 加实时修饰键状态翻译成 profile 的
`modifier+key` 字符串，过 `normalizeCaptureHotkey` 后由该行的
`accepts` 文法过滤；在拒绝 `escape` 的行上，裸 `escape` 解除武装，
充当取消手势。显示用 `captureHotkeyLabel`，于是行内读作
`Ctrl+Shift+A`——与遮罩工具栏
提示本就使用的拼写一致。hotkey_manager 仍负责全局热键注册，被丢弃
的只是它的 widget。

**裸 `f1`–`f24` 成为合法的呼出快捷键。** `isScreenshotHotkey` 接受
单独的功能键；字母、数字与命名键仍必须带修饰键，因为裸 `a` 或
`enter` 会在日常输入中触发。`_parseAccelerator` 无需改动——空修饰
列表本来就是合法的 `HotKey`。两套快捷键文法同时把功能键范围收紧到
`f1`–`f24`，即 `captureKeyOf` 与 `_parseAccelerator` 真正能拼写的范
围：`ctrl+f99` 此前能通过校验却在注册时静默失败。

## Consequences

* 页面上每一行快捷键——呼出键与全部六个遮罩绑定——都显示可读的键
  名，不再是修饰键符号。
* `f1` 到 `f24` 可以无修饰键全局绑定。设置页文案现已说明按下新组合
  键即可改绑。
* 全局呼出键仍拒绝裸字母、数字与命名键；遮罩内绑定不受影响，仍允许
  裸键。
* 手改的 profile 若带 `f25` 及以上或 `f0` 的绑定，现在会回退到默认
  值，而不是注册一个不存在的键。

## Alternatives considered

**保留 `HotKeyRecorder`，在外围改样式。** 否决：它的显示是内部 widget
`HotKeyVirtualView`，没有键名或主题钩子——符号输出无法从外部改变；
为了一个标签去 fork 录制器，比页面本就需要的二十行
`HardwareKeyboard` 处理还要多代码。

**全局允许任意裸键。** 否决：裸字母、数字或 `enter` 会在用户向其他
应用输入时触发——热键会弄坏它本该服务的机器。功能键是唯一没人用
来打字的键，因此例外到此为止。

**改用 Flutter 按键事件注册。** 否决：呼出键必须在其他应用持有焦点
时触发，只有操作系统级注册能做到。`hotkey_manager` 继续负责注册，
被替换的只是它的录制器 widget。

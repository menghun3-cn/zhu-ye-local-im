# Agent Note：一个没有点名字体的标签

Status: implemented

[English](2026-10-21-a-label-that-names-no-font.md) | 中文

## Problem

界面上一部分文字用的不是主题要求的那套字体。在一套中文优先的字体栈上，画错的
恰好是那些由 Material 自行构造样式的控件：按钮自己的标签、列表项的副标题、
分段控件的选项、输入框的提示。

主题把字体点了两次名。`WeChat.fontFamily` 是 `'Microsoft YaHei UI'`，
`WeChat.fontFamilyFallback` 是它背后的回退链，`ThemeData` 两个都拿到了 ——
并且附了这么一句说明：

> 中文优先：Windows 上 Material 默认的 Roboto 不含汉字，会回退到系统字体；
> 显式点名雅黑能让中英混排的基线一致。

这个意图只实现了一半。`ThemeData.fontFamily` 是一个构造参数，它被施加到**默认
文字主题**上 —— 它不是一个可读的字段，也到不了框架自行为自己构造的样式。因此
主题的 `textTheme` 各项带着字体家族，而每一个从其中之一继承的 `Text` 都会用雅黑
画出来。但像 `ButtonStyle.textStyle` 或 `ListTileThemeData.subtitleTextStyle`
这样的组件样式，是一个独立存在的 `TextStyle`，它**一个字体家族都没点**。

而这与「继承到字体」并不是同一件事。`AnimatedDefaultTextStyle` 是**替换**掉
外层样式，而不是与之合并；`TextStyle.merge` 则用另一边的值覆盖 `fontFamily` ——
包括用 `null` 覆盖。于是，一个没点家族的样式不会退回到主题那一个，而会退回到
平台随手给的那个 —— 那是另一张脸，中文覆盖范围和字形度量都不一样。

## Decision

**框架自行为自己构造的每一个样式，现在都点出主题的字体；回退链的末端是一张
有符号字形的脸。**

- `WeChat.theme` 里的组件样式 —— 按钮主题的 `textStyle`、列表项主题的
  `subtitleTextStyle`、分段按钮主题的 `textStyle`、导航栏的 `labelTextStyle`、
  chip 主题的 `labelStyle`，以及输入装饰主题的 `labelStyle` /
  `floatingLabelStyle` / `helperStyle` / `hintStyle` —— 都带上
  `fontFamily: WeChat.fontFamily` 与
  `fontFamilyFallback: WeChat.fontFamilyFallback`。
- 覆盖了这些样式的调用点也带上：`conversation_view.dart` 的发送按钮与气泡动作，
  以及 `conversations_page.dart` 的行内动作。一个没点家族的覆盖会替换掉主题那一个，
  所以覆盖本身也得点名。
- 输入框与表情按钮的字形在各自的调用点上点名字体，理由相同。
- `WeChat.fontFamilyFallback` 加上了 `'Segoe UI Symbol'`。中文字体里没有 `☺`，
  所以即便家族已经点名，输入区那个表情按钮 —— 唯一一个标签**就是**符号的控件 ——
  仍然画不出东西。这条链是「上一张脸缺这个字」的链，最后一环就是那张有符号的脸。

## Testing

- 主题的组件样式被断言为带着家族，写在 `test_flutter/ui/shell_test.dart` 里，
  紧挨着既有的「文字主题带着它」那条断言。
- `docs/screenshots/` 下的五张图重新生成并逐张读过：每一个按钮标签、列表项副标题、
  分段控件选项与输入框提示都用主题那张脸画出来了，表情按钮画出来的是一张脸，
  不是一个方块。

## Alternatives considered

**把中文字体注册到平台的默认家族名下，让没点家族的样式挑中它。** 否决：这只是
在测试里治好了症状。发布的应用跑在 Windows 上，那里��默认家族是 Windows 随手
替换出来的那个，而替身的中文覆盖范围与字形度量都不是设计当初对着的那一套。点名
字体，才是让图与意图一致的做法。

**给被截图的树套一层点名字体的 `DefaultTextStyle`。** 否决：那截图显示的就不是
发布版应用的样子。缺陷在发布版的样式里，而一幅把它藏起来的图，藏的正是这些图
存在的理由。

**不动主题，改成不收录这些图。** 否决：画错的标签是按钮和列表项 —— 正是读者第一眼
会看的地方。

**把表情字形换成 Material 图标。** 否决：`☺` 是设计稿用的那个字符，换成图标就是
另一幅和设计稿不一样的图。

## Consequences

**换来。** 整个界面一套字体栈，图里的标签就是用户看到的标签。

**让出。** 在调用点覆盖 `textStyle` 的组件样式，也必须自己点名字体，否则它会悄无声息
地把主题那一个丢掉。这是一条框架不强制、类型系统也表达不了的规则，于是下一个覆盖
样式的调用点得知道这件事。

**欠着。** `'Segoe UI Symbol'` 是 Windows 的脸。在 Android 上这条链会落到
`Roboto`，而那里的 `☺` 来自平台自己的 emoji 字体。这条链是一串脸，不是一句「它们
全都在」的承诺。

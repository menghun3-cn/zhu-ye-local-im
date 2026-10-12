# Agent Note: Shift+Enter 换行，而这件事不能交给框架

Status: implemented

## Problem

输入框是「Enter 发送、Shift+Enter 换行」。代码里两处注释都这么写，而它并不换行：Shift+Enter 把消息发出去了。

输入框本身没有坏。回答这个组合键的，正是那条旧注释把它推给的东西。框架默认的文本编辑快捷键表里，每一条都是 `shift: false` 的 `SingleActivator`，而 `SingleActivator` 对修饰键是**精确匹配** —— 于是 Shift+Enter 从整张表里穿过去，也从 `WidgetsApp` 自己的 `ActivateIntent`（同样是 `shift: false`）穿过去，最后穿出了框架。一个没人认领的 Enter，引擎会把它翻译成输入框的 `textInputAction`，而这个输入框是 `TextInputAction.send`；接着 `onSubmitted` 触发，消息就交出去了。到了那一步两个组合键已经无从区分 —— 这个动作只带「发送」这个意图，不带是哪些修饰键产生的它。「把 Shift+Enter 留给默认的换行」因此实际等于「让 Shift+Enter 发送」，而那句解释这件事的注释，正是没人再去看它的原因。

同一批注释里还有两处错的，作用都是把这个陷阱藏起来：`textInputAction` 被写成「只是给*平台*键盘的提示，对物理键盘不起作用」（它恰恰就是物理 Enter 变成的东西）；输入框被写成 `maxLines: null`，而代码里早就是 `maxLines: 6` 了。

为什么没有测试抓到：输入框的发送从来只用 `tester.testTextInput.receiveAction(TextInputAction.send)` 驱动过 —— 那是**引擎那条路**，而恰恰是那条路没坏。按键才是桌面用户走的那条路，而没有一条测试按过键。

## Decision

**Shift+Enter 被当成一个键位认领下来，和裸 Enter 放进同一张表。**
`SingleActivator(LogicalKeyboardKey.enter, shift: true)`，以及 `numpadEnter` 的同一条，都映射到新的 `InsertLineBreakIntent`。认领它就是把引擎挡在外面：被认领的按键事件会被消费、并以 handled 报告给引擎，那个分不清两个组合键的动作因此永远不会被咨询。裸 Enter 走的是同一条路，也照旧能用 —— `WidgetsApp` 把它的文本编辑表挂在树靠上的位置，而任何夹在那张表和输入框之间的 `Shortcuts` 都会覆盖它，这个输入框的表就是那个 widget。

**换行由我们自己插进去**，沿用粘贴兜底早就在照抄的那条规则：替换选区，光标落在插入内容之后。这条规则现在收在一个方法里 —— `_insertAtCaret` —— 两个调用方共用，因为它们的理由本来就是同一个：各自都拦住了输入框自己做这件事（一个认领了 Ctrl+V，一个认领了 Shift+Enter）。

**引擎那条路留着。** `onSubmitted` 仍然接在框上，只是它「不冗余」的理由不再是旧注释给的那条：它回答的是软键盘的发送键 —— Android 上没有修饰键、也没有第二个组合键 —— 以及任何上报动作而不是按键的平台。

**注释是重写而不是追加的。** 错的那一句是承重的：它写的是一个并没有在跑的机制，而这个 bug 的修法恰恰是一句「焦点链上究竟哪个节点有权回答这个按键」。`_ComposerField` 上那段重写后的文档把要害写清楚了 —— **没人认领的 Enter 会变成输入框的 `textInputAction`** —— 这样下一个想「交给框架处理」的人，得先跟这句话辩一场。

## Testing

`test_flutter/ui/composer_keys_test.dart`，五条，全部按**真按键**而不是驱动动作，沿用 harness 里 `sendCtrlV` 的先例：裸 Enter 请求发送、且不留换行；Shift+Enter 换行、改插入点、不请求发送；换行会替换掉选区；小键盘那两个键与主键盘的两个完全一致；换行仍然留在发出去的那段文字里。输入框是单独 pump 的，形状沿用 `composer_attachment_test.dart` 立下的那套 —— 不需要窗口、不需要控制器、不需要对端。

这些测试覆盖不到的是引擎那一半。widget 测试里没有引擎，所以它没法按一下键、再断言引擎**没有**额外发送一次；它能钉住的是把引擎挡在外面的那件事：组合键被认领、文本里多出一个换行、没有任何一次发送被请求。

## Alternatives considered

**让 Shift+Enter 落到框架的换行上去。** 这就是原来的代码。否决：并没有一个「框架的换行」可落。所有可能认领 Enter 的默认触发条件都是 `shift: false`，而引擎对一个没人认领的 Enter 的回答，是输入框自己的 `textInputAction`。

**把 `textInputAction` 改成 `TextInputAction.newline`，让引擎的兜底插入换行。** 否决：那会改掉 Android 软键盘的行为。这个输入框保留 `send`，是因为 Android 用户手上唯一的 Enter 就是输入法的发送键；为了修一个桌面端组合键把这个交出去，是让 app 的另一半来付账。

**把处理器挂到输入框自己的 `FocusNode` 上（`FocusNode(onKeyEvent: …)`），而不是用一张挂在它上面的 `Shortcuts` 表。** 可行，而且鉴于「焦点节点自己最先被问到」，它是最字面的做法。暂时否决：它会把输入框的按键处理拆到两个地方 —— 这张表已经声明了四个组合键、并且把它们写在一处 —— 而这张表覆盖 `WidgetsApp` 默认表这件事是框架有文档的行为，不是取巧。若将来有哪个 widget 在这张表与输入框之间认领了某个组合键，这条路仍然可以捡起来。

**给两个组合键都加上「正在输入法组字期间不发」的判断**（读 `controller.value.composing`）。没做。在 Windows 上，那个用来上屏组字的 Enter 属于输入法，根本不会以按键事件的形式到达；在 Android 上，动作那条路本来就是有意的发送。一个在本项目的机器上没法被执行的判断，只会是一段围着 `if` 的、无法验证的代码 —— 它属于一次能真的敲拼音、并看见到达了什么的改动。

**在框里放一句提示** ——「Enter 发送，Shift+Enter 换行」—— 或者给输入框加 tooltip。否决：那要改 `messageHint`，一句会被打包脚本拿去在 `app.so` 里搜的用户可见句子，只为了解释一个输入框自己用行为就能教会的惯例。

**顺便支持 Ctrl+Enter 发送**，或者把发送挪到带修饰键的那个组合键、把 Enter 还回换行。否决：前者没人要求；后者与本输入框有意遵循的桌面惯例相悖，会让常见的那次操作变成别扭的那次。

## Consequences

**换到了什么。** 这个组合键做到了代码和使用者的预期都写着的那件事；而「它为什么是一个**键位**认领、而不是一次落空」被写在了表旁边、写在触发条件旁边 —— 也就是下一次改这张表的人会站的地方。

**从此有测试真的按键了，而这是本仓库里新的一类覆盖。** 此前每一条输入框测试驱动的都是 `TextInputAction.send`；按键那条路一直没被测过，哪怕桌面用户走的全是它 —— 一个带注释的功能里的 bug 就是这么活下来的。现在表上其它被认领的东西（Ctrl+V 有它自己的 helper）反倒成了例外，而不是常态。

**新增的五条 widget 测试一次都没有真正跑过。** 写这份笔记的机器上 `flutter test test_flutter` 起不来：任何带管道的 `Process.start` 都会以 `CreateFile failed 231` 失败，`flutter` 工具、`dart test` 和打包脚本都因此跑不了。这里的分析依据是框架自己的源码 —— `SingleActivator` 的精确匹配语义、`WidgetsApp` 挂载 `DefaultTextEditingShortcuts` 的位置、以及 `onSubmitted` 那句「引擎会把 Enter 翻译成一个动作」的文档 —— 但仍然欠一次在工具链正常的机器上的、绿着的运行。

**没有任何用户可见的东西被新增。** 没有新文案、没有新图标、没有改布局：打包脚本的探针一个都没动，因为 `app_zh.arb` 里没有新句子可供它们去找。

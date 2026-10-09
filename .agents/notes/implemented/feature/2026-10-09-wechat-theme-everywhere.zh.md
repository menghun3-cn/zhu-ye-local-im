# Agent Note: 微信那套观感覆盖到每一个界面，而不只是会话

Status: implemented

## Problem

微信的 token 早就在了，会话那几个界面也用了。但别的界面一个都没用。导航栏和剩下的四个
页面 —— 设备、传输、剪贴板、设置 —— 仍然架在 Material 的默认值上；而它们背后那套
`ThemeData` 只命名了**页面会用手写出来的**那些颜色，把几乎每一个组件主题和大部分
`ColorScheme` 槽位都留在 Material 3 自己的值上。页面不必提到某个槽位，那个槽位照样会被
画出来：`Chip`、`Switch`、`SegmentedButton`、`NavigationRail`、`NavigationBar`，以及对话框
的底色，读的都是没人写下来的槽位，于是它们按 Material 的调色板渲染 —— 一片灰色列表里
一个薰衣草色的实心按钮、每一条次要文字上的紫灰 `onSurfaceVariant`、把纯白卡片往种子色
洗的 elevation tint。一个没被主题化的控件待在其它都已经是微信灰的页面里，看着就像从别的
应用里跑来的，而且它能躲过 review —— 因为它根本没出现在 diff 的任何一行里。

会话列表另外还有三处没做完。行里没有时间，「最后一句是什么时候说的」根本不在屏幕上。
行与行之间没有分界线，挤成一片。而「怎么进去」—— 连接、或者配对 —— 画成了一个实心胶囊，
参照物画一个安静的动作时不是这么画的。

## Decision

**每个颜色槽位都点名，包括没有任何页面提到的那些。** `theme()` 现在显式构造
`ColorScheme.light(...)`，其中 `surfaceDim`、`surfaceBright`、四个 `surfaceContainer*`
档位、`onSurfaceVariant`、`outline`、`outlineVariant`、`inverseSurface`、`inversePrimary`、
`errorContainer`、`onErrorContainer`、`shadow`、`scrim` 全部给了值。它们共守的一条规则是：
**谁都不许用默认值**，因为默认值就是 Material 的颜色，不是这个应用的颜色。

**`surfaceTint` 是 `Colors.transparent`。** 这是唯一一个默认值会**主动**破坏观感的槽位：
Material 3 会把有高度的表面往种子色那边调，而微信的表面是平的灰与白。一张被调过色的
纯白卡片，是「这套主题是继承来的、不是选的」最清楚的证据。

**页面够得着的组件都给组件主题** —— `appBar`、`card`、`divider`、`chip`、`listTile`、
`progressIndicator`、`switch`、`checkbox`、`radio`、`segmentedButton`、`filledButton`、
`textButton`、`navigationRail`、`navigationBar`、`dialog`、`inputDecoration`，外加
`iconTheme` 与 `textTheme`。`switch`、`checkbox` 和两个导航面用
`WidgetStateProperty` 按状态取值，于是品牌绿只在控件**开着**或**当前**时出现，其余时候是灰。

**两个导航面是故意分家的。** 侧栏坐在 `sidebarBackground` 上，用品牌色图标 + `listHover`
指示块标出当前项。底栏坐在 `toolbarBackground` 上，`indicatorColor: Colors.transparent`，
靠给图标和它的标签染色来标出当前页 —— 背后没有胶囊。这个差别是参照物里就有的，不是疏漏：
在手机尺寸的布局里底栏很薄，一个实心指示器会压过整条栏。

**四个页面不再各报各的数。** 每个页面都取 `WeChat.pagePadding`、`WeChat.cardPadding`、
`WeChat.cardGap`、`WeChat.sectionGap`，而不是本地的 `EdgeInsets` 和字面量间距。页面留白
以前是四份独立的意见，也就是两次「两个页面对同一个边距看法不同」的机会。

**安静的动作是一个词，不是一个胶囊。** `textButtonTheme` 把品牌绿设成无填充前景色，会话
行里「怎么进去」现在用的就是它：一个 `TextButton`，带着 6×6 的小圆点和那个动词，取代原来的
实心/描边胶囊。文字按钮保住了焦点环、键盘激活和 tooltip 语义 —— 手搓的 `Material` +
`InkWell` 会把这些丢掉。

**行里的时间来自数据，不来自时钟。** 会话行右侧那一列把时间戳叠在「动作或摘要」之上，
时间戳取 `latest?.at ?? peer.lastSeen`。新增的 `TransferView.at` 由 `app_controller` 在
Tracking 一条 Transfer 的那一刻、从它自己的时钟上读一次传下来 —— 因为引擎里的 `Transfer`
是协议对象、本身没有时间，而在渲染时读时钟会让同一条消息每次重建都印出不同的时间。
行与下一行之间还多了一条按 `conversationRowPadding` 内缩的分隔线，让线从**头像左缘**起笔：
整行通栏的横线会把列表切成一块块，而参照物里它是一整片。

**widget 测试的夹具现在用的是真正在跑的那套主题。** `test_flutter` 的 `_pane` 原本自己
搭了个 `MaterialApp`、塞的是 `ColorScheme.fromSeed(deepPurple)`，这意味着**每一个** widget
测试都是在一套应用从不使用的主题上跑的。现在它用 `WeChat.theme()`，只覆盖页面转场，于是
主题出现回归是这套测试看得见的事。

## Alternatives considered

**`ColorScheme.fromSeed(brand)`。** 这也是这次之前应用在用的写法，而且是最诱人的简化：
一行，换回一整套自洽的色阶。否决的理由是：这件事的重点就是一个**特定的**绿，而种子方案会
用算法自己推导出来，那个算法没有人同意过。这一版文件里唯一还适合用种子的地方：一处也没有。

**只给页面真正碰到的那些槽位配上主题。** 说得过去的最小改法，也正是之前那种状态的成因：
它恰好就是 reviewer 看得见的那些东西。否决的理由是这份清单**不可知** —— Material 会读页面
从没点名的槽位，而每一个默认下来的槽位都是一个落在错调色板里的控件。全部点名的代价是这个
文件更长；不点名的代价是一个没人能靠读页面找到的 bug。

**不动 `surfaceTint`，改成给卡片 `elevation: 0`。** 卡片确实会变平，但**其它每一处**有高度
的表面 —— 对话框、菜单、选中态的表面 —— 照样会被调色。在 scheme 层面设成透明是一次全修好。

**`ChipThemeData.visualDensity`。** 先写了，又删掉：这个参数在本版 Flutter 的
`ChipThemeData` 上不存在，`flutter analyze` 直接指出来了。记在这里，是因为别的组件主题
确实都收这个参数，所以它的缺席从邻近的几行看像是漏写。

**渲染时用 `DateTime.now()` 现取行里的时间。** 一行代码，不用穿参数。否决的理由是它会让
同一条消息每次重建都显示一个不同的时间；而且会话列表是「发生过什么」的记录，它的时间属于
那些事件，不属于画它的那一帧。

**把「连接」入口换成浅灰实心、而不是品牌绿的文字。** 保住了胶囊的轮廓，而且参照物在别的
地方确实也用灰底按钮。否决的理由是：在这个列表里行的职责是被扫视，一个实心形状会和未读
角标、头像抢眼睛；而品牌色的一个词，找的时候看得见，不找的时候不打扰。

**在主题测试里断言 `ThemeData.fontFamily`。** 它不是 getter。`fontFamily` 是构造参数、会被
应用到默认文字主题上，所以断言改成从 `textTheme.bodyMedium` 读那个族名 —— 页面里的文字
真正继承的就是那里。

## Consequences

**忘了 token 的页面，现在拿到的是一个「像微信」的值，而不是 Material 的值。** 这就是整件
事的要点，也改变了以后工作的失败形态：最坏情况是一处表面看着略偏，而不是一处看着像另一个
应用。

**以后再新增组件，要么在这里配上主题，要么它就继承默认值。** 组件主题是一份必须跟着
Material 目录走的清单；一个还没有任何页面用过的新组件类型，在被加进来之前就是没主题的。
这是多了一件要记的事，但它仍然比这份笔记描述的另一种结局好 —— 因为漏掉的地方现在只在
一个文件里看得见，而不是散在四个页面里。

**这套测试现在能抓住主题回归。** 因为夹具搭的是 `WeChat.theme()`，那些断言槽位取值和导航
配色的测试，在主题被换成种子方案或默认值时会失败 —— 而那恰好是原来会悄悄溜过去的改动。

**会话列表显示了以前不显示的时间，所以行更高了、右列也有了宽度上限。** 时间戳与
「动作或摘要」共处右列，套在列表宽度 42% 的 `ConstrainedBox` 里，于是很长的摘要会换行，
而不是把名字挤出去。

## Testing

`test_flutter/ui/shell_test.dart` 新增一个 `the WeChat theme` 组，直接在 `ThemeData` 上工作，
不需要 widget 树：

* 断言 Material 本来会自己填的槽位与 `ColorScheme.light()` **不同** ——
  `secondaryContainer`、`onSurfaceVariant`、`outline` —— 每一条都把后果写进 `reason`，
  因为「这不仅仅是 Material 自己会选的那个」才是这条断言的真正内容；
* `surfaceTint` 是透明，卡片/脚手架/分隔线的颜色就是那些 token；
* 字体族从 `textTheme.bodyMedium` 上读；
* 侧栏与底栏带的是微信的几档灰，且底栏的 `indicatorColor` 为透明。

`test_flutter/ui/pages_test.dart` 在一行真实的会话上新增了三个用例，对应三处没做完的细节
各一个：行会说出它最后是什么时候动的（「刚刚」那句在场）、行与下一行之间有一条内缩的细线
（`WeChat.divider` 的 `Divider`，位于 `conversationRowPadding` 的 `Padding` 里）、进去的方式
是一个词而不是实心按钮（`TextButton`，背景解出透明、前景解出 `secondaryText`，里面有一个
圆形小点）。

让这些断言真正有意义的，是 `test_flutter/support/ui_harness.dart` 里 `_pane` 的那处改动：
夹具若还搭着一套一次性主题，`WeChat.theme()` 的回归一个测试都不会失败。

# Agent Note: 导航轨是自己画的，不是借来的

Status: implemented

[English](2026-10-19-the-rail-is-drawn-not-borrowed.md) | 中文

## Problem

窗口够宽时左边那条导航轨，是 Material 的 `NavigationRail` 换了一层
`navigationRailTheme` 的皮。稿子（`design-preview/conversation.html` 与
`design-preview/styles.css`）画的是另一张图，而差的这三处都不是颜色：

- **当前项是一整块。** 稿子的 `.rail__item[aria-current="page"]` 把整项填上
  `--brand-soft`——图标与文字一起——文字同时转成 `--brand-strong`。组件标当前项
  用的是**图标背后**一个 56 × 32 的胶囊。`NavigationRailThemeData.indicatorShape`
  能换那个胶囊的形状；它的尺寸是 `_kCircularIndicatorDiameter` ×
  `_kIndicatorHeight` 两个私有常量，没有任何参数够得着。
- **六项是两段。** `.rail__spacer` 把四个「去处」（会话 / 设备 / 传输 / 剪贴板）
  和两个「来改点什么」的地方（设置 / 关于）用空白分开。组件把 `destinations` 画成
  连续的一段。
- **产品标记在最上面。** `.rail__brand` 把那枚竹叶气泡画在所有项之上，而主题没有
  任何一个槽位放它。

只有第一条是墙。`leading` 与 `trailing` 收的是任意 widget，`trailingAtBottom` 还能让
其中一个钉在底部，所以「分成两段」和「顶上有个标记」是够得着的——但代价是把项挪出
`destinations`，而在外面没人为你画它。手搓一个导航项本来就是这两处差异需要的东西，而
手搓的导航项背上稿子那块底，也正是第一条差异。三处其实是同一个答案。

主题槽位还没法断言。测试读 `navigationRailTheme.indicatorColor` 可以通过，而屏幕上那个
标记的形状、尺寸、范围全是错的：widget 测试看不见那张图。

## Decision

导航轨画在 `lib/ui/nav_rail.dart` 里。

`AppNavRail` 就是那一列：品牌标记、四个界面、一个 `Spacer`、两个工具，再加一个可选的
`trailing` 挂在这两个之下。它收一份有序的 `destinations` 和一个 `pinnedCount`——**从末尾
往前数**几个——这样 shell 那边的列表仍然只有一份，第七个界面也不会掉进错的那一段。
`NavRailDestination` 是它的项类型：一个图标、一个词、一个计数，而且没有选中态的另一枚
图标，因为这一列在某一项变成当前项时并不换图标。`RailItem` 就是那一项本身，公开，按
label 找得到。

`WeChat` 添上从稿子逐条抄来的十二个导航轨令牌（`railWidth` 84、上下两处 padding、项间距、
品牌位与标记、项圆角与内边距、图标与文字的间距、图标与文字的字号）；窄窗口继续用
Material 的 `NavigationBar`。shell 只构造一份有序的 `_Surface` 列表——两枚图标、一个词、
一个计数——两种布局拿到同一个顺序：导航轨取那枚描边图标，底栏两枚都要，因为把当前那一
格的图标填实是 Material 说「读者在这里」的方式。

## Consequences

- `lib/ui/nav_rail.dart` 是新增的。品牌标记是把稿子那份 24 × 24 的 SVG 逐条命令抄下来、
  缩放到 26，用 `CustomPaint` 画而不是用图标：最接近的 Material 替身（`Icons.eco`）是一片
  没有气泡的叶子，而这块正好与窗口自己那枚图标挨着。
- `lib/ui/wechat/theme.dart` 去掉 `navigationRailTheme`（没有东西读它了），添上那十二个
  令牌。标签继承的是 `lineHeightBody`（1.4），不是稿子那一页自己的行高，所以一项的底
  大约 56.4 像素，而稿子量出来是 58。
- `lib/ui/home_shell.dart` 把六个界面只构造一次、只放一份列表，并把 `pinnedCount` 和作为
  `trailing` 的更新入口交给导航轨。
- `test_flutter/ui/nav_rail_test.dart` 是新增的：两段与脚部、整块选中态、指针、以及 Tab
  走一遍。`ui_harness.dart`、`shell_test.dart` 与 `update_rail_test.dart` 里原来写
  `NavigationRail` 的地方改成 `AppNavRail`。
- 同轮在上面那条笔记里追加了「更新执行期间所有入口置灰、确认按钮改口更新并重启」：
  手搓 RailItem + 手搓的更新按钮（`_UpdateEntry`）现在由 shell 的 `_updateLocked`
  驱动置灰，置灰就是这个新组件自己的事了。
- 这条轨道从此归我们维护。键盘遍历、无障碍语义、RTL，以及将来任何禁用态都在我们手上；
  这些地方回归，除了我们自己的测试没有别的组件测试会红。
- 有几份旧笔记写的是组件，而这次构建写的是这条轨道：[固定在侧栏底部的更新入口](2026-10-12-an-update-entry-in-the-rail.md)
  把入口写成 `NavigationRail(trailingAtBottom: true)`；[左侧菜单更新按钮改为一键安装并在
  About 页进行](2026-10-15-the-rail-entry-installs-instead-of-opening-a-browser.md)
  把轨道量成 72 像素——那是组件的默认值，不是这份稿子的 84；[应用有了屏幕](2026-09-30-flutter-ui-shell.md)
  与 [WeChat 的样子覆盖每个界面](2026-10-09-wechat-theme-everywhere.md) 分别把
  `NavigationRail` 写作容器和一件换了皮的组件。这些是要一并带上的是事实，不是变了的决定。

## Alternatives considered

**继续用 `NavigationRail`，只设 `indicatorShape`。** 形状是参数，尺寸不是。在一个固定的
56 × 32 的盒子上套 `RoundedRectangleBorder`，出来是个更圆的胶囊，不是稿子那块底，也没有
任何东西把它撑到文字上面去。

**用 `leading` 和 `trailing` 把稿子拼出来。** `leading` 放品牌位、`trailing` 配
`trailingAtBottom` 放脚部，排布是够得着的——但两个工具为了拿到上方那段空白必须离开
`destinations`，而 `destinations` 之外的项没人画。两条路都落到手搓导航项上；组件能贡献
的只是一个 `Material` 和一个 `SafeArea`，却要替 shell 管一份它本来就管着的顺序。

**每项做一个 destination，用胶囊形的 `indicatorShape`。** 每一项唯一能动的杠杆是
`padding`，而 padding 动的是这一项的盒子，不动那个跟着图标走的 56 × 32 标记；标记只会
在一个更高的盒子里居中，而不是填满它。

**干脆用 `GestureDetector`。** 更省事，代价是丢掉键盘：`InkWell` 带来焦点、
`ActivateIntent` 的绑定，以及让这一列能被 Tab 走到的语义角色。

**`NavigationDrawer`，或者扩展态导航轨。** 这两个回答的是别的问题：抽屉是盖在内容上的
模态列表，扩展态导航轨把宽度花在标签上，而这份稿子已经把标签放在图标下面了。

**自绘的同时留一个主题槽位。** 没有东西会读它，而一个没人读的槽位，正是下一个读者去找
这条轨道的配色、然后找不到的地方。

# Agent Note: 禁用的按钮不再穿品牌绿

Status: implemented

[English](2026-11-20-disabled-buttons-look-disabled.md) | 中文

## Problem

关于页的更新按钮在下载期间其实已经拒绝了第二次按压——`session.busy`
整个期间 `onPressed` 都是 `null`——但它看起来和「完全没注意到这次按
压」一模一样。下面的进度条在走，按钮却还穿着品牌绿，和一个可点的按钮
同一个颜色，于是点了「更新」的用户很合理地以为点击被吞了。

根源在主题，不在按钮。`filledButtonTheme` 与 `textButtonTheme` 用
`WidgetStatePropertyAll` 钉死了 `backgroundColor`/`foregroundColor`，它对
所有状态——包括 `WidgetState.disabled`——都解析成同一个颜色。Material
自己的默认值会先检查禁用态；一个对所有状态都作答的主题会盖掉这个检
查，于是「不能按」和「能按」画出来毫无区别。排错页早就撞上过这个问题，
当时在本地绕了一下——它的注释把没说出口的话写明白了：「禁用的按钮看起
来仍然可以按」。

## Decision

禁用色这一对搬进了主题，所有按钮都能拿到——而且对全仓「可能禁用」的控
件扫了一遍，在实心/文字这一对之外又发现三处同样的毛病。

- **`filledButtonTheme`** 按状态解析 `backgroundColor` 与
  `foregroundColor`：禁用取 `surfaceSunken` 与 `disabledText`——调色板里
  本来就为「这里没什么可做的」定义的凹陷填充和最淡一档文字色——其余状
  态保持 `brandStrong` / `onBrandStrong` 不变。
- **`textButtonTheme`** 同样按状态解析 `foregroundColor`，禁用的安静操作
  淡成 `disabledText`，而不是继续是动作绿。
- **`segmentedButtonTheme`** 同样按状态解析两种颜色，理由相同：剪贴板页
  会把本平台做不到的同步模式显示成禁用分段，气泡皮肤选择器的文字色开
  关在没有草稿可应用时会禁用自己——两者都保持 `bubbleText` 配
  `surface`，看起来和「可以选」一模一样。
- **导航栏的更新入口**保留自己的 `styleFrom`，它给所有状态都写了
  `foregroundColor`，会盖掉主题的修复；现在同时写了
  `disabledForegroundColor: colors.disabledText`。
- **截图浮层的工具条**用自己的深色调色板，不在主题够得着的地方：「完
  成」与「钉图」在各自的 `styleFrom` 里写了
  `disabledBackgroundColor`/`disabledForegroundColor`（`white24`/
  `white38`，同一对颜色的深色版）。
- **附件缩略图的删除角标**用 `color: Colors.white` 钉死了可用态的墨
  色；现在写了 `disabledColor: Colors.white38`——否则禁用时回落到主题
  的 surface 灰，压在 scrim 圆点上读起来像「少了个 ×」而不是「禁用的
  ×」。
- **排错页的本地绕行删掉了。** 它的 `FilledButton.tonalIcon` 读的是同一
  个 `filledButtonTheme`，主题现在提供的正是它手搓的那一对——可用态落回
  主题的品牌色，禁用态落回同样的凹陷/淡色对。

审计过、刻意不动的控件：`_RowAction`/`_BubbleAction` 的 `onPressed` 是必
填 `VoidCallback`，永远不可能禁用；`_SendButton`、`ComposerTool`、
`EmojiPickerButton`、`PaneSplitter` 自己解析禁用外观；其余 `IconButton`
要么不会禁用，要么落到框架默认的禁用色；`Switch`、`Checkbox`、
`Radio` 从不给空 handler；传输页的 `Chip` 是标签不是控件。

## Alternatives considered

**只在更新按钮上覆盖颜色**，照排错页的做法。否决：它只修被报告的那一个
按钮，而同样「禁用却看不出禁用」的毛病还留在全应用每一个能禁用的控件
上——对话框的确认键、分享页的操作、设备页的连接键、剪贴板页做不到的
模式——每一个都会继续看起来可以按。

**只改按钮文字或加个转圈。** 否决，属于半个修复：进度句已经在下面说明
下载在做什么，而一个不能被按的控件本来就该看起来不能被按。缺的事实是
状态，不是措辞。

**用 `Opacity` 把整个按钮调淡。** 否决：在未知底色上做半透明，正是调色
板里那套命名色阶要避免的事，而 `disabledText`/`surfaceSunken` 在两种亮
度下早就把「未激活」编码好了。

## Consequences

- 全应用的 `FilledButton`、`TextButton` 与 `SegmentedButton` 第一次有了
  真正的禁用态，另外两处在主题够不着的地方也各自补上。更新卡的按钮在下
  载一开始就变灰，这正是报告要的反馈；第二次按压本来就不可能，现在看起
  来也不可能了。剪贴板页做不到的模式和皮肤选择器的文字色开关读起来是
  「不可用」而不是「坏了」。
- 导航栏入口在被锁定期间——卡片自己的更新检查期间，以及整个安装过程
  中——淡成 `disabledText`，和关于页按钮的表现一致。
- 以后的按钮只要进入禁用态就自动得到正确的样子，不必记得来要；排错页
  首创的「逐处绕行」模式不再需要。
- 手搓 `styleFrom`/`ButtonStyle` 前景色的按钮仍然按设计绕开主题——输入
  区的发送键自己管着它的禁用色对——所以新调用点如果再把颜色钉死给所有
  状态，就会在局部把这个 bug 请回来。浮层的修法就是要抄的范式：可用色
  和禁用色并排写。

## Testing

- `test_flutter/ui/update_session_test.dart`——「greys the update button
  while its download runs」对着一个被扣住的安装器按下「更新」，断言下载
  进行中 `FilledButton` 的 `onPressed` 为 null，并把主题实心按钮样式按
  `WidgetState.disabled` 解析，钉住 `surfaceSunken` / `disabledText`——正
  是以前会解析成品牌色的那一对。
- `test_flutter/ui/theme_buttons_test.dart` 钉住分段控件的禁用解析——
  `disabledText` / `surfaceSunken`——并确认选中与普通可用状态仍解析为
  `brandStrong` / `bubbleText`。

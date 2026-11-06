# Agent Note: 左侧「更新」入口会打开卡片并显示进度

Status: implemented

[English](2026-11-05-the-rail-update-entry-shows-its-work.md) | 中文

收窄了[左侧「更新」入口改为安装而不是打开浏览器](../feature/2026-10-15-the-rail-entry-installs-instead-of-opening-a-browser.zh.md)
的范围，并建立在[更新下载由 session 持有](2026-11-05-update-download-session.zh.md)之上：
安装已经可以脱离发起它的页面存活，但 rail 入口仍然必须证明这次点击已经生效，并展示
它有空间承载的紧凑状态。

## Problem

自动检查发现新版本后，rail 显示「更新」。点击它会在 session 里启动安装并切到「我的」
表面 —— 但落在的是卡片列表，下载的任何进展都看不见；入口本身也只知道一个布尔
「忙」答案：它可以被置灰，却说不出这次点击已被接受、说不出工作正在进行，也显示不出
下载进行到哪一步。对用户来说，这个按钮看起来仍然是死的。

## Decision

**rail 点击会打开展示这份工作的那张卡片。** 安装由 session 持有 —— 点击直接到达它，
与 About 卡片何时被构建无关 —— 所以 `MyPage` 欠一次请求的只是卡片所在的子页面：
shell 在 `_index` 旁边自增 `openAboutRequests` 计数，它一变就打开 `_SubPage.about`。
用计数器而不是标志位，是为了让每次点击都是一次请求，即使卡片当时已经开着；卡片
自己不需要「打开即安装」的路径，因为根本没有需要它消费的请求 —— session 已经拿着
这份工作了。

**rail 绘制 session 上报的状态。** `HomeShell` 本来就在听 session 的忙碌边沿；现在它
还保存 `_sessionPercent` —— 下载字节数已知时算出的整数百分比。比较的是展示值而不是
progress 对象，因此按字节块上报不会让 rail 的重建快过数字本身的变化。session 忙碌
期间入口置灰并显示「更新中」；下载比例已知时追加百分比行，其他阶段都是同一个更新中
状态。session 回到空闲 —— 失败、取消或交接 —— 入口恢复「更新」，也就是重试。

**「包已就绪、等回答」的窗口期保持可点。** `session.busy` 在安装包等待确认时为 false，
所以入口不会被一个它本来也点不到的模态对话框锁住；这时再按一次会计入一次
`confirmRequests`，这正是卡片把同一个问题再问一遍、而不是开始第二次下载的方式。

## Alternatives considered

**让点击落在卡片列表上。** 否：下载会在除了 rail 标签之外完全不可见地运行，进度条、
确认问题和失败句子都还要再点一下才出现。这次点击要的是更新，把它的卡片展示出来就是
答案。

**从卡片向上传一条 progress 回调。** 否：卡片现在是 session 的视图，而 shell 本来就在
听这个 session —— 第二条上报通道就是同一次更新的第二个来源。

**在 rail 里画进度条。** 否：rail 宽 84 像素，已经承载图标加标签。About 卡片继续负责
字节数和确定进度条；rail 只承载它有空间放下的那一个百分比。

**确认框打开期间锁住入口。** 否：`session.busy` 在那时已经是 false，而且锁住会藏起
唯一有意义的那次点击 —— 「再问我一次」。确认框是模态的，入口本来也点不到。

## Consequences

- `lib/ui/home_shell.dart` 在 `_sessionBusy` 旁跟踪 `_sessionPercent`，把
  `openAboutRequests` 传给 `MyPage`，并把 `updating`/`percent` 这一对值交给
  `_UpdateEntry`，由它选择「更新中」加百分比。
- `lib/ui/pages/my_page.dart` 在 `openAboutRequests` 变化时打开 About 子页面；它不持有
  任何安装状态。
- `lib/l10n/app_en.arb` 与 `lib/l10n/app_zh.arb` 新增 `railUpdateRunning` 与
  `railUpdatePercent`；生成的本地化文件一并提交。
- `test_flutter/ui/update_rail_test.dart` 断言点击会打开 About 并到达安装器、挂起的
  下载期间入口置灰且显示百分比、失败后恢复为重试。
- `test_flutter/support/ui_harness.dart` 改为按图标查找入口，这样标签变化后 finder
  仍然有效。

## Testing

`flutter test test_flutter/ui/update_rail_test.dart` 与
`flutter test test_flutter/ui/update_session_test.dart` 覆盖 rail 打开卡片、挂起下载时
入口置灰与百分比、失败后重试、取消确认后复用已准备安装包，以及 Android 安装器交接。

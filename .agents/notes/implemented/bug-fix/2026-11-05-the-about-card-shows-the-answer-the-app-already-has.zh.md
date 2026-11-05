# Agent Note: 关于卡片展示应用已知的答案

Status: implemented

[English](2026-11-05-the-about-card-shows-the-answer-the-app-already-has.md) | 中文

## Problem

应用启动时向 GitHub 问一次 —— `UpdateNotice` 整个运行期间都持有那个答案 ——
「我的」页关于卡片的摘要已经在读它：有新版本发布时卡片会写「有新版本」并给出
版本号。但卡片背后的页面没有。`AboutPage` 自己持有 `_answer`，只有按下它的按钮
或 rail 的安装入口到达时才会被赋值，所以跟着卡片的提示想弄清新版本是什么的
用户，看到的却是「检查更新」—— 同一个问题被问了第二次，出现在唯一负责回答它
的界面上。

这个缺口曾经是有意的：`offeredUpdate` 只在安装请求到达时才被采用，让卡片在
有人问它之前保持沉默。那条规则在通知的答案只用于一件事 —— 启动安装 —— 时说得通；
当「我的」卡片开始*展示*它的那一刻就不再成立：摘要和页面对一个双方都已知的事实
给出了两个答案。

## Decision

`AboutPage` 在拥有自己的答案之前镜像 `offeredUpdate`。`_adoptOffered()` 从
`initState` 和 `didUpdateWidget` 调用，覆盖 offered 答案变化的两种方式 ——
页面在通知已应答后才被构建，以及页面打开期间通知首次应答或再次应答 —— 并且
直接赋值而不调用 `setState`，因为两个调用点都运行在 build 之内。

只要 `_mirroring` 为真，镜像就会继续：通知带来的更新答案 —— 每小时一次的
周期检查 —— 会替换屏幕上的内容，使这张卡片提供安装的版本与 rail 入口将要安装
的版本一致。页面自己的检查（`_check`）或一次安装会结束镜像，此后到达的通知
答案不得改写正在执行的下载所针对的内容。提问发出或下载进行中时跳过采用；
已取回的安装包只在新显示的答案点名了不同版本时才被丢弃 —— 每小时的复查会为
同一个发布交出一个新的 `UpdateCheck`，为此丢掉下载会让「先答否、稍后再答是」
为同一次抓取付两遍钱。

展示答案不发起任何请求：问题已经由应用问过一次了。页面的承诺不变 —— 它依然
不会在到达时访问本地网络之外。

`MyPage` 把通知的答案实时传下去：「我的」页关于卡片的摘要和关于子页面都包在
对 `UpdateNotice` 的 `ListenableBuilder` 里，屏幕上任一方存在时落地的答案无需
等待无关的重建就会出现。在此之前摘要本身也可能过期 —— shell 按自己的原因重建
页面，而不是按通知的。

同一次修复还暴露出第二个被丢掉的请求。rail 的更新入口把按压计入
`installRequest`，此前由 `AboutPage.didUpdateWidget` 应答 —— 但卡片只在其
「我的」子页面打开期间存在，于是卡片列表显示时到达的按压无处应答而丢失；
现在该请求由 `MyPage` 以 `_pendingInstallRequest` 持有，只在未被确认期间向下
传递，由 `AboutPage.onInstallRequestHandled` 回执。按压之后才挂载的卡片在
`initState` 的下一帧应答它，而计数归零是确认落地，不是第二次按压。

Windows 与 Android 共用同一份代码：rail 入口只在宽窗口出现，但「我的 → 关于」
的路径两端一致，因此一次修复同时覆盖两个平台。在 Android 上，镜像来的答案还让
「更新」按钮为摘要所指的版本提供系统安装器流程。

同一次改动还修复了 `test_flutter/support/ui_harness.dart` 的 `openMyCard`：
它仍在找「我的」页改版为整卡可点之后就不再渲染的「查看详情」按钮，导致
`develop` 上所有打开「我的」卡片的测试全部失败。

## Alternatives considered

**到达时重新提问。** 否决：这会把「每次运行刻意请求一次」变成「每次访问请求
一次」，正是页面自身文档所禁止的 —— 而且它回答的是一个已有答案的问题。

**只在 `initState` 里采用一次 offered 答案。** 否决：页面打开后才落地的答案
—— 用户已在卡片上时启动检查才完成 —— 永远不会出现；每小时复查找到的更新
答案会让卡片提供一个过期版本的安装。

**永久镜像通知，即使页面已自行提问之后。** 否决：页面自己的检查或一次安装
执行过之后，它的答案才是更新的事实，之后到达的通知答案不得改写正在执行的
下载所针对的内容。

**只展示 `UpdateOutcome.available`，其余三种保持沉默。** 否决：`upToDate`、
`noRelease` 与 `unreachable` 也是答案，卡片依据应用已经跑过的那次检查写出
「已是最新」或「无法检查」，比一个暗示什么都不知道的按钮更诚实。「我的」卡片
的摘要仍然只呈现 available 这一种 —— 也是唯一值得提示的一种。

## Consequences

- `lib/ui/pages/about_page.dart`：新增 `_mirroring` 标志与 `_adoptOffered()`；
  `initState`/`didUpdateWidget` 采用 offered 答案；`_check` 结束镜像；文档注释
  改为说明卡片是镜像而非等待。
- `lib/ui/pages/my_page.dart`：「我的」页关于卡片摘要与关于子页面监听
  `UpdateNotice`；`_pendingInstallRequest` 在卡片确认前持有 rail 按压；
  新增 `_aboutCard`/`_aboutPage`/`_aboutPageWith` 辅助方法。
- `lib/ui/pages/about_page.dart`：`onInstallRequestHandled` 由
  `didUpdateWidget` 或 —— 对于按压之后才挂载的卡片 —— `initState` 确认；
  只有递增的 `installRequest` 才算按压。
- `test_flutter/ui/about_page_test.dart`：`show` 接受 `offeredUpdate`；新增
  测试覆盖不提问直接展示已知答案、采用迟到的答案、以及页面自己的答案优先于
  随后到达的 offered 答案。
- `test_flutter/ui/update_rail_test.dart`：新增测试在已知新版本下打开
  「我的 → 关于」，断言版本号、安装按钮存在且没有「检查更新」。
- `test_flutter/support/ui_harness.dart`：`openMyCard` 改为点击卡片本身。

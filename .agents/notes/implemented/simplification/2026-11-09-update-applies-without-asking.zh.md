# Agent Note: 更新不再询问，下载完成直接应用

Status: implemented

[English](2026-11-09-update-applies-without-asking.md) | 中文

部分取代[左侧菜单更新按钮改为一键安装并在 About 页进行](../feature/2026-10-15-the-rail-entry-installs-instead-of-opening-a-browser.zh.md)
与[关于页只有一个更新操作](../feature/2026-10-26-one-update-action-on-the-about-card.zh.md)
中记录的确认步骤，以及[更新下载由会话持有](../bug-fix/2026-11-05-update-download-session.zh.md)
里的 `confirmRequests` 机制。会话持有下载、重启后从磁盘恢复这两件事不变。

## Problem

按下「更新」会跑 `prepare`——下载、校验、解包——然后停下来问一句「更新并重启？」
或「安装更新？」，确认之后才 `apply`。这个问题存在的理由是 `apply` 会结束进程：
一个不声不响就把自己关掉的程序是可怕的。但实际上按下「更新」本身就已经是用户
「替换正在运行的构建」的决定，弹窗只多了一步、没有多一个决定——在 Android 上它
还把系统安装器（自带确认界面）挡在了第二道应用内闸门后面。

## Decision

`UpdateInstallSession` 把 `prepare` 和 `apply` 首尾相接地跑完。prepare 完成后由
会话自己 apply，除非它来自 `restore`；按到一个已就绪包上的按压直接调 `apply`，
不再递增 `confirmRequests`。确认弹窗、它的六个 l10n 词条、会话的确认计数全部移除；
`preparedIsRestore` 也随之消失——restore 与按压的区别现在完全由 `_prepare` 的
`restored` 参数承担，它决定完成的 prepare 是被应用还是只被提供。

`_progress` 旁边新增 `_applying` 标记交接正在进行。负责替换自身的平台在交接期间
不上报进度，没有这个标记，交接窗口内的第二次按压可能启动第二次交接。

`restore` 从磁盘找到的包依旧只被提供：打开一个页面不等于请求关闭应用，同一个
「更新」按压才会应用它。

## Alternatives considered

**只在 Android 上保留弹窗。** 否决：那里同样没有收益——`apply` 打开的是系统
包安装器，系统自己会问，应用内弹窗只是闸门前的又一道闸门。

**只在 About 页构建期间自动应用。** 否决：会话本来就比页面活得久，让交接取决于
有没有可见界面，会让「下载完成时你在传输页」和「下载完成时你正看着」表现不一致
——前者要等一次访问，后者不会。

**保留一个取消窗口——下载落地几秒后再应用。** 否决：一个会关掉应用的定时器比
两个极端都糟；按压已经回答了窗口本要问的问题。

## Consequences

- 按一次「更新」现在直接以应用关闭（Windows）或系统安装器打开（Android）收场，
  中间没有弹窗。
- 下载完成时若有传输正在进行会被打断——这是有意接受的；不再有重新考虑的时刻。
- `confirmRequests` 与 `preparedIsRestore` 不复存在；widget 测试改为断言
  `installer.applied`，而不是断言弹窗。
- `scripts/packaging-probes.json` 用同样独特且无占位符的
  `aboutUpdateInstallHintAndroid` 换掉了被移除的 `aboutUpdateConfirmTitle` 探针。

## Testing

`test_flutter/ui/about_page_test.dart`、`update_session_test.dart` 与
`update_rail_test.dart` 固定了这些行为：完成的 prepare 在没有 `AlertDialog`
的情况下被应用、restore 找到的包按压后不重新下载即被应用、apply 失败以通常的
失败文案呈现、交接期间的第二次按压不能启动第二次交接。

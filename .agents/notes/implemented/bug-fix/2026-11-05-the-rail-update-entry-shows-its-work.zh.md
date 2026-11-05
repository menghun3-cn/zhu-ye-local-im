# Agent Note: 左侧「更新」入口会打开卡片并显示进度

Status: implemented

[English](2026-11-05-the-rail-update-entry-shows-its-work.md) | 中文

收窄了[左侧「更新」入口改为安装而不是打开浏览器](../feature/2026-10-15-the-rail-entry-installs-instead-of-opening-a-browser.zh.md) 的范围：
安装仍然属于 About 卡片，但 rail 入口现在必须证明这次点击已经生效，并展示它
有空间承载的紧凑状态。

## Problem

自动检查发现新版本后，rail 显示「更新」。点击它可能看起来像没反应：shell 切到了
「我的」表面，但 About 卡片是「我的」里面的子页面，仅有 `installRequest` 计数并不
会打开它或启动安装。rail 也只知道一个布尔「忙」答案，因此无法说明这次点击已被
接受、无法表明工作正在进行，也无法显示下载进行到哪一步。

## Decision

**rail 点击会打开它要交接安装的那张卡片。** `MyPage` 把新的 `installRequest`
当作「打开 About 并启动一次」，通过 `installOnOpen` 传给卡片；About 卡片已经存在
之后，后续点击仍然走计数器，由 `didUpdateWidget` 应答。这个一次性标志会在第一帧后
清除，因此一个最终没有启动的请求不会残留，并在之后某次进入时自行启动。

**rail 绘制卡片上报的最新阶段。** `AboutPage` 把 `UpdateInstallProgress` 经
`MyPage` 传给 `HomeShell`，并按帧合并上报：下载按收到的字节块上报，而安装又可能
从 `didUpdateWidget` 启动。只要 progress 非空，入口就置灰并显示「更新中」；下载
字节数已知时再加百分比行，其他阶段都显示同一个更新中状态。收到 null 后恢复「更新」。

**已就绪的安装包不等于仍在进行的工作。** `_confirmingUpdate` 把「关闭前的确认框
正在打开」与「安装包已准备好」分开。回答否、失败或把安装器交接出去都会清除进行中
状态，但不会丢弃安装包，因此同一个控件就是重试入口，也不会为此重新下载二十兆字节。

## Alternatives considered

**让点击只切换表面。** 否：这正是被报告的 bug。用户点了「更新」，却落在卡片列表
上，没有任何证据表明已经提出了请求。

**让 shell 自己维护第二份下载状态。** 否：rail 会有一套与 About 卡片真实状态并行
的「正在下载」定义。两个来源描述同一次更新必然漂移；rail 只是卡片上报内容的投影，
不是第二个安装器。

**只上报 busy，不上报 progress。** 否：需求是按钮要显示更新中，条件允许时还要有
百分比。布尔值能置灰入口，却说不出下载进行到哪一步。

**在 rail 里画进度条。** 否：rail 宽 84 像素，已经承载图标加标签。About 卡片继续
负责字节数和确定进度条；rail 只承载它有空间放下的那一个百分比。

## Consequences

- `lib/ui/pages/my_page.dart` 会为新的 `installRequest` 打开 About 子页面，并把
  `UpdateInstallProgress` 向上传递。
- `lib/ui/pages/about_page.dart` 接受 `installOnOpen` 与
  `onUpdateProgressChanged`，在帧边界上报进度，并用 `_confirmingUpdate` 让
  「已准备但已回答否」的状态恢复可用。
- `lib/ui/home_shell.dart` 保存最新上报的进度并传给 rail 入口；入口在下载字节数
  已知时置灰、从「更新」切到「更新中」并显示百分比。
- `lib/l10n/app_en.arb` 与 `lib/l10n/app_zh.arb` 新增 `railUpdateRunning` 与
  `railUpdatePercent`；生成的本地化文件一并提交。
- `test_flutter/ui/update_rail_test.dart` 现在断言点击会打开 About 并启动安装器、
  挂起的下载期间入口置灰且显示百分比、失败后恢复为重试。`test_flutter/support/ui_harness.dart`
  改为按图标查找入口，这样标签变化后 finder 仍然有效。

## Testing

`flutter test test_flutter/ui/update_rail_test.dart` 与
`flutter test test_flutter/ui/about_page_test.dart` 覆盖 rail 打开卡片、挂起下载时
入口置灰与百分比、失败后重试、取消确认后复用已准备安装包，以及 Android 安装器
交接。

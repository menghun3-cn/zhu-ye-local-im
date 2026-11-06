# Agent Note: 设置卡片把默认接收文件夹也算作已设置

Status: implemented

[English](2026-11-06-settings-card-counts-the-default-incoming-folder.md) | 中文

## Problem

「我的」页上的设置卡片只读 `controller.incomingDirectory`——也就是用户亲手填的
文件夹，其余一概不看。而每个平台本来就有 `defaultIncomingDirectory`（Windows 是
下载目录，Android 是应用自己的 `incoming` 目录），没有手动选择时收到的文件也会
落在那里。因此在 Android 上，卡片显示「接收文件夹未设置」，但实际上目的地是存在
的——这读起来像一个坏掉的设置，而不是一个还没做的选择。

## Decision

卡片摘要改用页面本来就算好的那个解析结果：
`controller.incomingDirectory ?? seams.defaultIncomingDirectory`。只有选择和
平台默认都不存在时才显示「未设置」——目前这只发生在 `other` 平台，或拿不到
app-data 目录的 Android 构建上。控制器保留的区分（用户选定的文件夹 vs 平台建议）
没有变：设置页仍然把默认值显示为建议，而不是已存的选择。

## Testing

`test_flutter/ui/pages_test.dart` 在 Settings 相关的测试组里新增两个 widget
测试：一个带 `defaultIncomingDirectory` 的设备显示「已设置」而不显示「未设置」，
另一个两者皆无的设备显示「未设置」。

## Alternatives considered

**在摘要里直接显示解析出的路径。** 否：卡片摘要是简短的本地化标签，裸路径又长
又不本地化，而且只要点一下就能在设置页看到。

**新增第三种「使用默认文件夹」文案。** 暂否：需要在两个 ARB 文件里加字符串并重
新生成，而这两个状态用户无法采取不同动作——都表示「文件有地方可放」。

**让卡片只记录用户的选择。** 否：「未设置」回答的是没人问过的问题。用户想知道
的是收到的文件有没有目的地，而平台默认就是一个目的地。

## Consequences

- 在 Windows 和 Android 上，设置卡片现在总是报告文件夹已配置，与文件实际落点
  一致。
- 「未设置」只对完全没有默认目录的平台保留。
- 「已选 vs 默认」的区分仍然留在设置页里、可以编辑的地方；卡片保持摘要定位。

# Agent Note: 「我的」页链接到 QQ 反馈群

Status: implemented

## Problem

遇到问题或有建议的用户在应用内没有通往项目社群的入口。「我的」页已经聚合了低频页面，但每张卡片打开的都是应用内子页面；没有对外的社群入口。

## Decision

「我的」卡片列表在故障排查与关于之间新增「反馈问题或建议」卡片。标题与摘要走本地化（`myCardFeedback`、`myCardFeedbackSummary`），点击时把 `https://qm.qq.com/q/rpttgcx0MC` 交给 `LinkResolution.opener`，而不是打开子页面。地址是 `my_page.dart` 里的私有常量 `_qqGroupUrl`，就放在唯一的使用者旁边。

widget 测试安装 `ScriptedLinkOpener`，在足够高的窗口里点这张卡片，并断言打开的链接恰好只有这个 QQ 群地址。

## Alternatives considered

**做一个反馈子页面。** 否：目标是外部 QQ 群页面；应用内页面只会多加一个按钮，仍然要再跳一次同样的交接。

**把链接放到关于卡片。** 否：关于页讲的是程序本身与更新；反馈是社群入口，适合和「我的」页其他对外卡片放在一起。让关于继续保持最后，也保留了用户已经熟悉的卡片顺序。

**把群地址做成远程或可配置项。** 否：社群链接没有设置项或远程配置面；像 `appWebsiteUrl` 和更新端点一样写死在唯一使用者旁边更一致。

## Consequences

- Windows 与 Android 都会显示这张卡片，因为打开浏览器是 `LinkResolution` 已覆盖的平台外壳能力。
- 如果 opener 无法启动浏览器，卡片目前没有屏幕上的兜底；这与其他直接链接点击一致，而关于页在启动失败更有后果的场景保留了可选中的地址。
- 更换 QQ 群要改 `_qqGroupUrl`；widget 测试钉住了当前地址，误改会直接失败。

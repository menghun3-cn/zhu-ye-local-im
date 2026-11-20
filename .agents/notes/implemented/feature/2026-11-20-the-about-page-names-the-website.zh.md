# Agent Note: 关于页标明官网地址

Status: implemented

## Problem

关于卡片讲清了这个应用是什么、怎么拿到新版本，却只字未提项目在网上的
位置。官网承载着卡片装不下的信息——完整的系统要求、如实的外网说明、发
布记录——而读到关于页的用户没有任何指引可以过去。卡片知道的对外地址只
有更新检查用的 GitHub 端点，那是管道，不是可以送人的地方。

## Decision

`appWebsiteUrl`（`https://menghun3-cn.github.io/zhu-ye-local-im/`，即
`site/` 经 Pages 部署的地址）作为常量定义在 `about_page.dart`，就放在
展示它的页面旁边。卡片在更新区块之后新增一行：官网标签、「打开官网」
`TextButton`（与其他对外链接一样走 `LinkResolution.opener`），以及地址
本身的 `SelectableText`——与下载地址同一待遇，没有默认浏览器的机器仍
有可复制的地方。

两个新词条同时进了两份 ARB：`aboutWebsite`（官网 / Website）与
`aboutOpenWebsite`（打开官网 / Open the website）。按 `l10n.yaml` 的约
定，生成的 `app_localizations*` 文件重新生成并提交。

## Alternatives considered

**从 `updateRepository` 推导该地址。** 否：`updateRepository` 是给 API
和发布页用的 `owner/repo`；Pages 地址是另一种形状
（`owner.github.io/repo`），只是碰巧共用片段，对它做字符串拼接会把真
正随包发布的地址藏起来。

**把链接写进描述正文。** 否：`aboutDescription` 是一段关于应用本身的
文字；正文里裸一个 URL 既不是有意做成可选中的，也不可翻译，而卡片早已
有「标签 + 按钮 + 可选中地址」的现成模式，这里直接复用。

**链到 GitHub 仓库而不是官网。** 否：仓库已经能从更新流程的下载页到达；
官网才是用户真正读得下去的界面——值得新增的就是这一条地址。

## Consequences

- 关于页现在标明了一个稳定的对外地址，且不依赖任何更新检查的结果；它
  无条件渲染。
- URL 是写死的，换域名或 Pages 路径时要改 `appWebsiteUrl`——可以接受，
  因为那种场景下被改名的本来就是网站本身，而常量就放在唯一的使用者旁
  边。
- `test_flutter/ui/about_page_test.dart` 无需改动：新行只加控件，不加网
  络行为——opener 与下载按钮走的是同一个 `LinkResolution` 接缝。

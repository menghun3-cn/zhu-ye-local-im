# Agent Note: Make a staged clipboard entry reach the screen

Status: implemented

[English](2026-09-30-staged-clipboard-entry-never-reaches-the-screen.md) | 中文

## Problem

当剪贴板同步设为 *Ask me* 时，来自对端的条目不会被直接应用。它会被**暂存**（staged）：等待用户接受或丢弃，而 Clipboard 页面负责渲染这份等待列表。

`ClipboardMirror` 把暂存条目报在它自己的 `staged` 流上，而不是走控制器已经传入的 `onNotice` 回调。这个切分是刻意且正确的 —— 一个暂存条目是「待回答的东西」，不是这台 Device 的即时旁白 —— 但 `LocalTransferController` 里没有任何东西订阅这条流。mirror 提供的其它每条通道最终都走到了 `_notify()`：notice 走 `_notice`，apply 走包裹它的那些调用，而 `changes` 正是 UI 重建所依赖的流。

于是暂存条目抵达时，没有人被告知。页面继续渲染它上一次因某个无关事件触发变更时构建出的列表 —— 某个 Transfer 在推进、某个 peer 出现、剪贴板模式被切换 —— 或者等用户切走再切回来时自行纠正。功能是通的，看起来却是坏的：*Ask me* 恰恰是「用户正看着屏幕、就该在这时问他」的模式。

没有测试抓到它，因为测试都是直接驱动控制器、读取 `stagedEntries`，而那个值始终是对的。缺的是通知，而没有任何东西断言「会有人被告知」。

## Decision

控制器订阅 mirror 的 `staged` 流，并在其上通知 —— 与它对自己监视的其它每一处变更的做法相同：

```dart
_watch.add(clipboard.staged.listen((_) => _notify()));
```

该订阅被放进 `_watch`，因此 `close()` 会连同其余订阅一起取消它。

## Alternatives considered

**改为把暂存条目也走 `onNotice`。** 否决理由：Clipboard 页面把 notice 渲染为 Device 的旁白，把暂存列表渲染为等待回答的条目。把两者合并，要么让一个等待中的条目看起来像一次故障，要么逼 UI 从一种列表里把另一种 notice 筛出去。

**让 Clipboard 页面用定时器轮询 `stagedEntries`。** 否决理由：为了一条没接上的流而长期保留一个轮询，是把本该一次修好的疏漏变成永久成本；而且它会在控制器自身的通知之外，再引入一个「页面多久刷新一次」的问题。

**不管变的是什么，每次控制器变更就重建。** 否决理由：控制器对它监视的其它所有东西本来就会通知。这是一处漏掉的订阅，不是一条缺失的策略；换掉策略只会把下一处漏订阅也一起藏起来。

## Consequences

- 暂存条目一抵达就出现在 Clipboard 页面上，这正是 *Ask me* 承诺的全部内容。
- `test/app/app_controller_test.dart` 在缺陷原本所在的那一层钉住它：它监听控制器的 `changes` 流，并断言在有条目被暂存时该流会触发。移除这个订阅会让该测试失败。
- `test_flutter/ui/pages_test.dart` 透过 widget 树覆盖同一行为，因此页面本身与那条流都得到了检查。
- 被记下来的是教训而不只是修法：一条调用者**可以读**的流，与一条屏幕**会被告知**的流，不是一回事；而这个差别只在控制器里被决定。

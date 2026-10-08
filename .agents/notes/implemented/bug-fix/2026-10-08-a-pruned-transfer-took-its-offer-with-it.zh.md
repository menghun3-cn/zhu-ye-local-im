# Agent Note: 一条被裁剪的 Transfer 会把它未送达的 offer 一起带走

Status: implemented

[English](2026-10-08-a-pruned-transfer-took-its-offer-with-it.md) | 中文

## Problem

`LocalTransferController._pruneTransfers` 在被跟踪的 Transfer 列表超过一百条
之后会把它裁掉。它先丢已 settle 的，然后不分状态丢最旧的：

```dart
_transfers.removeWhere((tracked) => tracked.transfer.isSettled);
while (_transfers.length > keep) {
  _transfers.removeAt(0);
}
```

除列表之外，还有两样东西持有一条 Transfer。一个是它进度上的
`StreamSubscription`，在 settle 时被取消。另一个是 `_incoming`——一个
**broadcast** `StreamController`，这一点被两个 widget 测试暴露了出来：

```
Bad state: No element
#0      List.single
#1      main.<anonymous closure>  (test_flutter/ui/pages_test.dart:414:68)
```

一条收到的 offer 已经被加进 `_incoming`，而测试的监听器还没跑。broadcast
controller 不会让一个未送达的事件活着——事件由 `add` 捕获到的东西持有——所以当
那条 Transfer 唯一的强引用就是被 `_pruneTransfers` 移掉的那条 `_Tracked` 记录
时，这条 offer 就变得可回收，对端问出的那个问题就被丢掉而不是送达。

窗口很窄，而这恰恰是它活下来的原因：得累积到一百条 Transfer、得有一个监听器正
在半路、顺序还得刚好对上。在一个新 controller 上发一个文件的测试永远看不到它。
一个在二十个用例里跑过一百条 Transfer 的测试套件会。

## Decision

`_pruneTransfers` 只丢**已 settle** 的 Transfer。那个不分状态丢最旧的 `while`
循环留着，因为替代方案是一个在进程生命周期内一直增长的列表，而一百条*活着*的
Transfer 远远超过任何人会盯着看的量——但一条尚未 settle 的 Transfer 是一个仍在
路上的问题，只要还有已 settle 的可丢，它就永远不是候选。

`_pruneTransfers` 的文档注释现在把规则和理由都写下来了，好让下一个伸手去动那个
`while` 循环的人不得不读到它为什么在那里。

## Alternatives considered

**在监听器跑之前，对每一条未送达的 offer 保持一个强引用。** 否决：那等于在
controller 这一侧，把 `StreamController` 本来就在做的那笔账重做一遍，而且每一条
加进 `_incoming` 的事件都要在每一条出去的路上配一次移除——监听器抛异常、监听器
取消、监听器压根没被挂上。非对称规则更小，而且自身没有失败模式。

**把 `_incoming` 改成非 broadcast 的 controller。** 否决：那会丢掉重建的组件树
挂上来的第二个监听器，而一个在 offer 还在屏幕上时被 dispose 又重建的页面会把它
弄丢——用一次罕见的丢失换来一次常见的丢失。

**在跟踪它之前就把 offer 发到 `_incoming` 上，让引用变得无关紧要。** 作为修复
否决，但作为一个观察保留：它缩小了窗口而没有关上它，而且它让 `_track` 与
`_incoming` 的顺序变成一条承重的约定，理由却没有任何别的地方共享。列表的裁剪
规则才是错的那件事。

**在 controller 里纯粹为了留住事件而挂一个 `_incoming` 监听器。** 否决：一个唯一
目的就是打败垃圾回收的空订阅者，是一段没法被读成注释的注释，而下一个删掉它的人
会在没有任何测试失败的情况下把 bug 带回来。

## Consequences

- 一条收到的 offer 再也不会在送达之前被回收，无论被跟踪的列表在做什么。
- 裁剪的上界对已 settle 的历史仍然成立，那本来就是这条上界的目的。一个拥有超过
  一百条*活着*的 Transfer 的 controller 仍然会丢最旧的，和从前一样。
- `_incoming` 增加了一段说明，讲明 broadcast controller 不持有自己未送达的事件，
  所以一个「加了事件、又丢掉对载荷的最后一个引用」的调用方制造了一场竞态——这条
  规则是本次修复所遵守的，而不是关于本次修复的注记。

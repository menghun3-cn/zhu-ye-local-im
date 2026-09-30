# Agent Note: Make the ControllerScope tell its dependents that something changed

Status: implemented

[English](2026-09-30-controller-scope-never-notified-its-dependents.md) | 中文

## Problem

`ControllerScope` 是这个应用里每个页面够到 controller 的唯一途径：页面在自己的 `build` 里调用 `ControllerScope.of(context)`，自己不持有任何订阅。这个类在文件头写明了自己的安排 —— 每次变更在根部发一次通知，而不是每个 widget 一个订阅 —— 而实现这一点的机制是 `_ControllerProvider.updateShouldNotify`：

```dart
bool updateShouldNotify(_ControllerProvider oldWidget) =>
    !identical(oldWidget.controller, controller);
```

两个操作数是同一个对象。`_ControllerScopeState` 在整个 scope 的生命周期里持有同一个 controller，并且每次重建都把这同一个实例交给 `_ControllerProvider`，所以 `identical` 恒为 `true`，这个表达式也就恒为 `false`。

这套安排里也没有别的东西能替它把通知带下去。交给 `_ControllerProvider` 的 `child`，是 state 在 `pumpWidget` 那一刻拿到的那一个 widget 实例 —— 它从不改变 —— 而 Flutter 的 `updateChild` 会跳过一个 widget 实例相同的子树。于是 scope 重建了，却谁也够不到。每个读了 controller 的页面，都停在它第一次 build 的样子。

这个症状只有在 widget 套件终于能跑起来之后才看得见。在双窗口端到端测试里，配对是成功的：两侧都放行了，两个 controller 都报告 `isServing`。对话框能往下走，因为对话框的步进是它自己的局部状态。但 Devices 页面始终没有重绘成「已配对」的文案 —— `Pair another Device` 一直没出现，测试就卡在等一个永远不会变的屏幕上。断言是对的，是屏幕冻结了。

此前没有任何东西抓到它，原因有两个，彼此独立。纯 Dart 套件直接驱动 `LocalTransferController`，不建任何 widget 树，所以它对「树会不会重建」无话可说。而 `flutter analyze` 查的是类型，不是某个 `InheritedWidget` 到底有没有真的触发过。

## Decision

`updateShouldNotify` 返回 `true`：

```dart
@override
bool updateShouldNotify(_ControllerProvider oldWidget) => true;
```

`true` 是正确答案，而不是绕开问题的权宜之计，理由就在这个 widget 是什么：它**只**在 controller 报告过一次变更时被重建（见 `_ControllerScopeState`），controller 实例在整个 scope 生命周期里是同一个，而 controller 交出来的一切都是在 `build` 里读的。所以「发生了一次变更」正是依赖者想被回答的那个问题 —— 这里不存在第二个可供比较的值，能比这次重建本身多说一点什么。

让它生效的是 `InheritedElement.notifyClients`：它会遍历那些通过 `dependOnInheritedWidgetOfExactType` 注册过的依赖者，直接把它们逐个标记为脏。这条路径与「父级重建自己的 child」不是同一条，因此不受上面那个「child 实例相同就短路」的影响。

## Alternatives considered

**保留比较，但去比一个会变的值。** 否决理由：controller 的 `changes` 流是刻意粗粒度的 —— 一个「有东西动了」的 tick，而不是每个字段一条流 —— 所以任何可比的值都得在 scope 这边凭空造出来；而一个不是由同一个 tick 推导出来的值，要么漏掉变更，要么在一个页面并不读的变化上重建。

**让每个页面自己订阅 `changes`。** 否决理由：这正是这个类存在的意义所要避免的安排。十几个各自为政的订阅互相竞争，每个页面都得记得取消自己那一份，而一个忘了取消的页面会把一个监听者泄漏进一条比该 widget 活得更久的广播流里。

**用手写的 `InheritedWidget` 换成 `InheritedNotifier`。** 这是一个货真价实的替代方案，也是最接近 Flutter 惯用答案的那个：它在 `Listenable` 的通知上通知依赖者，完全不需要 `updateShouldNotify`。没有取它的原因是 controller 暴露的是 `Stream` 而不是 `Listenable`，要采用它就得二选一：要么改变 controller 是什么，要么新增一个唯一职责就是做类型转换的适配器。一行的改动保住了现有安排，而被修好的那次通知是可以在测试里直接观察到的。

## Consequences

- 读到 controller 的页面，现在会在 controller 报告变更时重建 —— 这正是这个类一直宣称的行为。在此之前，Devices 列表不会因 Discovery 而填充，Transfers 列表不会增加行，Settings 页面也不会跟着改名更新 —— 这些在纯 Dart 套件里一样都看不见，而在真正驱动一棵树的那一刻全都看得见。
- 重建依旧刻意保持整棵子树级别的：controller 交出来的视图都是小的值对象，所以一个页面的 `build` 很便宜；而一棵只重建自己一次的树，不会像各自为政的订阅那样跟自己抢。
- 钉住它的是 `test_flutter/e2e/two_window_e2e_test.dart`。配对那条用例断言「已配对」的文案抵达了两个 Devices 页面，所以把比较改回 `false` 会让它失败，而不是让它卡住。

# Agent Note: ControllerScope 坐在了需要它的路由下面

Status: implemented

[English](2026-10-08-controller-scope-sat-below-the-routes.md) | 中文

## Problem

点开一个会话，看到的是一片空白。设备列表画得出来，配对能用，两台机器上的
Session 都活着——可点一台已连接设备的卡片、或者卡片上的「打开会话」按钮，
出来的是一块空面板。两台机器、双向、都是 release 包、每次都复现。

说它空白并不准确：不是「有内容但内容为空」，而是**什么都没有**——没有提示
语、没有输入框、没有附件按钮、没有发送按钮。报告里点名了这四样东西的缺席，
这就排掉了最容易想到的那个解释：会话开出来了、只是掉了对端——真是那样，
输入区还是会画出来，只是附件按钮变灰而已。

release 构建把构建期异常画成一个纯灰窗口。截图里就是纯灰，这也正是症状读
起来像「空白页」而不是像报错的原因。同一个失败在 `flutter test` 下会直说自
己是什么：

```
Bad state: no ControllerScope above this widget
```

当调用方 context 上面没有 `_ControllerProvider` 时，`ControllerScope.of` 就
抛这句。`ConversationPage` 在 `build` 里调它。provider 是存在的——应用确实装
了一个——但它不在那个 context 上面。

`LocalTransferApp` 只包了自己的 `home`：

```dart
home: Builder(builder: _screen),   // _screen 返回 ControllerScope(child: HomeShell(...))
```

用 `Navigator.of(context).push(...)` 压上去的路由，并不构建在 `home` 下面。
它构建在根 navigator 的 overlay 里，而那是 `home` 的**兄弟节点**——navigator
同时持有这两者。`_PeerCard._openConversation` 正是这样压路由的，于是
`ConversationPage` 被构建在作用域外，干第一件事就抛了。

应用里其他对话框都没受影响，原因值得写下来：它们把 controller 当**构造参数**
收（`showSendFileDialog(context, controller, …)`），而不是从作用域读，所以
「是 `home` 的兄弟」对它们从来就无所谓。会话页是唯一一个从被压路由里经作用
域去取 controller 的界面，也是唯一一个坏掉的界面。

## Decision

作用域包住整个 `MaterialApp`，而且只在真有 controller 可放时才包：

```dart
final app = MaterialApp(…, home: Builder(builder: (context) => _screenFor(context)));
return controller == null ? app : ControllerScope(controller: controller, child: app);
```

这里有三个承重点。

**在 `MaterialApp` 外面，而不是 `home` 里面。** navigator 是 `MaterialApp`
自己创建的，没法从外面递进来，所以应用自己的树里根本不存在「在 navigator 之
上、又在本地化之下」的位置。包住 `MaterialApp` 就把作用域放到了 navigator 之
上，因而也在 `home` **以及**压在它上面的每一条路由之上——这正是会话页需要的
性质。

**`home` 仍然必须是 shell。** 早先试过把 shell 挪进 `MaterialApp.builder`、
把 `home` 留成占位符。那会渲染出一个**空**窗口：`builder` 只是给 navigator
做装饰，它不提供 navigator 要显示的那条路由，所以占位符 `home` 让 navigator
无物可建。这个失败形态和被修的那个故障长得一模一样——这正是它值得写下来的
原因。

**启动期间作用域是不存在的。** `home` 必须能在三种状态下被驱动——启动中、失
败、运行中——因为它是路由的唯一来源，而作用域在还没有 controller 时是装不上
的。那两种状态下底下也没有任何东西需要它：启动页和失败页只读自己的字符串。

## Alternatives considered

**教 `ConversationPage` 把 controller 当构造参数收。** 否决，尽管这是最小改动，
而且和应用里每个对话框的现有做法一致。它修好这一个页面，却把陷阱留在原地：
下一个从被压路由里读作用域的页面会以同样方式坏掉，而且是以灰窗口而不是以堆栈
的形式坏掉。作用域存在的意义就是让页面不必被逐个穿线；该修的是它坐在哪。

**只包 `home` 的子树，但用嵌套 `Navigator` 压路由。** 否决：作用域底下的嵌
套 navigator 确实能让被压路由落在它里面，是能work，但代价是应用里每个对话框
都改在那个 navigator 的 overlay 里渲染，而不是根 overlay——这是对对话框定位
和关闭方式的实质改变，为了少挪一个 widget 不值得。

**让 `ConversationPage` 容忍作用域缺失，比如 `maybeOf` 返回 null。** 否决：
这是把一个接线错误变成一个悄悄没 controller 也能渲染的页面。`ControllerScope.of`
抛异常是刻意的——它头部写着，构建在作用域外的页面「是值得大声失败的接线错误」
——在这里把它软化，只会把下一个同类缺陷藏起来而不是暴露出来。

**保持作用域原位，改从作用域底下的 context 压路由，例如给会话页配自己的
`Navigator`。** 否决：路由终究还是要落进某个 overlay，于是「哪个 overlay 在
作用域之上」这个问题只是被挪了个地方。

## Consequences

- `lib/ui/app.dart` 把作用域装在 `MaterialApp` 外面。它是应用整棵树唯一的组
  装点，那里的注释写明了作用域为何在应用之外而不是在 `home` 之下。
- `test_flutter/ui/app_tree_test.dart` 是新增的，钉住这件事：它 pump
  `LocalTransferApp` 本身——`main` 构建的那棵树——并从 shell 内部的 context
  压出会话，断言页面构建成功、提示语和输入框在屏上、以及 pop 之后回到 shell。
  对着旧代码它会以 `no ControllerScope above this widget` 失败，也就是用户报
  的那个灰窗口。
- 这个套件的存在本身就有理由：共用的 harness 抓不到这类缺陷。
  `test_flutter/support/ui_harness.dart` 把它的 `ControllerScope` 包在它的
  `MaterialApp` 外面——正是本次修复采用的形态，注释还写着包在 `home` 周围的
  作用域对对话框不可见——所以每个 widget 测试构建的都是**正确**的树，而
  `lib/ui/app.dart` 构建的是另一棵树。一个自建树的套件管不到应用发布的树；
  这个套件构建的是应用的树。
- `test_flutter/ui/app_tree_test.dart` 要驱动两个时钟，因为
  `LocalTransferApp._open` 会在 widget 测试的假时钟上绑一个真的 `ServerSocket`。
  每轮先让出到真实事件循环，再推进假时钟；与 `startUiDevice` 记录的是同一个
  坑，只是这里的 controller 是应用自己造的。
- Session 掉线的设备在会话页上仍然没有任何提示：标题退化成裸指纹、地址行读作
  `neverSeen`、附件按钮变灰。这一点本次没动，值得单独修——页面现在足够可达，
  这事才开始要紧。

# Agent Note: 会话开着就会每帧重写一次会话文件

Status: implemented

[English](2026-10-14-conversation-save-sharing-violation.md) | 中文

## Problem

打开「设置」页后，「提示」列表会自己刷屏，只要程序还在跑就刷个没完：

```
the conversation could not be saved: PathAccessException:
  Cannot rename file to .../LocalTransfer/messages.json,
  path '.../LocalTransfer/messages.json.tmp'
  (OS Error: 另一个程序正在使用此文件, errno = 32)
```

`errno = 32` 是 `ERROR_SHARING_VIOLATION`。程序外面没有任何东西占着
`messages.json`；是程序自己占着——一次一个保存。

两个缺陷凑在一起才出了这个事。

**循环。** `ConversationsPage.build` 会在「记忆中的会话」显示在屏幕上时，挂一个
帧后回调去调 `markConversationOpened`。那个方法改读取状态、调 `_notify()`、然后
await 一次保存——而 `_notify()` 正是让页面重建、进而挂上下一个回调的东西。本来用来
斩断这个环的守卫没有做到：

```dart
final advanced = before == null || now.isAfter(before);
if (!advanced && !movedLast) return;
```

`now` 每次调用都从时钟现取，`before` 是上一次的标记，所以第一次之后
`now.isAfter(before)` 恒为真。它上面的注释写着「只在真有变化时才写，免得每次重建
都把会话文件重写一遍」——意图是对的，而这个谓词从没实现过它。一个会话开着屏幕，
它就以每帧一次的速度重写文件，开多久写多久。

**竞态。** `FileMessageStore.save` 把整个会话写进 `messages.json.tmp`，删掉目标，
再把暂存文件改名盖上去。控制器会从好几个方向同时要保存——传输结束、会话被打开、
消息被删除——而上面那个回调并不 await 它请求的保存。于是保存互相重叠，而它们共用
同一个暂存文件：落在「另一个保存还开着它」那一刻的改名会被拒绝，Windows 把这种
拒绝报成「另一个程序正在使用此文件」。每次拒绝都变成一条提示，这就是列表会滚的原因。

两半都没有测试抓到。没有任何测试连续调过两次 `markConversationOpened`，也没有
任何测试在不 await 前一个的情况下启动两个保存。

## Decision

**让守卫真的成立。** `markConversationOpened` 现在除非这个标记真的会推动什么，
否则在碰文件和发通知之前就返回：一个从没被打开过的会话、一个与上次打开的不是同一个
的会话、或一个还压着水印盖不住的消息的会话。

```dart
if (before != null && !movedLast && unreadCount(peer) == 0) return;
```

读时钟挪到了守卫之后，所以一次什么都不写的调用也什么都不花。

**把保存串起来。** `FileMessageStore.save`——以及形状一模一样的
`FileProfileStore.save`——现在改为串行而非重叠：

```dart
final started = previous == null
    ? _write(json)
    : previous.then((_) => _write(json));
```

链条由一个不会失败的 future 持有，所以一次保存被拒绝不会让后面每一次都带着同一个
错误直接失败；链条在最新的那次保存完成时清掉，所以它不会跟着一个在通知区里待一周的
进程一起长。

## Alternatives considered

**让页面别再每次 `build` 都挂回调。** 否决：这只修掉了两个调用点里的一个，
`markConversationOpened` 照样可以被别处以循环的方式调用。守卫才是契约；某个调用点
恰好不会自旋，不是。

**改成比较读取状态而非时钟**——只在 `toJson()` 输出变了时才写。否决：这是在用比较
map 来回答一个水印已经能回答的问题，而且只要有消息到来它照样每次重建都写，因为状态
确实变了。未读数才是真正被问的那个问题。

**每次保存用不同的暂存文件名。** 否决：它消掉了共用句柄的竞态，却换来两个更糟的问题。
保存可能因此乱序落地，旧快照会盖掉新快照；而一次中途失败的保存会按尝试次数留下暂存
文件，还没有东西清理它们。

**改名失败就重试几次。** 否决：这是给一个有病因的竞态贴创可贴，而且只是让失败变慢，
不是让失败消失。程序自己两次保存之间的共享冲突，不是该靠等解决的问题。

**去掉先删再改名，直接改名盖上去。** 此处否决：保存串起来之后没有第二个保存开着文件，
而那句 delete 正是让意图好读的地方；它还会拉长「崩溃后连目标都没有」的窗口，而原子写
的存在就是为了避开这个。

**每个 peer 一个会话文件。** 否决：改动比缺陷本身大得多，而且这是用一个需要枚举、
需要清理、需要保持一致性的目录，去换一把锁。

## Consequences

- 「提示」列表不再自己刷屏；打开一个会话花一次写入，之后不再写。
- 关掉的是两个潜在竞态而不是一个：`FileProfileStore.save` 形状相同、暴露相同，
  用同样的方式修掉。
- `test/app/app_controller_test.dart` 用一个会计数的 store 钉住守卫：打开会话写一次，
  之后再隔开调用二十五次什么都不写。用旧守卫这条用例记录到的是 27 次保存。
- `test/history/message_store_test.dart` 钉住串行：背靠背启动、再一起 await 的八个
  保存全部成功，磁盘上留下的是最后一次，且不留暂存文件；而一次因父路径被挡而失败的
  保存，在障碍消失后能正常成功。
- 守卫的代价是每次调用一次 `unreadCount`，与会话列表为了画角标已经在每次
  `build` 里做的是同一份工。
- 已知缺口：串行是按 store 算的，所以两个 store 指着同一条路径仍然会竞态。
  没有任何地方会构造出两个。

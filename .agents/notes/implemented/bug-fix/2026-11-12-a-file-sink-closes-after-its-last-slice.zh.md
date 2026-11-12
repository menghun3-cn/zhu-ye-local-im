# Agent Note: 文件汇聚点只在最后一个分片落盘后才关闭

Status: implemented

## Problem

`FilePayloadSink.close` 可能在某个分片的 `writeFrom` 仍在途时执行，
Windows 随之报 `FileSystemException: An async operation is currently
pending`。widget 套件把它当作未处理异步错误，挂在当时正在跑的任意
测试上——一条接收中的文件在写盘途中被关闭的 Session 判负时，错误经
`_publishLandings`/`_abandonLandings` 浮出来，而那两处的
`await sink.close()` 本身没有任何防护。

这个竞争是结构性的，不是漏了某个 `await`。`TransferEngine` 把分片帧
和控制消息汇进同一条串行队列，所以 `onChunk` 的 `await sink.write`
总在 `onComplete` 结束 Transfer 之前完成——*对有序的结束而言*。但
`engine.close()`、Session 断开和 `onChannelError` 都不经队列直接到达
`finish`：一个已经走进 `writeFrom` 的任务会继续跑，而 `onSettled`
同时触发 `_closeSinks`，app 侧的落地代码也在等同一个 close。两个调
用方、一个句柄，它们和仍在途的写之间没有任何顺序。

## Decision

**每个句柄操作都走同一条尾链。** `FilePayloadSink` 持有 `_tail`，一条
`Future<void>`，每次 `setPosition`+`writeFrom` 对和最终的 `close` 都
接在它后面。于是 close 只能排在它之前提交的写*后面*——而这正是在
途的那组：`onChunk` 在写之前检查 `isSettled`，Transfer 结束后不会再
有新写提交。尾链吞掉自己的错误（`run.then((_) {}, onError: ...)`），
否则一个失败的分片会毒化其后排队的所有操作；错误依旧送达 write 自
己的 awaiter，也就是把它报成 `ioError` 的那个 `onChunk`。

其余都不变：`PayloadSink` 的契约、`IncomingTransfer` 里先 settle 再
close 的顺序、以及让落地代码和 `_closeSinks` 等同一次释放的共享
`_closing` future，统统保持原样。修复放在 sink 内部，因为只有 sink
自己知道有一个句柄操作还没结束。

## Alternatives considered

**让引擎关闭前先排空队列。** 否决：`close` 存在的意义就是 Session
已经没了或正在走；让关闭等待在途的磁盘写，会把引擎拆除耦合到文件
系统延迟上，一个卡住的写会卡住整个 close。sink 级尾链把等待限制在
已提交的操作内，边界相同，却不动引擎的契约。

**给每个 `await sink.close()` 调用点加防护。** 否决：一共有三处
（`_closeSinks`、`_publishLandings`、`_abandonLandings`），下一个调
用方还得记得同样的防护。「句柄在有挂起操作时绝不关闭」这条不变式属
于拥有句柄的对象。

**`_closed` 置位后拒绝写。** 否决，因为它不充分：它防的是 close *之
后*提交的写，而出问题的情形是 close *之前*提交的写。缺的是顺序，不
是拒绝。

## Consequences

**得到的。** 写盘途中被判负的 Transfer——Session 掉线、引擎关闭、对
端取消与最后一个分片赛跑——现在能干净地关闭文件，不再把挂起操作的
`FileSystemException` 作为未处理异步错误抛出来。接收文件的落地或清
理与之前完全一致；只是 close 会等一下，且只等已提交的写。

**代价。** 同一个 sink 上的文件操作从「由消息队列隐式排序」变成显式
串行。顺序本来就如此，只是对唯一不走队列的调用方——`close`——把它
变成了保证。

**测试。** `test_flutter/ui/pages_test.dart` 的文件搜索用例就是复
现：改动前在这台机器上稳定失败，改动后通过。`test/transfer/` 继续
通过，其中包括专门走非队列 settle 路径的 Session 断开用例。

# Agent Note：收到的图片在一个还不存在的文件上被画了出来

状态：implemented

[English](2026-10-10-a-received-picture-was-drawn-before-its-bytes-landed.md) | 中文

## Problem

从对端收到的一张图片在会话里始终是一块灰色的破图占位框——一个 broken-image
图标加文件名（`pasted-1791595231659873.bmp`），并且一直如此。文件本身毫无
问题：`Downloads\LocalTransfer` 里的 348,214 字节，一份教科书式的 32 位
`BI_RGB` 位图（340×256，头部逐字节核过），同一个 Flutter 构建在它作为
*发送方* 那份拷贝时解码毫无怨言。解码器从来不是问题；解码器从来拿到手的
就不是一个完整的文件。

线索的终点在 `LocalTransferController.acceptInto`
（`lib/app/app_controller.dart`）：

```dart
await transfer.accept(itemIds: ..., sinks: sinks);
accepted = true;
...
// The bytes are verified and closed by now — `accept` does not return until
// they are — so it is only here that a received image has a path worth
// drawing.
if (landed.isNotEmpty) {
  _recordLocalPath(transfer, landed.values.first);
}
_notify();
```

这段注释在它唯一存在的理由上判错了。
`IncomingTransfer.accept`（`lib/core/transfer/incoming_transfer.dart`）把
`AcceptMessage` 发出去就返回——它唯一会碰的收尾是 *"Throws ... if the Offer
has already been answered"*。字节是那之后才一帧一帧过去的，并且在
`onComplete` 里校验——那完全是事件循环里更晚的一轮。于是
`_recordLocalPath` 在文件还是 **空** 的那一刻就触发了：会话树重建，看到
`kind == image && localPath != null`，切到 `_bareImage`，`ImageBubble` 对一个
零字节文件 resolve 了一个 `FileImage`。解码失败，`_unreadable` 置位，而
`ImageBubble` 没有任何重试——`_follow` 只在 *路径变化* 时重新 resolve，而路径
永远不变。所以那个破图框是永久的：跨过每一个进度跳变、跨过完成、跨过此后
的每一次重建。

这件事狡猾在：代码库把正确的规则 **写了两遍**，代码却仍然错了。
`_Tracked.localPath`：*"a path still being written to would draw half a
picture or fail outright"*。`TransferView.localPath`：*"a received image is
given a path only once its bytes are all present"*。而既有的测试——
`a received picture keeps a path worth drawing`——只查了 `acceptInto` 之前
`localPath` 为 null、传输收尾之后非空；有 bug 的代码轻轻松松就满足了，因为它
把路径记得 **太早**，而不是压根没记。中间态没有任何断言。

## Decision

`acceptInto` 现在在 transfer 的 outcome 说出「字节是真的」那一刻才记路径，
而不是在答复发出去的那一刻：

```dart
if (landed.isNotEmpty) {
  final path = landed.values.first;
  unawaited(transfer.outcome.then((outcome) {
    if (outcome is TransferCompleted && _recordLocalPath(transfer, path)) {
      _notify();
    }
  }));
}
```

`Transfer.outcome` 是 transfer 自己的校验流程负责完成的那一个 future——
`finish(TransferCompleted(...))` 只有在每个已接受项的字节数对上、摘要校验
通过之后才会运行。把记录挂上去，路径出现的时机就恰好是 `_Tracked` 文档说它
该出现的时机；传输失败的路径则永远不会出现，这对一个从没到达的文件是诚实
的回答。`_recordLocalPath` 现在回答「找没找到记录」，所以只有真的变了才会
notify；多出来的那次 `_notify()` 盖住了一个竞态——outcome 自带的进度通知会
比回调落地早一拍重建 UI。

其他一切不动。发送方本来就在 `_track` 时记路径，而且记得对——它指的文件是
用户自己的、在 transfer 存在之前就是完整的。`ImageBubble` 维持不重试的立场，
因为路径只在校验之后才来，解码时没有东西值得重试。

测试补上了缺失的那条断言——在旧代码上必挂的那条：

```dart
await bob.controller.acceptInto(offer, incoming);
expect(
  bob.controller.transfers.single.localPath,
  isNull,
  reason: 'the answer is on the wire but the bytes are not here yet, ...',
);
```

## Alternatives considered

**把 `accept` 改成等到收尾。** 否决：那会改掉一个方法的含义，而它的其他
调用者——连同它的名字——说的都是「发一个答复」；它还会让 `acceptInto` 的
future 被整个传输时长占住。引擎的 offer/accept/complete 三段是刻意的设计，
读错的是应用层，不是引擎。

**在 `_track` 的进度订阅里提升路径。** 考虑过：给 `_Tracked` 加一个
`landedPath` 字段，状态落定为 settled 时提升成 `localPath`。否决：往一个
存在的意义就是老老实实成对存放的记录里穿一个待定值，而且 outcome 的判定
反正还是得在别处做一次。等在 `outcome` 上让整条规则在路径出生的那一个地方
全部可见。

**让 `ImageBubble` 重试失败的解码。** 否决：治的是症状——重试会把未来任何
一个把不存在的文件递给气泡的调用方都糊弄过去，而且每次重试都是对一个本不该
被指认的文件再读一遍。气泡的契约（「不重试，路径只在可画时才被记录」）是
合理的；错的是记录。

**在每一次收尾时都记路径，包括失败。** 否决：失败传输的半截文件是刻意留下
供断点续传的，但它不是一张图——画它会得到一次截断的解码，「打开所在文件夹」
也会指到一堆残骸。

## Consequences

- 收到的图片在字节过线期间显示带名字和进度条的气泡——文档里说的「传输的
  事务」长相——校验完成的那一刻翻成裸缩略图，且解码保证拿到完整的文件。
- 收到的 *文件* 免费获得同样的正确性：「打开所在文件夹」只会在文件真的
  落盘之后出现。
- 灰色破图框从此只有文件被删或真的解不开这两种来路，与它自己文档的声明
  一致。
- `dart test` 444/444，含新增的中间态断言。

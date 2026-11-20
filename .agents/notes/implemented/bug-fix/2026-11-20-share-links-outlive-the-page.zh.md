# Agent Note: 分享链接活得比页面久，删除真正吊销

Status: implemented

[English](2026-11-20-share-links-outlive-the-page.md) | 中文

## Problem

两个缺陷同出一源：链接分享页自己留了一份分享列表，而链接服务端留了真
正的那份。

- **退回上一层就把卡片丢了。** `_ShareByLinkPageState` 持有
  `List<_Share>`；「传输」子视图在 `_sharing` 翻回时会卸载页面，状态连同
  每张卡片一起被销毁。链接本身在服务端还活着 30 分钟，但发送方再也看不
  到、复制不了、也管不了它们。
- **删除从来没删过。** `_removeShare` 只把卡片从那个部件列表里拿掉。服务
  端的 `_shares` 条目继续活着，于是「已删除」的链接在过期前照常提供文
  件——那个看起来像吊销的控件其实不是。

## Decision

服务端是发送方分享列表的唯一事实来源；页面从它重绘。

- **`LinkTransferServer` 学会了描述和吊销自己的分享。** `_ShareEntry`
  现在保存当初发出去的 `url`——重建链接可能在网卡变化后指向别的地址，所
  以存字符串而不是重建。`activeShares()` 为每个活着的条目返回一个
  [ActiveShare]（token、url、fileNames、createdAt），过期条目即使清理定
  时器还没跑也不列出；`revokeShare(token)` 移除条目，`/s/` 与 `/f/` 从此
  按「已过期」应答。
- **`LinkTransfer` 透传两者**，即 `shares` 与 `revokeShare`。
- **页面不再自存列表。** `ShareByLinkPage` 每次 build 直接从
  `LinkTransfer.instance.shares` 画卡片；创建分享就是一次 `setState`，删
  除分享是 `revokeShare` 加一次 `setState`。`_Share` 及其 `GlobalKey` 一
  并移除。
- **`_ShareCard` 改为有状态**，自己持有 QR 的 `GlobalKey`——「复制二维码」
  要靠它在重建后仍然找到 `RepaintBoundary`，而从服务端数据重绘的卡片已
  经没法向页面侧的模型借 key 了。复制二维码的逻辑随之搬进卡片。

## Alternatives considered

**保留界面列表，但放到更长寿的地方**（控制器或界面单例）。否决：它造出
了服务端已知信息的第二份拷贝，而删除按钮反正还得伸手进服务端去吊销——到
那一步，服务端列表本来就是诚实的事实来源。

**把分享持久化到磁盘。** 否决：服务端在进程内，应用一退出所有链接照样死，
持久列表只会留下指向死链的卡片。

**只修删除按钮。** 否决，属于半个修复：没有持久化，退回时卡片照丢——而
丢卡片正是被报告的症状。

## Consequences

- 分享在离开子页、切换 tab、任何重建之后依然存在——直到用户删除它或
  30 分钟到期，先到为准。重启应用仍会结束所有分享，因为服务端本身就在
  进程里。
- 垃圾桶图标现在名副其实：链接立即失效，由服务端验证而非假设。
- 即使分钟级清理定时器还没跑，过期分享也会在下次重建时从列表消失。
- `activeShares()` 按插入顺序返回，与旧界面列表的展示顺序一致。

## Testing

- `test/link_transfer/link_server_test.dart` 覆盖 `activeShares`（url、
  fileNames、存活标记）与 `revokeShare`——包括被吊销的 `/s/` 页应答
  404、第二次吊销返回 false。
- `test_flutter/ui/share_by_link_page_test.dart` 通过真实的「传输」子视
  图驱动退回再进入，断言卡片仍在，然后删除并断言
  `LinkTransfer.instance.shares` 为空。

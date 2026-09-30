# Agent Note: 已连接的对端被读成「从未出现」

Status: implemented

[English](2026-09-30-a-connected-peer-read-as-never-seen.md) | 中文

## Problem

一台开着 Session 的设备，名字底下写着：

```
从未出现 · 最后出现于 3 小时前
```

同一个事实说了两遍，而第二遍和第一遍自相矛盾。`neverSeen` 来自
`describePeerAddress`，`lastSeen(…)` 来自 `describePeerFacts`，两者都不知道对方
已经说过什么。这一个症状有三个成因，所以它需要三处修复而不是一处：

* 对端列表用 `..address ??= session.address?.address` 把 Session 并进对端。对于
  Discovery 早就定位过的对端——也就是常见情况，毕竟配对本身就是走 Discovery 做
  的——等号左边早就不是 null 了，于是 Session 的地址从来没被取用。卡片因此可能
  显示一个 Session 并不在其上的地址。
* `describePeerFacts` 只要对端有地址就追加「最后出现于」，不管它是否连着。
* `describePeerAddress` 只要 `sessionPort` 是 null 就返回
  `peerNotAccepting(address)`——于是一台 Session 活着、但 beacon 里没带端口的
  设备，被描述成「不接受连接」，而这话说的是本机正在和它讲话的设备。

## Decision

一次 Session 就是一次目击，而它跑在其上的那个地址就是本机最好的地址。

* 对端列表的 wired 分支改为优先用 Session、再退回已知信息：
  `..address = session.address?.address ?? entry.address`、
  `..sessionPort = session.handshake.device.listenPort ?? entry.sessionPort`、
  `..lastSeen = _clock().toUtc()`——活着的 Session 意味着对端此刻就在这里，所以
  记录是现打的时间戳，而不是停在 Discovery 上次报告的那一刻。
* `describePeerFacts` 只在「有地址且**没有**连接」时追加最后出现时间。已连接的
  对端读作它的地址加 `sessionOpen`，一字不提时间。
* `describePeerAddress` 在没有 Session 端口、而对端已连接时返回裸地址：不管它的
  beacon 登了什么，Session 就是它接受本机的证明。

## Alternatives considered

**保留 `??=`，只改那句话。** 否决：地址仍然是 Discovery 上次说的那个。一条经由
与 Discovery 报告不同的网卡开起来的 Session，会被贴上它并不在其上的地址，这比
没有标签更糟——它是一个错的标签。

**既然时间是事实，就把它一起印出来。** 否决：对已连接的对端来说，它和「已连接」
说的是同一件事，并排印出来读起来就是两句互相争抢的陈述。这个列表的职责是「我在
哪里能找到这台设备」；时间属于那些找不到的设备。

**已连接时只显示「已连接」，不显示地址。** 否决：Session 掉线时用户恰恰需要地址
来知道那是哪一台机器。

**让卡片相信 `lastSeen` 而不是 Session，理由是 Session 可能已经陈了。** 否决：
`isConnected` 每次构建都是从活的 Session 注册表读出来的——它是卡片上最新鲜的
事实——而 `lastSeen` 才是那个被写下来的。

## Consequences

- 一台已连接设备的卡片读作 `10.0.0.7:47655 · 已连接`，只要 Session 还在就一直
  这么读。这个地址同时也是会话页 AppBar 显示的那个，来自同一个 `PeerView` 和同
  一个函数。
- `test_flutter/ui/labels_test.dart` 把这三种读法当作值来钉住，比为它们搭三块屏幕
  更便宜也更精确：从未被定位过的对端只被描述一次而不是两次；已连接的对端即使
  没登出 Session 端口也保留它的地址；已连接的对端从不报告最后出现时间。
- `test_flutter/ui/pages_test.dart` 从卡片上断言同一件事：Session 开着时卡片提供
  会话入口、印出地址、而且不印 `neverSeen`。

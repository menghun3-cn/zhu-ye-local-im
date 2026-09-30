# Agent Note: A LinkManager owns the sockets and hands out Sessions

Status: implemented

English | [中文](2026-09-30-link-manager-owns-the-sockets.zh.md)

## Problem

套接字以下的一切都已存在，而套接字以上什么都没有。发现层
（[LAN discovery](../../architecture/2026-09-29-lan-discovery-by-broadcast.md)）
产出带地址与监听端口的 `DiscoveredPeer`；[SecureLink](../../architecture/2026-09-29-core-wire-protocol-and-secure-session.md)
把 `ByteTransport` 变成带认证的 Session；传输引擎与剪贴板镜像各自需要的是 Session，
从不直接要套接字。但在这两半之间没有任何对象：没有东西绑定监听端口，没有东西发起拨号，
没有东西决定同一个对端连两次会怎样，也没有东西告诉大家某个 Session 已经消失。应用层
只能自己实现这一整套，而第二份实现必然与第一份不一致。

## Decision

`LinkManager` 是唯一碰套接字的对象。

- **`serve(port)`** 绑定 `0.0.0.0`（默认端口 47655，传 0 表示任意空闲端口），把每个
  被接受的连接以 responder 身份变为 Session。**`connect(host, port)`** 拨号并以
  initiator 身份建立。两者都返回 `ManagedSession`，失败一律报 `HandshakeException`——
  拨号被拒、主机不可达、超时、对端不是被固定的设备、对端不持有 Pairing Secret，
  对调用方而言都是同一种错误。
- **`ManagedSession` 是 `SessionHub` 加上角色与地址。** 管理器交出的不是裸
  `SecureLink`，而是 hub：一个 Session 同时承载传输会话与剪贴板会话，而 hub 是唯一
  被允许读取该链路流的对象。
- **每个对端只保留一个 Session。** 已在持有的对端再次连入时，新连接被关闭并抛
  `HandshakeException`，既有 Session 不受影响。若改成替换，任何一次对端重连都会打断
  正在进行的传输，而且任何持有 Pairing Secret 的对端都能随时顶掉别人的 Session。
- **设备绝不与自己对话。** 对端声称本机 Fingerprint 的 Session 一律拒绝。回环连接被
  读回是最常见的情形；接受它会让设备给自己发看起来像对端发来的传输。
- **`expectedFingerprint` 固定对端。** 握手只能证明对端持有 Pairing Secret，永远不能
  证明它是某一台特定设备。已经决定要拨给谁调用方应传入该 Fingerprint，得到的是拒绝，
  并且本机侧不会登记任何 Session，而不是一个陌生人的 Session。
- **事件，而不是回调。** `events` 是 `SessionEstablished`、`SessionLost`、
  `SessionRefused` 的广播流。重建设备列表的应用层与自行开启的剪贴板镜像都监听同一批
  事件，谁也不拥有这个管理器。
- **信任不在这里决定。** 持有 Pairing Secret 就是全部的准入判断。Owner Group 成员关系、
  收藏、逐次传输确认都位于这条接缝之上——这正是「可以收我的文件」与「可以读我的剪贴板」
  得以分开的原因。

## Alternatives considered

**让应用层自己持有 `ServerSocket` 并直接调用 `SecureLink.establish`。** 否决：上面每一条
规则——每对端一个 Session、拒绝自己、固定对端、断开上报——都会变成每个使用方各自重写
一遍，而这些规则之所以存在，正是因为它们很容易被微妙地写错。放进一个被测对象里，就只
写一次。

**按「连接」而不是按「对端」保留 Session，冲突时替换。** 否决：网络抖动后重连、或对端
UI 自己重连，都会无声地杀掉在途传输；而能随时顶掉 Session 的对端，就是能打断别人工作的
对端。

**让管理器为每个 Session 拥有一个 `TransferEngine` 和剪贴板镜像。** 本次否决：引擎需要
应用层选择的落地 sink 与限额（收到的文件存哪里？），镜像需要一个 `SystemClipboard`。
两者都是应用层策略。管理器只交出 hub，不对上面跑什么发表意见。

**按对端解析 Pairing Secret，等握手识别出对端之后再定。** 否决，且在结构上不可能：
这个秘密正是用来认证握手本身的，不可能在对端已知之后再选。每个管理器一个秘密、由配对
流程在单次 `connect` 时覆盖，是诚实的形状。

## Consequences

- 应用层可以只针对 `LinkManager` 编写：发现、连接、持有 `ManagedSession`、关闭。
  它上面没有任何东西需要 `Socket`。
- `serve` 绑定所有网卡。这是设备在局域网上可达的前提，也意味着同一链路上的任何东西都
  可以**尝试**握手；拦住它的是 Pairing Secret，不是绑定地址。
- Session 断开如今两端都能观察到，因为传输完成信号改由读侧派生——见
  [对端断开与秘密确认](../../bug-fix/2026-09-30-peer-teardown-and-secret-confirmation.md)，
  本次增量必须先修掉它，`SessionLost` 才成立。
- 被拒连接会上报为事件，但不会自动重试。自动重拨策略属于应用层，只有它知道用户是否
  要求过这件事。
- `lib/core/` 依然没有 Flutter 依赖：管理器由 `dart test` 在真实回环套接字上验证，
  包括一次贯穿受管 Session 的完整传输。

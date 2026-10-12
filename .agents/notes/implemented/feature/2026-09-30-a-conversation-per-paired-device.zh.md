# Agent Note: 每台已配对设备一个会话

Status: implemented

[English](2026-09-30-a-conversation-per-paired-device.md) | 中文

## Problem

两台设备配对并连上之后，没有任何地方可以发东西。设备卡片先是 Pair、再是
Connect，然后是一个小小的溢出菜单，里面是「发送文本」「发送文件」「信任」——
三个都意味着*和这台设备说话*的目的地，却被摆成三件互不相干的事，其中还有一件
根本不是说话。发送是「一条消息一个对话框」：选文件、确认路径，然后看着结果出现
在另一个面（Transfers）上，混在应用里所有别的传输中间，和几秒前刚发出去的那条
文字看不出任何关系。想给一台已配对设备发个文件，用户得先找到卡片、找到菜单、再
挑对那一条。

Transfers 面对「我所有设备上正在发生什么」是个好答案，对「和这一台说话」是个
很差的答案。而这个应用里没有任何东西是后面那个答案。

## Decision

点击一台已连接设备的卡片，就打开这台设备的会话，而发送就住在这个会话里。

`ConversationPage` 以对端的 `Fingerprint` 为键——就是链路上使用的那同一个身份
——它显示的一切都从那个已经在通知的 controller 里读：

* AppBar 显示对端名字和它的地址，整个会话期间都在屏幕上。那个地址是「我到底在
  和哪台机器说话」的答案，也是用户走过去找另一台时手上需要的信息。
* 历史是 controller 掌握的这个对端的每一条 Transfer，最新在前
  （`ListView(reverse: true)`，所以最新一条在底部）。发出的靠右，收到的靠左。
  文本载荷显示正文——`TransferView.text`，从 `Transfer.text` 透传过来，正是为了
  这个——文件显示文件名和 `bytesOf` 进度。剪贴板条目被过滤掉：它们也以 Transfer
  的形式走，但是被镜像而非写读，留在这里只会是噪音。
* 还没被答复的 offer 在自己的气泡里显示「接受」和「拒绝」，于是送来的东西和它
  需要的决定就在同一个地方。
* 底部的输入区是一个 `TextField`（回车即发送）、一个附件按钮（沿用现有的文件
  选择器 `showSendFileDialog`）和一个发送按钮。文本经 `controller.sendText`
  发出，寻址用的是对端的 Fingerprint，而不是列表里的某个位置。
* 信任挪到了这里，AppBar 的溢出菜单里：作用在单台设备上的两件事——给它发东西、
  信任它——现在都在那台设备的屏幕上。

对 offer 的答复只写一遍。`acceptOffer` 与 `rejectOffer` 放在
`lib/ui/transfer_actions.dart`，Transfers 列表和会话都用它们，所以从哪一边接受
一个文件，跑的都是同一段代码，包括问文件夹和 `defaultIncomingDirectory` 兜底。

卡片上每个状态只有一个动作：对端不在设备组里时是 **Pair**，在组里但还没
Session 时是 **Connect**，Session 开着时整张卡片本身就是入口，名字旁边再配一个
「打开会话」按钮。

## Alternatives considered

**保留溢出菜单，把会话加进去。** 否决：那等于保留菜单，而菜单就是问题本身。三个
以对端为作用域的动作用一个图标收着，就是三件用户得去学的事；一张点开就是会话的
卡片，则是他本来就会的一件事。

**用长按打开会话。** 否决：点击卡片本来就是「对这台设备做那件显而易见的事」的
手势。长按目标是不可见的——它要替换掉的菜单之所以没人发现，也是同一个原因。

**一个全局会话列表，所有设备都在同一个视图里。** 否决：一个设备组可以有多台
设备，而链路上并没有「跨设备的会话」这个概念。一台设备一个页面，把对端这个
键——一个 `Fingerprint`——当作身份，而跨设备的场景 Transfers 面已经覆盖了。

**让页面自己记一份发出去的东西，边到边追加。** 否决：controller 已经拥有 Transfer
列表，再有一个地方记着「发出过什么」就得和它保持步调一致——而且页面一关就丢历史。

**做成真正的即时通讯：送达勾、正在输入、能留存的会话。** 否决：在这条链路上那
是空头承诺。没有服务端、也没有常驻信道：Session 只在两台设备都在线时存在，而协议
没有应用层的确认，能让一个勾诚实地表示「已送达」或「已读」。气泡里显示的改成真正
已知的东西——种类、状态、进度。

## Consequences

- 给一台已配对设备发文件现在是：点开设备、点附件、选文件。配它的那条文字就在同
  一段滚动历史里。
- `showSendTextDialog` 已删除。文本在输入区里打，经 `controller.sendText` 发出；
  不再有一个只为了收一行字而存在的对话框。
- 设备面除了打开、配对、连接之外，不再承载以对端为作用的动作；`DevicesPage` 现在
  接收 `defaultIncomingDirectory`，好让它推出去的会话能和 Transfers 面一样回答
  文件夹那个问题。
- `test_flutter/support/ui_harness.dart` 增加了 `openConversation`、
  `onConversation` 与 `conversationOffered`，好让测试能从卡片走进某个对端的会话
  里、在里面断言，并在点它之前先等卡片把它提供出来。`onConversation` 用的是
  `find.descendant` 而**不是** `find.ancestor`：ancestor 形式会收敛成
  `ConversationPage` 组件本身——对 `isNotEmpty` 没问题，对一次点击则是静默地错，
  因为点击会落到消息列表正中间，而不是那个被指名的控件上。
  `test_flutter/ui/pages_test.dart` 用它们检查「一台已开 Session 的设备会提供它的
  会话」，`test_flutter/e2e/two_window_e2e_test.dart` 则通过它们把一份文件从 Alice
  的会话驱动到 Bob 的 Transfers 面。

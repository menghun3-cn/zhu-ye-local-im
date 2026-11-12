# Agent Note: 发不出去的消息先作为草稿留下

Status: implemented

## Problem

对端没有 Session 时，发送的结局是一条 toast。`_target(to)` 在 `Transfer`
诞生之前就拒绝了——对端被点名但不可达时是 `AppRefusal.noSessionOpen`，
什么都没连上时是 `AppRefusal.noPeerConnected`——`guarded` 把这个拒绝变成
屏幕顶部的一行字。用户敲下的字就此消失：不在会话里，也没有任何能找回它
重发的地方。对一个承诺「我写的东西还在」的消息界面来说，对端离线时消息
蒸发是三种结局里最坏的一种——送达、可见地失败、悄悄丢失——而它正是第三种。

更硬的约束是结构性的：离线对端没有 Session，造不出 `Transfer`；而
`MessageRecord`——会话落盘的形状——只解码*已结束*的状态。排队的消息不是
一个结局，它是一件还欠着的东西。

## Decision

**草稿是自己的记录，和历史放在一起。** `UnsentMessage`
（`lib/core/history/unsent_message.dart`）携带对端、本地铸造的 id、类型、
时间戳、名称与字节数、正文或本地路径，以及 `appOwned` 标记——仅此一份
本应用可以收回的文件，即粘贴写出的临时图片。它*不是*伪造了状态的
`MessageRecord`：历史读取器拒绝一切非结局的东西，而草稿不是结局。

**它存在同一个信封里，自己的键。** `StoredConversation` 新增 `unsent`，
和 `messages`、`reading` 并列读写。格式版本仍是 1：这个键是纯新增，旧版本
像对待 `reading` 一样忽略它，新版本读旧文件得到空草稿列表。
`LocalTransferController` 把草稿放在 `_unsent`，在 `_loadHistory` 里载入，
经 `_viewOfUnsent` 合成进 `transfers`——一个出站视图，状态取已结束的
`failed`（没有在途的东西，所以不画进度条、不画取消按钮），另加
`TransferView.unsent` 标记，这是唯一能把「还欠着」和「在线路上断了」
区分开的旗标。

**排队发生在拒绝处，而不是发送之前。** 会话里的 `_sendOrQueue` 只捕获
这两个离线拒绝并调用 `queueUnsentMessage`；其余拒绝仍是真实错误、仍然
toast，因为把它们排进草稿会把 bug 藏在草稿后面。暂存的每一项独立处理，
所以半成功的发送——文本发出去了、文件被拒——各自归各位。

**感叹号本身就是界面。** 未发送气泡在气泡左侧画红色
`Icons.error_outline`——消息来向那一侧已被头像占用——点按弹出重发对话框：
预览（文字，或文件名）、重发、取消。取消让草稿原样保留。未发送的*图片*
保留气泡而不走已送达图片的裸图路径，因为裸图没有地方放这个标记。

**重发是一次新的发送，不是原地改状态。** `resendMessage` 先移除草稿，
再走 `sendText`/`sendFile`/`sendImage`/`sendAppOwnedImage` 这几扇和新发送
相同的门，真实的 `Transfer` 出现在会话最新的一端。任何失败——对端仍离线、
文件已被移动——都会把草稿放回去，并如实说出失败。草稿的 id 命名的是那次
尝试，Transfer 的 id 命名的是那次送达，两者刻意不同。

**草稿随会话一起消亡。** `deleteMessage`、`clearConversation` 和
`deleteConversation` 都把草稿和其余记录一起带走，最后一个还会把
`appOwned` 草稿路径和已跟踪的一起收进删除列表。`deleteMessage` 自己删除
appOwned 草稿文件：被选的文件是用户的、留着，但粘贴写出的临时图片在
草稿消失后没有别的主人。

## Alternatives considered

**伪造一条 `state: failed` 的 `MessageRecord`。** 否决：记录的读取器校验
只解码结局，失败状态会声称有东西发出去了然后断了。什么都没发出。它还会
把「还没发」和「发了但失败」装进同一个桶，而只有其中一个能重发成新
Transfer 而不对旧的那条说谎。

**在被拒绝之前就乐观排队。** 否决：成功的发送得反过来出队，而因*非*
离线原因被拒——点名多个对端却没指定、offer 已被应答——的消息会被静默
留成草稿而不是被报告。只捕获两个具名拒绝让其余失败保持响亮。

**草稿只放内存。** 被需求本身否决：用户要求未发送的消息随会话跨重启
保留。现有信封里的 `unsent` 键是交付这一点的最小持久化，对旧版本零成本。

**重发成功后让失败气泡原地变绿。** 否决：草稿的 id 不是 Transfer id，
没有可改的引擎对象，「你看到的消息变了状态」会是视图层对两条不同记录
的虚构。新 Transfer 出现在最新位置如实说明了发生的事——又一次尝试，
在更晚的时间。

## Consequences

**得到的。** 离线发送现在可见、有标记、可重发；跨重启存活；而协议、
Transfer 状态机和已落盘历史的契约都没动——草稿从不假装自己是过
Transfer。*开始之后*失败的发送（对端传输中掉线）仍走普通的失败历史路径，
那条路径没变，也正确地区分开了。

**代价。** `transfers` 现在合并三个来源，每个 `TransferView` 的消费者都
要尊重新旗标——`send == null` 且 `unsent == true` 是契约。文件被移动或
删除的草稿在重发时才失败，而不是排队时：`queueUnsentMessage` 存的是路径
而不是「字节还在」的承诺，草稿放回加 toast 是诚实的答案。

**测试。** `test/history/unsent_message_test.dart` 钉住编解码——往返，
以及手改可能产生的畸形形状。`test/app/app_controller_test.dart` 的
`unsent messages` 组用分属不同 beacon 网络的真实配对 Device 钉住行为：
排队、离线重发后恢复、连上后重发送达、经 `MemoryMessageStore` 的重启
持久化、删除、参数拒绝。`test_flutter/ui/unsent_message_test.dart` 钉住
界面：标记、对话框、取消让草稿继续欠着，以及文件草稿报出自己的名字。

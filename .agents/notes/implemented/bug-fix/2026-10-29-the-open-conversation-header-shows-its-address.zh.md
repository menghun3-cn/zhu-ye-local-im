# Agent Note: 打开的对话以地址作为标题

Status: implemented

[English](2026-10-29-the-open-conversation-header-shows-its-address.md) | 中文

## Problem

对话行以对端地址作为主标题，但打开这行后，标题却换成了对端自称的别名。两台设备可以
宣告相同的主机名，因此标题不再回答对话行刚刚回答过的问题：这个对话连接的是哪台
机器？标题下方的端点仍然包含地址，但最大的那一行却让用户用可能重复的事实辨认对端。

## Decision

打开的对话头与其列表行使用同一套标题规则：Discovery 定位到对端时使用
`PeerView.address`，只有没有地址可显示时才回退到 `displayName`。
`describePeerTitle` 拥有这条规则，面板标题和推入的 `ConversationPage` 都调用它。

副标题不再重复地址。`describePeerConnection` 只显示监听端口——或对 Discovery
尚未定位的对端显示从未出现——别无其他；可达状态移到了标题旁的在线状态词，见
[对话头只陈述一次在线状态](2026-11-26-conversation-header-presence.zh.md)。
这样两行各自承担不同事实：标题说明是哪台机器，下一行说明标题和在线状态都没
说过的 Session 细节。

这延伸了
[对话行以地址作为主标题](2026-10-23-a-conversation-row-leads-with-its-address.md)
记录的规则：从列表扩展到所有对话头。

## Testing

`test_flutter/ui/labels_test.dart` 钉住地址优先的标题、名称兜底，以及不重复地址的
连接行。对话 widget 测试断言：打开 Bob 的对话后，标题显示 Bob 的地址而不是别名，
下方显示端口。

## Alternatives considered

**保留别名作标题，把端点放在副标题。** 否：会重复的正是别名，把信息更弱的事实
放成最大的文字，并不能帮助用户辨认机器。

**把 `address:port` 放进标题。** 否：标题会混合机器身份和传输细节，而长端点还会
挤占用户读取地址所需的空间。

**只改面板标题，不碰推入页面。** 否：同一个对话会因为打开方式不同而用不同方式
标识对端。

## Consequences

- 已知网络地址时，每个打开的对话都以对端地址作标题。
- 别名仍可在设备页和对话控件中找到，但不再是对话顶部的主要标识。
- 连接行保留端口且不再打印标题里的地址；可达状态是标题行的在线状态词。

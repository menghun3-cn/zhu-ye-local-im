# Agent Note: 在线指示离开应用外壳与头像

Status: implemented

[English](2026-10-27-presence-indicators-leave-the-chrome-and-avatar.md) | 中文

## Problem

[早先的在线状态功能](../feature/2026-10-26-presence-is-visible-before-opening-a-conversation.zh.md)
把在线状态放在三个地方：每个会话行上的文字、每个头像上的圆点，以及应用外壳
里的在线/离线总数。实际使用中，外壳总数重复了会话行已经说明的事实，还占用
会随 Discovery 变化的导航空间。头像圆点又用另一种更难辨认的形式重复行内文字，
让头像读起来像状态控件，而不是设备身份。

## Decision

`PeerView.presence` 与 `labelForPeerPresence` 仍然是会话列表里在线状态的来源。
会话行继续在标题旁显示「在线」「连接中」或「离线」，离线设备有最后出现时间时
也继续显示。头像现在是普通的 `Avatar`，右下角不再带状态标记。

应用外壳不再在导航轨品牌标下方或窄窗口底栏上方绘制 `ConnectionSummary`。
`AppNavRail` 不再提供状态槽位。只为这些指示存在的支撑代码已经移除：
`PresenceAvatar`、`PresenceDot`、`PresenceCounts`、数量与提示文案，以及对应的
widget 测试。设备页仍然是查看完整地址、最后出现事实和单设备连接详情的入口。

## Alternatives considered

**只在窄窗口保留总览。** 否：那条窄带仍然会重复每个可见会话行的文字，而且为
一个没人使用的总数保留两套外壳行为，只会多一份需要维护的契约。

**保留圆点但让它更不显眼。** 否：会话行已经用文字说明状态。更小或更低对比度的
圆点仍然在重复同一件事，也仍然比文字更难读。

**连行内文字一起删掉。** 否：文字是不依赖色觉、可直接访问的答案，回答现在能否
发送消息。用户要求去掉的是重复指示，不是有用文字。

**把已经没人用的 widget 和计数模型留着。** 否：无用的外壳 API 会邀请下一位
调用者把同样的重复带回来，也会让测试暗示已经不再交付的行为。

## Consequences

- 导航轨把纵向空间还给导航项，窄窗口底部只保留导航栏。
- 用户失去全局一眼可见的数量，以及总览直达设备页的快捷入口。会话行仍然逐台说明
  在线状态，设备页也仍然只差一次点击。
- 头像只负责识别设备，不再同时编码 Session 状态。在线状态保留在用户真正采取
  动作的那一处文字里。
- 线格式、持久化数据和 Session 行为都没有改变。

## Testing

`test_flutter/ui/presence_test.dart` 固定剩余的行内文字。
`test_flutter/ui/pages_test.dart` 断言已连接的会话行显示「在线」，并断言头像中
没有定位的状态浮层。`test_flutter/ui/shell_test.dart` 断言宽窗口导航轨与窄窗口
底部导航都不再显示在线、离线或空状态文案。


# Agent Note: Android 落在会话列表，消息菜单由长按呼出

Status: implemented

## Problem

Android 版本有两处没有像一台手机那样工作。

消息只能从右键打开的菜单里删除，而 `TransferContextMenu` 只监听
`onSecondaryTapDown`。Android 没有第二个鼠标键，于是在这个产品真正发布的平台
上，根本没有任何手势能触达「删除」—— 控制器里有这个动作，界面上却到不了。

打开应用还会跳过会话列表。`ConversationsPage` 在还没选中任何东西时会回退到
`controller.lastConversation`，在宽屏上这只是列表旁的一次预选中 —— 但窄屏布局
一次只显示一个面板，同样的回退让被记住的会话成了整屏。于是启动直接落在一个没人
要求的对话里，离真正作为本页面家的列表只有一步之遥。

## Decision

`TransferContextMenu` 在 `onSecondaryTapDown` 之外也响应 `onLongPressStart`，
在手势发生的位置打开同一个菜单。长按由 `TransferMenuGestures.longPressMenu`
把关，默认值是 `Platform.isAndroid`：其他地方的长按留给 `SelectionArea`，那里
它是选中气泡内文字的方式。答案做成字段而不是在 `build` 里读平台，是因为 widget
测试跑在宿主机上 —— `Platform.isAndroid` 永远为假 —— 否则这个手势永远无法被
测试覆盖。

`ConversationsPage` 新增 `restoresLastConversation`，默认 true。被记住的会话回
退只在 `widget.restoresLastConversation` 成立时生效，`HomeShell` 传入
`widget.seams.platform != DevicePlatform.android`。`requestedPeer` —— 设备页要
求打开某个会话 —— 不受影响：那是使用者的主动动作，不是回退。

门禁按平台而不是按宽度。窄的 Windows 窗口和以前一样恢复上次会话；变的只是哪些
平台采用「一次一个面板、列表即落点」的约定。

## Alternatives considered

**所有平台都开长按。** 否决：在桌面上长按本来就是选区手势，拿它开菜单会让选词
失效 —— `words in a bubble can be selected` 这条 widget 测试抓到的正是这个。其
他触屏平台以后要启用只需改那一个字段。

**在 `build` 里判断 `defaultTargetPlatform == TargetPlatform.android`。** 否
决：`flutter_test` 对 `defaultTargetPlatform` 的回答是 Android，于是这个手势会
在每一条 widget 测试里生效 —— 包括被它弄坏的选区测试 —— 而且它混淆了「框架以
为的平台」和「这个二进制跑在什么平台上」，后者 seams 已经用 `DevicePlatform` 回
答了。

**按窄布局而不是按平台把关。** 否决：需求说的是平台约定，不是窗口宽度。窄的
Windows 窗口仍然是桌面界面，改它的落点是没人要求的行为变更。

**每次到达都恢复上次会话，只在冷启动跳过。** 不需要单独机制：回退只在
`_untouched` 期间生效，而它在第一次选中或返回时就结束了，所以不提供回退本来就
只影响「什么都没选过的到达」—— 冷启动和会话内第一次切到这个标签。

## Consequences

**换来的。** 在 Android 上长按任意消息气泡都会打开和右键相同的菜单 —— 包括
「删除」—— 应用落在会话列表而不是上一个对话里。桌面端两个方向的行为都不变。

**付出的。** 在 Android 上气泡内的长按不再发起选词：菜单手势赢得了手势竞争。
因此那里无法复制句子的一部分；整条消息的复制（「复制」）仍然可用，菜单本来就带
这条。这个取舍和手势本身来自的消息应用约定一致。

## Testing

`test_flutter/ui/delete_message_test.dart` 新增一条长按测试，设置
`TransferMenuGestures.longPressMenu` 后断言菜单弹出并完成删除；现有的右键与选区
测试在字段为 `Platform.isAndroid` 默认值 —— `flutter test` 下为 false —— 的情
况下运行，钉住了桌面端不变的一侧。

`test_flutter/ui/pages_test.dart` 新增一条 Android 重启测试：以
`platform: DevicePlatform.android` 启动的设备打开过会话后重建窗口，显示的是列
表而不是会话。现有的 `the default conversation is ready to type in on startup`
测试钉住了同一回退在 Windows 侧的行为。

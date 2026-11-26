# Agent Note: 对话头只陈述一次在线状态

Status: implemented

[English](2026-11-26-conversation-header-presence.md) | 中文

## Problem

打开的对话顶部用对端地址作标题，副标题却在「10.0.0.7，不接受连接 · 离线」里把
地址又印了一遍。一行里有三个毛病：地址出现两次；「不接受连接」断言了一个配置
事实——对端拒绝 Session——而安静的局域网给不出这个结论，离线、未配对或正在重
启的对端都同样不宣告 Session 端口；「离线」则把标题旁断开图标已经说过的话又说
了一遍。第二行的全部高度都花在了标题行和列表行已经说过的事情上。

## Decision

在线状态移到标题行。`_PaneHeader` 和推入式 `ConversationPage` 的 AppBar 现在在
标题旁绘制 `labelForPresenceState`——在线 / 连接中 / 离线——取代了只能说「不
在线」、却说不出是哪种不在线的 `link_off` 图标。文字和图标一样不依赖色觉，而且
它说出了图标说不出的状态。

`describePeerConnection` 现在返回 `String?`，只承载标题和在线状态都没说的内
容：监听端口；或者对 Discovery 尚未定位的对端显示从未出现——除非此时恰好有
Session 开着，因为连接是更强的事实。已定位但没有 Session 端口的对端不再有副标
题行，对话头因此收成一行。

转发目标选择器把状态留在副标题里，因为它的行没有可以放在线状态的标题行；
`labelForPresenceState` 是那里共用的单词读法。随之不再被引用的
`conversationDisconnected` 字符串已从 ARB 文件移除。

## Testing

`test_flutter/ui/labels_test.dart` 钉住可空契约：已定位但无 Session 端口的对
端不说任何话；已连接的对端不说在线状态词已说过的话；从未出现的对端仍显示从未
出现，除非此时有 Session 开着。

## Alternatives considered

**保留「不接受连接」，只去掉重复的地址。** 否：误导的是这个短语本身。空的
`sessionPort` 只意味着「没有宣告端口」，任何当前拨不通的对端都会产生它；能推
翻它的唯一事实是活着的 Session，而那种情形本来就不显示这句话。

**在在线状态词旁保留 `link_off` 图标。** 否：文字已经把状态作为文本承载，和图
标一样不依赖色觉，两者并列等于把离线说两遍。

**在对话头显示列表行的「离线 · 3 分钟前」。** 否：标题行只放得下状态，放不下时
间戳；最后出现时间留在行上，`labelForPeerPresence` 已经把它放在那里。

## Consequences

- 对端没有 Session 端口可报时，对话头少一行；两种主题下状态都能一眼读出。
- 「不接受连接」仍出现在对话列表的预览兜底里（`describePeerAddress`），那里它
  是地址唯一的展示位置；对话头不再做这个断言。
- `describePeerConnection` 的可达性尾巴对所有调用方消失；转发选择器通过
  `labelForPresenceState` 显式补回。

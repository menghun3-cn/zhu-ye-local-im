# Agent Note: Addresses in a message are clickable links

Status: implemented

[English](2026-11-13-addresses-in-a-message-are-clickable-links.md) | 中文

## Problem

消息里收到的网址只是一段死文字。会话把它和周围的字用同一种墨色画出来，
唯一的用法是选中、复制、粘贴到浏览器——每个聊天应用多年前就消除掉的
那十几步。发送方已经把地址送上了网线，接收方却还得自己把它送进一个能
打开它的界面。

## Decision

文字消息的内容在气泡构建时被扫描，其中的网址被画成链接——加下划线、
用主题的链接色——点击后在本机浏览器打开。

- **`messageLinks`**（`lib/core/util/message_links.dart`）是识别器，
  纯 Dart，`dart test` 直接覆盖：`https?://` 和 `www.` 开头、RFC 3986
  的字符集，不识别裸 `example.com`（裸域名和版本号、文件名太难区分，
  猜出来的误报比便利更糟）。句尾标点和没有配对的右括号会被裁掉——
  `（见https://a.com）` 链接的是 `https://a.com`，不是括号——`www.`
  的匹配会补上 `https://` scheme，因为浏览器接不了没有 scheme 的地址。
- **`_LinkifiedText`**（`lib/ui/conversation_view.dart`）是消息 `Text`
  外面的一层有状态包装：它构建 `TextSpan`——普通文字用原墨色，每个
  地址用链接样式加一个 `TapGestureRecognizer`，并负责 dispose 这些
  recognizer，这是无状态 build 做不到的事。没有地址的消息仍然构建
  原来的普通 `Text`。会话外层的 `SelectionArea` 照常工作：拖拽不是
  点击，跨链接选中复制的仍是地址本身的字符。
- **`isOpenableLink` 放宽**：从「github.com 的 https」变成「任意带
  host、无空白和控制字符的 http/https 地址」。GitHub 限制存在的理由
  是地址来自 GitHub 响应；消息里的地址是对端写的文本，所以现在的校验
  是 scheme 白名单——真正能挡住伪造地址混进 shell 的东西——而不是
  一张会拒绝大多数人互相发送内容的 host 名单。
- **Windows 改走 `rundll32 url.dll,FileProtocolHandler`**，不再用
  `cmd /c start`。`start` 在所有地址都来自 GitHub 时是安全的；对端
  文本可以带 `&`，而 `cmd` 会把它读成命令分隔符。`rundll32` 是同一个
  「交给默认处理程序」，中间没有命令 shell。
- **Android 走新的 `browser` channel**
  （`cn.hnasct.local_transfer/browser`，方法 `openUrl`），在
  `MainActivity` 里发 `ACTION_VIEW`——与 `files`、`update` 两个 channel
  已确立的模式相同，这也是没有引入 launcher 插件的原因。Kotlin 在
  发 intent 前同样复查 scheme 和 host，manifest 的 `<queries>` 声明了
  `http`/`https` 的 `VIEW`，免得 Android 11+ 的包可见性在明明有浏览器
  时回答「没有」。
- 点击走既有的 `LinkResolution.opener` 接缝，widget 测试像 About 页
  链接那样换成替身。

## Alternatives considered

**`flutter_linkify` / `linkify` 包。** 否决：为一个正则表达式买一个依赖，
而这个项目别处也自己写匹配，并且 `lib/core` 保持不依赖 Flutter，规则才能
在 `dart test` 下被钉住。

**`url_launcher` 插件。** 第三次以同样的理由否决——为平台 shell 和
runner 自有 channel 已经能回答的调用买一个原生注册（`openInBrowser`
的注释记着这个取舍；`2026-11-12-tapping-a-landed-file-opens-it` 一天前
为打开文件否决过它）。Android 那一半无论哪条路都是三十行 Kotlin，
channel 版本还让「本应用不带插件」成立。

**保留 `cmd /c start`、把地址校验做得更严。** 否决：让地址对 `cmd`
危险的字符——`&`、`|`、`>`、引号——同时也是合法 URL 字符
（`?a=1&b=2` 是普通用法），字符黑名单会把真链接挡掉，却防不住一个
无 shell 调用本来就没有的注入。

**每个气泡用 `SelectableText.rich` 代替共享的 `SelectionArea`。** 否决：
area 已经让列表里每个 `Text` 可选中，包括跨消息边界；每气泡一个
selectable 会让跨两条消息的拖选在气泡边缘断掉——而用户要的不是
到边缘为止的选区。

**识别裸域名（`example.com`）。** 否决：版本号（`1.2.3`）、文件名
（`a.b`）、带点的缩写和域名在没有启发式时无法区分，每个误报都是一个
打开错误地址的链接。`www.` 是折中——人们写「我指的是个网址」时用的
就是它。

## Consequences

- 收到的 `https://…` 或 `www.…` 地址以 `brandStrong`——调色板里本就
  定义为链接文字色的 token——加下划线绘制，点击在 Windows 和 Android
  的默认浏览器打开。在皮肤气泡上链接色仍取主题色，这是已知的粗糙边缘，
  图片皮肤花哨时可能不够醒目。
- 两个方向都有链接，不只是收到的：识别器是文本的事实，自己发出的
  地址和收到的同样可以打开。
- 没有浏览器或平台既不是 Windows 也不是 Android 时 opener 回答
  false，地址留在屏幕上供手动复制——与 About 页链接给出的答案相同。
- `isOpenableLink` 不再限定 host，About 页的 GitHub 链接也走同一个放宽
  后的闸门；它实际打开的东西没有变化。
- Kotlin 那一半靠检查和 `test/platform/android_bridge_test.dart` 里的
  Dart 侧契约测试验证，没有实机 instrumented 验证——这台机器上没有
  门禁会构建 APK。

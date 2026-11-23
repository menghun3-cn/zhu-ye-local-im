# Agent Note: A landed message file can be shared to another app on Android

Status: implemented

[English](2026-11-23-share-a-message-file-to-other-apps.md) | 中文

## Problem

会话里收到——或本机发出——的文件和图片只能在本应用内使用：可以打开、可以
显示所在目录、可以复制像素。最常见的下一步是把它发给微信，而此前除了离开
应用、在文件管理器里找到文件、再拖进聊天框之外没有别的办法。

微信本身没有分享 SDK，也没有供第三方应用投递文件的 URL scheme，所以「分享到
微信」不可能是一次直接调用。Android 提供的替代品是系统分享面板：一个
`ACTION_SEND` intent，微信在内的所有接收方都应答，由用户选择目标。这个面板
就是可用的全部机制，它也是这个功能诚实的名字：菜单项写的是「分享」，而不是
「分享到微信」，因为面板里有什么是设备说了算，不是我们。

## Decision

分享搭的是应用已有的平台通道，而不是新插件。`MainActivity` 的
`cn.hnasct.local_transfer/files` 通道在 `openFile`、`openFolder` 旁边加了
`share` 方法：它把每个路径经现有的 `update_file_provider` FileProvider 转成
`content://` URI——`update_paths.xml` 已经暴露 `filesDir`、`cacheDir` 和外
部存储，覆盖了接收文件（`filesDir/incoming`）和被选中文件的落点——单个文
件按真实 MIME 类型（复用 `mimeOf`）发 `ACTION_SEND`，多个发
`ACTION_SEND_MULTIPLE`（`*/*`），并把所有 URI 放进 intent 的 `ClipData`，
让读取授权对每一个都生效。

Dart 侧的接缝与 `OpenResolution`/`RevealResolution` 同构：
`lib/ui/share_file.dart` 定义 `FileSharer`（`supported` +
`share(paths)`），`SystemFileSharer` 用 `Platform.isAndroid` 回答
`supported`，并把列表过滤成仍然存在的文件；`ShareResolution.sharer` 是测试
替换用的可变字段。`transfer_actions.dart` 新增 `canShareTransferFile`
（`localPath != null && sharer.supported`）与 `shareTransferFile`，
`TransferContextMenu` 在谓词成立处画一行「分享」——`Icons.share_outlined`，
位于「打开」与「复制图片」之间。分享返回 false 时弹出与其他文件操作相同的
TopToast 提示。

分享的只是 `view.localPath`——多项目发送取第一项，与「打开所在文件夹」和
「打开」给出的答案相同，因为视图每条消息只跟踪一条路径。

## Alternatives considered

**`share_plus` 插件。** 否决：它要引入一个依赖和第二套 FileProvider 配置，
而已有通道上约 50 行 Kotlin 就能做完。本项目刻意几乎不带插件——runner 自
己的通道存在的意义就是让平台事实不经拉包抵达——而这个功能在通道上缺的东
西一样都没有。

**`startActivity` 之前先做 `queryIntentActivities` 预检，像 `openPath` 那
样。** 对这个方法否决：Android 11+ 上包可见性会过滤查询结果，除非 manifest
声明了对应 intent filter，否则被过滤为空的答案会报「没有应用能接收」，而微
信明明就在那儿。直接启动 intent 让系统如实解析；空面板会抛
`ActivityNotFoundException`，Dart 读出来同样是 false——两种情况给用户的是
同一句话。

**定向微信**（写死它的包名，或走 `weixin://` scheme）。否决：微信没有给第
三方应用投递文件的 API，把包名写死只会在微信没装时坏掉，却仍然假装自己是
微信功能。选择器才是 Android 真正提供的契约。

**现在就做 Windows。** 推迟而非否决：Windows 没有面向任意文件的系统分享契
约。可行的路——拷进微信的 `FileStorage` 目录，或写 `CF_HDROP` 剪贴板条目
——要么脆弱要么需要手写 Win32，都不值得塞进一个需求偏 Android 的改动。
`FileSharer.supported` 就是将来 Windows 实现的插口。

## Consequences

* 菜单项出现在 `TransferContextMenu` 服务的每个界面——会话气泡和传输卡片
  的菜单 alike——只要存在分享面板；目前即只有 Android。
* 这样分享出去的文件由用户所选应用在只读授权下读取，授权只覆盖这一次分享；
  应用不留记录，字节也只经接收应用离开设备。
* `supported` 挂在 sharer 上，而不是在谓词里读 `Platform.is`，所以 widget
  测试可以在不假装成 Android 的情况下让菜单项出现或消失。
* Kotlin 侧没有新增 manifest 条目：`update_file_provider` 已经覆盖本应用
  能写入接收或被选中文件的所有目录。

## Testing

`test_flutter/ui/share_transfer_test.dart` 通过 harness 完成一次真实的双
设备传输，打开落地文件的菜单，点「分享」，断言 sharer 收到的正是落地路径；
随后把 `supported` 关掉，断言该行消失而菜单其余部分仍在。通道方法本身只在真
机上被执行——任何宿主机都开不了选择器。

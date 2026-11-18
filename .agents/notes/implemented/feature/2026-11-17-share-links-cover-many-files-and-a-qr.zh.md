# Agent Note: Share links cover many files and carry a QR code

Status: implemented

[English](2026-11-17-share-links-cover-many-files-and-a-qr.md) | 中文

## Problem

「通过链接分享」页面只能靠系统文件选择器喂文件，而且一个文件一条链接：
把五个文件拖到页面上什么都不会发生，分享它们意味着五张卡片、五个 URL、
五次复制。接收方那边也没有页面——每条链接直接下载它那一个文件，于是
「这是度假拍的照片」到达时是一串互不相干的 URL。而且把链接弄到手机上
的唯一办法，是选中、复制、粘贴到手机能看见的地方。

## Decision

现在一次选择或拖放就是一次分享：一个指向服务端渲染列表页的链接，加上
编码同一链接的二维码，都在一张卡片上。

- **`LinkTransferServer.createShare`**（`lib/core/link_transfer/`）在
  `_links` 旁边多了一张表：`_shares[token] → {files, createdAt}`，共用
  同样的 30 分钟过期与同一轮清理。返回的 URL 是 `/s/<token>`；
  `GET /f/<token>/<index>` 按序号流式下载——用序号而不是文件名进
  URL，非拉丁字符和重名都不可能弄坏链接。列表页由 handler 直接渲染：
  文件名做 HTML 转义、输出 UTF-8（响应默认的 latin1 会把 `报告.pdf`
  写成 `??.pdf`），因为接收方是个普通浏览器，可能没装本应用——也可能
  不是本应用的语言；页面用英文，与它旁边的单文件索引页一致。
- **`ShareByLinkPage`** 把整个内容区包进 `DropTarget`（`desktop_drop`，
  与会话页同一个插件），所以文件落在页面任何位置——不只是空态——都走
  和选择器相同的 `_sharePaths` 路径。路径先经 `File.existsSync()` 过滤：
  拖入的文件夹被跳过，一次全被滤掉的拖放会得到「没有可分享的文件」
  提示，而不是静默或误报失败。
- **卡片**展示文件数、文件名、`SelectableText` 链接和 84px 的
  `QrImageView`。三个操作：复制链接（不变）、复制二维码、删除。
  「复制二维码」通过卡片的 `RepaintBoundary` 按 4 倍尺寸读回像素，
  把 PNG 交给 `PasteResolution.paste.writeImage`——与截图复制图片同一
  条缝，所以 Android 上也能用，widget 测试也有现成替身。
- **`qr_flutter: ^4.1.0`** 是新增依赖：纯 Dart、三年稳定，同时提供
  展示用的 `QrImageView` 和 boundary 光栅化用的 `QrPainter`——不需要
  第二套二维码实现。
- 每文件一条的 `/download/<token>` 路径和会话里的 `shareByLink` 动作
  原样保留：分享「组」和单文件链接是两种东西，合并它们只会让一个
  已上线的流程为零收益买单。

## Alternatives considered

**保留每文件一链、每卡片加二维码。** 被用户否决：五个文件意味着五个
要粘贴的 URL、五张要展示的码，而消除这种摩擦正是这个功能存在的
理由。列表页才让「一次分享」真正等于一个链接。

**链接后面挂 zip 包。** 否决：需要压缩依赖和服务端打包步骤，而且接收方
还是得先解压才能看到东西。列表页上逐文件下载正是各家局域网分享工具
收敛出的形态。

**下载 URL 里带文件名（`/f/<token>/<name>`）。** 否决：百分号编码、
HTML 与 URL 两套转义、重名，是三只穿同一条裤子的 bug；序号索引无聊
但不会错。

**手写二维码渲染。** 否决：二维码的版本选择与纠错等级是有标准的，
`qr_flutter` 是纯 Dart 且稳定；自己画等于给项目攒第三套二维码实现。

**复制二维码的文字（即 URL）而不是图片。** 否决：那正是复制链接按钮
已经做的事；「复制二维码」指的是聊天软件能直接粘贴的那张图。

## Consequences

- 把文件拖到「我的 → 链接分享」立即生成分享——没有选择器、没有暂存
  步骤——出现的卡片同时带着链接和对应的码。
- 同一局域网里的接收方在任意浏览器打开 `/s/<token>`，看到带逐文件
  下载按钮的列表；每次 `/f/` 命中都带着单文件路由已有的
  `Content-Disposition` 处理。
- 二维码编码的是分享页 URL，扫码和粘贴链接落在同一页面——一次分享，
  两种递送。
- 复制二维码走 `pasteboard` 的写图通道；平台拒绝时卡片会如实报失败，
  而不是假装成功。
- 分享页只有英文，与现有 `/` 索引页一致；中文优先的接收页是可能的
  后续改进，不是回退。
- 单次分享的文件数没有上限，与选择器从来没有上限一致。

## Testing

- `test/link_transfer/link_server_test.dart` 覆盖组链路：列表页列出
  每个文件（含非拉丁字符文件名）、`/f/<token>/<i>` 按序号吐出正确
  字节并带 `filename*`，目录与不存在路径被过滤，全被滤掉的分享返回
  null，未知 token 与越界序号返回 404。
- `test_flutter/ui/share_by_link_page_test.dart` 驱动真实页面：选择器
  与 `DropDoneDetails` 拖放各自产生一张带 `QrImageView` 的卡片，
  只拖文件夹得到无文件提示，复制二维码按钮往替身剪贴板里放进了
  PNG 魔数开头的字节。

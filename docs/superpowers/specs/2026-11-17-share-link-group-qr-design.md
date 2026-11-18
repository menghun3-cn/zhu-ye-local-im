# 合并链接页 + 二维码 + 拖拽分享 — 设计

日期：2026-11-17 · 分支：`feat/share-link-group-qr`（worktree `zhu-ye-local-im-share-link`）

## 意图与背景

「我的 → 通过链接分享」页面（`ShareByLinkPage`）目前只能通过系统文件选择器
逐个生成下载链接：每个文件一条 `http://IP:port/download/<token>`，30 分钟过期。
本次要做三件事：

1. 文件可以直接**拖到该页面**生成分享，不必先点按钮选文件。
2. 一次分享（无论几个文件）合并成**一个链接**，接收方打开是文件列表页，
   逐个下载。
3. 每条分享同时生成**二维码**（编码同一个链接），卡片内嵌展示，并提供
   「复制二维码图片」按钮。

## 目标 / 非目标

目标：

- `ShareByLinkPage` 支持 OS 文件拖入（Windows；Android 上 `DropTarget`
  自然不工作，不做额外处理）。
- 一次选择/拖入 = 一个分享组 = 一张卡片 = 一个链接 + 一张二维码。
- 接收方页面：文件名列表 + 每行下载按钮，服务端渲染 HTML。
- 「复制二维码」把二维码渲染成 PNG 写入系统剪贴板（可粘贴到微信等）。

非目标：

- 不做 zip 打包下载、不做「全部下载」按钮。
- 不改会话消息右键菜单里的 `shareByLink`（`transfer_actions.dart`）：它仍走
  单文件 `/download/<token>` 直链，保持不变。
- 不做拖拽文件夹（链接服务只服务单文件；拖入目录被跳过）。
- 不做二维码扫码统计、下载次数等。

## 现状约束

- `LinkTransferServer`（`lib/core/link_transfer/link_server.dart`）：
  `_links[token] → _LinkEntry{filePath,fileName,createdAt}`；路由
  `/`、`/download/<token>`、`/info/<token>`；30 分钟过期定时清理；
  `_contentDisposition` 已处理非 latin-1 文件名。
- `LinkTransfer.createLink` / `LinkTransferServer.createLink`：单文件入口，
  被 `transfer_actions.dart` 的 `shareByLink` 使用 —— **签名与行为不动**。
- UI 侧可复用件：
  - `desktop_drop` 的 `DropTarget` + `_dropping` 覆盖层模式
    （`conversation_view.dart` ~L624）；
  - `PickerResolution.picker.files()` 返回 `List<XFile>`（path/name）；
  - `PasteResolution.paste.writeImage(bytes)` 跨平台图片写剪贴板
    （`clipboard_paste.dart`，带测试替身）；
  - `classifyPaths`/`File.existsSync()` 判定真实文件。
- 新依赖：`qr_flutter: ^4.1.0`（pub.dev 最新稳定版，发布于 3 年前，
  纯 Dart，无平台通道，widget 与 `QrPainter` 都可用）。

## 方案

### 服务端：分享组

`LinkTransferServer` 新增与 `_links` 并列的 `_shares` 表：

```dart
_shares[token] → _ShareEntry {
  files: [{path, name}],   // 保序
  createdAt,
}
```

- `createShare(List<({String path, String name})> files, {peerAddresses})`
  → 返回 `http://<ip>:<port>/s/<token>`；文件不存在/为空返回 null。
- 路由新增：
  - `GET /s/<token>` → 服务端渲染的列表页：标题、文件数、每行
    文件名 + 大小（serve 时 `stat`）+ 「下载」按钮，链接到
    `/f/<token>/<index>`；token 无效/过期 → 404 页。文件名做 HTML 转义。
  - `GET /f/<token>/<index>` → 流式下载第 index 个文件，复用
    `_contentDisposition`；index 越界/过期 → 404。
- 过期清理：`_cleanupExpiredLinks` 同时清 `_shares`（同一 30 分钟）。
- `LinkTransfer` 门面加 `createShare`（内部先 `File.existsSync` 过滤）。
- 单文件 `createLink`/`/download`/`/info` 原样保留。

### 页面：`ShareByLinkPage`

状态：`List<_Share>`，每项 `{token 链接, 文件名列表, createdAt}`。

- 整页（header 之下的内容区）包 `DropTarget`：
  - `onDragEntered/Exited` → `_dropping`，显示覆盖层
    「松开生成分享链接」（新 l10n `shareByLinkDropHint`）。
  - `onDragDone` → 取 `detail.files` 路径，过滤 `File.existsSync()`
    （目录自然被滤掉），走与选择器相同的 `_createShare` 流程。
- `_pickAndShare` 与拖放合并为一个入口 `_sharePaths(List<String> paths)`：
  启动 server → `shareAddressHints` → `createShare` → 加入列表。
- 卡片布局（每分享一张）：
  - 顶行：文件图标 + 「N 个文件」+ 首个文件名（超长省略）；
  - 二维码：`QrImageView` 内嵌约 84×84，白底；
  - 链接 `SelectableText`（monospace）；
  - 过期提示；
  - 操作行：复制链接（现有 `_copyLink`）、复制二维码
    （`Icons.qr_code`，tooltip `shareByLinkCopyQr`）、删除。
- 「复制二维码」流程：`QrPainter`/`QrCode` 离屏绘制 → `ui.Image` →
  PNG `Uint8List` → `PasteResolution.paste.writeImage` → 成功 SnackBar
  `shareByLinkCopiedQr`，失败 `shareByLinkCopyQrFailed`。
  QR→PNG 封装成独立函数便于 widget test（`runAsync` 内可用）。
- 空态文案补一句「或将文件拖到此处」。

### l10n

新增 key（zh/en ARB 同步，`flutter gen-l10n` 随构建生成）：
`shareByLinkDropHint`、`shareByLinkCopyQr`、`shareByLinkCopiedQr`、
`shareByLinkCopyQrFailed`、`shareByLinkFileCount`（带 count 参数）、
`shareByLinkEmpty` 文案更新。

### 测试

- `test/link_transfer/link_server_test.dart` 增补：
  - `/s/<token>` 返回 200 且包含全部文件名；
  - `/f/<token>/<i>` 下载内容正确、Content-Disposition 文件名正确
    （含非 latin-1 名）；
  - index 越界、未知 token、过期 → 404。
- `test_flutter/ui/` 新增 share_by_link 页面测试：
  - picker stand-in → 生成一卡，含 `QrImageView`；
  - 以 `DropDoneDetails` 驱动 `DropTarget.onDragDone` → 同样生成；
  - 复制二维码调用 `PasteResolution.paste` stand-in 的 `writeImage`。
- QR→PNG 函数单测（纯 Dart 侧若可行放 `test/`，否则 `test_flutter/`）。

### Agent Note

`implemented/feature/2026-11-17-share-link-group-and-qr.{md,zh.md,i18n.yaml}`
三件套，同 PR 提交。

## 取舍说明

- **服务端渲染而非复用 `/` 单文件页**：列表页数据（文件名/大小）只在
  请求时才有意义，且避免在 Dart 侧拼接 JS；HTML 转义集中一处。
- **索引式下载 URL `/f/<token>/<i>`**：不用文件名进 URL，中文名、
  特殊字符、重名都不构成问题。
- **每次拖放/选择 = 新卡片**：不与已有分享合并，行为可预期；
  服务端本来就按 token 隔离。
- **`qr_flutter` 而非自绘**：QR 编码纠错、版本选择是标准算法，
  自己写是重复造轮子；包是纯 Dart、三年无更新即稳定。
- **复制走 `PasteResolution.paste.writeImage`**：与截图复制图片同一
  通道，测试有现成替身；不用 Win32 `CF_DIB` 私有路径，Android 也能用。

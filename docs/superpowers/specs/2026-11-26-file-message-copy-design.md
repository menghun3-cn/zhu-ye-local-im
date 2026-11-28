# 文件消息「复制文件」— 设计文档

日期：2026-11-26
状态：已实现（PR #317）

## Intent / Why

用户希望聊天里收到或发出的**文件消息**右键能像在文件夹里 Ctrl+C 一样，把文件本身放进系统剪贴板；粘贴到文件管理器或支持文件粘贴的应用时得到的是文件，而不是路径文本或文件内容。图片消息不在本次范围内：它已经有「复制图片」，语义是复制图片内容。

## 现状（已核实）

- `TransferContextMenu`（`lib/ui/transfer_actions.dart`）是会话与 Transfers 页共用的右键菜单；文件消息目前提供打开所在目录、打开、分享、转发、删除等，没有复制文件。
- 图片消息已有 `canCopyImage` / `copyTransferImage`，经 `PasteResolution.paste.writeImage` 把图片字节写进剪贴板；文本消息有 `copyTransferText`。
- `ClipboardPaste`（`lib/ui/clipboard_paste.dart`）已是剪贴板接缝：能读文件列表/图片，也能 `writeImage`；`ScriptedClipboard` 是 widget 测试的替身。
- `pasteboard` 插件的 `Pasteboard.writeFiles` 在 Windows 写 `CF_HDROP`，正是资源管理器复制文件的格式；Android 插件的 `writeFiles` 只接受 URI 字符串，不适合直接喂本机路径。
- Android 侧已有 `cn.hnasct.local_transfer/files` 通道与 `update_file_provider`：`update_paths.xml` 已放行 `filesDir`、`cacheDir`、外部存储，足够覆盖收到/发出的文件；`MainActivity.sharePaths` 已示范 FileProvider URI + `ClipData` 的做法。

## 方案（已选定）

复用 `ClipboardPaste`，新增 `writeFiles(List<String> paths)`，只服务 `PayloadKind.file` 的单文件消息。

- **菜单谓词**：`kind == PayloadKind.file && localPath != null && names.length == 1`，并在执行时确认 `localPath` 是普通文件。多文件/文件夹 Transfer 不显示该项：`TransferView.localPath` 对它们只可靠地指向第一个落地项或目录，复制其中一个会给出错误答案。
- **Windows / 桌面**：`SystemClipboardPaste.writeFiles` 调 `Pasteboard.writeFiles(paths)`；平台不支持或写入被拒时返回 false，由 UI toast 说明失败。
- **Android**：`SystemClipboardPaste.writeFiles` 不走 pasteboard 插件，改走 `android_files` 通道新增的 `copyFiles`：`MainActivity` 把每个存在的文件经 `update_file_provider` 转成 `content://` URI，组成 `ClipData` 后 `ClipboardManager.setPrimaryClip`。读权限由 Android `ClipboardService` 在其它应用拉取剪贴板时授予，与既有图片复制的机制一致，不需要新 provider 或 Manifest 变更。
- **文案**：新增 `copyFile` / `cannotCopyFile`（中文「复制文件」/「没能复制这个文件。」），与 `copyImage`、`copyText` 同组。

## 明确不做（non-goals）

- 图片消息不新增「复制文件」；「复制图片」保持现状。
- 不复制文件路径文本、不读取文件内容进剪贴板。
- 不支持多文件消息或文件夹 Transfer 的整体复制；这类消息本次不显示该菜单项。
- 不改协议、不改消息持久化格式。

## Approaches considered

1. **扩展 `ClipboardPaste.writeFiles` + Android 自有通道（采用）**：与 `writeImage` 同一接缝，widget 测试可用 `ScriptedClipboard` 断言；Android 用 FileProvider URI 才能被其它应用读取。
2. **只做 Windows，Android 不提供/失败**：改动更小，但 Android 是 v1 平台，且复制文件在 Android 上并非做不到，留下缺口不划算。否决。
3. **复制路径文本**：实现最简单，但不是用户要的「文件夹里复制文件」效果。否决。

## 测试与门禁

- `test_flutter/`：文件消息右键出现「复制文件」并把落地路径交给 `ScriptedClipboard.writeFiles`；写入被拒时提示失败；图片消息菜单不出现「复制文件」。
- Agent Note 三件套（`.agents/notes/implemented/feature/`）。
- 门禁：`verify-agent-notes`、`verify-translation-pairs`、`flutter analyze`、`dart format`、`dart test`、`flutter test test_flutter`；Android 原生改动至少保证 `flutter build apk --debug` 可编译。

## 留给实现者的决定

- Android `ClipData` 的 label/MIME 细节按 `sharePaths` 的既有写法对齐；若真机验证发现剪贴板项缺 MIME，调整 `ClipDescription`。

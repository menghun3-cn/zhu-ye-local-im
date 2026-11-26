# Agent Note: 文件消息按文件复制

Status: implemented

[English](2026-11-26-a-file-message-copies-as-a-file.md) | 中文

## Problem

会话里的文件消息可以打开、打开所在目录、分享、转发、删除，却不能像在文件
管理器里复制文件那样，把文件本身放进系统剪贴板再粘贴成一个文件。图片消息已
经有「复制图片」，但那复制的是图片内容而不是文件 —— 是另一回事，也不是这次
用户要的。

## Decision

`ClipboardPaste` —— 输入框读 Ctrl+V 所经过、图片复制也写入的同一道缝 —— 新
增 `writeFiles(List<String> paths)`。在 Windows 和其他桌面平台上它调用
`Pasteboard.writeFiles`，写入的是文件管理器写的 `CF_HDROP` 列表；在 Android
上则走应用自己的 `cn.hnasct.local_transfer/files` 通道，因为 pasteboard 插
件的 `writeFiles` 要的是 content URI，而不是本应用持有的文件系统路径。
Android 侧把每个存在的文件经现有的 `update_file_provider` 转成
`content://` URI，组成一个 `ClipData` 交给 `ClipboardManager`；读权限由
Android 的 `ClipboardService` 在其它应用拉取 `getPrimaryClip` 时授予，与图片
复制依赖的是同一机制，所以不需要新的 provider 或 Manifest 条目。

菜单项是 `copyFile` / `cannotCopyFile`，只对 `names.length == 1` 且
`localPath` 是真实文件的 `PayloadKind.file` 消息出现。多 item Transfer 和文
件夹发送被刻意排除：它们的 `localPath` 至多只可靠地指向第一个落地文件，复制
它会看起来像复制了整条消息，实际却把错误的东西放进剪贴板。类型在建菜单时
和点击时各检查一次，因为一个只含一个文件的文件夹发送，其路径仍是目录。写入
被拒时用户看到 `cannotCopyFile`；复制成功则什么都不说，因为粘出来的文件就
是确认。

这正是[图片笔记](2026-10-09-pictures-stand-on-their-own-and-can-be-copied.md)
*对图片*否决过的文件侧复制：「复制图片」仍然表示图片内容，而「复制文件」现
在表示文件本身。两条菜单由 `PayloadKind` 区分，所以任何一面都不必猜用户要
的是哪种复制。

## Alternatives considered

**只做 Windows，走 `Pasteboard.writeFiles`，Android 不支持。** 否决：Android
是 v1 平台，而在 Android 上复制文件并非做不到 —— 它需要平台自己的通道早已
会为 open/share 构建的 `content://` URI 形式。

**复制路径文本。** 否决：那不是用户要的文件管理器式复制，而且打开所在目录已
经用更有用的形式给出了路径。

**也给多 item 和文件夹 Transfer 提供复制。** 本次否决：`TransferView` 对这
些消息并不可靠地持有每个落地路径，唯一诚实的单路径答案会复制第一个文件或目
录，而消息名义上是多个。那比没有这条菜单更糟。

**把「复制图片」也改成复制图片文件。** 按范围否决：用户只要求文件消息，而现
有的图片复制已经回答了图片内容的问题。

## Consequences

- 一条落定的单文件消息在两个 v1 平台上都能把文件本身粘贴进文件管理器或其它
  应用。
- 剪贴板缝现在除了图片也能写文件；测试通过 `ScriptedClipboard.copiedFiles`
  断言路径。
- Android 的文件复制依赖 `update_paths.xml` 持续放行收到和选中文件可能所在
  的目录；收窄那个 provider 会静默弄坏这个动作。
- 文件夹发送和多文件 Transfer 仍然没有复制项；若将来需要，`TransferView`
  必须携带所有落地路径而不是一个。

## Testing

`test_flutter/ui/pages_test.dart` 覆盖落定文件消息提供 `copyFile`、把落地
路径交给脚本化剪贴板，以及写入被拒时报告 `cannotCopyFile`；图片菜单测试断
言 `copyFile` 不出现。Android 通道本身由编译以及 open/share 已在使用的同一
条 FileProvider 路径验证。

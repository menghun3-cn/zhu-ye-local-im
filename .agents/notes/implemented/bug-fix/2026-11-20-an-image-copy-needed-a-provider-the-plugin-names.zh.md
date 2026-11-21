# Agent Note: 复制图片需要一个由插件自行指定的 provider

Status: implemented

[English](2026-11-20-an-image-copy-needed-a-provider-the-plugin-names.md) | 中文

## Problem

在 Android 上长按收到的图片并选择「复制图片」总是失败，弹出「没能复制这张
照片」的提示；同一个操作在 Windows 上正常。

`SystemClipboardPaste.writeImage` 委托给 `Pasteboard.writeImage`。在
Android 上，插件把字节写成 `cacheDir` 下的临时 PNG，再把 `content://` URI
交给剪贴板——而这个 URI 是用
`FileProvider.getUriForFile(context, "${packageName}.provider", file)` 构造
的，authority 字符串**硬编码在插件内部**。App 的 Manifest 只声明了一个
`FileProvider`，authority 是 `${applicationId}.update_file_provider`，服务
于更新安装器和 `MainActivity` 里的文件/文件夹打开器。没有任何组件应答
`<applicationId>.provider`，于是 `getUriForFile` 在一个字节到达剪贴板之前
就抛异常，插件回 `error`，而 Dart 侧——它正确地把「剪贴板拒绝写入」当作
普通结果处理——于是弹出了失败提示。

Windows 看不到这个问题，因为它的 `writeImage` 路径是另一条：插件写临时
文件，经自己的通道设置 `CF_BITMAP`，整个过程没有 `FileProvider`。iOS 和
macOS 同样原生写图。这个 bug 在构造上就是 Android 独有的，而不是测试偶然
漏掉的。

## Decision

Manifest 为插件要求的 authority 声明第二个 `FileProvider`，与更新用的那个
并列：

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.provider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/clipboard_image_paths" />
</provider>
```

路径文件**只**放行 `cacheDir`（`<cache-path name="clipboard_image"
path="."/>`），即插件写临时 PNG 的唯一目录。现有的 `update_paths.xml` 已经
包含 `cache-path`，但复用它会把 `filesDir` 和外部存储也暴露在新 authority
之下——比剪贴板写入所需的面更大，且没有任何收益。

一个 Manifest 里放两个 `FileProvider` 是 Android 的常规做法：authority 是
区分它们的键，各自持有自己的路径文件。

## Alternatives considered

**让插件改用已有的 `update_file_provider` authority。** 做不到，除非 fork
或打补丁：authority 是 `PasteboardPlugin.kt` 里的字符串字面量，不是参数。
用 `dependency_override` 指向打过补丁的 fork 被否决——为了一行 Manifest
配置背负这样的维护面不值得。

**在 `MainActivity` 里用自己的通道写剪贴板图片。** 否决：那会重复插件在其
他三个平台上已经做的事（解码、压成 PNG、`ClipData`），而真正缺的只是
provider 声明。修复属于 Manifest——缺失的事实就在那里。

**让新 provider 复用 `@xml/update_paths`。** 以最小权限否决：那个文件把
整个 `filesDir`（收到的文件、身份数据）和外部存储都列入白名单。剪贴板只
需要一个目录；新的路径文件恰好只授予那一个。

## Consequences

- Android 上的「复制图片」现在能到达系统剪贴板；分享链接页的二维码复制
  走同一个 `writeImage` 接缝，一并修好。
- 插件在每次复制后仍会把临时 PNG 留在 `cacheDir`——这是插件内部既有的泄
  漏，有系统缓存清理兜底，本次改动不去动它。
- 这次没有 Dart 侧或 widget 测试覆盖：故障完全位于 Manifest 与插件的交
  互里，`dart test` 和 `flutter test` 都够不到。验证方式是在真机上构建并
  点按。

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

只声明 authority 事实证明还不够。真机验证显示 `ContentResolver` 把
`<applicationId>.provider` 的 URI 路由到了*更新* provider 的实例——
logcat 报 "The authority `...provider` does not match the one of the
contentProvider: `...update_file_provider`"——于是剪贴板 URI 的 `getType`
失败，剪贴板项拿不到可用的 MIME 类型。Android 在一个包内**按类名只运行一
个 provider 实例**：两条 `<provider>` 声明如果都写
`androidx.core.content.FileProvider`，会在 `ActivityThread` 的 provider
缓存里撞车，第二个 authority 被第一个实例应答，而那个实例根本不知道剪
贴板路径。

## Decision

Manifest 为插件要求的 authority 声明第二个 provider，与更新用的那个并列
——并且第二个必须是不同的*类*：`ClipboardFileProvider`，一个在应用包
内声明的 `FileProvider` 空子类：

```xml
<provider
    android:name=".ClipboardFileProvider"
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

同一个类的两个 provider 不能靠 authority 区分：`ActivityThread` 的运行
中 provider 缓存以类名为键，所以剪贴板 provider 必须是另一个类才能拿到
自己的实例。一行子类是拿到它的最小代价。

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
  点按——在模拟器上，对暂存的
  `content://<applicationId>.provider/clipboard_image/…` URI 执行
  `content query`/`content read` 能取回临时 PNG，logcat 也不再为它记录
  "Failed to get type"。其他应用读取该 URI 仍走剪贴板的常规授权：
  Android 的 `ClipboardService` 会把剪贴板项中 URI 的读权限授予每一个拉
  取 `getPrimaryClip` 的包，这正是 provider 保持不导出的原因。

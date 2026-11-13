# Agent Note: Tapping a landed file opens it

Status: implemented

[English](2026-11-12-tapping-a-landed-file-opens-it.md) | 中文

## Problem

本机收到的文件只能被看见，不能被用起来。Windows 上各界面只提供
**打开所在目录** 一个答案；Android 上连这一个都回答「没能打开」——
`SystemRevealer` 当初只写了 Windows。气泡上的点击在两个平台上都没有任何
反应：用户刚接收完的文件根本没有办法被打开，而打开一个收到的 APK 或文档
恰恰是最先要做的事。

这个缺口不是某个平台的偶然疏漏。`Revealer`、`LinkOpener` 和更新安装器各自
只回答了一类「交给操作系统」的事——文件夹、网址、本应用自己下载的 APK——
而一条经由局域网到达的文件哪一类都不属于。

## Decision

打开文件成为与「打开所在目录」并列的正式动作，出现在每一个展示已结束
Transfer 的界面上：

- **`FileOpener` / `OpenResolution`**（`lib/ui/open_file.dart`）与
  `Revealer`、`LinkOpener` 两条缝同形：生产环境拿到 `SystemFileOpener`，
  测试拿到替身。Windows 走 `explorer`，并复用 revealer 需要的 `/`→`\`
  参数转换，理由相同——Explorer 把参数里的 `/` 当成自己的开关来解析，而
  收到的路径在所有平台上都是 `/` 拼的。Android 走 runner 自己的 channel。
  两者在调用任何 shell 之前都先确认路径确实存在。
- **`SystemRevealer.reveal` 补上了 Android**——同时搬到了
  `lib/ui/system_reveal.dart`，因为它在 Android 上需要的 channel 是 Flutter
  依赖，而 `reveal.dart` 必须能被 `dart test` 加载：所在目录交给同一条
  channel 的 `openFolder`，由它通过 `content://` URI 请求文件管理器显示。app 私有
  存储里的目录是任何文件管理器都浏览不到的，所以那里回答 false 是正常
  情况，现有的 toast 会如实说出打开失败。
- **`MainActivity` 新增 `files` channel**
  （`cn.hnasct.local_transfer/files`），方法为 `openFile`/`openFolder`。
  两者都把目标以 FileProvider 的 `content://` URI 加读授权交给
  `ACTION_VIEW`——这是 Android 唯一允许交给其它应用的地址形式，
  `file://` 路径会被直接拒绝。文件按真实 MIME 类型提供
  （`MimeTypeMap`，`.apk` 显式写明，因为收到的更新恰好就是这种文件），
  所以 APK 会进入系统安装器，其它类型进入声明它的应用；目录以
  `resource/folder` 提供，没有接收方时回答 false 而不是报错。
- **`update_paths.xml` 暴露了可以被打开的范围**：整个 `filesDir`
  （收到的文件落在其下的 `incoming/`，用户手填的目标目录也在其下）、
  整个 `cacheDir`（文件选择器交回来的文件在这里），以及共享存储——
  因为本机*发出*的文件可能仍在那里。
- **界面**：文件气泡点击即打开——除裸图外，它的点击本来就是预览；
  右键/长按菜单在**打开所在目录**旁加了**打开**；Transfers 卡片在目录
  按钮旁加了打开按钮。`localPath` 只在 `TransferCompleted` 之后才被记录
  （`_recordLocalPath` 跑在 transfer 的 outcome 上），所以点击永远不会
  碰到写了一半的 `.part` 文件。
- ARB 新增两个词条：`openFile` 与 `cannotOpenFile`。

## Alternatives considered

**`url_launcher` 或 `open_file`/`open_filex` 插件。** 否决，理由与
`external_links.dart` 否决 `url_launcher` 相同：插件是为两次调用买来的
原生注册，而本项目已经拥有做这件事的 channel——`paths` 管数据目录、
`update` 管安装器、现在 `files` 管打开。无论哪条路，Kotlin 都只是三十
来行 `Intent`。

**对 `file://` URI 发 `ACTION_VIEW`。** 否决：Android 拒绝把 `file://`
路径交给其它应用——新版本上直接 `FileUriExposedException`——这正是
FileProvider 和它的按 URI 读授权要解决的问题。

**让 Android 把收到的文件存到公共存储**（`MediaStore` 的 Downloads 或
SAF），好让文件管理器能显示所在目录。否决为不成比例：那是存储模型的
改动——权限、URI 持久化、返回 `content://` 而非路径的选择器应答——
而买来的只是让**打开所在目录**可用；用户真正的需求是*打开文件*，私有
目录并不妨碍这一点。私有 `incoming/` 仍是原先记录在案的差距。

**在 Android 上隐藏「打开所在目录」。** 否决：诚实的答案已经在了——
channel 回答 false，toast 如实说明打开失败——而且用户自选的、位于私有
目录之外的目标是可以被文件管理器显示的，所以这行字并非句句都是假。

**Windows 上用 `cmd /c start`、用 `explorer /select,` 高亮文件。** 两条
否决维持
`2026-10-10-a-folder-spelled-with-the-wrong-slash-opened-documents` 与
`2026-10-09-images-arrive-on-their-own-and-a-file-can-be-shown-in-its-folder`
中的原判：`cmd` 会给一个受对端文件名影响的名字带来引号陷阱，`/select,`
与路径共用一个 token，空格就会拆散配对。

## Consequences

- Android 上收到的 APK 现在能进入系统安装器——正是报告所指的那种文件——
  其它类型进入声明它的应用，或者 Android 自己的选择器。
- 只要路径存在，**打开**就在两个平台上与目录动作并列提供：Windows 补上了
  从未有过的点击打开，Android 补上了此前整体缺失的答案。
- FileProvider 的暴露面比只有 `update/` 宽了；授权仍是按 URI、按 intent
  逐次授予，扩大 paths 本身并不暴露任何东西。
- Kotlin 半边靠检查和它周围的 Dart 契约验证，没有实机跑过：widget 套件
  在 `OpenResolution` 处替身，本机的门禁也不构建 APK。

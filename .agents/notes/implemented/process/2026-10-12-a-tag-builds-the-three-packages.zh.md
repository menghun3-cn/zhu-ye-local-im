# Agent Note: 打一个 tag，出三个包

Status: implemented

## Problem

这个程序能告诉使用者「有新版本」的每一个入口，都指向 GitHub Releases —— 而那里从来
没有发布过任何东西。「关于」页的下载按钮、以及侧栏那个更新入口（上一笔改动），打开的
都是 `releases/latest`，而那个页面一直是空的。一份构建要到达别人机器上，唯一的办法是
有人在某一台特定的 Windows 机器上跑一遍 PowerShell 脚本，然后把 zip 手动发过去。

那个缺口周围长出了三处具体的漂移。

**版本号有三个来源，而只有两个被比对。** `pubspec.yaml` 与 `appVersion` 由
`test/app/app_version_test.dart` 绑在一起，但
`scripts/pack-windows-portable.ps1` 里硬写着
`LocalTransfer-1.0.0-windows-x64-portable`。没有任何东西拿它和别的比 —— 而文件名是
一个包对外声称的最显眼的那句话。

**发布版是用调试密钥签的。** `android/app/build.gradle.kts` 里还留着 Flutter 模板那行
`signingConfig = signingConfigs.getByName("debug")`，上面顶着个 `TODO`。对
`flutter run --release` 来说这是对的，对一个要发出去的 APK 来说是错的：Android 用
**包名加签名密钥**一起标识一个应用，所以装了调试签名包的人，将来必须先卸载，才能装上
正式签名的版本。这件事在「还没有使用者」的时候不会有人发现。

**根本没有安装包。** `packaging/` 里只有一份说明。

## Decision

**tag 是触发条件，而且是唯一的触发条件。** `.github/workflows/release.yml` 由
`push: tags: ['v*']` 触发。没有任何东西是靠「在机器上点一下」产出的，推分支也不产出
任何制品。这是从 `AGENTS.md` §2.2 推出来的：那里已经写明 tag 是在 `release/vX.Y.Z`
的 PR **合入之后**打在 `master` 的 tip 上 —— 也就是说，tag 是「代码与它声称的版本号
都已定稿」的第一个时刻。

**流水线拒绝构建一个名字错误的发布版。** 第一个任务把 tag 与 `pubspec.yaml`、
`lib/app/app_version.dart` 三者比对，任何一处不一致就失败。它是这条流水线里唯一一个
真正拦得住上面那种故障的检查，而且它跑在任何编译之前。`dart test` 覆盖了其中两处，
tag 只有 CI 能覆盖。

**三个产物，名字来自已经校验过的版本号。** Windows 安装包、Windows 绿色包、
Android APK。

**CI 调用的就是开发者调用的那些脚本**，而不是另写一串 `flutter build`：Windows 那个
任务完整跑 `scripts/pack-windows-portable.ps1 -Smoke`，连冒烟都跑。一条自成一体的
流水线就是第二套打包实现，而且没有任何东西会去验证它。

**安装包是第二种格式，不是第二条流水线。**
`scripts/pack-windows-installer.ps1` 在
`build/dist/LocalTransfer-<版本>-windows-x64-portable/` 不存在时拒绝执行，并且会重新
抽查那个目录里的七样东西 —— `local_transfer.exe`、`flutter_windows.dll`、
`data\app.so`、三个 VC++ 运行库、以及说明书。`packaging/local_transfer.iss` 随后把
整个目录原样搬进去。两个脚本对「包里该有什么」都不持有自己的说法，因此没有对不上的
余地。

**每用户安装。** `PrivilegesRequired=lowest`，装到
`%LOCALAPPDATA%\Programs\LocalTransfer`，不弹 UAC。这个程序绑三个 socket、在
`%APPDATA%` 下写一个文件，没有任何要管理员权限的理由；要了，只会教人养成闭眼点过去的
习惯。代价是安装包不能替你加防火墙规则（那需要提权）——说明书把这件事讲明白并给出
手动命令，而不是让安装包看起来已经替你处理了。

**两份说明，因为其中一份会说假话。** 绿色包那份开头写着「不需要安装、不写注册表、
想删除就直接删掉整个文件夹」，对安装版就是错的。与其让一个文件两头兼顾地含糊其辞，
让安装包带上 `packaging/安装说明.txt`，讲清怎么装、怎么卸、怎么原地升级；至于程序
本身怎么用，仍然用那份绿色包的说明，一字不改。

**真密钥，且缺了它要大声失败。** `android/app/build.gradle.kts` 在
`android/key.properties` 存在时读它，不存在时退回调试密钥，这样任何机器上
`flutter run --release` 都还能跑。真正让它安全的是流水线：四个 Secret 缺一个就拒绝
开始；构建完之后跑 `apksigner verify --print-certs`，证书里没有 `CN=LocalTransfer`
就失败。于是「Secret 忘了配」不可能悄悄变成一个调试签名的发布版。

**`.iss` 必须带 UTF-8 BOM，而且打包脚本会强制这一点。** Inno Setup 6 会把没有 BOM 的
定义文件按 ANSI 解码，而本机代码页是 936 —— 简体中文有相当一部分能被它吃下去。结果
不是报错，而是一个向导和一批快捷方式的名字悄悄变成乱码。脚本会读前三字节，不是
`EF BB BF` 就拒绝编译。

**版本号是读出来的，不是抄出来的。** 两个打包脚本都从 `pubspec.yaml` 取版本，那个硬写
的数字删掉了。与之配套的节奏写在 `AGENTS.md` §9：日常功能与修复只加第三位，只有明确
的里程碑才动第二位，第一位在 1.0.0 之前不动。

## Testing

写这份笔记的机器上验过这些：

- `scripts/pack-windows-installer.ps1` 的 PowerShell AST 解析 0 错误，原有四个脚本也是 0。
- 把它完整跑了一遍：版本号推导正确（从 `pubspec.yaml` 得到 `1.0.0`），完整性抽查也能
  在上一轮打包留下的目录上通过全部七项 —— 然后它停在本机没有 ISCC 这件事上，给出的
  正是叫你 `choco install innosetup` 的那段话。
- `.github/workflows/release.yml` 用仓库自带的 `package:yaml` 解析通过，且结构就是想要
  的那个形状：顶层键 `name, on, permissions, jobs`；触发 `{push: {tags: [v*]}}`；
  任务 `version, windows, android, release`，步数分别为 2/6/8/4，每个 step 都有
  `uses` 或 `run`。
- 用 JDK 的 `keytool` 真的生成了一份 PKCS12 密钥库，并用创建时的口令打开成功 ——
  证书是 `CN=LocalTransfer, OU=Development, O=LocalTransfer, L=Hangzhou, ST=Zhejiang, C=CN`，
  有效期 10000 天。
- 两个新的中文文件都带 UTF-8 BOM，`.iss` 是 UTF-8 带 BOM，新说明书与它同级那份的编码
  一致。

**当时没验过的，以及第一次跑出来的结果。** 本机没装 Inno Setup，所以
`packaging/local_transfer.iss` **至今仍未被编译过**；`flutter build windows` / `build apk`
在这里根本跑不了（有一段时间本机 Dart 无法创建子进程，于是 `flutter`、`dart test`、
`flutter analyze` 全都不可用）。上面那些全是静态检查加上一个脚本的两条报错路径，仅此
而已。它第一次真正受检，就是 `v0.1.0` 那次发布。那一次校验版本号通过，两个构建作业全
红 —— 红的不在 Inno Setup 指令里（那一步根本没走到），而在
`android/app/build.gradle.kts` 和绿色包脚本自己的 zip 校验里。`subosito/flutter-action@v2`
对固定住的 `3.47.5` 解析无恙，所以上面那段盯着的另一件事站住了。两个缺陷与修复的理由见
[拥有它们的那篇 note](../bug-fix/2026-10-12-two-build-steps-that-had-only-ever-run-on-one-side.md)。

## Alternatives considered

**本地脚本发版，CI 只负责构建。** 否决：那样「是哪台机器产出的」就成了这次发布的一部分
含义。同一个 tag 跑两次会得到不同的字节，而「在我机器上是好的」会变成发布流程本身。

**用 MSI（WiX）而不是 Inno Setup。** 否决：它对组策略批量部署更好，而本项目没有那个
需求，代价是定义文件的复杂度高出一截。Inno Setup 是 Flutter 桌面应用的主流选择，装
它只要一行 `choco`。

**全机安装到 `Program Files`。** 否决：它让每一次安装与卸载都要提权，换来的东西这个
程序一样也用不上。

**让安装包自己再构建一份。** 否决：同一份源码构建两次，就是两次「它们可能不一样」的
机会；而验证恰恰住在绿色包那个脚本里。

**继续用调试密钥签名，然后把它写进文档。** 否决：它一直隐形，直到有使用者想升级的那
一天；而到那时候唯一的修法是卸载重装。

**让 CI 来打 tag（`TAG_MODE=ci`）。** 暂时否决，但只差一点：`git-publish` 支持它，而且
它能去掉最后一个手动步骤。保持 `local` 的原因是：tag 正是这个工作流的版本检查所信任的
输入，而一个既写 tag 又信任 tag 的工作流，等于在检查自己的作业。

**在 CI 里钉死 Inno Setup 的版本。** 否决：`choco install innosetup` 拿到的是当前
6.x，与照着说明书操作的开发者拿到的是同一个。让定义文件保持可移植的是那些 `#define`
和 BOM 检查。

**引入 Inno Setup 的简体中文语言包。** 搁置，不是否决：Inno Setup 没有官方简体中文
消息文件，要用就得引入一份来路不明的非官方 `.isl`。所以向导框架的文案是英文，而每一句
属于本产品的文案是中文。哪天这个混搭让人不舒服了，它可以再谈。

## Consequences

**换到了什么。** 发布离「真的发生」只差一条命令：在 `master` 上推一个 tag，三个包就
带着 changelog 条目出现在 Releases 页面上。侧栏那个更新入口和「关于」页那个按钮，总算
有了可指之处。

**版本号在任何东西被构建之前就被检查。** tag 与 `pubspec.yaml` 不一致、或
`pubspec.yaml` 与 `appVersion` 不一致，都会让发布停住，而不是发出去一个名字是错的东西。

**`.github/` 从此存在了，而它没有门禁。** 这里没有 PR 工作流：`AGENTS.md` §5 那六道
门禁仍然只在开发者机器上跑。一个在每次 PR 上跑 `dart test`、`dart format`、
`flutter analyze` 与两个文档校验器的 `gates.yml` 是显然的下一步，而它被刻意留在了这笔
改动之外。

**这条流水线的第一次执行就是 `v0.1.0` 那次发布，而它在那里失败了。** 失败在流水线而
不在产品 —— 校验版本号通过，两个构建作业都死在工具里 —— 于是 tag 被删掉，重推到带着
修复的 `master` tip 上，正好就是上一段为它写下的那种情形。tag 会移动是实打实的代价，
而且是明知故付：它名下什么都没发布过，所以没人下载过任何东西。缺陷本身见
[它们自己的 note](../bug-fix/2026-10-12-two-build-steps-that-had-only-ever-run-on-one-side.md)。

**CI 用的是工作流里钉住的那个 Flutter 版本。** 升它从此变成第二处需要显式改的地方，
而不是自动跟着 `stable` 走。这是为「发布产物可复现」付的代价。

**这份密钥库不能重新生成。** 它是这个应用在 Android 上的身份。一旦丢了，将来的任何
APK 都无法覆盖升级已经装上的版本。它在版本库之外，而它唯一的另一份副本只能是工作流
读取的那个 GitHub Secret。

**本机构建的 APK 只有在 `android/key.properties` 存在时才是正式签名。** 否则构建照样
成功，产出一个调试签名的包 —— 那对 `flutter run` 是对的，拿给别人是错的。CI 是这件事
的检查点；在开发者机器上，检查点是 `apksigner verify --print-certs`，说明书里写了。

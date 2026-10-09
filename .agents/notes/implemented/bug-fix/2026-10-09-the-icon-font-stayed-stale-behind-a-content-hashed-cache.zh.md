# Agent Note: 打包出来的图标字体停在了旧的子集上

Status: implemented

[English](2026-10-09-the-icon-font-stayed-stale-behind-a-content-hashed-cache.md) | 中文

## Problem

Windows 绿色包里出去的那份 Material 图标字体，缺了右键菜单里新加的
**复制图片** 需要的那一个字形：

```
PACK_THREW: MaterialIcons-Regular.otf 里没有这些字形，界面上的图标会是空白的:
      0xef7f (Icons.content_copy_outlined)
```

`scripts/pack-windows-portable.ps1` 里的守卫干对了活。它说不出的是**为什么**，
而第一个解释 —— 也就是脚本自己注释里写的那个 —— 是错的。

**排除「这个图标是死代码」**：`0xf090`（`Icons.folder_open_outlined`）**在**字体里。
它和缺失的那个在同一个文件、同一个 widget、同一个 `_item(...)` 列表里，只隔七行
（`lib/ui/transfer_actions.dart`）。一个按可达性扫描的 tree-shaker 不可能留一个丢一个。

**排除「这次压根没重编 app」**：

| 文件 | mtime |
| --- | --- |
| `lib/ui/transfer_actions.dart` | 20:00:12 |
| `pubspec.yaml`（脚本摸过） | 20:10:31 |
| `.dart_tool/flutter_build/<hash>/app.dill` | 20:11:07 |
| `build/.../Release/data/app.so` | 20:11:19 |
| `.dart_tool/flutter_build/<hash>/release_bundle_windows-x64_assets.stamp` | **19:14:07** |
| `build/.../Release/data/flutter_assets/fonts/MaterialIcons-Regular.otf` | **19:14:06** |

`app.dill` 重编了，里面确实有 `0xef7f`。跑图标 tree-shaker 的那一步
（`release_bundle_<platform>_assets`，即 `BundleWindowsAssets`）**根本没跑** ——
它的 stamp 比它该读的源码还老一个小时。构建成功、exit 0、面向用户的文案一条不少，
一个图标是空的。

**根因。** Flutter 的构建系统判「要不要重跑一个 target」靠的是**输入的内容哈希**，
不是修改时间。`build_system.dart` 的 `Node.computeChanges` 分支在
`fileStore.currentAssetKeys[absolutePath] != previousAssetKey` 上；mtime 一次都没出现。
打包脚本的失效步骤执行的是 `(Get-Item $pubspec).LastWriteTime = Get-Date`，
而它改动的字节**恰好是零个**。`BundleWindowsAssets.inputs` 里**确实**列了
`{PROJECT_DIR}/pubspec.yaml` —— 这正是那一摸看起来有理的原因 —— 但「列在输入里」
不等于「改得动缓存」。

删产物也不是把手：`BundleWindowsAssets.outputs` 是**空列表**，输出侧没有任何东西
可以让缓存发现「缺了」。输入侧 `build_system.dart` 把规则写得很直白：
*"If the stamp file is missing, the target's action is always rerun."*

## Decision

打包脚本不再摸 `pubspec.yaml`，改成**删掉那个 target 的 stamp 文件** —— 凡是
`.dart_tool/flutter_build/*/release_bundle_windows-x64_assets.stamp` 都删掉 ——
于是承载图标 tree-shaker 的那一步必定重跑。stamp 目录名是从构建配置推出来的哈希，
所以用通配而不是写死。**只删这一个** stamp；kernel snapshot 与 AOT 各有各的 stamp，
不受影响，代价因此是「重做一份字体」而不是「重编一个 app」。

顺带两处保险。构建前先删掉上一次产出的 `MaterialIcons-Regular.otf`；构建后断言
它回来了。这一条把「这步悄悄跳过」—— 也就是上面那个「绿色构建 + 坏界面」的失败模式
—— 变成它发生的那一刻的硬失败，而不是别人机器上一个空胶囊。

## Alternatives considered

**继续摸 `pubspec.yaml`。** 否：它就是 bug 本身。对内容哈希的缓存来说，时间戳的变化
不是输入的变化；而那句说它有用的注释会继续被人相信。

**把「删产物」当作失效机制。** 否，但保留为上面说的探针：`outputs` 是空的，
缺一个输出不是缓存会去看的东西。

**`flutter clean`，或者把 `.dart_tool/flutter_build/` 下所有 stamp 都删掉。**
否：本机 `flutter clean` 是静默 no-op（沙箱 safe-delete 拦批量删除，而它照样 exit 0，
还打印 `Failed to remove ...\build`）；全删 stamp 则会为了一个字体问题重跑
kernel snapshot 和 AOT 编译。删一个 stamp 更小，而且正对着出错的那一步。

**往 `pubspec.yaml` 追加一个字节让哈希变掉。** 否：它把「构建」变成「顺手改清单文件」
的副作用，而且下一次构建哈希又变回去，白让那一步再失效一轮。

**换一个已经在子集里的图标（`Icons.content_paste`，`0xe192`，在）。** 否：
那是拿修复去掩盖机制，下一个新图标还会同样失败。如果将来 Flutter 换了失效规则、
换到删 stamp 覆盖不到的方向，它仍是退路 —— 而新增的那条构建后断言正是用来发现这一点的。

## Consequences

- 包自己的字体守卫现在过在一份**确实是当前**的字体上：子集从 48 个码位变成 49 个
  —— 原来的那批，加一个 `0xef7f`；`$requiredGlyphs` 11 条全中。
- 重跑那一步的代价是重做一份子集字体，几秒钟，仅此而已：AOT 编译、kernel snapshot、
  原生链接都保留自己的 stamp，仍然是增量的。
- 将来 Flutter 若改了这一步的失效方式，会在脚本里**大声失败**，而不是安静地把
  空白图标发出去。
- 推理写在脚本里、就在那一步旁边 —— 因为上一版的错误推理也住在那里，而且足以撑过两轮使用。

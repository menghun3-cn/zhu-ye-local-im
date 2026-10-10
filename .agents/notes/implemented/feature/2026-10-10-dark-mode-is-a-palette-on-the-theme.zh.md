# Agent Note: 深色模式是主题上的一层调色板

Status: implemented

## Problem

设计稿签下来的时候，刻意留了一屏没做完。它的 `[data-theme="dark"]` 块已经写好、设计系统页
也能切过去，但稿子自己的 README 就是这么说的：深色令牌写了、没逐屏走过查，而 Flutter 端的
深色排在样板定稿之后（`design-preview/README.md`）。换皮与布局两轮都已经落地，所以这就是那
一项 —— 三连的最后一个。

障碍从来不是那些值。稿子已经把每一个深色令牌都给了，而且深色令牌和浅色令牌是同一批**角色**：
一块面板、一块板、一条发丝线、一种字色。障碍是：这个代码库里的「一个颜色」不是一个角色。它是
`WeChat` 上的一个 `static const`，按名字在十个文件、几十个调用点上被读出来。

一个叫 `WeChat.surface` 的颜色，是一个关于**浅色**的事实。说出这个名字的 widget，无论调色板
多想让它深色，它都渲染不到深纸上 —— 因为它根本不是在问某个调色板，它是在点一个值。深色模式
需要的，是让问题变成「读的人在哪张纸上」，并且让这个问题在每一个 widget 本来就提问的地方被
回答。

设计自己的规矩定死了答案的形状。深色块「只覆盖语义令牌，组件代码一行不动」。一块需要每个
widget 自己去分支的调色板，不是这个意思。

## Decision

**颜色是一个 `ThemeExtension`，而且有两个。** `WeChatColors` 是一个 `@immutable` 扩展，装着
设计点名的每一个颜色角色 —— 从 `brand` 到 `inversePrimary` 共三十个 —— 再加上它所属的
`Brightness`。`WeChatColors.light` 是稿子画在里面的那套；`WeChatColors.dark` 是把稿子
`[data-theme="dark"]` 块里的同批角色一个值一个值读出来的。widget 问
`WeChatColors.of(context)`，那是对 `Theme.of(context)` 的一次查表 —— 也就是每一个 widget
本来就在用的那个机制。

**`WeChat.theme` 收一个调色板，`MaterialApp` 收两套主题。** `theme()` 现在的签名读作
`theme(WeChatColors colors)`，把入参经 `extensions: [colors]` 盖到 `ThemeData` 上。
`app.dart` 传 `theme: WeChat.theme(WeChatColors.light)`、
`darkTheme: WeChat.theme(WeChatColors.dark)`、`themeMode: ThemeMode.system`，正在跑的应用
与那个失败屏两处都传。`ColorScheme` 仍然由调色板建出来 —— 按调色板自己的 brightness 选
`ColorScheme.light(...)` 或 `ColorScheme.dark(...)` —— 所以 Material 的构造函数只决定这里没
点名的那些槽位。

**尺寸、圆角、字阶不动，于是它们留在原地。** 它们仍是 `WeChat` 上的 `static const`。换调色板
是换一张纸；一个十四像素的圆角不是。

**深色模式跟随操作系统，而且不被写下来。** 没有设置项、没有 UI 里的 `ThemeMode` 开关、设备
档案里没有新字段。`ThemeMode.system` 就是全部的选择。

**识别绿永远不压白字 —— 而深色模式正是这件事显形的地方。** 接调色板时翻出三处早就跟设计不
一致的地方，三处是同一个错：把一个填充色当成了按钮。

- 输入区的发送按钮、气泡里那个实心动作，都是 `brand`（`#07C160`）配白标签 —— 正好是换皮那轮
  拆出 `brandStrong`/`onBrand` 要避免的那个 2.4:1 配对。它们现在是 `brandStrong` 配调色板的
  `onBrandStrong` —— 浅色下深绿压白、深色下亮绿压近黑，正是换皮那篇笔记预言的那次翻转。
- 会话列表行的「连接」动作是 `brand`；稿子的 `.rowact--primary` 是 `--brand-strong`。现在它
  是 `brandStrong`。
- 两条进度条的轨道都是 `Colors.black12`，在深色气泡上等于看不见。它们是 `surfaceSunken` ——
  也就是稿子的 `--surface-3`，一个槽位同时管进度条轨道和控件的凹陷底。

## Alternatives considered

**在每个调用点分支 `Theme.of(context).brightness`。** 拒绝：那正好是设计规矩的反面。每个
widget 会各自决定「面板」在深纸上是什么，而第一个决定得不一样的，就是一页画在两种主题里的
页面。

**把浅色调色板反相，推出深色的。** 拒绝：反相会把品牌绿放到近黑上，在某个亮度上发颤，并且
让抬起来的那块面板比它下面的页面**更暗**。换主题时必须活下来的是那个**关系** —— 面板在页面
之上、侧栏夹在两者之间、收到的气泡比它所在的板子亮 —— 而反相把它整个翻过来。深色那些值是
稿子的，是作为值挑出来的。

**保留 `static const` 颜色，在旁边另加一套 `WeChatColors`。** 拒绝：同一个颜色有两个真源。
在任何一个没被迁移的 widget 上，静态那个会赢，于是深色模式在有人记得的地方生效、在没人看的
地方失效 —— 这是最糟的失效方式，因为它看起来是好的。

**让用户自己选主题。** 推迟，不是拒绝：设计只有两套调色板，运行时不派生第三套，而一个设置项
意味着一个被持久化的偏好和一次设备档案格式的改动 —— 设计从没要过。在有人开口要更多之前，
跟随系统是诚实的默认。

**在同一个 PR 里把 `WeChat` 和 `lib/ui/wechat/` 改名。** 推迟，和换皮那篇一样：仍然是一个跨
所有调用点的杂活，仍然不是这个 PR。

## Consequences

**颜色现在是一次 `BuildContext` 查表，于是三件事跟着来了。** 一个点了颜色的 `const
TextStyle` 不得不丢掉 `const`，因为一次查表不是常量表达式。一个拿不到 context 的私有 getter
—— 消息气泡的字色 —— 变成了一个收调色板的普通方法，而调色板从气泡的 `build` 穿过两个画它内
容的辅助函数被递下去。还有那个画进度轨道的辅助函数，需要它本来就有的那个 context，于是它像
其它一切一样去问调色板。

**浅色模式下除了那三处修正，什么都不变。** 浅色调色板就是原来那些值，所以换皮的结果没有变
—— 这正是这个 PR 能以 diff 而不是以截图来评审的原因。发送按钮、连接的那个点、两条进度条轨道
在浅色下确实变了，因为它们在浅色下本来就是错的；每一处都是挪到设计本来就有的令牌上。

**深色调色板没有逐屏走过查，而本 PR 改不了这一点。** 稿子自己就是这么说的：令牌在了、切换器
能用了、没有人把每一页都看过。本 PR 能说的是测试钉住的那几个关系 —— 板子比页面亮、收到的气泡
比板子亮、侧栏夹在两者之间、亮绿上的字是深色。某一页看起来**对不对**，仍然是前后截图对比的
事，而深色模式现在已经被加进那次对比里了。

**一组测试被重写，一组被新增。** `shell_test.dart` 里关于主题的那些断言现在读
`WeChatColors.light.*`，另外新增的 `the dark palette` 组钉住上面那几个关系、钉住
`WeChat.theme(WeChatColors.dark)` 盖出的是深色 `ColorScheme`、钉住
`WeChatColors.of(context)` 会解析到正在跑的那套主题，还钉住 `lerp` 在中点翻转 brightness
而不是突变。

**调色板只能经主题拿到，而一个裸的测试不是主题。** `WeChatColors.of` 回退到 `light` 而不是
抛异常，于是在一个裸 `MaterialApp` 下被 pump 起来的 widget —— 测试里的一个对话框、应用树
之外的一个 paint 回调 —— 渲染浅色页面而不是崩掉。应用永远会装上两者之一，所以这个回退从不是
一个正在跑的窗口会显示的东西。

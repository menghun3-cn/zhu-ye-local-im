# Agent Note: 截图窗口探测只在 Windows 上运行

Status: implemented

[English](2026-11-06-screenshot-window-probe-is-windows-only.md) | 中文

## Problem

v0.1.36 随 Windows 截图工具套件一起发布，而 `main` 开头无条件执行
`await ScreenshotWindowArgs.current()`。这个调用最终走到
`desktop_multi_window` 的 `WindowController.fromCurrentEngine()`，向
`mixin.one/desktop_multi_window` 通道请求 `getWindowDefinition`。该插件没有
Android 实现，于是在 Android 上 await 抛出 `MissingPluginException`——发生在
`runApp` 之前，也在把 seams 故障转成 `StartupFailureApp` 的那个 `try` 之外。
进程活着但什么都没画：整个应用打开后是一片空白。Windows 不受影响，因为它的
runner 确实实现了这个通道。

## Decision

`main` 只在 `currentPlatform() == DevicePlatform.windows` 时才发起这个询问
——那是唯一能孵化出这些窗口参数所属的额外引擎的 platform。这个比较是明写的，
而不是从「插件可能不存在」反推出来的，理由与 `controlsWindow` 相同：新增一个
platform 是一项必须在旁边写明理由的决定。截图功能其余所有入口——
`ScreenshotService.open`、设置项——本来就已经在
`_LocalTransferAppState` 里用同一个比较挡住了，所以这是唯一没设防的调用点。

## Testing

`main` 无法从测试到达——它要绑定发现端口并调用 `runApp`——因此没有自动化
测试锁定这个守卫；检查就是一个 `currentPlatform()` 比较，对照它保护的调用
人工复核。它修复的回归发生在 platform 层（一个没有实现的通道），Windows
主机上的 `dart test` 套件本来也复现不了：证明就是 Android 包打开后看到的是
应用而不是空白。

## Alternatives considered

**在 `ScreenshotWindowArgs.current()` 内部捕获
`MissingPluginException`。** 否：作为唯一修复，它会让这个函数在每一个无法承载
该功能的平台上静默回答「没有窗口」，掩盖了「这个问题根本不该被问」的事实。
platform 门写明了答案为何为 null；吞掉异常只说明这次碰巧为 null。

**把检查放进 `current()` 写成 `Platform.isWindows`。** 否：`Platform.is*`
回答的是宿主，而不是本项目的 platform 词汇表——`DevicePlatform` 才是启动路径
其余部分比较的对象，第二套同义方言正是两者漂移的方式。

**给插件补一个 Android 空实现。** 否：Android 侧没有可实现的东西——该功能按
设计就是 Windows 独有，一个只为让本不该发生的调用返回点什么而存在的桩通道
没有意义。

## Consequences

- Android 恢复为打开应用；截图代码在那里根本不会被触碰，与
  `_openScreenshots` 早已对服务做的门控一致。
- 未来新增的 `DevicePlatform` 默认得到 `windowArgs == null`——安全的答案——
  直到有人决定它能承载该功能并在比较处写明。
- Windows 多窗口流程不变：主引擎的参数仍为空，解码为 null，应用照常继续。

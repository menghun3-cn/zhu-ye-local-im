# Agent Note: 仅 Windows 的 Snipaste 式截图工具集

Status: implemented

[English](2026-11-20-windows-screenshot-tools.md) | 中文

## Problem

文件与剪贴板传输应用的用户经常需要截取屏幕上的内容——一个错误对话框、一张图表、一条想贴到别处的消息。Snipaste 是参照行为：全局快捷键唤出全屏暗色遮罩，拖动框选区域（或选窗口、或全屏），图片进入剪贴板，可以钉在其他窗口之上或添加标注。此前应用里完全没有这些能力；剪贴板只有文本、文件和已配对设备间的镜像条目。

需求刻意按 Snipaste 的形状提出，而不是「加一个截图按钮」：钉图窗口要跨重启持久存在、要有悬浮历史、要有标注编辑器、要有可自定义的全局快捷键，并且全部由一个**默认关闭**的开关把守——因为能截屏的全局快捷键是这个应用能做的最具侵入性的事。

## Decision

该功能仅限 Windows，由四个部分组成，每个部分在 `desktop_multi_window` 的独立 Flutter 引擎中运行：

* **截图遮罩**——一个覆盖虚拟屏幕（`GetSystemMetrics(SM_*VIRTUALSCREEN)`）的窗口，始终置顶。区域拖框、窗口模式（`EnumWindows` + `WindowFromPoint` + `PrintWindow`，能截取被遮挡的窗口）和全屏模式，可在工具栏中切换。完成时把 PNG 以 `CF_DIB` 写入剪贴板——由 Win32 手写，因为 Flutter 的 `Clipboard` 只带文本——并追加进历史。
* **历史**——`ScreenshotLibrary`（索引 JSON + 每条目一个 PNG，上限 20 条），在悬浮网格窗口中展示，可从遮罩、「我的 → 截图」卡片和既有原生 `HostShell` 新增的托盘菜单项进入。
* **钉图**——`PinStore` 保存 `PinRecord`（位置、尺寸、置顶、鼠标穿透），启动时恢复为无边框置顶窗口。鼠标穿透是 `WS_EX_TRANSPARENT | WS_EX_LAYERED` 加上固定不透明 alpha，通过唯一窗口标题 → `EnumWindows` 查找来设置——因为所有钉图引擎共享同一进程 id，而 `desktop_multi_window` 的 windowId 是 UUID 而非 HWND。
* **标注编辑器**——箭头、矩形、自由画笔、文字和序号标记叠加在图片上；点「完成」时把笔画经 `ui.PictureRecorder` 重放并把 PNG 原地重写，因此历史条目或钉图仍是同一个文件。

开关和快捷键存在 `DeviceProfile`（`screenshotEnabled`、`screenshotHotkey`，默认 `ctrl+shift+a`——刻意避开 QQ 和微信已在全局占用的 `Ctrl+Alt` 系组合）。主引擎里的 `ScreenshotService` 通过 `hotkey_manager` 对齐注册，并把开关状态经既有宿主通道推给托盘菜单；关闭即注销快捷键、隐藏入口，但钉图和历史保留——它们是用户的图片。

UIA 控件边界吸附明确延后：没有插件提供该能力，v1 只做常规参考线选择。

## Consequences

* 该功能新增五个运行时依赖（`desktop_multi_window`、`window_manager`、`hotkey_manager`、`win32`、`image`，另显式声明 `ffi`）和少量手写 Win32。GDI 与剪贴板代码是最可能在特殊环境下需要关注的部分——多显示器负原点已处理，混合 DPI 以遮罩窗口自身的 DPI 近似。
* 钉图在功能开启时每次启动都会恢复；想去掉的用户逐个关闭钉图即可，关闭会删除其记录。
* 快捷键字符串是 profile 数据，因此旧版本读取新版本写下的 profile 时会回退到默认值——宽容解析是刻意的。
* Android 完全不受影响：「我的」卡片、服务和托盘入口都位于 `DevicePlatform.windows` 判断之后。

## Alternatives considered

**用 `screen_capturer` / `flutter_screen_capture` 取像素。** 核心路径否决：它们自带遮罩或基于文件的流程，无法驱动 Snipaste 式交互（同一遮罩内切换模式、窗口跟随高亮、被遮挡窗口的 `PrintWindow`）。`win_desktop.dart` 里的 GDI 路径约 150 行，恰好够用。

**用 `tray_manager` 做历史入口。** 否决：应用已有原生通知区图标（`host_shell.cpp`）和手写菜单；第二个托盘图标是重复。只加一个菜单项和一个通道方法（`setScreenshotEnabled`、`screenshotHistory`）扩展了既有外壳。

**`window_manager` 0.6.x / `hotkey_manager` 0.3.x。** 刻意回退：两个最新版都只有几天历史，且 0.6.x 把 window_manager 重写到 `nativeapi` 上，本功能用不到。0.5.2 / 0.2.3 是插件示例所针对的版本。

**在引擎间传字节传图片。** 否决：每个窗口从其 `WindowConfiguration` 参数里指明的库/钉图目录自行读取 PNG——这也让钉图恢复和编辑器重开走同一条路径，并把大位图完全挡在参数通道之外。

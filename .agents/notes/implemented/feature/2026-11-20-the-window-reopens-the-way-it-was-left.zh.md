# Agent Note: 窗口按上次的状态重新打开

Status: implemented

## Problem

主窗口每次都以创建时的尺寸打开，用户上次把它留在什么状态完全不被记住。
习惯最大化使用的人，每次启动、每次更新之后都得重新最大化——更新交接
会重启进程，所以「下次」也包括「刚更新完」。窗口化的情形是同一个问题
的缩影：两种状态都没有记录，用户拖标题栏做出的选择就这样被丢掉了。

## Decision

`HostShell`——本就持有 Dart 够不到的窗口事实（托盘图标、自启动项）——
现在也持有最大化这一位。它存为 `HKCU\Software\cn.hnasct.local_transfer`
下的 `WindowMaximized`（REG_DWORD），在 `Attach` 时读一次，由
`set_maximized` 在值真正变化时才写回。之所以用注册表而不是 profile 文
件，是因为窗口在 `main.cpp`/`FlutterWindow::OnCreate` 里创建，那时 Dart
还没有打开任何接缝；原生侧必须自己回答。

`FlutterWindow::OnCreate` 在窗口仍不可见时询问
`host_shell_.maximized()`，为真则调用 `Win32Window::SetShowMaximized()`，
让第一次 `Show()`——仍推迟到首帧——用 `SW_MAXIMIZE` 而不是
`SW_SHOWNORMAL` 呈现窗口。对已最大化的窗口用 `SW_SHOWNORMAL` 会把它还
原，所以这个决定必须落在 show 命令上，而不是更早的 `ShowWindow` 调用。

`WM_SIZE` 是写入方：`SIZE_MAXIMIZED` 与 `SIZE_RESTORED` 都记录
`IsZoomed(hwnd)`，而 `SIZE_MINIMIZED` 被忽略——最小化的窗口底下仍是最
大化的，最小化期间问 `IsZoomed` 会错误地清掉这一位。问 `IsZoomed` 而
不是只信 `wparam`，是为了让托盘隐藏再恢复这类场景下记录的仍是真实状
态——光看尺寸码说不清窗口是什么。

只保留最大化这一位，是有意的：被记住的窗口化矩形在硬件变动后可能落在
屏幕外或已断开的显示器上，所以非最大化启动永远使用创建时的 1280×720
几何。

## Alternatives considered

**用 `window_manager` 的 `setBounds`/`getBounds` 做持久化。** 否：该插
件已是截图窗口的依赖，但主窗口是手写的 `Win32Window`，在任何 Dart 运
行之前就显示了，而 `window_manager` 是 Dart 侧 API——状态照样要跨同一
条原生/Dart 边界，只不过中间多了个插件。runner 已经为自启动读写
`HKCU`，旁边再加一个值是更小的机制。

**把位置和尺寸和最大化位一起持久化。** 暂不：那是更完整的答案，但它会
拖进显示器 DPI 与断开显示器的边界情况，而最大化位没有这些问题；需求
本来就只是「最大化保持最大化，窗口化保持窗口化」。创建尺寸仍是窗口化
时的几何。

**把这一位存在 profile 文件里，再用方法通道推下去。** 否：窗口在
profile 存储存在之前就显示了，Dart 永远慢一帧——窗口会先以错误状态闪
一下再跳变。原生读取必须发生在窗口创建的地方。

## Consequences

- 最大化的窗口在正常启动、托盘退出后、以及更新交接之后都会以最大化重
  新打开——注册表按用户而非按安装路径存放，移动或更新可执行文件都保
  留它。
- 最大化恢复的第一条 `WM_SIZE` 不会重写该值：`Attach` 在任何尺寸消息
  到达前先从注册表给 `maximized_` 赋值，而 `set_maximized` 只在变化时
  写。
- 状态按 Windows 用户而非按 Device 档案存放——与自启动项已做的选择一
  致，对窗口矩形来说也是正确的范围。
- `windows/runner` 是 Dart 测试套件够不到的 C++；该行为靠构建 runner 并
  手工跨重启验证最大化/还原，而不是靠自动化测试。

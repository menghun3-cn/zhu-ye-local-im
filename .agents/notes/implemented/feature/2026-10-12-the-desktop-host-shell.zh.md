# Agent Note: 桌面宿主层：单实例、托盘，以及一个有含义的关闭按钮

Status: implemented

## Problem

这个程序以桌面窗口的形态发布，行为却像一个浏览器里的页面。缺的是四件事，而没有一件是 Dart 能问得出
来的：语言里没有窗口句柄，没有通知区域，也没有注册表。

**第二次启动就是第二个程序。** 一台机器上两个窗口就是两台拥有两套身份的设备，设备页上什么都是两
份，同一个文件会到达两次。

**关闭按钮永远结束进程。** 对于一个全部意义就在于从网络上接收东西的程序，这是错误的默认值。关掉窗口
是使用者不去看它的方式，不是使用者不再可被触达的方式。

**没有办法开机自启**，于是一台本该随时可被触达的设备，每次重启之后都得手动启动。

**设置里改不了上面任何一条** —— 而 Android 既没有通知区域、也没有自己的关闭按钮，绝不能给它摆出两个
背后什么都没有的行。

最后一点还有一半容易被忽略，而它决定了这次的实现方式：门禁根本不编译 `windows/**`。
`analysis_options.yaml` 把它排除在外，`dart format` 不读 C++，也没有任何测试套件会构建它。runner 做了
什么，只由「把它编译出来」这一件事来验证，除此之外没有别的。

## Decision

一个 `HostShell` —— 纯 Win32，里面没有 Flutter —— 位于
`windows/runner/host_shell.{h,cpp}`，由两处驱动：窗口的消息处理器，以及一条名为
`cn.hnasct.local_transfer/host` 的 method channel。

**单实例是一个具名互斥量，在还没有窗口的时候就取。** `wWinMain` 在 COM 初始化之前、在任何窗口存在
之前调用 `HostShell::AcquireSingleInstance()`。名字用的是 `Local\` 命名空间，所以在另一个登录会话
里 —— 或者另一个使用者 —— 运行这个程序，是第二个、完全正当的实例。当互斥量已被占用时，新进程找到
持有它的那个窗口，为该窗口的属主调用 `AllowSetForegroundWindow`，投递一条注册消息，然后退出，自己
从不创建窗口。`AllowSetForegroundWindow` 不是装饰：没有它，Windows 会把窗口提到使用者刚才点击的
那个窗口*后面*，读起来就是「第二次启动什么也没发生」。

**runner 的窗口类不再是 Flutter 的默认值。** 原本是 `FLUTTER_RUNNER_WIN32_WINDOW`，一个所有 Flutter
Windows 程序共用的名字。第二次启动若按这个名字去找窗口，有可能把某个毫不相干的程序的窗口提起来，
然后自己静默退出。现在它是 `cn.hnasct.local_transfer.window`，在 `win32_window.h` 里以
`kWin32WindowClassName` 声明，使窗口本身和这次交接不会各走各的。

**关闭按钮有一个被存下来的含义。** `CloseBehaviour` —— `quit` 或 `tray` —— 与其他使用者设置一起
放在 profile 里，默认是 `tray`：`WM_CLOSE` 把窗口藏起来，进程继续运行，因此仍然能接收。Dart 把
这个选择推给宿主两次：一次是在设备启动时、在任何更慢的事情发生之前，一次是在使用者改动它的时候。

**通知区域图标是在窗口第一次被藏起来时加上的，也只在那时加。** 一个被打开来发一个文件的程序，不会
在身后留下一个常驻图标。`WM_CLOSE` 被吞掉**仅当图标加得上**：一个藏起来又回不去的窗口，就是一个
使用者够不着的进程，而 `Shell_NotifyIcon` 失败是实实在在可能发生的事，不是理论上的。图标会在 shell
广播 `TaskbarCreated` 时补回来，那是 Windows 一次把所有图标全部丢掉的唯一时刻。

**开机自启是读出来的，从不记下来。** 条目是
`HKCU\Software\Microsoft\Windows\CurrentVersion\Run\LocalTransfer`，内容为正在运行的可执行文件的
路径，带引号 —— 因为这条目是当作命令行来启动的，而路径里常有空格。Dart 这一侧不缓存关于它的任何东
西：`autostartEnabled` 去问注册表，`setAutostart` 在写完*之后*把答案读回来。因此一次失败的写入，和
一个亲手删掉条目的使用者，两者都会表现为「实际会发生什么」，而不是「被要求了什么」。

## 哪些由 Dart 决定，哪些由宿主决定

`PlatformSeams` 携带两个彼此独立的事实，而且它们是有意分开的。

`hostShell` 在任何平台上都始终存在。它持有 `HostShell` 的实现，而一个没有实现该 channel 的平台会
回答 `MissingPluginException`，`PlatformHostShell` 把它变成「什么也没发生」。因为一个托盘图标不可用
就画不出来的设置页，比一个安静地什么也不做的开关更糟。

`controlsWindow` 是一个普通的 bool，只在 Windows 上为真。设置页正是按它决定要不要画出这一组 —— 是
缺失，而不是禁用，因为一份列出「这个平台做不到什么」的界面，读起来就是坏的。它是同步的，在等待任何
东西之前就已经知道，这就是它不由「去问 `hostShell`」推导出来的原因：那会把一次 await 塞进页面的构
建过程，并让「这一行是否提供」取决于平台此刻是否答应。

## Testing

`test/profile/device_profile_test.dart` 覆盖这个 profile 字段：默认值、往返、两个 wire 名字，以及
那份宽容解码 —— 它让来自更新版本的取值读成默认值，而不是让旧版本失败。

`test_flutter/ui/window_settings_test.dart` 用 `ScriptedHostShell` 覆盖设置页：`controlsWindow` 为
假时这一组不存在；关闭方式的选择同时到达正在运行的窗口和存下来的 profile；一个已经开机自启的宿主，
开关显示为开，而*没有*问过它任何东西；一次没生效的写入，让开关留在关而不是开。

runner 本身没有测试。它由「被编译出来」来验证 ——
`cmake --build build/windows/x64 --config Release --target local_transfer` —— 这是本项目里唯一会编译
`windows/**` 的命令。

## Alternatives considered

**用一个 pub 插件。** `launch_at_startup`、`tray_manager`、`window_manager` 以及若干个单实例包，合起
来足以覆盖这四种行为。它们输给了本项目的一项既有决定：这个程序不引入任何插件，好让它依赖的每一个
平台事实都写在这个仓库里、都能被读到。四个包会带来四个维护者、四套平台通道接口，和一棵传递依赖相当
大的依赖图，换来的却是大约三百行 Win32 就能回答的问题 —— 而本项目确实拥有的两条 channel，
`.../host` 与 `.../paths`，本来就是它自己的。

**每个事实一条 channel。** 三条 channel，分别是关闭行为、自启的读与自启的写。否决：它们都由同一个
窗口回答，runner 的处理器会退化成一张每项只有一条的查表。

**从 `hostShell` 是否答应来推导 `controlsWindow`。** 否决：那会让一个同步就知道的问题 —— 这个构建能
不能改变自己的窗口 —— 取决于一次需要等待的平台调用，也会让一个页面的形状取决于平台此刻是否可达。

**把自启状态记在 profile 里。** 否决：那是操作系统所拥有事实的第二份副本。两者可能不一致，而错的会
是副本那一份。

**`SetQuitOnClose(false)`，让关闭永远不结束任何东西。** 否决：退出必须继续可用，而
`quit_on_close_` 正是结束消息循环的东西。它现在仍然是 `true`。托盘这条路径是*把窗口藏起来*而不是关
掉它，所以当使用者确实想退出时 —— 包括从通知区域的菜单里 —— `WM_DESTROY` 与 `PostQuitMessage`
依然按平常的方式发生；那条菜单发出的就是一条普通的 `WM_CLOSE`，只是标志位已经翻过去了。

**从启动起就显示图标。** 否决：那会在一个使用者可能只是打开来发一个文件的程序身后，留下一个常驻的
通知区域条目。

## Consequences

**换来的。** 程序可以在屏幕上没有窗口的情况下继续运行并接收东西；两次启动就是一个窗口；开机自启是
一个会说真话的开关，汇报的是操作系统实际会做什么；关闭方式的选择能活过一次重启，因为它是 profile
字段而不是窗口状态。

**runner 在所有门禁之外。** `analysis_options.yaml` 排除了 `windows/**`，也没有测试套件会构建它，
所以那里的错误只会被「把它编译出来」抓到，除此之外没有别的。`windows/runner` 下每一份源码也都是纯
ASCII 加 `\uXXXX` 转义：在 936 代码页下，runner 源码里的一个非 ASCII 字节就是 C4819，而本项目的
`/WX` 把它升级成硬错误。

**已知缺口。** 通知区域菜单的两条文字 —— 显示主窗口、退出 —— 是宿主自己写下的转义字面量，而不是本
地化字符串，因为菜单由 runner 构建，为了两个词去够 Dart 就意味着引擎忙的时候菜单画不出来。
`HKCU\...\Explorer\StartupApproved\Run` 没有被查阅，所以使用者从任务管理器里禁用的条目仍然读作开；
把开关关掉再打开会重写它。另外只有 Windows 实现了这条 channel —— `controlsWindow` 的存在，正是为了
让其他平台不必假装自己也能。

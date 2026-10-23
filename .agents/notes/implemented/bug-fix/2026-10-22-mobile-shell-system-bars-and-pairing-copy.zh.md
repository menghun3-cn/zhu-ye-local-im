# Agent Note: 让移动端外壳避开系统栏并说清配对边界

Status: implemented

[English](2026-10-22-mobile-shell-system-bars-and-pairing-copy.md) | 中文

> **部分被取代**：
> [发现设备后自动连接](2026-10-23-discovery-connects-automatically.zh.md)
> —— `SafeArea` 的决定仍保留，但监听状态现在报告自动连接是否就绪，不再使用旧的
> 配对边界文案。

## Problem

主页外壳刻意没有 `AppBar`，但它的 `Scaffold.body` 绘制页面时没有顶部
`SafeArea`。因此在 Android 的窄屏会话布局里，紧凑的返回按钮距离窗口顶部只有
8 个逻辑像素，大部分点击目标被状态栏盖住，点击也可能被系统栏截走。用户进入
会话后可能无法返回。

同一页面还会对所有没有 Session 监听端口的设备显示 `监听：不接受连接`。设备尚未
配对时，Discovery 与配对监听本来仍然可用；接受 Session 则正确地需要配对产生的
群密钥。旧文案把这条认证边界压缩成一句让整个网络页面看起来坏掉的话。配对后若
监听真的失败，又需要与「尚未配对」不同的答案。

## Decision

外壳用 `SafeArea(bottom: false)` 包住 body。顶部与侧边的系统留白因此作用于所有
页面，因为外壳是始终包围它们的那个 widget。`bottom: false` 避免在
`NavigationBar` 上方重复增加底部留白，因为它已经处理底部系统区域；输入区也自己
拥有底部 `SafeArea`。

监听事实现在区分三种状态：

* 已有 Session 端口时显示 `onPort(port)`；
* 未配对设备显示 `sessionsNeedPairing`，中文为 `配对后接受连接`；
* 已配对但没有 Session 端口时显示 `notAcceptingSessions`，保留监听启动失败时
  如实报告的状态。

这是文案与布局修复，不是放松认证。未配对设备仍会应答配对请求，但在没有群密钥时
不会接受 Session。

## Alternatives considered

**只在 `ConversationsPage._PaneHeader` 上补留白。** 否决：外壳下的设备、传输、
剪贴板、设置和关于页面同样没有 `AppBar`；只修一个头部会留下同类缺陷，并诱使
别处再复制一份留白规则。

**在外壳上方恢复 `AppBar`。** 否决：外壳移除这条栏是有意为之，窗口标题栏已经
承载应用名，设备名属于设备页面。空 `AppBar` 只会用无信息的装饰来占空间。

**让未配对设备接受 Session。** 否决：群密钥是消息与剪贴板内容的认证边界。去掉
它会让局域网发现或地址本身成为足够的授权。

**两种原因都继续显示泛化的「不接受连接」。** 否决：它会对未配对用户说应用坏了，
而实际下一步是配对；同时掩盖已配对设备监听绑定失败这一不同状态。

## Consequences

Android 上所有外壳页面现在都从状态栏下方开始，包括窄屏会话头部与返回按钮。
底部留白仍由导航栏和输入区负责，因此不会在它们上方多出一条空白带。

设备页与设置页现在会说明没有 Session 监听的原因。用户仍可在未配对状态发现对端并
完成配对；配对后，监听事实会变成真实端口。

Widget 套件会向窄屏窗口注入 28 像素顶部留白，打开已配对会话，断言返回按钮从留白
下方开始，并点击它返回列表。设备页测试钉住未配对文案。

## Testing

`test_flutter/ui/shell_test.dart` 覆盖窄屏状态栏留白与返回导航。
`test_flutter/ui/pages_test.dart` 覆盖未配对监听文案；既有配对路径仍断言真实端口。

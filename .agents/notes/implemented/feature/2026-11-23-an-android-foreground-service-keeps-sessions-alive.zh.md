# Agent Note: Android 前台服务让 Session 在后台保持存活

Status: implemented

## Problem

Android 上整个产品——UDP 广播监听、TCP Session、Dart 定时器——都活在
应用进程里，而 Android 会冻结或回收退到后台的进程。于是切换到其他应用
就让本机离线：发现停止广播、对端的 keep-alive 超时、App 看起来像死了，
直到重新打开。广播发现那篇笔记早已把这个问题列为待决的 Android 层决
策（「发现是否只在前台运行」），后台约束文档也记录了 `dataSync` 的时
间预算，却一直没有落地的答案。

## Decision

`LocalTransferForegroundService`（手写 Kotlin，不引插件）由
`MainActivity.onCreate` 经 `startForegroundService` 启动，并以
`FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE` 类型调用
`ServiceCompat.startForeground`。服务本身什么都不做；它唯一的职责是
让进程保持前台优先级，使其中的 socket 与定时器在用户待在其他应用时
继续运行。一条常驻的 `IMPORTANCE_LOW` 通知（「正在局域网中保持在线」）
向用户解释这个常驻任务，点按通知会回到应用。

- 服务是 `START_NOT_STICKY`，并在 `onTaskRemoved` 里自行停止：用户从
  最近任务划掉是明确的「下线」动作；被重启的服务会在没有 Flutter 引擎、
  socket 全死的情况下回来——那是一条说谎的通知。
- 选 `connectedDevice` 而非 `dataSync`：Android 15+ 给 `dataSync` 设了
  每 24 小时 6 小时的预算，常驻应用会撞墙；`connectedDevice` 没有这种
  超时。Android 14+ 要求 connectedDevice 服务持有固定权限集合中的一
  项，所以 manifest 声明 `CHANGE_WIFI_MULTICAST_STATE`——这是诚实的
  选择：局域网发现本就是广播/组播相邻的，而且将来 MulticastLock 也要
  同一个权限。
- Android 13+ 在授予 `POST_NOTIFICATIONS` 之前隐藏前台服务通知；
  `MainActivity.onResume` 只问一次（用 SharedPreferences 记标记），因
  为没有它服务照样运行——只是通知栏里看不到；而从没见过通知的用户无
  法知道应用是故意保持在线的。
- Dart 侧改动：无。服务只保住进程，网络栈原样不动。

## Alternatives considered

**`dataSync` 前台服务类型。** 语义最贴合（同步/传输），但 Android 15+
把它限制在每 24 小时 6 小时并会调用 `onTimeout`——不适合常驻应用。
否决。

**`specialUse` 类型。** 没有时间预算，但需要在 manifest 里声明用途属
性、审核口径模糊；`connectedDevice` 对「与局域网对端保持连接」的语义
更干净。否决。

**插件（`flutter_foreground_task` 一类）。** 成熟且功能全，但会破坏项
目「零插件、核心纯 Dart 可无头测试」的约束，只用到它 5% 的能力。否
决。

**只加 WakeLock/WifiLock。** 能让 CPU 保持唤醒，但进程仍可能被冻结或
被杀，单独用收益有限。息屏（doze）保活是另一项独立决策，本次不做。
否决。

## Consequences

- 切换应用不再让设备离线；代价是通知栏常驻一条通知，它如实说明应用
  在做什么。
- 应用新增四个 manifest 权限（`FOREGROUND_SERVICE`、
  `FOREGROUND_SERVICE_CONNECTED_DEVICE`、`POST_NOTIFICATIONS`、
  `CHANGE_WIFI_MULTICAST_STATE`），全是普通或运行时授权型，不暴露新数
  据。
- 息屏 doze 仍可能让 socket 停摆——本次只覆盖「切应用」场景。若实测
  出现息屏断线，下一步是 partial wake lock，届时单独决策。
- 代价是前台服务的基线耗电：进程保持可运行，这正是产品作为对端常驻
  所必须的。
- 验证：`flutter analyze`、`dart format`、`dart test` 及 Agent Note/
  翻译配对门禁全绿；Kotlin 侧随正常 Android 构建编译。真机验证（切应
  用→对端保持在线；划掉→离线）记录为手工检查，不做自动化。

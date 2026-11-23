# Android 前台服务常驻设计（短设计）

日期：2026-11-23
状态：待批准

## 意图与原因

Android 端目前切到其他应用后进程被冻结/被杀，UDP 广播监听、TCP Session、
Dart 定时器全部停摆，对端把本机标记为离线。这是平台行为，不是代码 bug。
目标是让 App 在「切应用」场景下保持在线，同时**不引入任何 Flutter 插件**，
保持核心层纯 Dart、平台事实走 MethodChannel 的既有模式。

## 目标 / 非目标 / 反目标

- 目标：App 启动后常驻，切到其他应用、锁屏息屏前的任意时刻保持在线；
  用户从最近任务划掉 App 后恢复离线（显式退出 = 主动下线）。
- 非目标：息屏（doze）后的深睡保活——那需要 WakeLock/WifiLock，耗电高，
  本次不做；Android 17 的 `ACCESS_LOCAL_NETWORK` 权限请求是另一件事；
  不做「设置开关」，启动即常驻。
- 反目标：进程被系统杀死后服务自己复活——START_STICKY 重启的服务里没有
  Flutter engine，socket 已死，复活只会留一个无用通知。所以服务必须是
  「陪着进程活」，不是「独立于进程活」。

## 约束

- 零插件：全部手写 Kotlin + manifest + 通知，不新增 pub 依赖。
- targetSdk 跟随 Flutter 当前稳定版（约 API 36）：Android 15+ 的
  `dataSync` 前台服务有 6 小时/24 小时预算，超时被系统降级。
  因此服务类型选 `connectedDevice`——语义是「与外部设备持续通信」，
  与本产品「和局域网对端保持会话」吻合，且没有 dataSync 的时间预算。
- Android 13+（API 33+）需要 `POST_NOTIFICATIONS` 运行时权限；不授权时
  通知不进通知栏，但服务仍以 foreground 优先级运行（系统仍在任务管理器
  里显示）。仍需请求权限，否则用户不知道为什么一直有个「运行中」任务。
- Android 12+ 限制后台启动 FGS：我们只在前台 Activity 创建时启动，合法。

## 方案（已选定）

一个 `LocalTransferForegroundService`（Kotlin `Service`），
`onCreate`/`onStartCommand` 里 `startForeground(id, notification, type)`，
通知走一个 `IMPORTANCE_LOW` 的 channel（无声、无震动、不可划走）。

- **启动时机**：`MainActivity.onCreate`（Flutter 引擎拉起后、UI 首帧前
  后均可，选 onCreate 尾部）`ContextCompat.startForegroundService`。
- **停止时机**：`onTaskRemoved`（用户从最近任务划掉）→ `stopSelf`。
  进程被系统杀死时服务同死，`START_NOT_STICKY` 保证不空壳复活。
- **通知文案**：「正在局域网中保持在线」式一行 + channel 名
  「后台保活」。channel 与文案做成资源字符串，随包内中英文？——
  Android 资源只支持一种默认语言，通知文案直接用中文写死（应用
  label 已是中文「竹叶局域网传输」，manifest label 同样不走 Flutter
  l10n），如需英文后续再议。**（我的决定：与现有 label 一致，中文。）**
- **通知图标**：复用 `@mipmap/ic_launcher` 作为 small icon（手写服务
  没有 Flutter 的 flutter_launcher_icons 产物差异，launcher icon 本身
  就是合法 drawable）。
- **POST_NOTIFICATIONS**：`MainActivity.onResume` 首次执行时，
  API 33+ 且未授权则 `ActivityCompat.requestPermissions` 请求一次
  （fire-and-forget，不需要回传 Dart；拒绝的后果只是通知不可见）。
- **Dart 侧改动**：零。服务只负责保活，网络栈原样运行。

## 被考虑过的替代方案

- **`dataSync` 类型**：语义最贴合（同步/传输），但 Android 15+ 有
  6h/24h 预算，常驻场景会撞墙。否决。
- **`specialUse` 类型**：无时间限制，但需要 manifest 声明用途属性、
  口径模糊；侧载分发虽不走 Play 审核，但 `connectedDevice` 语义更干净。否决。
- **插件（flutter_foreground_task 等）**：功能现成，但破坏「零插件、
  核心纯 Dart 可无头测试」的既定约束，且引入的是一个只用其 5% 的依赖。否决。
- **只加 WakeLock/WifiLock**：防 CPU 深睡但进程仍可能被冻结，单独用
  收益有限。否决（息屏保活留作后续单独决策）。

## 留给实现者的部分

- `AndroidManifest.xml`：`FOREGROUND_SERVICE`、
  `FOREGROUND_SERVICE_CONNECTED_DEVICE`、`POST_NOTIFICATIONS` 三个权限；
  `<service>` 声明带 `android:foregroundServiceType="connectedDevice"`、
  `android:exported="false"`。
- Kotlin：`LocalTransferForegroundService.kt`（startForeground +
  channel + 通知 + onTaskRemoved）+ `MainActivity` 两处挂钩
  （onCreate 起服务、onResume 请求通知权限）。
- 通知 channel id、通知 id 等常量命名。
- Agent Note 三件套（`.agents/notes/implemented/feature/`，本 PR 内）。
- 验证：无法在本机跑 Android 设备测试；以 `flutter analyze`、
  `dart format`、`dart test` 门禁 + manifest/Kotlin 人工复查为准，
  真机验证步骤写进 Agent Note 的验证章节。

## 验证

- `flutter analyze`、`dart format --set-exit-if-changed .`、`dart test`
  全绿。
- 手工检查：manifest 权限与 service 声明完整；service 不 exported；
  channel 在 API 26+ 创建、低版本跳过；`startForegroundService` 只在
  前台调用。
- 真机（实施者无法执行，记录在案）：安装后切到其他应用，另一台设备
  上本机保持在线；从最近任务划掉后恢复离线。

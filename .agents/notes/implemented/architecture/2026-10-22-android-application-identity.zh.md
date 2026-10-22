# Agent Note: 给 Android 使用竹叶应用标识

Status: implemented

[English](2026-10-22-android-application-identity.md) | 中文

## Problem

Android 安装后的启动器名称为 `local_transfer`，这是 Dart 包名，而不是应用其余
界面展示的产品名。同时 Gradle namespace、application ID、Kotlin 包名和 method
channel 都使用 `cn.hnasct.local_transfer`，因此 Android 把应用私有的
profile、消息和收到的文件放在
`/data/user/0/cn.hnasct.local_transfer/files`。

产品名是 **竹叶局域网传输**，仓库归属标识是 `io.menghun3-cn`。最初要求的点分
标识是 `io.menghun3-cn.zhu-ye-local-im`，但 Android application ID 遵循 Java 包名
语法：连字符不是合法的包段字符。原样写入会得到一个无法构建的 manifest。

## Decision

Android 标识采用 `io.menghun3_cn.zhu_ye_local_im`，即符合平台语法的最近拼写：

* Gradle 的 `namespace` 与 `applicationId` 都使用它。
* `MainActivity.kt` 位于
  `android/app/src/main/kotlin/io/menghun3_cn/zhu_ye_local_im/MainActivity.kt`，
  声明同名 Kotlin 包，并注册 `io.menghun3_cn.zhu_ye_local_im/paths` channel。
* Dart 侧使用同一个 paths channel，因此 Android 存储位置仍只有一个来源：
  `filesDir.absolutePath`。
* 启动器名称为 `竹叶局域网传输`。

Android 从 `applicationId` 推导私有存储位置。改动后路径为
`/data/user/0/io.menghun3_cn.zhu_ye_local_im/files`，不存在另一个 Dart 专属存储根。

## Alternatives considered

**原样使用 `io.menghun3-cn.zhu-ye-local-im`。** 否决：Android 包段不允许连字符，
应用无法构建。用下划线替换既保留归属与项目词，也满足平台语法。

**保留 `cn.hnasct.local_transfer`，只改启动器名称。** 否决：安装身份和私有存储
目录仍带旧归属名，而需求明确覆盖代码与存储。

**保留旧 application ID，启动时迁移私有目录。** 否决：Android 不允许一个
application ID 读取另一个应用的私有沙箱。新包无法读取旧包
`/data/user/0/cn.hnasct.local_transfer/files`，除非存在本产品没有实现的显式导出、
备份或用户参与的数据转移。

**同时修改 Windows runner 的 channel 和窗口类。** 否决：本次需求只针对 Android，
而 Windows host-shell 协议是另一份持久契约。没有 Windows 迁移方案就改名，会把
显示修复扩大成第二次兼容性破坏。

## Consequences

新 APK 是另一个 Android 应用包，可以与旧的
`cn.hnasct.local_transfer` 并存，但不能覆盖升级。若只想保留一个启动器入口，用户
需要先卸载旧包再安装新标识。旧配对记录、消息、设置和待处理文件仍留在旧包的私有
沙箱里，新包看不到；需要重新配对与配置。

收益是归属明确的稳定应用标识、清晰的中文启动器名称，以及代码、平台 channel 和
存储路径一致的包身份。Android bridge 测试会同时读取 manifest、Gradle、Kotlin
和 Dart 源码，把名称、namespace、application ID、包目录与 channel 钉在这个
标识上。

## Testing

`test/platform/android_bridge_test.dart` 无需模拟器即可核对启动器名称、
`io.menghun3_cn.zhu_ye_local_im` 的 namespace 与 application ID、Kotlin 包路径，
以及 Dart/Kotlin paths channel 的一致性。Profile 位置测试使用新的应用私有目录
作为 fixture。

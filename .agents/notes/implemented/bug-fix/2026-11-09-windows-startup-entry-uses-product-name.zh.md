# Agent Note: Windows 自启动项使用产品名

Status: implemented

[English](2026-11-09-windows-startup-entry-uses-product-name.md) | 中文

## Problem

安装后的应用在用户可见处已经统一为中文：安装包的快捷方式与开始菜单组、窗口标题、可执行文件的
`FileDescription` 和 `ProductName` 都写着「竹叶局域网传输」。但 Windows 还有一处没有跟上：支撑
「开机自启动」的每用户 `Run` 项，值名仍是 `LocalTransfer`，而 Windows 列出启动应用时用的正是这个
值名。需求是在不改名 `local_transfer.exe` 的前提下，把显示名称统一起来。

## Decision

`Run` 值名现在是「竹叶局域网传输」，与快捷方式、开始菜单、窗口标题和可执行文件元数据已经使用的
名称一致。可执行文件名仍是 `local_transfer.exe`：这次只要求改显示名称，而 Flutter/CMake 与打包
流水线仍以这个文件名为准。

`HostShell` 同时读取当前值名和旧的 `LocalTransfer` 值名，因此旧版本写下的条目仍算作已启用。
`Attach` 每次启动迁移一次这条旧条目，但只在它指向当前正在运行的可执行文件时才迁移：先写入新值，
写成功后才删除旧值，因此一次失败的写入不会让用户失去自启动。指向其他安装位置的条目保持不动。
关闭开关会同时删除两个名字；打开开关会写入产品名并移除旧名。

## Consequences

- 新建的自启动项，以及被迁移的旧条目，在 Windows 的启动列表里显示为「竹叶局域网传输」，不再是
  `LocalTransfer`。
- 旧条目在本版本第一次启动时被搬移，而不是留下第二个自启动项。
- `autostartEnabled` 仍然只从注册表读取答案；旧名字只是兼容输入，不是第二个事实来源。
- 包名、绿色包更新载荷检查、安装器路径和可执行文件本身仍沿用 `local_transfer` / `LocalTransfer`
  的写法。

## Alternatives considered

**把可执行文件改名为 `竹叶局域网传输.exe`。** 否决：需求范围只到显示名称，而且构建与更新流水线
仍以 `BINARY_NAME.exe` 以及打包脚本的 `local_transfer.exe` 契约为准。

**继续把 `Run` 值名写成 `LocalTransfer`。** 否决：那正是启动列表里一直显示的内部式名称。

**同时写入两个 `Run` 值。** 否决：同一个应用会有两个自启动项，之后每次读取、写入和关闭都必须永
远记得这一对名字。

**只在用户拨动开关时迁移。** 否决：已经开启自启动的用户会一直看到旧名称，直到恰好碰一下那个开
关。

## Testing

Windows runner 没有单元测试设施；这项改动由正常 Windows 构建编译 `windows/**` 来覆盖。注册表契约
刻意保持很小：两个名字都参与「是否启用」的读取，写入永远指向产品名，删除覆盖两个名字，而迁移只
发生在条目指向当前可执行文件时。

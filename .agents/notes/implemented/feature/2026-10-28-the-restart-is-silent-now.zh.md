# Agent Note: 重启现在是静默的

Status: implemented

[English](2026-10-28-the-restart-is-silent-now.md) | 中文

## Problem

在「更新并重启」后的确认框之后，Windows 会再显示两个不确定进度指示：关于页上
约 600 ms 的进度条，以及随后一个独立的交接窗口——转圈加「正在替换本目录并
重启…」——等待新构建把自己复制到原位置。安装版还会显示 Inno Setup 自带的静默
安装进度窗口。对一个用户已经同意的步骤，出现三个彼此分离的「等待」瞬间，而且
没有一个带百分比、没有一个可操作。

## Decision

确认框是唯一的宣告。之后：

- **关于页不再画任何新东西。** `handingOver` 进度状态不再上报给页面（它的句子和
  `aboutUpdateHandingOver` 这条 l10n key 已删除），Windows 上确认框之后页面也不再
  设置进度状态。Android 仍显示「正在打开系统安装器…」。
- **交接窗口消失了。** 以 `--apply-update` 启动的构建改为就地完成：
  `UpdateHandoff.run()` 在 isolate 上替换目录、启动更新后的构建并退出。
  `lib/ui/update_handoff.dart` 已删除。用户接下来看到的是更新后的应用。
- **安装版同样保持静默。** Inno Setup 改用 `/VERYSILENT` 而不是 `/SILENT`，
  因此不再出现安装窗口；它现有的 `[Run]` `/update` 条目仍然负责重新拉起应用。
- **失败仍然会被报告。** 当新构建无法启动或复制失败时，便携版会把
  `.update-failed.txt` 写到应用目录下；下一次启动会读取它（与之前相同）。
  旧进程启动 staged 构建失败时也会写报告，因为旧窗口可能已经关掉了。

## Alternatives considered

**保留交接窗口，只去掉关于页的进度条。** 这仍然会在用户已经同意之后显示一个
没有信息量的转圈，并保留一个唯一用途就是「等待中」的窗口。

**为复制过程显示真实的进度条。** 复制在 isolate 上进行；逐文件进度需要一个
port 和 stream，只为了显示一个没人能据此行动的数字（设计交接窗口时已经否决过
同一个想法）。

**隐藏窗口而不是删除它。** 一个被隐藏的 Flutter 窗口仍然会初始化完整的引擎、
消耗同样的资源，还会给将来的代码留下陷阱；删除 `update_handoff.dart` 才彻底
移除这条路径。

## Consequences

- 一次宣告，然后重启：用户接下来看到的就是更新后的应用。
- 失败报告是静默交接失败后留下的唯一痕迹，下一次启动时由 `previousFailure()`
  读取一次即删——契约与之前相同。
- 原生 runner 的注释和文档不再引用交接窗口；`--apply-update`、`--staged`、
  `--target` 的旗标契约保持不变。

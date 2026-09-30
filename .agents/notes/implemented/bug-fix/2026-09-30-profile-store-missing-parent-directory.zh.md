# Agent Note: Make the profile store create the directory it writes to

Status: implemented

[English](2026-09-30-profile-store-missing-parent-directory.md) | 中文

## Problem

`profile_location.dart` 决定一台 Device 的身份存在哪里，并在自己的文件头里写明了它承担的那一半约定：*"Nothing here creates anything. These functions decide a path; the store and the transfer sink are what make it exist."*（这里不创建任何东西。这些函数只决定路径；让它真的存在，是 store 与 transfer sink 的事。）

`FileProfileStore.save` 没有让它存在。它把新内容写进一个同级的临时文件，删掉目标文件，再把临时文件改名覆盖上去 —— 而 `File.writeAsString` 不会创建缺失的父目录。于是在一台从未运行过本应用的机器上，第一次保存就抛了：

```
PathNotFoundException: Cannot open file,
  path = 'C:\Users\owner\AppData\Roaming\LocalTransfer\profile.json.tmp'
  (OS Error: The system cannot find the path specified., errno = 3)
```

这不是边角情况。本项目算出的每一个 profile 路径，其所在目录在首次启动时都不存在：Windows 上是 `%APPDATA%/LocalTransfer`，Android 上则是用户按预填值接受一个 Transfer 时，应用私有目录下的 `incoming`。`loadOrGenerateLocalProfile` 会立刻调用 `save` —— 它先铸造身份并落盘，然后 Device 才有可对外宣告的指纹 —— 所以这个失败发生在第一帧之前。在 Windows 上，应用根本起不来。

没有测试抓到它，原因值得记下来：每个 `FileProfileStore` 测试都把 store 建在 `Directory.systemTemp.createTemp` 里，而那个目录是存在的。这套测试对损坏、原子替换、残留临时文件都查得很细，却对「文件放在哪个目录里」无话可说，因为 fixture 已经替它建好了。

## Decision

`FileProfileStore.save` 在写临时文件之前，递归创建目标的父目录：

```dart
await temp.parent.create(recursive: true);
```

用递归而非只建一层：路径是在别处算出来的，这个 store 没有立场对它能有多深持有意见。

## Alternatives considered

**让 `openPlatformSeams` 去建目录。** 否决理由：它知道 profile 路径，却不知道 incoming 目录 —— 那是 transfer sink 的职责；这样修只会覆盖一半路径，并把另一半留在第三个地方。store 管自己的文件，正是 `profile_location.dart` 已经写明的安排。

**让 `profile_location.dart` 在算路径时顺手建目录。** 否决理由：那些函数是纯函数，测试会调用它们来问「Android 与 Windows 的规则分别解析成什么」。一个被问问题就写盘的函数，就没法用来问问题了。

**把 profile 放到一个保证存在的目录里**，比如直接用 `%APPDATA%` 或系统临时目录。否决理由：这两者都会把这台 Device 的身份散落到它并不拥有的命名空间里；而临时目录熬不过一次重启 —— 那恰恰是这个文件存在的唯一理由。

**把保存失败当作非致命、退化为纯内存运行。** 否决理由：它把一个响亮、可修的错误变成了沉默的错误。无法持久化的 Device 每次重启后都要重新配对，而界面上不会有任何东西说明原因。

## Consequences

- 首次启动现在在两个 v1 平台上都能走通。两个平台都受影响，而此前都没有从一个干净的 profile 目录跑过。
- `test/profile/profile_store_test.dart` 用两条用例钉住它：都写入尚不存在的目录，一条只差一层，一条差好几层。
- `test_flutter/platform/seams_test.dart` 从真正的入口覆盖同一片地面：它对着一个临时 `%APPDATA%` 打开接缝、铸造一个身份，再第二次打开接缝，找回同一台 Device。
- store 现在会做出自身文件之外的文件系统改动。这是刻意的，也是这个类职责的一次扩大；但另一个选项是一个起不来的应用，那不算选项。

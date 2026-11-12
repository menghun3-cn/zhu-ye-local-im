# Agent Note: 文件夹作为一个 Transfer 整体发送，目录结构编码在名字里

Status: implemented

## Problem

输入框能发文件和图片，唯独发不了文件夹：`classifyPaths` 把目录过滤掉，
因为目录有路径却没有字节；而且线上格式也没有办法表达「这些 item 同属
某个目录结构下」。想发一整个文件夹的用户只能自己打包，或者一个文件一个
文件地发。

## Decision

**目录树编码在 item 名字里。** 文件夹发送是一个 `PayloadKind.file`
Offer，它的 item 以 `folder/sub/dir/file.txt` 命名 —— 以 `/` 分隔的相对
路径，根是文件夹自己的名字。不新增 `PayloadKind`、不加 manifest item、
不动协议版本：接收端把名字里的 `/` 读作「这是路径」，用平铺名字本来就
有的规则逐段消毒（[incomingLandingFor]），在用户选的目录下重建目录，
每个文件仍走原有的暂存与重名编号。旧版本接收端会把整个名字拍平
（`a_b_c.txt`）—— 是降级，不是损坏。

**一个文件夹，一个 Transfer。** `LocalTransferController.sendFolder`
先枚举目录树（[listFolderForSend]），在哈希任何字节之前对照
`TransferLimits.defaults` 检查数量与大小，然后把全部交给一次
`sendFiles`。接收端只应答一次、落盘一次。

**字节源不占句柄。** 一个文件夹可以有几千个 item，所以每个 item 的字节
来自 `ChunkedFileByteSource`：构造时 stat 定长，每次 read 才打开并关闭
句柄 —— Offer 挂着等应答的那段时间里没有任何文件被锁住，否则在
Windows 上用户连刚发出去的文件夹都移动不了。

**不随行的东西。** 空目录不产生 item（线上格式没有办法说「这是个目录」）；
符号链接不跟随 —— 链接可以指到所选文件夹之外；不可读的条目被跳过并计数。
超出 Offer 上限的文件夹在哈希之前就被拒绝，各自的 `AppRefusal` 让界面
能说清超的是哪一条。

**输入框把文件夹当一个附件暂存。** 工具栏新增第二个附件按钮
（`menuSendFolder`）让系统选目录；拖放和粘贴进来的目录路径走同一条暂存
路径。托盘 chip 显示文件夹名字，文件在按下「发送」时才枚举 —— 选好之后
文件夹里变了，发的就是当时的内容。

## Alternatives considered

**新增 `PayloadKind.folder` 加 manifest。** 否决：旧版本接收端遇到未知
kind 会拒绝整个 offer，比拍平名字的降级更糟；而且「没有字节流的目录」
需要格式并不具备的 item 语义。

**全部拍平成裸文件名。** 否决：丢掉了需求本身要的结构，而且不同目录下
的同名文件会被静默重命名。

**每个文件一个 Transfer。** 否决：N 次 offer、N 次应答，接收端也没有
「这是同一个文件夹」可以落成一棵树。

**把文件夹压成 zip 再发。** 否决：改变了字节本身 —— 接收端拿到的是要
解压的文件而不是文件夹 —— 还绕开了 Transfer 自带的逐文件摘要校验。

## Consequences

**得到的。** 文件夹带着它自己的树、名字和逐字节校验跨过链路，仍在协议
本来就有的上限之内。新旧版本两个方向都能互通。

**代价。** `PayloadItem.name` 现在的含义是「一个名字，或 `/` 分隔的路
径」—— 今后所有生产和消费 item 名字的代码都必须知道这个约定，所以它
写在 [incomingLandingFor] 和这篇笔记里，而不是只留在注释里。每 64 KiB
一块的按读打开/关闭多付一次系统调用，相对要哈希的同一批字节可以忽略。
空文件夹不会到达，且没有提示。

**留待后续。** Android 的文件夹选择未经验证 —— `file_selector` 的目录
应答和 scoped storage 下的 `dart:io` 直读未必够得着用户选的目录；如果
不行，该入口在 Android 上隐藏，而不是阻塞整个特性。枚举时记下的
`skipped` 计数暂时没有界面展示。

**测试。** `test/app/folder_listing_test.dart` 固定遍历行为（树形命名、
大小、空目录、链接），`test/app/incoming_path_test.dart` 固定落盘规则
（穿越、空段、反斜杠），`test/transfer/chunked_file_byte_source_test.dart`
固定字节源；输入框的文件夹 chip 与按钮由
`test_flutter/ui/composer_folder_test.dart` 覆盖。

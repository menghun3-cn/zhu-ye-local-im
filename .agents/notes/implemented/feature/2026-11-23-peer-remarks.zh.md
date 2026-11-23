# Agent Note: A user-given Remark names a peer on this Device

Status: implemented

[English](2026-11-23-peer-remarks.md) | 中文

## Problem

对话列表在 Discovery 已经定位到对端时，行标题一律显示对方的地址——这是
`2026-10-08-a-nameless-peer-shows-its-address.md` 有意的决定，因为列表真正
要回答的问题是「哪台机器是它」。但地址是很差的联系人名：DHCP 换一段租约
它就变，对用户也说明不了这是谁的机器；「NAS」和「妈妈的手机」在列表里只是
两串没有区别的数字。

对端自报的 Alias 也填不上这个缺口。它是自报的、可选的、在每台看到它的
设备上都一样——它回答的是「线上管它叫什么」，而不是「我的联系人里它是哪
一个」。

## Decision

**Remark（备注）**是用户在本机给某个对端起的名字。它存在 `DeviceProfile`
的 `remarks` 表里，按 Fingerprint hex 做键——纯本地 profile 数据，不上线、
不同步到 Owner Group，被备注的对端永远看不到。按 Fingerprint 而不是按地址
做键正是要点：对端 IP 在底下怎么变，备注都还在。

`PeerView` 新增 `remark` 字段，由 `LocalTransferController.peers` 从
profile 组装；`displayName` 的解析顺序是 **Remark → 自报 Alias → 地址 →
Fingerprint**。由于所有界面都读 `displayName`——对话列表及其搜索排序、
会话页头、Devices 卡片、转发选择器、剪贴板页、Transfers 查询——备注在
所有显示 peer 名字的地方生效，而这些界面一行都不用改。唯一需要显式分支
的是 `describePeerTitle`：它按设计优先显示地址而不是 Alias，所以现在优先
显示备注而不是地址。

`DeviceProfile.setRemark` 用与自报名称相同的
`DeviceDescriptor.sanitiseAlias` 规则清洗，空白即清除，拒绝 `self`。
`forgetDevice` 会连同对端其余记录一起删掉备注，删除对话不会留下指向虚无
的名字。profile JSON 新增可选的 `remarks` 对象；此前版本写出的 profile
读出来没有备注，键不是 Fingerprint 的条目与文件里其它 peer 引用一样被拒
绝。

编辑入口放在对话已有的操作位置：行的右键菜单和会话页头的 ⋮ 菜单都提供
「修改备注」，弹出的对话框经 `LocalTransferController.setPeerRemark`
写入——一次 profile 写入加重绘，不动任何 Session，也什么都不发送。

## Alternatives considered

**覆盖 `KnownDevice.alias`。** 否决：该字段记录的是对端*自报*的内容，
`noteDevice` 每次观测都会刷新它——存在那里的备注会被下一次公告悄悄覆盖。
两者是不同性质的事实，现在分属不同字段。

**通过 Owner Group 同步备注。** 否决：备注是一个人私有的标签（「妈妈的
手机」不是那台手机该广播的名字），而且线上格式根本没有这个字段。本地
专属还意味着协议零改动、没有版本错位要处理。

**只在对端没报 Alias 时用备注兜底。** 否决：用户要的是备注替代 IP、充当
联系人名；做成兜底会让两个名字在屏幕上竞争，还多出一条用户看不见的规则。
备注永远优先——清空它就回到旧行为。

**单独的每对端存储文件。** 否决：profile 已经在持久化同类用户状态
（收藏、剪贴板白名单、接收目录），带原子写入和损坏处理；为一张表再开一
个文件是重复造机械。

## Consequences

* 每个显示 peer 名字的地方都显示备注——包括用户没有点名要求的地方
  （气泡发送者名、转发选择器）。这是要求的行为，也是诚实的行为：同一
  台设备在两个页面叫两个名字更糟。
* 自报 Alias 和地址并没有消失——它们仍在事实行（`describePeerFacts`）
  和 Devices 卡片的副标题里，所以备注永远不会藏起分辨两个备注所需的
  事实。
* `avatarLabel` 让位于备注的首字母：按地址末段画的头像是在给一个并未
  显示的名字做标记。
* 给之后被删除的对端设过的备注会被 `forgetDevice` 清掉；给从未见过的
  对端设备注不可能发生，因为编辑入口都在对话界面上。
* `hasRealAlias` 仍然只报告对端自报的内容——「未自报名称」这类提示
  继续说的是真话。

## Testing

`test/profile/device_profile_test.dart` 覆盖设置/清除/清洗/自身/往返/
缺键/坏键/`forgetDevice`。`test/app/views_test.dart` 固定
`displayName` 与 `avatarLabel` 的优先级。`test/app/app_controller_test.dart`
驱动一对真实配对设备，断言备注出现在设置方的 `PeerView` 上而对端自己
看到的视图不受影响。`test_flutter/ui/labels_test.dart` 固定
`describePeerTitle` 让备注优先于地址和 Alias。

# Agent Note: 更新下载由会话持有，而不是页面

Status: implemented

[English](2026-11-05-update-download-session.md) | 中文

本笔记决定的会话持有机制不变；
[更新不再询问](../simplification/2026-11-09-update-applies-without-asking.zh.md)
后来移除了本笔记描述的确认步骤与 `confirmRequests` 机制——完成的 prepare 由
会话自己应用。

## Problem

更新安装——下载、校验、解包、提问、交接——原本存在 About 页的 State 里。而
这个页面只在 My 的「关于」子页打开时才构建，于是下载中途离开页面就丢掉了下载
已经产出的全部结果：`prepared` 在 `!mounted` 时被丢弃，进度与就绪状态随之消失，
回到页面只能再按一次「更新」。如果第一次的孤儿 fetch 还在跑，再按一次会让两个
`prepare` 同时写同一个 `.part` 文件，最终以校验失败收场、整包重下——这正是用户
实际看到的「中断」。而且即便包真的下载完了，也只有重新打开页面、再按一次按钮
走一遍 `prepare` 才会被发现；重启应用后磁盘上明明已有字节，流程却照样从头再来。

## Decision

**`UpdateInstallSession` 在进程生命周期内持有这次安装。** 会话是一个
`ChangeNotifier`，由 `HomeShell` 持有——它是唯一比所有界面活得久的部件——并沿
`MyPage` → `AboutPage` 传下去。它保存答案、进度、失败、已就绪的更新和在途的
prepare future；About 卡片只是它的视图。`install(answer)` 是「安装这个」的唯一
入口：采用答案、让已经在跑的 prepare 被第二次请求汇合而不是再开一个、并把「按到
已就绪包」计为一次 `confirmRequests` 递增——即再次提问，而不是重新下载。
`reset()` 对应卡片上一次全新检查的语义。

**提问仍归卡片。** 会话上报 `prepared`；卡片把新出现的就绪更新转化为一次
`_ConfirmUpdateDialog`，除非这个就绪包来自 `restore`——从磁盘找到的包是被
「提供」的（显示就绪文案，按钮负责提问），而不是被「宣布」的，因为打开一个页面
并不等于请求关闭应用。

**重启后能再次找到已完成的下载。** `UpdateInstaller.hasFetchedPackage(check)`
回答答案所指的包是否已在更新目录里、完整且与发布校验值一致——一次本地的摘要
读取，不碰网络。`HomeShell` 在 notice 落到可用版本时调用 `session.restore(answer)`；
命中时会话运行与按下按钮相同的 `prepare`，此时只剩本地校验与解包。restore 绝不
下载：盘上没有就是没有，下一次点击照旧走网络；上次被杀掉的运行留下的 `.part`
仍由下一次 `prepare` 接续，机制不变。

**rail 入口直接按会话。** `_installUpdate` 调用 `session.install(notice.answer)`
并把 My 界面带到前面；`installRequest` 计数器与卡片的 `didUpdateWidget` 消费一并
移除。这同时修复了 My 页整合留下的一个断点：rail 按下去原本在 About 卡片恰好已
构建之前什么都不做，且首次构建时挂起的计数永远不会被消费——rail 测试描述的流程
现在能走通，靠的是会话而不是页面持有请求。

## Testing

`test/ui/update_install_test.dart` 在真实安装器与临时应用目录上锁定
`hasFetchedPackage`：只有「在且匹配」才为真，缺失、摘要不符、无校验值、平台不
支持均为假。`test_flutter/ui/update_session_test.dart` 覆盖会话本身——请求汇合、
confirm 计数、restore 的「不下载」与「备好已有」、每版本只查一次、reset——以及
架在它上面的卡片：页面不在时完成的下载仍欠一次提问、下载中途重建的卡片看到原
进度、恢复出来的包被提供而不弹窗、按一下即安装。
`test_flutter/support/ui_harness.dart` 的 `openMyCard` 现在点卡片本身——它曾找的
「查看详情」按钮自 My 页落地起就不存在了，这正是 rail 测试在 develop 上为红的
原因。

## Alternatives considered

**保留页面内下载、只让页面不销毁。** 否：`Offstage`/`IndexedStack` 包装能保住
widget 状态，但保不住需求点名的进程边界——重启依旧一无所获——还让一个不可见
页面的监听器与定时器无谓地活着。会话还必须比 My 自身的重建活得久，页面级属主
给不了这个保证。

**持久化一份描述已完成下载的标记文件。** 否：更新目录本身就是记录——包名带版本、
字节带校验和。第二个文件就是第二个需要保持为真的东西，而 `hasFetchedPackage`
读的那一个不会说谎。

**对恢复出的包自动弹确认框。** 否：重启时盘上有字节不等于用户此刻要求关闭应用。
卡片显示就绪、等待那个「是」的点击；而活下载刚产出的包仍会立刻提问，与从前一致。

**restore 时自动续传 `.part`。** 暂不：`.part` 接续已让下一次点击足够便宜，而在
用户走开之后悄悄重启一次抓取是另一个承诺，不在本次范围内。钩子已留好，以后需要
随时可加。

## Consequences

- 下载中切换界面不再丢下载与结果；第二次点击汇入在途抓取而不是与之赛跑。
- 更新目录里已有完成包的重启能直接找到：按一下到提问，不再重复下载。
- rail 更新入口现在真的会安装了——它自 My 页落地起就是死的，相关测试重新变绿。
- 会话是进程级的，所以从 rail 发起的安装对卡片可见，且不会被它重复发起。
- `UpdateInstaller` 新增了一个成员；实现者都在本仓库内
  （`PlatformUpdateInstaller`、`ScriptedUpdateInstaller`）。

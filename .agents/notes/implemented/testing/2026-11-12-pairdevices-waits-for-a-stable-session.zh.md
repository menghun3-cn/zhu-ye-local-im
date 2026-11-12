# Agent Note: pairDevices 等的是稳定的 Session，而不是侥幸的瞬间

Status: implemented

## Problem

`test_flutter/support/ui_harness.dart` 里的 `pairDevices` 以固定 300 ms
延迟收尾，再断言一次两个 Device 都还持有 Session。这是在赌时序，而
`pages_test.dart` 里那条三 Device 用例——全套件中唯一把第三台 Device 放进
同一 beacon 网络的——大约三次里输两次。

机理不是 Session 层的 bug，而是测试没有等完一个有文档记载的产品行为。
Device 加入 Owner Group 时组密钥轮换，`_syncLayers` 看到 `secretChanged`，
拆掉整个 session 层重建，每个成员重新拨号。重建的 `LinkManager` 还会绑一个
*新的*临时 Session 端口，所以轮换后的短窗口内，Discovery 宣告的端口和
仍开着的握手所记的端口本来就可能不一致。测试在这个窗口里的某个瞬间，
同时断言了两件事——「Session 保持开着」和「页眉写的是宣告的端口」。

## Decision

**harness 等的是连续性，不是瞬间。** `pairDevices` 现在要求两个 Device 的
Session 连续非空满 300 ms 才返回，任一侧被观察到为空就重置窗口。对占
绝大多数的两 Device 用例来说，配对后不会再有轮换，所以耗时和原来固定
延迟的那半秒相同；对三 Device 用例，等待只会持续到最后一次轮换的重拨
落地为止。

**端口断言用同样的方式等收敛。** 记住会话的用例现在轮询，直到会话页眉
写出 Discovery 当前为 Carol 宣告的端口，且每次轮询都重新读取宣告端口，
而不是只快照一次。反向断言——页眉上*不应*出现 Bob 的端口——保持不变，
因为两者是不同的临时端口，没有任何时序能让它们相等。

## Alternatives considered

**给测试 Device 固定 Session 端口。** 否决：`sessionListenPort` 是每台
Device 一个，同主机的三台要协调三个端口；临时端口才是生产用的，钉死它
等于不再覆盖 `_serveSessionLayer` 存在的意义——端口被占时的回退路径。

**等待「最近 N ms 内没有 session 层重建」。** 否决：重建从 widget 树上
看不见，要观察就得伸手进 controller 的私有层状态，这会让套件耦合到
harness 刻意不知道的实现细节。

**失败后重试整个用例。** 否决：重试只是把同一个竞态藏进每一条配对
Device 的用例里，还教会套件接受 flaky。窗口检查在竞态所在的唯一位置
把它消掉了。

## Consequences

**得到的。** 三 Device 用例从约三次一成变成连续六次通过，`pairDevices`
断言的也变诚实了：不是「Session 曾经存在过」，而是「Session 一直开着」。
今后任何在场景中途加 Device 的测试都继承同样的容忍度。

**代价。** 每次 `pairDevices` 失败前最多等 20 s，而不是 300 ms 就失败——
但只在 Session 真的无法保持时才走到那里，而那正是值得多看一眼的时候。
约 35 处现有调用付出的代价至多是原来那 300 ms。

**测试。** 不靠新增用例，靠重复验证：原先 flaky 的用例连续跑了六次，
并完整跑了一遍 `test_flutter` 套件。

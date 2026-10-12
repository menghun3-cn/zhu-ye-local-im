# Agent Note: The Owner identity is a persisted key pair, and the profile is its local state

Status: implemented

English | [中文](2026-09-30-owner-identity-key-pair-and-device-profile.md)

## Problem

[CONTEXT.md](../../../../CONTEXT.md) 把 Owner 定义为「由一把永不离开设备的密钥对确立」，
把 Fingerprint 定义为「设备公钥的 SHA-256」。但在本次增量之前，代码库里没有任何东西拥有
这把密钥对：`DeviceDescriptor` 里的 Fingerprint 是运行中的代码随手填的，设备在重启后会把
一切——包括「我是谁」——忘干净，Known Devices、收藏（Favorite）、Owner Group 成员关系也
没有地方可以持久化。后续每个依赖身份连续性的功能——配对、收藏跳过确认、剪贴板只在 Owner
Group 内镜像——都只能各造一套存储，而它们必然彼此不一致。

## Decision

设备的持久化自我是一个对象 `LocalProfile`，通过 `ProfileStore` 作为一个整体加载和保存：

- `OwnerIdentity` 持有 Owner 的 Ed25519 密钥对。Fingerprint 是原始公钥字节的 SHA-256——
  与对端使用的推导方式相同，所以双方无需第三方即可就身份达成一致。这把密钥只签身份挑战；
  绝不参与会话密钥协商，所以泄露它不会暴露任何会话流量。会话密钥仍只由
  [SecureLink](../../architecture/2026-09-29-core-wire-protocol-and-secure-session.md)
  及其内部的临时 X25519 交换派生。
- `DeviceProfile` 是围绕这份身份的本地状态：对外广播的 `alias`（用与对端自报名号相同的
  规则做清洗，复用 `DeviceDescriptor.sanitiseAlias`）、平台、设备所属的
  [Owner Group](../../architecture/2026-09-29-owner-identity-gates-clipboard.md)、
  收藏集合，以及带最后见面时间与地址的 Known Devices 表。
- `ProfileStore` 只搬运 JSON。`MemoryProfileStore` 覆盖测试；`FileProfileStore` 先写
  同目录临时文件再改名落位，写一半崩溃时旧档案完好无损。无法解码的文件会先被移到
  `<path>.corrupt` 再抛 `ProfileCorruptedException`——绝不删除，因为那是设备身份的唯一副本。
- 持久化形态在 `kind: ed25519-seed` 标签下内嵌 Ed25519 种子；加载时若档案的 `self`
  fingerprint 与种子对应的密钥不一致，直接拒绝：这种组合不是设备，是自相矛盾，必须大声
  失败，而不是悄悄变成另一台设备。
- 身份旁边另有一个 `session` 段，承载群密钥（`LocalProfile.groupSecret`，在配对产出它
  之前不存在）——因为忘记它的设备每次重启都要重新配对。它放在 `LocalProfile` 而不是
  `DeviceProfile` 上：profile 是界面要渲染、测试要手工构造的状态，密钥材料不该出现在
  这两处中的任何一处。

信任的切分与词汇表严格一致：Owner Group 成员关系是镜像授权；收藏是更弱的「跳过逐次传输
确认」授权；Known Devices 不授予任何东西——它们只是观测记录。

## Alternatives considered

**用临时密钥派生 Fingerprint，重启即重掷。** 否决：指纹每次重启都变的设备无法被认出，
产品里所有信任决策——收藏、Owner Group、已固定的对端——都会随之清零。

**把密钥对存进操作系统的凭据库（DPAPI、Keystore）。** v1 否决：每个平台都要写一条
platform channel，而档案文件本就放在用户自己的 profile 目录里，威胁模型与磁盘上其他状态
一致。种子在 JSON 文件里以 base64 明文存放，用户可读——这正符合它的真实面目；将来 v2 若
把种子挪进凭据库，改的是一个访问器，而不是模型。

**让收藏隐含 Owner Group 成员关系，或反之。** 否决：
[Owner 身份闸住剪贴板](../../architecture/2026-09-29-owner-identity-gates-clipboard.md)
的全部意义就在于「可以收我的文件」和「可以读我复制的所有内容」是两种授权。收藏若悄悄
获得剪贴板访问权，就击穿了这条边界；而群成员若被迫每次传输都确认，镜像在实践里就一文不值。

**档案损坏时静默重新生成。** 否决：其失败模式是「某天起所有设备都把这个设备当陌生人」——
这恰恰是 Owner 概念要防止的那种无声的身份变更。把损坏文件移开并上报，控制权留在用户手里。

## Consequences

- 设备重启后保有相同的 fingerprint、相同的 Owner Group、相同的对端历史。配对、收藏、镜像
  可以建立在身份连续性之上，而不必各自造轮子。
- 私钥以 JSON 文件形式放在本地磁盘。能读到这个文件的人就能**成为**这台设备——这与磁盘上
  其他状态的信任边界相同，且刻意不再更强。
- 群密钥共享同一条边界，而且在效果上它更强：密钥证明身份，而群密钥才是打开 Owner Group
  内 Session 的那把钥匙。
- `lib/core/` 保持无 Flutter 依赖：平台是 `loadOrGenerateLocalProfile` 的参数，不是 core
  自己探测的东西，所以 `dart test` 门禁依然覆盖这里的全部代码。
- 从不完整副本恢复的档案——只有身份种子没有 profile 段，或反之——在加载时以
  `FormatException` 报出缺失的部分，而不是静默取默认值。

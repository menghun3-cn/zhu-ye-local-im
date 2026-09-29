# Agent Note: Owner identity layer gates clipboard mirroring

Status: implemented

[English](2026-09-29-owner-identity-gates-clipboard.md) | 中文

## Problem

LocalSend 的模型只有 Device 与一个 Favorite 标记，别无其他。对于文件传输这已足够——每次传输都是带明确接收方的用户主动行为——但对剪贴板同步并不安全。

剪贴板内容经常包含密码、一次性验证码与私钥。「这台设备可以接收我的文件」与「这台设备可以读取我的剪贴板」是两种不同的信任等级，而单一的 Favorite 标记无法表达这种区别。一个用户若曾为了传文件而收藏同事的笔记本，那么在开启剪贴板同步后，就会把密码静默镜像过去。

## Decision

领域模型引入 **Owner**：Device 所属的人，由一对永不离开该 Device 的密钥确立。共享同一 Owner 的 Device 构成 **Owner Group**，剪贴板 Mirror 仅在该组内发生。Device 通过一次性 **Pairing** 加入组——扫描二维码，或使用短码并比对短认证字符串。

没有账号，也没有服务器。`Favorite` 保留，但它明确**不是** Owner Group 的成员身份，也不授予任何剪贴板访问权；正因如此，术语表中这两个概念被刻意区分。

## Alternatives considered

**逐设备剪贴板开关，与 Favorite 解耦。** 不引入新的身份概念：每台 Device 获得一个独立的「与该设备共享剪贴板」开关。否决理由是其失败模式静默且严重：配置失误会变成安全事件，而用户无法被指望可靠地管理一张逐设备的信任等级矩阵。

**把 Favorite 直接当作充分信任。** 最简单，且与 LocalSend 完全一致。否决理由相同：它混淆了用户并不会去区分的两种信任等级。

**完整账号体系。** 直接否决：它需要服务器，而产品明令禁止。

## Consequences

- `Owner`、`Owner Group`、`Pairing` 成为核心领域概念，模型刻意偏离 LocalSend。产品不再是一个「LocalSend 克隆」，而是一个带身份层的局域网传输工具。
- Pairing 需要面向用户的流程，而它同时也是让跨子网连接无需发现即可成立的机制：一个功能服务两个需求，二维码一次携带地址、端口、公钥指纹与一次性令牌。
- 密钥丢失即意味着丢失整个组：每台 Device 都必须重新配对。恢复方式属于产品决策而非技术决策，目前尚未确定。
- 剪贴板能力因平台而异（读取剪贴板的限制远比写入严格），因此一台 Device 发起 Mirror 与应用 Mirror 的能力被分别声明。

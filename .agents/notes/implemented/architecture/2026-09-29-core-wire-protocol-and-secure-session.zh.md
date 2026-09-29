# Agent Note: The wire protocol and the authenticated secure session

Status: implemented

[English](2026-09-29-core-wire-protocol-and-secure-session.md) | 中文

## Problem

局域网中的两台 Device 需要在无服务端、无账号、无云端的条件下交换文本、文件与剪贴板 Mirror。于是有两件事平台不会白送：一是如何在字节流之上给消息分帧，二是一个既保密又经认证的 Session —— 因为局域网是敌对环境，任何能连到监听端口的宿主都能开一条 TCP 连接开始说话。

认证才是麻烦的地方。没有服务端，就没有 CA 去签发设备证书；没有账号，就没有可锚定信任的东西。两台 Device 在相遇之前唯一能共享的，就是通过带外途径建立的 Pairing Secret —— 二维码，或短码加 SAS 比对（见 [owner-identity-gates-clipboard](2026-09-29-owner-identity-gates-clipboard.zh.md)）。Session 必须且只能由这个 secret 认证，并且要跑在纯 Dart VM 上，让同一份代码服务 Windows 与 Android 而不引入原生加密库。

## Decision

本项目自研分帧层与握手，跑在 `dart:io` socket 之上，位于 `lib/core/`：

- `protocol/frame.dart` —— 线上分帧。
- `protocol/messages.dart` —— 控制消息词汇表。
- `transport/byte_transport.dart` —— 上层对网络唯一需要知道的东西。
- `identity/` —— Device、Fingerprint 与 Pairing Secret。
- `security/hkdf.dart`、`security/secure_link.dart` —— 密钥派生与 Session。

## The frame layer

每个帧都是 `u32 length | u8 kind | payload`，其中 `length` 计入 kind 字节与 payload，于是读取方总能知道还要等多少字节。帧有三种：`control`（`0x01`，UTF-8 JSON 对象）、`chunk`（`0x02`，传输 id、`u64` offset 与原始字节）、`sealed`（`0x03`，12 字节 nonce，后接密文及其 16 字节 Poly1305 tag）。

length 前缀由攻击者控制，因此编码与解码两侧都在 `maxFrameBytes`（16 MiB）之上拒收 —— 没有这个上限，线上的九个字节就能让解码器去分配 4 GiB。解码器是增量的，并做惰性压缩：TCP 交付的是字节区间而不是消息，且小帧连成的流不应在每帧都 memmove 活的尾部。流在帧中途结束会抛 `ProtocolException`，而不是看起来像一次干净的通话结束。

封装位于分帧**之上**而非之下：`sealed` 帧的明文恰是一个内层帧的完整编码。于是一个解码器同时服务明文握手与加密会话，中途不存在需要把半消费的读缓冲在两层之间交接的时刻。

## The handshake

握手是 X25519 + HKDF-SHA256 + ChaCha20-Poly1305，并把 Pairing Secret 作为预共享密钥材料混入：

1. 每侧生成临时 X25519 密钥对与 32 字节 nonce，发送 `hello`（或 `helloAck`），携带自己的 Device 描述符、临时公钥、nonce 与 `wireProtocolVersion`（1）。
2. 声称自己就是本 Device Fingerprint 的对端、或讲另一个协议版本的对端，在任何密钥派生之前就被拒绝。
3. `ikm = X25519 共享密钥 ‖ Pairing Secret`；`salt = initiatorNonce ‖ responderNonce`，按角色而非按到达顺序排列，于是无论谁先开口，两侧都构造出同一个 salt。
4. `HKDF-Extract` 得到 PRK；两次 `HKDF-Expand` 分别以 `i2r`、`r2i` 为标签，得到两个 32 字节的方向性密钥。每个方向各自一把密钥，于是一条记录永远不可能被反射回发送方。
5. 记录以 ChaCha20-Poly1305 封装，AAD 为 `local-transfer/v1 record`。

标签 `local-transfer/v1` 作为域分离被混入每一次派生：协议一旦变更，派生结果随之改变，旧版本与新版本会派生出不同的密钥，而不是在不同语义下静默互通。

同一个 PRK 还派生出一个六位短认证串 —— `HKDF-Expand` 在 `sas` 标签下取四个字节、对一百万取模 —— 由两侧 Device 显示。完成握手只能证明对端知道 Pairing Secret，**不能**证明对端是*哪一台* Device，因为任何持有同一 secret 的 Device 都能通过同样的认证。SAS 补上的正是这个缺口：用户带外比对，不一致的对端即被断开。

握手失败的每一种方式 —— 超时、对端挂断、传输在交换中途死掉 —— 都表现为 `HandshakeException`，于是调用方只需按一种错误类型判定「未建立 Session」，而不必去区分 socket 错误与协议错误。

## The transport seam

`ByteTransport`（`incoming`、`add`、`done`、`close`）是上层对网络唯一需要知道的东西。`SocketByteTransport` 包装 TCP socket，拆除时用 `destroy()` 而非优雅关闭，于是一条被放弃的 Session 永远不会去等对端可能永不发送的 FIN。`MemoryTransportPair` 在进程内把两条传输对接起来，于是完整握手与会话既能跑在真实 socket 上、也能纯内存运行，而代码路径毫无差异。

## Alternatives considered

**用 `dart:io` 的 `SecureSocket` 走 TLS。** 可直接得到久经检验的记录层。否决理由：TLS 用证书做认证，而这里既无 CA 也无账号。要把信任锚定在 Pairing Secret 上，要么自建私有 CA 并给每台 Device 下发客户端证书，要么使用 `dart:io` 并不暴露的 PSK 密码套件 —— 而且 TLS 仍无法在不做一次额外带内交换的前提下派生出 SAS，而那次交换恰恰是记录层存在的意义所在。

**Noise 协议框架。** 一个久经审阅的框架，其 `XXpsk3` 形态的握手与本项目的威胁模型高度吻合。否决理由：Dart 侧没有在维护的实现，采纳它等于移植它；而这里真正需要的子集 —— 一次 X25519 交换、一次 HKDF、一个 AEAD —— 比那次移植还小。

**明文加逐消息独立 HMAC。** 更小、更易审阅。否决理由：没有保密性，而且是手工拼装一套 encrypt-then-MAC 组合，而 AEAD 本已把它标准化了。

**以 FFI 引入 `libsodium` 或其他原生加密库。** 否决理由：给一个纯 Dart 代码库引入原生依赖与逐平台构建步骤，换来的却是 `package:cryptography` 已经用 Dart 提供好的原语。

**从依赖里取 HKDF。** 否决理由：密钥派生是唯一一处「静默变更失败得悄无声息」的地方 —— 它只会产出对端根本对不上的密钥，而不会抛错 —— 因此这里自行持有该派生，并用本仓库自己的测试对照 RFC 5869 的公开向量把它钉死。

## Consequences

- Session 仅由 Pairing Secret 认证，没有 PKI、没有逐设备证书、没有账号，这正是「无服务端」约束所要求的。
- 协议从此由本项目自行定版并保持兼容。`wireProtocolVersion` 与 `local-transfer/v1` 标签让未来的变更可被探测而非静默错配，但这里刻意不做协商：版本 1 与版本 2 就是不互通。
- 加密风险从此由本仓库承担。缓解手段：只用久经检验的原语（X25519 与 ChaCha20-Poly1305 来自 `package:cryptography`，HMAC-SHA256 来自 `package:crypto`）、用 RFC 向量钉死的自研 HKDF、每方向一把密钥且每条记录一个新 nonce、以及明文恰为一个内层帧的 `sealed` 记录，使任何数据都无法绕过检查帧的那一层被夹带。
- `test/security/secure_link_test.dart` 在内存传输对与真实回环 socket 两种方式上钉住了与安全相关的行为：完成握手、SAS 一致、错误 secret 被拒、被篡改记录被拒、握手后未加密帧被拒、版本不匹配、对端自称本机 Fingerprint、对端在握手中途挂断，以及 1 MiB 载荷跨多次 socket 读取重新拼装完整。
- 剪贴板 Mirror 与传输引擎尚未实现。它们是接下来的增量，预期直接消费本层而不做改动。

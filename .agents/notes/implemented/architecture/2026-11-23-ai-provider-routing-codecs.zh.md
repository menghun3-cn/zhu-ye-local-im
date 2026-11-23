# Agent Note: AI 供应商通过一种规范格式讲四种协议

Status: implemented

[English](2026-11-23-ai-provider-routing-codecs.md) | 中文

## Problem

应用要加入 AI 能力——对话、消息处理、智能回复——而这些功能都先需要同样两件事：一套配置「有哪些模型、它们在哪」的机制，和一套调用它们的机制。参考设计是 magpie，它的答案是一个本地网关：讲四种线路协议（OpenAI Chat、OpenAI Responses、Anthropic Messages、Gemini），并在它们之间互相转换。

移植 magpie 本体从来不在选项里：它是 Go 应用，Android 没有合理的方式承载 Go sidecar。能借的是问题的*形状*——而这个形状比看上去小。magpie 的「四种协议互转」是 hub-and-spoke，不是 4×4 网格：一种规范格式加每协议一个编解码器，就足以让任意供应商服务任意调用方。应用同时掌握调用的两端，所以为用不到的通用性付一个完整翻译网格的成本是划不来的。

两个产品决策框定了其余部分。供应商按设备各自配置、绝不共享——Owner Group 的信任边界不延伸到 API key。本期工作分期：本文覆盖核心（配置、编解码、路由）；本机网关和设置 UI 是建在其上的独立改动。

## Decision

`lib/core/ai/` 是无 Flutter 依赖的纯 Dart 模块，`dart test` 可以端到端覆盖：

- **`ai_message.dart`**——规范格式：角色、文本内容、工具调用（参数保留原始 JSON，让编解码器边界不必在转义上达成一致）、用量统计，以及五种流式事件。
- **`protocol/`**——每协议一个 `AiCodec`（`openai_chat`、`openai_responses`、`anthropic`、`gemini`），加上能扛住多字节字符跨 chunk 边界的共享 SSE 解析器。每个编解码器拥有自己的 URL 路径、请求头与报文结构；`modelsSpec`/`decodeModels` 给设置 UI 一条拉取模型列表的路径，不需要第二套 HTTP 栈。
- **`provider.dart` + `presets.dart`**——provider 按协议记录 base URL（模型条目记录自己讲哪种协议，因为一个自定义端点可能前置多个上游 API），key 落盘加密，模型目录需显式启用。引用语法沿用 magpie：`provider/model` 或 `group/<id>`。
- **`secret_box.dart` + `provider_store.dart`**——用已在依赖中的 `cryptography` 包做 AES-256-GCM。每安装生成一次 32 字节随机密钥；`apiKey` 字段以 `v1:<nonce‖ct‖tag>` 形式落盘，读取时透明解封。加密前的明文值仍可读，并在下次保存时自动加封。文件机制——原子临时文件改名、损坏文件移开、写入排队——委托给与会话历史相同的 `MessageStore` 抽象。
- **`ai_router.dart`**——把引用解析成具体成员（组可嵌套、环被剪断），按序尝试，仅在可重试错误（429/5xx/额度/网络）上做带冷却的故障转移。致命错误——key 错、模型不存在——立即抛出而不转移，因为下一个成员只会以同样方式失败，还会把真实原因藏起来。流式回复只在供应商开始应答之前允许转移；之后半截回复比诚实报错更糟。

传输层收在 `AiTransport` 之后，测试用夹具脚本化响应；`IoAiTransport` 是 `dart:io` 实现。

## Consequences

- 四种协议中的任何一种都能服务后续所有 AI 功能而无需新管线；新增第五种协议就是再加一个编解码器文件。
- 磁盘上的 `providers.json` 不含明文 key，但加封密钥就放在旁边——这是混淆级保护，真正的加固是 OS keystore（DPAPI、Android Keystore），已记录为后续工作。
- 故障转移按请求、存于内存：重启后每个成员重新获得机会，这与按日重置的额度行为一致。
- 网关（PR2）与设置 UI（PR3）原样消费本模块；编解码层刻意与传输无关，正是为此。
- Anthropic 与 Gemini 的工具调用是尽力映射；Gemini 的工具*结果*目前折叠进用户文本，等 function-calling 工作落地再补。

## Alternatives considered

- **嵌入或 fork magpie。** 否决：它是 Go 二进制，Android 无法合理承载；为使用其网关内部而 fork 一个 4 万 star 的项目是维护陷阱。hub-and-spoke 的洞察值得保留，代码不值得。
- **只做 OpenAI 兼容。** 需求方否决，选择对齐 magpie 的协议覆盖；否则 Claude 与 Gemini 官方端点将无法接入。
- **用 pub 包实现各协议。** 否决：四个 API 的覆盖都不完整，且各自带自己的 HTTP 栈；编解码器每个几百行，用夹具即可全量测试。
- **每端点一个 API key。** 否决：magpie 的自定义供应商模型是每 provider 一个 key；需要不同 key 的上游诚实地建模为多个 provider。
- **明文 key 落盘。** 设计评审中否决；加封被拉进本里程碑而非推迟。

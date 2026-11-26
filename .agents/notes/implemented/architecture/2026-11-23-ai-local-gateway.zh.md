# Agent Note：AI 网关是架在路由器之上的仅回环 OpenAI 端点

Status: implemented

[English](2026-11-23-ai-local-gateway.md) | 中文

> **部分被取代**，见
> [网关局域网 scope 与供应商草稿](../feature/2026-11-24-ai-gateway-lan-and-draft.zh.md)：
> 绑定不再由「只绑回环」一刀切——`AiGatewayConfig.scope` 可选回环或
> `0.0.0.0`，且 `enabled` 现在默认开启。
>
> **被修正**，见
> [网关密钥环](2026-11-24-ai-gateway-keys.zh.md)：单个生成的 bearer
> 令牌变为可维护的命名密钥列表；下文的端点、逐请求读取存储与绑定
> 生命周期不变。

## Problem

AI 核心（见
[2026-11-23-ai-provider-routing-codecs](2026-11-23-ai-provider-routing-codecs.zh.md)）
为应用提供了 provider、编解码器和路由器——但只有应用内部的代码能用到它们。设计的
第二个里程碑要补上让「配置一次，到处可用」成为事实的那块：只会说 OpenAI 协议的工具
——Claude Code、Codex、OpenCode、一条 curl 命令——应该能指向一个本地端点，用上所有
已启用的模型，包括路由组，而不必再配第二套密钥。

约束来自已经定下的产品决策。Provider 按设备配置、绝不共享，所以网关不能变成把这台
设备的密钥暴露给局域网的通道。它跑在一个必须随进程干净启停的 Flutter 应用里，目标是
Windows 和 Android 两个平台。

## Decision

`lib/core/ai/ai_gateway.dart` 是 `AiGateway`：一个绑定
`InternetAddress.loopbackIPv4` 的裸 `dart:io` `HttpServer`，提供两个端点——
`GET /v1/models` 和 `POST /v1/chat/completions`（含流式）。它持有一个
`AiConfigStore`、一个 `AiRouter` 和一个 token，并通过 store 在每个请求时重读配置，
所以设置页改动无需重启即生效。

- **仅回环。** 绑定更宽的地址会把 owner 的 API key 发布到局域网，这与按设备配置的决策
  相悖。默认端口 0——端点显示在界面上，而不是写进各处配置。
- **生成的 bearer 凭据**守住这个端口——最初是单个 `lt-ai-` 令牌
  （`gateway_token.dart`），现在是按
  [网关密钥笔记](2026-11-24-ai-gateway-keys.zh.md)的命名密钥列表。威胁
  不是网络——而是同一台机器上的其他进程，否则它们可以把 `providers.json`
  里存的 key 全部花掉。秘密放在 `providers.json` 旁的独立文件，因为它们
  按设计要在界面上明文展示，泄漏时不应把旁边的 provider key 一起带走。
  `sk-`/`lt-ai-` 前缀让它像 magpie 的 `sk-magpie-key` 一样一眼可辨。
- **入站只讲 OpenAI 协议。** `/v1/models` 列出已启用的 `provider/model` 引用加
  `group/<id>` 条目，正是 magpie 暴露它们的方式；`/v1/chat/completions` 把请求映射到
  规范格式（字符串或分片数组 content、工具调用与结果、`tools`/`tool_choice`
  函数定义、`max_tokens`/`top_p`/`stop`），再把
  规范流事件以 `chat.completion.chunk` 帧回写，结尾是每个 OpenAI 客户端都在等的
  `data: [DONE]`。非流式请求收到流式回复——或反过来——会跨边界折叠，而不是挂起。
  Anthropic/Gemini 入站端点有意不做：编解码层本来就双向翻译，它们只是端点而非新机制，
  等有消费者需要时再加。
- **错误沿用 OpenAI 外壳**——`{"error": {"message": ...}}`，畸形请求 400、token 缺失
  401、未知路径 404、上游失败 502——因为每个客户端都已经知道怎么打印这个形状。
- **生命周期归应用，不归存储。** `PlatformSeams` 新增 `aiDirectory` 路径
  （`<appData>/ai`），由 `profile_location.dart` 与其他持久路径用同一套规则解析——
  没有持久位置的地方为 null。`_LocalTransferAppState` 在 controller 启动后组装
  `SecretBox` + `AiConfigStore` + `AiRouter` + `AiGateway`，仅当持久化的
  `config.gateway.enabled` 为真时才绑定，并在 `dispose` 中停止服务。Android 共用同一
  份代码，但出厂默认关闭。网关启动失败被吞掉：消息功能不能依赖一个 AI 监听器。

## Consequences

- 外部工具可以原样使用应用里配置好的 provider 和路由组；唯一需要的凭据就是界面上展示
  的 token。
- `ai/` 下有 `providers.json`（密封的 key）、`secrets.key`（密封密钥）和
  `gateway_token`——全部按设备存储、不做同步、不进日志。
- 每个请求都从磁盘持久化的配置重读，与路由器现有的「每次加载」行为一致；不存在需要
  失效的设置缓存。
- 网关除了 1 MiB 的请求体上限外没有并发限制——本地工具仍可排队请求，但每个都有界，
  且只在回环上。
- 设置界面（PR3）是启用/停用与展示 token 的预定所有者；目前唯一翻转开关的方式是编辑
  `providers.json`。

## Alternatives considered

- **用 shelf 而不是裸 `dart:io`。** 仓库已为 link-transfer 服务端依赖 shelf，但那个服务
  是局域网文件传输端点；网关需要逐请求的流式控制（SSE 帧之间
  `HttpResponse.flush()`），且只有两个端点，不值得为它引入路由抽象。
- **绑定 `0.0.0.0` 做局域网共享。** 否决：会把 owner 的 API key 发布给网络上每台设备，
  与按设备信任的决策矛盾。局域网共享若将来需要，是一个独立特性，要有自己的命名 key
  和额度，照 magpie 的方式做。
- **token 放进 `providers.json`。** 否决：该文档封存 provider key，并在每次设置保存时
  重写；一个要在界面上展示的凭据应放在独立文件里，轮换和展示都不必碰密封存储。
- **现在就做 Anthropic/Gemini 入站端点。** 推迟：还没有消费者，而每个都只是架在已有
  编解码器之上的薄端点。
- **网关放进 `LocalTransferController`。** 否决：controller 管的是对端会话和传输；AI
  监听器是另一种生命周期，会把消息启动和 AI 配置耦合在一起。

# AI 模型配置与路由 + 本机网关 — 设计文档

日期：2026-11-23
状态：待评审

## Intent（意图与原因）

给 ai-local-im（Flutter 局域网 IM，Windows/Android）接入 AI 能力。产品路线分期：

1. **本期（本文档范围）**：AI 模型配置与路由——provider 管理、四种协议编解码、路由组失败转移、本机 OpenAI 兼容网关。
2. 后续迭代：App 内 AI 对话、AI 处理已有消息（总结/翻译/润色）、智能回复建议。

参考对象是 yetone/magpie（GitHub，Go，本地 AI 网关），但只借鉴其数据模型与协议覆盖思路，**不 fork、不嵌入** magpie 本体。

## 已确认的决策（来自需求方）

- AI 功能给 IM 的最终用户在 App 内使用（对话、处理消息、智能回复），不是给开发者工具用。
- **provider 各自配置、互不共享**：每台设备保存自己的 API key 与模型列表，不走 Owner 设备组共享（区别于 magpie 的 LAN sharing / remote magpie）。
- **四种协议**：对齐 magpie 的覆盖面——OpenAI Chat Completions、OpenAI Responses、Anthropic Messages、Gemini。
- **方案 B**：客户端适配层 + 本机网关端点。App 内功能走客户端层；同时在 `127.0.0.1` 暴露一个 OpenAI 兼容端点，让本机其他工具/Agent 能用 App 里已配置的 provider。
- 功能分期：对话 → 处理消息 → 智能回复，本期只做地基（配置 + 路由 + 网关），聊天 UI 不在本期。

## Goals

- provider 的增删改查与持久化：厂商预设（Anthropic/OpenAI/Google/DeepSeek/Kimi/GLM 等）+ 自定义兼容端点（OpenAI 兼容地址、Anthropic 兼容地址、Gemini 兼容地址，可只填其一或多填）+ 本机模型（Ollama/LM Studio，无 key）。
- 模型清单：`provider/model` 形式的引用；支持从 provider 拉取模型列表（各协议的 models 列表端点）。
- 规范内部消息格式（canonical format），四个协议编解码器实现「任意 provider ↔ 任意客户端」的 hub-and-spoke 互转，含 SSE 流式输出。
- 路由组（routing group）：有序成员列表，按顺序尝试，失败（限流/额度/5xx/超时）自动转移到下一成员；支持嵌套组。
- 本机网关：`127.0.0.1` 上的 HTTP 服务，对外暴露 OpenAI 兼容 API（至少 `/v1/chat/completions`、`/v1/models`），用本地 token 鉴权，复用同一套路由与编解码。
- 设置 UI：provider 列表/编辑、路由组编辑器、网关开关与接入信息展示。中英双语（l10n）。

## Non-goals（本期不做）

- 订阅登录流（Claude/ChatGPT/Copilot/Gemini 账号 OAuth）——工作量大且合规风险高，v1 只支持 API key 与自定义端点。
- 账号池、额度/用量统计、成本核算。
- 意图路由（magpie 的 auto/<model> 与意图判断模型）、按 token 预算路由。
- provider 的 LAN 共享 / 远程 magpie（与「各自配置」决策一致）。
- 网关绑定到局域网地址或对外暴露；Android 上的常驻网关（v1 网关仅桌面端常驻，Android 可做但非强制）。
- App 内聊天 UI、消息处理、智能回复（后续迭代，但数据模型要给它们留位）。
- 工具调用（function calling）的完整支持——编解码层对 tool_calls 字段做透传/尽力映射即可，不承诺语义等价。

## Anti-goals（即使技术上可行也不做）

- 不引入 magpie 二进制/源码依赖，不启动 Go sidecar（Android 无法合理承载）。
- 不为协议互转引入重量级 LLM 框架依赖；优先 dart:io HttpClient + 手写编解码，保持 `dart test` 可测。
- 不把 API key 写进日志、诊断信息或对端 IM 消息。
- 不破坏现有门禁：`dart test` 必须全绿，widget 测试进 `test_flutter/`。

## 约束

- Flutter/Dart，v1 平台 Windows + Android；开发机 Flutter 3.47.x / Dart 3.13.x。
- 现有技术栈惯例：`dart:io HttpClient` 直连（无 http/dio）、`shelf` 已在依赖中（本机 HTTP 服务有先例：`core/link_transfer/link_server.dart`）、持久化 = 应用数据目录下 JSON 文件 + 原子写（`core/history/message_store.dart` 模式）、数据目录解析走 `core/profile/profile_location.dart` + MethodChannel。
- 密钥存储：providers.json 内含 API key。Windows 文件权限保护弱；`cryptography` 包已在依赖中，可用于本地加密——具体方案留给 builder，但必须不落明文到日志。
- 工程流程（AGENTS.md 强制）：所有改动在 `develop` 切出的 worktree 分支上进行；同 PR 必须带 `.agents/notes/` 三件套 Agent Note；门禁全绿后才提 PR。

## Approaches（考虑过的方案）

### 方案 A：纯客户端适配层（已被否决）

只有 `lib/core/ai/` 客户端层，无网关。改动最小，但需求方明确要本机网关能力。

### 方案 B：客户端适配层 + 本机 OpenAI 兼容网关（已选）

- **客户端层**：canonical 格式 + 四个协议 codec + provider 存储 + 路由组 failover。App 内后续功能与网关共用此层。
- **网关层**：shelf HTTP server 绑 `127.0.0.1`，入站 OpenAI Chat Completions（v1 必做）/ Responses / Anthropic Messages / Gemini（codec 已具备，入站端点按成本逐个开放，至少 Chat Completions 与 `/v1/models`）。鉴权：启动时生成本地 token（形如 `lt-ai-…`），存于 provider 配置同级文件，UI 展示供复制；未带 token 的请求拒绝。
- **取舍**：入站只做 OpenAI Chat Completions 起步，可以让 Claude Code/Codex/OpenCode 这类填 base URL 的工具直接用；Anthropic/Gemini 入站端点是顺手的扩展而非本期承诺。
- **为什么不选更重的方案**：不做 LAN 共享（与决策冲突）、不做订阅登录（超出范围）、不嵌入 magpie（平台不允许）。

### 编解码实现方式（builder 可在此范围内细化）

- 手写 Dart codec：每协议一个文件，负责 canonical↔wire 的请求构造、SSE 流解析、错误分类。优点：零新依赖、`dart test` 可用 fixture 全覆盖、与项目风格一致。已知难点：OpenAI Responses 的有状态事件流、Anthropic 的 `content_block_*` 事件、Gemini 的 `streamGenerateContent` alt=sse。
- 备选（不推荐为默认）：引入 pub 包（如 `openai` 系）。覆盖不全且引入依赖；仅当手写某协议成本失控时再评估。

## 设计要点

### 模块布局（建议，builder 可微调命名）

```
lib/core/ai/
  ai_message.dart          # canonical：role/content/tool_calls/usage 等
  protocol/
    codec.dart             # 抽象：encodeRequest / decodeStream / decodeResponse / classifyError
    openai_chat.dart
    openai_responses.dart
    anthropic.dart
    gemini.dart
  provider.dart            # Provider 模型、模型引用 provider/model、group/<id>
  provider_store.dart      # JSON 持久化（原子写），含 apiKey、端点、启用模型
  routing_group.dart       # 有序成员、嵌套组、failover 判定
  ai_router.dart           # 解析 model ref → 逐成员尝试 → 返回流；流开始后不再 failover
  ai_gateway.dart          # shelf server：/v1/models、/v1/chat/completions（+ 可选 /v1/messages、/v1/responses）
  gateway_token.dart       # 本地 token 生成/读取
lib/ui/pages/ai_settings_page.dart（或并入 settings 结构，按现有页面惯例）
```

### Provider 数据模型（草案）

```jsonc
// <appData>/ai/providers.json
{
  "providers": [
    {
      "id": "deepseek",
      "name": "DeepSeek",
      "kind": "preset",               // preset | custom | local
      "endpoints": {                  // 按协议填，缺哪个协议就不能用哪个协议的模型
        "openaiChat": "https://api.deepseek.com/v1",
        "anthropic": null,
        "gemini": null,
        "openaiResponses": null
      },
      "apiKey": "sk-…",               // local 类可为空；每 provider 一个 key（对齐 magpie）
      "models": [                     // 拉取到的目录 + 启用标记，而非仅启用集
        { "id": "deepseek-chat", "protocol": "openaiChat", "enabled": true }
      ]
    }
  ],
  "routingGroups": [
    { "id": "main", "name": "主力", "members": ["deepseek/deepseek-chat", "group/fallback"] }
  ],
  "gateway": { "enabled": false, "port": 0 }   // port=0 表示自动选空闲端口；token 存独立文件
}
```

模型引用语法对齐 magpie：`provider/model`，路由组 `group/<id>`。成员可嵌套组。

**协议归属（builder check #1/#2 定稿）**：

- `endpoints` 的值一律是 **base URL**，不是完整端点：codec 按各协议约定自行拼路径（OpenAI 系 `/chat/completions` 等、Anthropic `/v1/messages`、Gemini `:generateContent`/`:streamGenerateContent`）。UI 对用户粘贴的地址做归一化（去尾斜杠；提示 Anthropic 根地址不带 `/v1`、OpenAI 系带 `/v1`）。
- **协议是每个 model 条目的属性**（`models[].protocol`），不是 provider 级。预设厂商的模型列表来自哪个端点，`protocol` 就是哪个；自定义端点填了多种协议时，「拉取模型列表」按所选协议拉取并写入对应 `protocol`；同名模型在多个协议下都存在时，UI 允许用户切换/新增条目。路由解析 `provider/model` 时按该条目的 `protocol` 选 codec。
- `apiKey` 每 provider 一个（对齐 magpie 的自定义供应商模型）；自定义端点若需不同 key 的上游，建成两个 provider。
- `models` 保存**已拉取的完整目录 + 每条的 enabled 标记**；「拉取模型列表」写入/更新目录但不自动启用新模型。`/v1/models` 与选择列表只暴露 `enabled: true` 的条目。
- 厂商预设清单（Anthropic、OpenAI、Google Gemini、DeepSeek、Kimi、Zhipu GLM、MiniMax、Qwen、Mistral、Groq、xAI 等）随 builder 实现时按 magpie 预设表对齐；预设的端点与 key **可覆盖**（代理/区域端点场景），kind=custom 不要求预设。

### 路由语义（对齐 magpie 的核心行为）

- 每个请求按成员顺序尝试；可重试错误（HTTP 429、5xx、连接失败、超时、额度/配额类错误信息）→ 记入该成员冷却，转下一成员。
- **SSE 流一旦开始吐字节，不再 failover**（半截回复比重试更糟）；只有首包前的失败才换成员。
- 冷却时长 builder 定（建议 60s 起步），成功后清除。
- 非流式与流式请求行为一致；`/v1/models` 返回所有 provider 的启用模型 + 路由组（magpie 同样把组暴露为可选模型）。

### 网关安全

- 只绑 `127.0.0.1`（不绑 0.0.0.0/LAN）；端口可配，`port: 0` = 自动选空闲端口。
- **生命周期**：`gateway.enabled` 持久化；为 true 时 App 启动即绑定（对齐 magpie 常驻网关的行为），UI 开关即改此字段。状态存 `providers.json` 的 `gateway` 节；**网关 token 存独立文件** `<appData>/ai/gateway_token`（与含用户 API key 的 providers.json 分离，token 泄露不连带供应商密钥）。
- Bearer token 鉴权；token 启动时生成一次、持久保存、UI 明文展示供复制（本机工具场景，与 magpie 的 `sk-magpie-key` 等价）。
- 请求体大小上限、并发上限 builder 定；不记录请求/响应正文到日志。
- Android：代码路径与桌面共用，UI 上默认关闭、可开启；不做前台服务常驻保证（v1 非强制）。

### UI 范围（本期）

- 设置/AI 页：provider 列表（增删改、测试连接、拉取模型列表）、路由组编辑器（成员排序、嵌套选择）、网关卡片（开关、地址、token、复制按钮、各客户端接入示例）。
- 视觉沿用现有设置页与 design-preview 设计语言；文案走 l10n 双语。

## Testing

- `test/`（dart test，无 widget）：codec fixture 测试（每协议至少：非流式请求构造、SSE 流解析、错误分类）；provider_store 读写与原子性；router failover（fake codec/transport 注入错误序列）；gateway token 鉴权。
- `test_flutter/`：AI 设置页 widget 测试。
- 手测：本机起网关，用 curl/OpenAI SDK 各打一次四协议 provider（至少 OpenAI 兼容 + 一个 Anthropic 端点）。

## 留给 builder 的决定

- SSE 解析的边界情况处理、usage/token 统计字段映射。
- 错误分类的具体清单（哪些 HTTP 状态/错误体算可 failover）。
- apiKey 是否本地加密及加密方案（cryptography 已在依赖）。
- 网关端口选择策略与并发/请求大小限制的具体值。
- Responses/Gemini/Anthropic 入站端点是否本期全开放（至少 Chat Completions + /v1/models 必须）。
- l10n key 命名与文案。

## Builder check 记录

reviewer（subagent）提出 6 问，全部有明确默认解，已定稿如下，无遗留「需求方专属」问题：

| # | 问题 | 定稿 |
| --- | --- | --- |
| 1 | provider 配多协议端点时，`provider/model` 用哪个 codec | 协议是每个 model 条目的属性（`models[].protocol`），预设按拉取来源推断，自定义可在 UI 切换 |
| 2 | endpoint 存 base URL 还是完整 URL | 一律 base URL，codec 按协议拼路径；UI 归一化用户输入 |
| 3 | apiKey 每 provider 还是每端点 | 每 provider 一个（对齐 magpie）；多 key 上游拆成多个 provider |
| 4 | `models` 存启用集还是目录 | 存完整目录 + enabled 标记；新拉取不自动启用 |
| 5 | 网关生命周期与状态位置 | `gateway.enabled` 持久化、enabled 时随 App 启动绑定；token 独立文件存放；Android 共用代码、默认关 |
| 6 | 预设清单与可编辑性 | 预设对齐 magpie 列表，端点与 key 可覆盖 |

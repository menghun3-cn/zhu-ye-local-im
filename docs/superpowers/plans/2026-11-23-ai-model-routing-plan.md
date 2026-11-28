# 实施计划：AI 模型配置与路由 + 本机网关

依据：`docs/superpowers/specs/2026-11-23-ai-model-routing-design.md`（已批准）
日期：2026-11-23

## 分支与 PR 策略

按 AGENTS.md：所有工作在 `develop` 切出的 worktree 分支进行。本里程碑拆成三个可独立合并的 PR，降低单 PR 体积与评审风险：

| PR | 分支 | 内容 | 依赖 |
| --- | --- | --- | --- |
| 1 | `feat/ai-core` | canonical 格式、四协议 codec、provider 存储、路由组 failover（纯 Dart，无 UI、无网关） | 无 |
| 2 | `feat/ai-gateway` | shelf 本机网关（/v1/models、/v1/chat/completions，token 鉴权） | PR1 |
| 3 | `feat/ai-settings-ui` | 设置页：provider 管理、路由组编辑器、网关卡片 | PR1（PR2 可并入或随后） |

每个 PR 同带 `.agents/notes/` 三件套 Agent Note；门禁：`verify-agent-notes.ps1`、`verify-translation-pairs.ps1`、`flutter analyze`、`dart format`、`dart test`、`flutter test test_flutter`。

## PR1 — `feat/ai-core`

### 任务

1. **`lib/core/ai/ai_message.dart`** — canonical 模型：`AiRole`（system/user/assistant/tool）、`AiContentPart`（text/image_url 预留）、`AiToolCall`、`AiUsage`、`AiMessage`、`AiChatRequest`（model ref、messages、stream、temperature 等透传字段）、`AiStreamEvent`（text_delta、tool_call_delta、usage、done、error）。
2. **`lib/core/ai/protocol/codec.dart`** — 抽象接口：
   - `encodeRequest(AiChatRequest, AiModelRef) → HttpRequestSpec`（method、url、headers、body）
   - `decodeResponse(body) → AiChatResponse`（非流式）
   - `decodeStream(LineIterator/SSE) → Stream<AiStreamEvent>`
   - `listModels() → Future<List<String>>`（可选能力）
   - `classifyError(status, body) → AiErrorKind`（fatal / retryable-quota / retryable-transient）
3. **四个 codec**：`openai_chat.dart`（/chat/completions + SSE `data:` 解析）、`openai_responses.dart`（/responses，有状态事件流——最复杂，单独仔细处理）、`anthropic.dart`（/v1/messages，`content_block_delta` 等事件、`x-api-key`+`anthropic-version` 头）、`gemini.dart`（`:streamGenerateContent?alt=sse`，`x-goog-api-key` 头）。
4. **`lib/core/ai/provider.dart` + `provider_store.dart`** — 按设计文档 schema；JSON 原子写（参照 `message_store.dart`：temp 文件 + rename + 损坏备份）；`AiModelRef` 解析（`provider/model`、`group/<id>`）。
5. **`lib/core/ai/routing_group.dart` + `ai_router.dart`** — 有序成员解析（嵌套组展开、环检测）、逐成员尝试、可重试错误冷却（默认 60s）、SSE 首字节前才可 failover。
6. **厂商预设表** `lib/core/ai/presets.dart` — 对齐 magpie 预设（Anthropic、OpenAI、Google、DeepSeek、Kimi、GLM、MiniMax、Qwen、Mistral、Groq、xAI 等），每预设给各协议默认 base URL。

### 测试（全部 `test/`，dart test）

- 每 codec：fixture JSON/SSE 文本 → canonical 断言（请求构造、流解析、错误分类三个方向）。
- `provider_store`：读写往返、原子写、坏文件恢复。
- `ai_router`：fake codec 注入错误序列验证 failover 顺序、冷却、嵌套组、环检测；流开始后不 failover。
- `AiModelRef` 解析边界。

### 验收

`dart test` 全绿；`flutter analyze` 零问题；无 UI 变更。

## PR2 — `feat/ai-gateway`

### 任务

1. **`lib/core/ai/gateway_token.dart`** — token 生成（`lt-ai-` + 随机）、`<appData>/ai/gateway_token` 读写。
2. **`lib/core/ai/ai_gateway.dart`** — shelf server 绑 `127.0.0.1`（端口读 `providers.json` 的 `gateway.port`，0=自动）：
   - `GET /v1/models` → enabled 模型 + 路由组（OpenAI 格式）
   - `POST /v1/chat/completions` → 解析请求 → `ai_router` → SSE 或 JSON 回写（canonical→openai_chat codec 出站）
   - Bearer token 校验；体大小/并发上限；不记正文日志。
   - 生命周期：`gateway.enabled` 时 App 启动绑定（在 app_controller 初始化处挂载，仿 `link_server` 的启停模式）。
3. **可选端点**（成本允许则做）：`/v1/messages`（Anthropic 入站）、`/v1/responses`。

### 测试

- `test/`：token 校验、models 列表、chat completions 端到端（fake router）、错误路径。
- 手测：`curl http://127.0.0.1:<port>/v1/chat/completions` 打真实 provider。

## PR3 — `feat/ai-settings-ui`

### 任务

1. AI 设置页（按现有 settings_page 结构）：provider 列表、新增/编辑（预设卡片 + 自定义 URL 表单）、测试连接、拉取模型列表（按所选协议）。
2. 路由组编辑器：成员增删排序、嵌套组选择。
3. 网关卡片：开关、地址、token 展示与复制、接入示例（OPENAI_BASE_URL 等）。
4. l10n 双语文案；`test_flutter/` widget 测试。

## 风险与备注

- **OpenAI Responses 协议**是四个里最复杂的（有状态事件、`response.*` 事件族）；PR1 里它单独成任务，若成本失控可降级为「v1 仅请求/响应透传、不支持该协议入站」——但 codec 本身仍要实现。
- **SSE 解析**：`dart:io HttpClient` 的 `response` 是 byte stream，需按 `\n\n` 分帧 + `data:` 行解析；UTF-8 跨 chunk 边界要处理（`utf8.decoder` + `LineSplitter` 组合或手写缓冲）。
- **apiKey 存储**：PR1 即上加密（需求方明确）。`lib/core/ai/secret_box.dart`：AES-256-GCM（`cryptography` 已在依赖），随机主密钥首次启动生成、存 `<appData>/ai/secrets.key`；`providers.json` 中 `apiKey` 字段存 `v1:<base64 nonce+ciphertext>`，读时透明解密，旧明文值兼容读入后下次写回即加密。已知边界：密钥与密文同机存放是混淆级保护，OS keystore（Windows DPAPI / Android Keystore）为后续加固项。key 不落日志。
- **Android**：网关代码共用，UI 默认关；不做前台服务。

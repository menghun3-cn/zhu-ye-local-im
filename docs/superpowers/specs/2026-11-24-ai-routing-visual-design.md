# AI 路由可视化、内置供应商与编辑器打磨 — 设计

日期：2026-11-24。基线：`feat/ai-gateway-scope`（PR #316，未合入）。

## 背景与目标

用户在测试 AI 设置页时提出五点：

1. 添加供应商时名称框应只显示占位符，名称必须由用户自己输入。
2. 参考 magpie「Routing」页的请求动画（请求经过时一只喜鹊从 agent 节点飞到
   provider 节点、返回时飞回），实现类似效果，主角换成「竹叶」。
3. 用已配置好的一个 API 做联调测试。
4. 内置两个公开免费接入——OpenCode Zen 和 Kilo——默认启用。
5. 供应商可启用/停用。

其中第 5 点经核实**已经实现**：`AiProvider.enabled` 存在，路由
（`ai_router.dart` `_call`）、网关暴露面（`exposedModelRefs`）都尊重它，
设置页列表行也已有 Switch（`ai_settings_page.dart` `_ProviderTile`）。
本设计不再改动，仅在 PR 描述中说明。

## 已核实的平台事实（2026-11-24 实测）

- **Kilo**：`https://api.kilo.ai/api/openrouter` 是 OpenRouter 兼容端点。
  `GET /api/openrouter/models` 与 `/api/openrouter/v1/models` 均 200，
  返回 `{data:[{id,...}]}`（469 个模型，OpenRouter 形状与 OpenAI `/models`
  兼容）；`POST /api/openrouter/v1/chat/completions` 用
  `Authorization: Bearer anonymous` 实测 200 返回真实补全。
  匿名免费额度约 200 req/h/IP。稳定虚拟模型：`kilo-auto/free`、
  `openrouter/free`。
- **OpenCode Zen**：`https://opencode.ai/zen/v1`，模型目录
  `GET /zen/v1/models` 匿名 200（105 个）。匿名 `Bearer public` 在本机
  实测 `/chat/completions` 与 `/responses` 均返回
  `429 FreeUsageLimitError`（按 IP 的免费额度/客户端限制，
  换模型、加 `x-opencode-client` 头结果相同）。用户确认该接入
  仍要内置默认启用——端点按用户提供的四条核对后收录三条
  （Gemini 路由是 Zen 自有格式，与本仓库 Gemini codec 的
  Google 原生路径不兼容，不收录）：
- **magpie 动画**：位于其 Web UI Routing 页，CSS/JS 实现，喜鹊沿
  agent↔provider 连线飞行；`prefers-reduced-motion` 时降级为淡入淡出。
  我们用 Flutter 重写等价物，不移植其代码。

## 设计

### A. 供应商名称：占位符 + 必填

- 新建供应商（草稿，`onDelete == null`）时名称框初始为空，
  `hintText` 显示预设名/「自定义」作为建议。
- 已有供应商编辑时名称照旧预填。
- 名称为空时「保存」按钮禁用（`onChanged` 触发 setState），
  不再走 `_collect` 里回退到 `_draft.name` 的静默兜底——
  fetch/test 不受影响（它们只用 endpoints 和 key）。

### B. 内置供应商（默认启用）

新增 `AiProviderKind.builtin`（序列化为 `"builtin"`，旧文件读到未知值
回退 `custom`，向后兼容）。

`AiConfig` 增加 `builtinsSeeded`（bool，默认 false，序列化进
`providers.json`）。`AiRuntime.open` 在组装完成后：

```
config = await store.load()
if (!config.builtinsSeeded) {
  providers += 缺失的内置项（按 id 去重）
  builtinsSeeded = true
  await store.save(config)
}
```

只播种一次：用户之后删除内置供应商不会被复活；用户改过的端点/key
不受影响（只在 id 缺失时追加）。

内置条目（写在 `presets.dart` 旁新文件 `builtin_providers.dart`）：

| id | 名称 | kind | endpoints | apiKey | 启用模型 |
|---|---|---|---|---|---|
| `opencode-zen` | OpenCode Zen | builtin | openaiChat + openaiResponses → `https://opencode.ai/zen/v1`；anthropic → `https://opencode.ai/zen` | `public` | `mimo-v2.6-flash-free`、`deepseek-v4.1-flash-free`（协议 openaiChat，取自当日实测目录；Zen 免费层恢复后用户可重新拉取全量） |
| `kilo` | Kilo | builtin | openaiChat → `https://api.kilo.ai/api/openrouter/v1` | `anonymous` | `kilo-auto/free`、`openrouter/free` |

模型启用是「尽力而为」：这两个端点的免费目录都是动态的，写死的 id
可能失效。失效表现为该模型请求报错，用户点「获取模型列表」即可换成
当日可用的免费模型——拉取结果默认禁用、手动勾选，与既有规则一致。
不在启动时做网络拉取：首启阻塞在不可控的外网超时上不值得，
内置条目的价值是「端点/key/协议已经替你填好」。

### C. 路由可视化页 + 竹叶动画

**事件源**：`AiRouter` 增加
`Stream<AiRouteEvent> get events`（broadcast）。`chat` 内部发出：

- `attempt(member, requestId)`：每个被尝试的成员（含 failover 后的下一个）；
- `served(member, requestId)`：非流式回复完整读回、或流式回复的事件流
  正常结束/出错时（用 async* 包装 `decodeStream` 的结果，在流关闭时发）；
- `failed(member, requestId)`：成员失败（retryable 或致命）。

事件带单调递增 `requestId`，并发请求不串线。事件是 best-effort
观测面：stream controller 用 broadcast、`sync: false`，订阅者异常不影响
请求路径；`chat` 本身不等待事件。

**页面**：`lib/ui/pages/ai_routing_page.dart`，从 AI 设置页加一个
「路由」入口（ListTile，图标 `Icons.hub_outlined`）push 进入。

- 左侧一个节点「请求来源」（l10n `aiRoutingSource`），右侧纵向排列
  全部 provider 节点（名称 + 启用模型数；停用的 provider 灰显、
  不画连线）。
- `CustomPaint` 画从左节点到各 provider 节点的贝塞尔连线（启用时
  高亮色，停用时灰色虚线或不画——实现时取不画，视觉更干净）。
- 每次 `attempt` 事件生成一片「竹叶」：用 `Icons.eco`/自绘叶形，
  沿连线贝塞尔路径从左节点飞到 provider 节点（约 600ms，
  easeInOut + 轻微旋转/摆动）；`served`/`failed` 时原路飞回并移除。
  流式请求在流结束前叶子停在 provider 侧——正好表达「还在路上」。
- 并发请求各自有叶子（按 requestId+member 区分）；同一 provider
  的多片叶子纵向微错开避免完全重叠。
- 底部一行状态文字显示最近事件（如
  `kilo/kilo-auto/free ✓` / `✗ 重试中`）。
- 无 provider 时显示空态文案 + 返回设置的提示。
- `MediaQuery.disableAnimations` 为真时不飞叶子，事件只更新状态文字
  （对齐 magpie 的 reduced-motion 降级）。

连线路径用固定布局计算：左节点竖直居中，右侧节点按列表均分高度，
贝塞尔控制点取水平 1/3 处，保证任何 provider 数量下曲线都平滑。

### D. l10n 新词条（中英）

`aiKindBuiltin`（内置/Built-in）、`aiRoutingTitle`（路由/Routing）、
`aiRoutingSource`（请求来源/Requests）、`aiRoutingEmpty`、
`aiRoutingLastEvent` 相关、`aiProviderNameRequired`（若用禁用按钮方案
则不需要——保存禁用已隐含；名称框 hint 复用现有 label）。

### E. 测试

- `dart test`：
  - `AiRouter` 事件流：fake transport 下断言 attempt→served /
    attempt→failed→attempt→served（failover）顺序与 member 正确；
    流式响应的 served 在流关闭时发出。
  - `AiRuntime.open` 播种：临时目录首开得到两个内置 provider 且
    `builtinsSeeded=true`；二次 open 不重复追加；用户删除内置项后
    不再复活；旧 `providers.json`（无该字段）首次打开自动补齐。
- `flutter test test_flutter`：路由页 smoke（有/无 provider 两态）。
- 联调：用已配置的 API 在本机发一次 `POST /v1/chat/completions`
  验证动画与 `servedBy`。

## Non-goals

- 不做 magpie 的「Routing recipes / smart routing / 用量统计」；
  只画「谁在被请求」。
- 不做动画的拖拽编辑、节点拖动、缩放。
- 不为 Zen/Kilo 做专项协议适配——它们都是 OpenAI 兼容，走既有
  openaiChat codec；Zen 的 Responses-only 免费模型由用户自行
  在编辑器里切协议 tab 获取。
- 不在启动时联网拉取内置模型目录（理由见 B）。

## 风险

- Zen 匿名层当前 429：内置后该 provider 的请求会失败，路由页恰好
  能把这个失败可视化（叶子飞回 + 状态 ✗），不算隐藏问题。
- `AiRouteEvent` 是新增的公开流，未来 App 内聊天接入时复用同一事件源，
  不需要第二套埋点。
- 事件流若未来消费者变多，broadcast 多播语义已保证互不干扰。

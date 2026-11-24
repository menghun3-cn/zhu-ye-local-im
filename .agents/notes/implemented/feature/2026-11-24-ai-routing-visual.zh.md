# Agent Note: 内置公共供应商、带飞叶的路由页与命名供应商编辑器

Status: implemented

[English](2026-11-24-ai-routing-visual.md) | 中文

> 扩展
> [局域网网关与草稿供应商](2026-11-24-ai-gateway-lan-and-draft.zh.md)
> 与[设置界面](2026-11-24-ai-settings-surface.zh.md)：AI 区域新增
> 首启即用供应商、实时路由视图，以及更严格的编辑器语义。

## Problem

对 AI 设置页的实际试用产生了五点修正。

「添加供应商」把名称预填为预设名，导致每个供应商都以厂商名存活，
除非用户想到去改——这个字段教了错误的默认值。灵感来源 magpie 在
请求进行中会让一只鸟沿 agent→provider 连线飞行；我们的设置页没有
任何等价物回答「此刻正在请求哪个供应商」。而触达一个可用模型的唯一路径
是：知道厂商、找到它的 key 页面、粘贴凭据——完全没有零配置路径。

## Decision

**两个公共供应商默认启用。** `aiBuiltinProviders`
（`builtin_providers.dart`）收录 OpenCode Zen 与 Kilo——带共享凭据
（`public` / `anonymous`）的端点，无需注册。`AiRuntime.open` 把它们
按 `providers.json` 里的新标记 `AiConfig.builtinsSeeded` 恰好播种一次：
id 缺失才追加，已存在不动，标记无论如何都翻转。用户删除内置项后
不会复活；改过端点的用户不会被覆盖。播种的模型列表刻意保持很小——
两个上游都在轮换免费目录，过期的 id 会在使用时报错，由编辑器的
「获取模型列表」刷新。播种时不做网络拉取：首启延迟不能取决于外部
API 的心情。

Kilo 端点 `https://api.kilo.ai/api/openrouter/v1`——实测匿名
`Bearer anonymous` 返回真实补全，模型目录在 `/models` 与
`/v1/models` 均可访问。Zen 的三条可用路由由需求方提供，并按 codec
的路径规则核对：`openaiChat`/`openaiResponses` 用
`https://opencode.ai/zen/v1`，`anthropic` 用 `https://opencode.ai/zen`
（codec 自己拼 `/v1/messages`）。Zen 的 Gemini 路由**不**播种——
它讲 Zen 自有的模型路径形状，不是 Gemini codec 发出的
Google 原生 `/v1beta` 布局。

**路由器广播自己的路径。** `AiRouter` 新增
`Stream<AiRouteEvent> events`——按具体 `provider/model` 成员发出
`attempt`/`served`/`failed`，带每次 `chat` 调用的 id，failover 的
各步骤与并发请求互不串线。流式回复只在事件流结束时才算 served；
中途离开的订阅者记为 failed，因为供应商没能答完。事件是
best-effort：broadcast controller、不等待、抛异常的订阅者拖慢不了
请求。

**路由视图画连线、放飞叶。** `AiRoutingView` 是 AI 页的第一个 tab，
占满全高——实时路由正是这个页面存在的理由，所以它打头而不是内嵌在
滚动列表里。画三列——Agent、显示 `ip:port` 的「竹叶网关」节点、
provider 节点——agent→网关与网关→provider 各画一条贝塞尔连线，每段
约为旧单跳的一半长。每个在途请求一片 `Icons.eco` 竹叶按 attempt 从
agent→网关→provider 飞出、served/failed 时飞回；叶子所在的连线在
飞行期间变虚线。位置是布局与控制器 0→1 进度的纯函数，窗口缩放免费
重锚。`MediaQuery.disableAnimations` 时不飞叶子、只留状态行——与
magpie 的减弱动效降级同义。供应商启用/停用无需新工作：
`AiProvider.enabled` 本来就管着路由与网关暴露面，设置页列表的开关
也已存在。

**provider 节点按需出现，不是全量列出。** 目录可以有几十个供应商，
全画出来会把右列挤出屏幕，所以节点只在路由事件点名它的 provider 时
出现，事后保留 20 秒（或叶子仍在飞向它时，无论流跑多久）。空闲画布
只剩 Agent 与网关——「能请求谁」在供应商 tab，「正在请求谁」在这里。

**成员健康按节点区分，不是一刀切。** `failed` 事件新增 `cooling`
标记：成员进入冷却而非彻底失败时为 true。视图维护
`member → 冷却截止` 与 `member → 最近致命错误` 两张表，按最坏优先
汇总到 provider 节点上（琥珀色「冷却中 42s」、红色「上次请求失败」
展示 30 秒），并从 `AiRouter.coolingDownUntil` 播种页面打开前已在
途的冷却——被熔断的成员显示为冷却，而不是整张图都像死了。1 秒
心跳负责让标记过期、刷新倒计时，并轮询 `AiRuntime.configVersion`
（每次 `save` 自增）与网关签名，使页面别处的编辑无需重载握手即可
重绘画布。

**名称框先问再答。** 新建供应商的名称框初始为空——预设名降级为
`hintText`——名称非空前保存按钮禁用。获取模型/测试连通不受影响：
它们只读端点与密钥。

## Consequences

- 全新安装零配置即得两个可用供应商。两者都是免费层公共端点：
  限流、目录轮换、Zen 当前的匿名 429 都是上游事实，UI 如实呈现
  （路由页会画出失败的飞行）而不是当 bug 藏起来。
- `providers.json` 新增 `builtinsSeeded`；旧文件读作 `false`，
  下次打开补齐——正确，因为它们早于该特性。
- `AiProviderKind` 新增 `builtin`；未知 kind 字符串读回仍回退
  `custom`。
- 路由页的活性完全来自 `AiRouter.events`：网关请求与未来的应用内
  聊天共用同一事件流，聊天落地时页面不需要第二套埋点。
- 飞叶是每次飞行一个 `AnimationController`——用
  `TickerProviderStateMixin` 而非单 ticker 版本，因为并发请求是真的。

## Alternatives considered

- **播种时联网拉取内置模型目录。** 否决：首启会阻塞在外部 API 的
  状态上，且答案到下次启动就过期了。固定短名单加既有拉取按钮
  诚实且即时。
- **id 缺失就复活已删除的内置项。** 否决：「只播种一次」是唯一
  尊重删除的规则。标记让这个选择成为永久事实而非推断。
- **动画做成卡片大小、嵌在设置页里。** 否决：最终交付的是完整路由
  视图作为 AI 页的第一个 tab（不是缩略图，也不是 push 的独立页）——
  magpie 已证明人们要的是节点、连线、实时飞行的全貌，而独立 tab
  把它放大到整个窗口高度。
- **预填名称、让用户自己忽略。** 被需求方否决：每个供应商都叫
  「DeepSeek」告诉用户的只是它预设自谁，说明不了实际指向哪个端点。

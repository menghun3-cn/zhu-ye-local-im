# Agent Note: 内置公共供应商、带飞行马车的路由页与命名供应商编辑器

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
各步骤与并发请求互不串线。`attempt` 在 `_call` 内、所有前置校验
通过后、`transport.send` 之前发出——因模型停用或缺端点被拒的成员
只产生 `failed`，因为请求根本没离开设备，马车不能假装跑过。流式回复只在事件流结束时才算 served；
中途离开的订阅者记为 failed，因为供应商没能答完。事件是
best-effort：broadcast controller、不等待、抛异常的订阅者拖慢不了
请求。

**路由视图画连线、放飞马车。** `AiRoutingView` 是 AI 页的第一个 tab，
占满全高——实时路由正是这个页面存在的理由，所以它打头而不是内嵌在
滚动列表里。画三列——Agent、显示 `ip:port` 的「竹叶网关」节点、
provider 节点，三者都缩放到约原来尺寸的 1.8 倍，让飞奔的马车在节点
上更醒目——agent→网关与网关→provider 各画一条贝塞尔连线，
每段刻意画短，让三列读起来像一条管线而不是三个孤岛。每个在途
请求一辆马车按 attempt 从 agent→网关→provider 跑出、
served/failed 时跑回，每段 1 秒、慢到能看清（叶子保留为网关与
品牌标志，换的只是飞行体）。出发会排在回程车后面：串行调用方在
回复落地的瞬间（即回程途中）就发出下一个请求，此时放行会让两辆
反向而行的车同屏，读起来像一次顺序交换；排队的 attempt 在最后一辆
车靠岸后重新校验并出发。去程的车仍可自由重叠，真正的并发照旧靠
`callId` 配色区分。马车是 `lib/ui/route_cart.dart` 里的
`RouteCart`/`RouteCartPainter` CustomPaint 剪影（双倍尺寸绘制）——
**去程车厢空、回程堆满货包**（五个描边货包堆成两层锥形），随行进
方向掉头。步态是 trot：对角腿对共用步相（近前+远后、近后+远前），
蹄子沿二次曲线前后摆并在中途抬起，远侧腿在身体下方用更淡的颜色，
尾巴反相摆动，车身每步一颠——每 800ms dash 循环一个步态周期。
步态时钟取共享 dash 控制器的值——墙钟驱动，回程不会倒放——
车轮辐条仍随里程转动。轮廓往「马」的方向再推了一步：弧形颈、
耳朵、颈脊鬃毛短划。排队的 attempt 若在放行前请求已结束，
会在结束事件到达时被丢弃——否则它会飞出去后永远停在 provider
端，再没有第二个结束事件把它带回家。
车所在的那一段连线才变虚线——每帧按每辆车的实时 0→1 进度
判定所在路段（t ≤ 0.5 在 agent→网关段、t > 0.5 在网关→provider
段，去回程同理），停在 provider 端或回程途中的车不会让另一段
空虚线假装还有流量。虚线图案朝车实际行进的方向滑动——回程段
反向——由只在有车在跑时重复的控制器驱动，空闲画布不耗帧。车身颜色是其
`callId` 的纯函数（品牌绿周围
4 档明度 × 2 档饱和度），并发请求可以区分，而 failover 的各
成员——同一次调用、不同 provider——保持同一颜色。位置是布局与控制器 0→1 进度的纯函数，窗口缩放免费
重锚。`MediaQuery.disableAnimations` 时不跑车、只留状态行——与
magpie 的减弱动效降级同义。供应商启用/停用无需新工作：
`AiProvider.enabled` 本来就管着路由与网关暴露面，设置页列表的开关
也已存在。

**provider 节点按需出现，不是全量列出——而且会滞留。** 目录可以有
几十个供应商，全画出来会把右列挤出屏幕，所以节点只在路由事件点名
它的 provider 时出现，距上次请求 5 分钟后才消失（或马车仍在跑向
它时，无论流跑多久）。空闲画布只剩 Agent 与网关——「能请求谁」在
供应商 tab，「正在请求谁」在这里。节点按首次请求顺序占据固定槽
位（上限 10 个），而不是纵向紧排——节点出现或消失不会让邻居滑
动，出现/消失的抖动正是「活着」和「晕车」的差别。节点卡片同时写出
两方名字：标题行是 provider 名，健康时第二行是最近一次路由事件
点名的具体模型（成员引用 `provider → modelId`，经
`model.label ?? id` 解析），无模型记录时回退为启用模型数，冷却/
失败状态出现时让位给健康信息；有马车在跑的节点还会呼吸——
品牌色光晕随共享 dash 控制器的 800ms 周期胀缩，「正在被请求」
不需要徽标，最后一辆车停稳即停。provider 或模型删除后条目在
重载时清掉。

**成员健康按节点区分，不是一刀切。** `failed` 事件新增 `cooling`
标记：成员进入冷却而非彻底失败时为 true。视图维护
`member → 冷却截止` 与 `member → 最近致命错误` 两张表，按最坏优先
汇总到 provider 节点上（琥珀色「冷却中 42s」、红色「上次请求失败」
展示 30 秒），并从 `AiRouter.coolingDownUntil` 播种页面打开前已在
途的冷却——被熔断的成员显示为冷却，而不是整张图都像死了。1 秒
心跳负责让标记过期、刷新倒计时，并轮询 `AiRuntime.configVersion`
（每次 `save` 自增）与网关签名，使页面别处的编辑无需重载握手即可
重绘画布。

**动画之下是请求日志。** 动画与列表平分页面高度，列出最近 7 天
*已完成*的请求——每条两行：第一行 `MM-dd HH:mm:ss` 独占一列、
旁边是实际应答的模型；第二行是紧凑指标行
（`2.3秒 · 首字耗时 2.1秒 · 37.4k token · 缓存 99% · 16.3 token/秒`——
速度一项是输出 token 数除以墙钟耗时，上游未拆分时回退用总量），悬停展开
未缓存输入/输出/缓存读/缓存写的精确计数。请求列表渲染在独立的
圆角、`borderStrong` 描边面板里——记录区相对画布是一个有边界的
区域，而不是直接铺在页面背景上的一条裸带；每条记录再各自是一张
`surfaceSunken` 底、`divider` 细边框的卡片，行与行一眼可分。
`AiRouter` 把每个跑完
的回复（流式以事件流结束为准；失败不留行——红色节点已经说明了）
写进 `providers.json` 旁的 `requests.json`，经由网关密钥进来的请求
会带上密钥名，每次写入按窗口裁剪并硬上限 500 行。计时用路由器自己的时钟，token 数来自
`AiUsage`——新增 `cachedTokens`，按协议各自解码
（`prompt_tokens_details`、`input_tokens_details`、
`cache_read_input_tokens`、`cachedContentTokenCount`），并以
OpenAI 形状回传给网关调用方。网关因此对每个上游都请求流式——
即使调用方要的是折叠后的整段回复：只有流式形状带首字标记与
逐块 usage，`_fullReply` 再把它装回去；非流式上游应答会让
TTFT 与 usage 永远空白。推理输出也算首字证据：各 codec 把思考
内容放到独立的 `AiStreamKind.reasoningDelta` 事件（折叠时绝不进
正文），路由器的 TTFT 时钟在首个文本、推理或工具调用事件处停表
——否则推理模型恰恰在用户等待最久的请求上显示 `—`。上游只报
total/completion 时，prompt
部分按两者之差推导，缓存命中率照常渲染。记录是 fire-and-forget：日志失败
永远到不了请求路径。视图按 `AiRequestLog.version` 重载，由同一个
1 秒心跳与 `configVersion` 一起轮询。

**名称框先问再答。** 新建供应商的名称框初始为空——预设名降级为
`hintText`——名称非空前保存按钮禁用。获取模型/测试连通不受影响：
它们只读端点与密钥。

**画布是快捷方式，不只是插画。** 点 provider 节点会跳到该供应商的
编辑器（页面为此持有显式的 `TabController`）。内容宽度低于下限时
画布横向滚动而不是把节点挤在一起；请求记录保留约 40% 的下限
（最少 120px），矮窗口不会把它压成一条缝。冷却态用主题新增的
`warning` 令牌——琥珀色表「等待」，红色留给「失败」。

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
- 每辆马车一次飞行一个 `AnimationController`——用
  `TickerProviderStateMixin` 而非单 ticker 版本，因为并发请求是真的。
- `requests.json` 是诊断日志而非计费账本：只有 served 的请求入账，
  token 数字是供应商上报了什么就记什么（缺失保持缺失，显示 `—`），
  速度是 completion tokens 除以首字之后的生成时长——没有首字
  标记时用整个耗时。

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

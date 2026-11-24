# Agent Note：AI 设置页通过同一个 AiRuntime 编辑同一份 AiConfig

Status: implemented

[English](2026-11-24-ai-settings-surface.md) | 中文

## Problem

PR1 为应用提供了 AI 核心，PR2 提供了回环网关，但屏幕上没有任何东西能够触达它们：
`providers.json` 只能手工编辑，网关开关没有对应的界面元素，而本地工具需要的 token
也无处可见。第三个里程碑就是设置界面——而有意思的决定不是页面长什么样，而是
*写路径归谁所有*。

有两个事实约束了形态。应用已有持久化惯例——JSON 文档跑在 store 抽象后面、原子写、
损坏文件移开——`AiConfigStore` 遵守这套惯例。而网关的绑定是 `gateway.enabled`
标志的副作用：只持久化标志而不动 socket，会让文档和正在运行的服务端互相矛盾——
这正是设置页绝不能制造的那种脑裂。

## Decision

**`AiRuntime`（`lib/core/ai/ai_runtime.dart`）是唯一的写路径。** 它持有
`AiConfigStore`、`AiRouter`、token 和已绑定的 `AiGateway`。`save(config)` 先持久化，
再让 socket 与标志保持一致——启用即绑定、停用即关闭；绑定失败时标志保留（用户的
决定不变，下次启动重试），而 `gateway`/`endpoint` 报告 null，让界面能说「已配置但
未监听」。`AiRuntime.open(directory)` 是纯 Dart——只用 `dart:io`——所以
`dart test` 能对着临时目录覆盖整个生命周期。

只要 `seams.aiDirectory` 存在，应用状态就打开 runtime——即使网关标志是关的，因为
设置页需要一个写标志的地方——并把它一路交给 `HomeShell` → `MyPage` →
`AiSettingsPage`。My 页只在 runtime 存在时才出现 AI 卡片，与截图卡片同一条规则：
做不了事的界面是缺席，而不是置灰。

**页面是视图，不是第二个存储。** `AiSettingsPage` 持有加载出的 `AiConfig`，每次
保存后重读；编辑一律走 `runtime.save`，绝不绕行。供应商和路由组编辑器是对话框：
改草稿、交回一个 `AiProvider`/`AiRoutingGroup`——页面在保存回调里重读文档，而不是
闭包住卡片构建时的那份拷贝，这样编辑期间落地的拉取不会被静默丢弃。

界面具体覆盖：

- **网关卡片**——启用开关；启用期间端点和 `lt-ai-` token 是只读可复制字段（经
  `seams.clipboard` 复制、用 `TopToast` 提示，与其他拒绝提示同一风格）。
- **供应商**——预设选择器（`aiProviderPresets` 目录）或自定义端点；编辑器有名称、
  API 密钥（密码框，提示本地模型可留空）、每个协议一行的基础地址、以及带逐模型
  启用开关的模型目录。「获取模型列表」调用新增的
  `AiRouter.fetchModels(provider, protocol)`——它接收 provider 对象，因此能对着
  *未保存*的端点修改去拉取；拉到的 id 以禁用状态并入目录并保留已有的启用标记——
  刷新不会静默扩大网关暴露面。
- **路由组**——名称加有序成员列表，支持上移/下移，因为顺序*就是*故障转移顺序。
  成员选择器提供 `config.exposedModelRefs()` 减去自身。
- **删除**会移除供应商*以及*所有以 `provider/` 为前缀的组成员——悬空引用会让它
  被排进的每个请求都失败，比悄悄变短的列表更糟。

## Consequences

- 拨动网关开关无需重启应用即可绑定或释放端口；端点和 token 就在屏幕上，可直接粘贴
  给客户端。
- `AiRouter.listModels(providerId, …)` 继续服务已存储的供应商；
  `fetchModels(provider, …)` 服务编辑器的草稿。两者共用一条代码路径。
- AI 卡片的摘要（「网关开/关」）读的是 `runtime.gateway`，只在重建后才新鲜——可以
  接受，因为从子页返回时卡片列表会重建。
- 新增约 45 个 l10n 词条，中英文 ARB 都已补齐，生成的本地化文件按 `l10n.yaml`
  重新生成并随提交入库。
- 依然按设计缺席：应用内 AI 聊天、消息处理、智能回复——这套配置就是为它们存在的。

## Alternatives considered

- **网关生命周期放进设置页。** 否决：socket 必须在用户打开设置之前就存在，而页面
  持有的服务会随页面消亡。`AiRuntime` 以应用生命周期为界持有它。
- **让设置字段独立于网关标志编辑 `providers.json`。** 否决：即上文的脑裂。一处
  `save` 让文档与 socket 保持同步。
- **每个关注点单独一页**（供应商页、组页、网关页）。v1 否决：My 页的子页模式已经
  提供了带返回键的单一界面，为约 45 个字段做三页导航得不偿失。
- **只对已持久化的供应商提供拉取模型。** 否决：编辑器的意义就在于先改错的端点
  *再*拉取；`fetchModels` 接收草稿 provider 对象正是让这件事诚实的关键。
- **拉到的模型自动启用。** 否决，与 store 文档记载的规则一致：启用必须显式，
  刷新才不会扩大暴露面。

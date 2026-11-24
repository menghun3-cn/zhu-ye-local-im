# Agent Note：AI 网关默认开启并可服务局域网；供应商草稿在保存前不落盘

Status: implemented

[English](2026-11-24-ai-gateway-lan-and-draft.md) | 中文

> 修订
> [仅回环的网关](2026-11-23-ai-local-gateway.zh.md)：绑定不再由「只绑
> 127.0.0.1」一刀切——scope 成为持久化设置；开关默认值也改为开。

## Problem

AI 设置界面的首次实际使用提出了两条修正。

网关最初默认关闭且仅回环。「默认关闭」让「配置一次，到处可用」变成了
需要先知道网关存在的第二步发现；「仅回环」是正确的默认值却不是正确的
上限——局域网里第二台机器想用同一批供应商时，除了手改 `providers.json`
没有任何办法。

供应商编辑器有同类但更隐蔽的问题：选预设或「自定义」会在编辑器打开
之前就把新供应商写进 `providers.json`，于是即使取消对话框，供应商也
已经留下了——界面替用户做了决定。

## Decision

**网关 scope 是持久化设置，且默认开启。** `AiGatewayConfig` 新增
`scope`（`AiGatewayScope.loopback` | `lan`），`enabled` 在构造函数与
`fromJson` 中都默认 `true`——新装的应用启动即绑回环、用首选端口
（`AiGatewayConfig.defaultPort`，被占用时回退临时端口）；
`gateway` 节缺失时按开处理。回环暴露在生成的 bearer token 之后风险
为零，token 文件本来就是为此存在的。

**局域网是可选项，且指 `0.0.0.0`，不是第二个 socket。** 绑定
`InternetAddress.anyIPv4` 用一个监听者同时应答 `127.0.0.1` 和所有
局域网地址——这正是「包含本机和它的 IP」的要求。`AiGateway` 在绑定时
枚举非回环 IPv4 接口（`NetworkInterface.list`，失败降级为空列表），
设置卡片才能为每个地址打印一条可复制的端点。`dart:io` 无法区分虚拟
网卡与物理网卡——Hyper-V `vEthernet`、VMware、VirtualBox 接口都报为
以太网——所以列表会过滤已知虚拟适配器名称和 VirtualBox 默认的
`192.168.56.0/24` 主机网段；改名后的虚拟网卡仍可能出现，但代价只是
多一行端点，绑定本身不受影响，因为 socket 无论如何都是 `0.0.0.0`。
留下的列表再按 RFC1918 网段排在 overlay 网段（Tailscale 的
100.64/10、VPN）之前排序——接口枚举顺序是任意的，overlay 网卡经常
排在最前，而局域网对端真正拨打的是私网地址；第一条就是路由节点
对外宣称的网关地址。卡片提供回环/局域网
`SegmentedButton`，始终显示本机端点，局域网 scope 下为每个发现的
地址追加一行 `http://<lan-ip>:<port>/v1`，并提示令牌是链路上唯一的
凭据。

**scope 或端口变化会触发重绑。** `AiRuntime` 现在记住运行中服务器所
绑定的 `AiGatewayConfig`；`enabled`/`port`/`scope` 任一不同的保存会
先停旧 socket 再绑新的。此前 `running != null` 会让所有 enabled 保存
直接短路——scope 切换会静默继续服务回环。

**添加供应商在保存前只是草稿。** `_addProvider` 不再预持久化预设骨架，
而是在内存中的 `AiProvider` 上打开编辑器，由 `_saveProvider` 既有的
追加路径在用户确认时才写盘。未持久化的草稿不显示删除按钮——没有
可删的东西——通过给编辑器对话框的 `onDelete` 传 null 实现。

## Consequences

- 每次安装从首次启动就监听回环。token 在绑定前生成，是唯一凭据；
  本机进程仍能从应用数据目录读到 `gateway_token`——与读
  `providers.json` 同属一个暴露等级，已接受，因为两个文件都是
  per-user 应用数据。
- 局域网模式把端点发布到所有接口，包括 `0.0.0.0` 覆盖的 VPN 与虚拟
  网卡。这是该模式的明示代价；按接口分别绑定因没有消费者而被否决。
- `providers.json` 的 `gateway` 节新增 `scope` 字符串；此前写入的
  文件读回为 `loopback` 及其存储的 `enabled`——除了整个节缺失的情况，
  现在按开处理。功能尚未交付用户，无需迁移。
- 取消添加供应商对话框不再改动 `providers.json`；`_uniqueProviderId`
  的 slug 只在保存时占用，两个被取消的草稿不会互相冲突。

## Alternatives considered

- **网关保持默认关闭。** 被需求方否决：这个功能存在的意义就是被使用，
  回环+token 不构成暴露。代价只是一个监听端口和一个文件。
- **给每个局域网接口分别绑定。** 否决：`0.0.0.0` 已经应答全部接口加
  回环；枚举并逐个绑定引入了接口晚于绑定出现等失败模式，却没有行为
  收益。
- **局域网用第二个端口。** 否决：两个监听者意味着两个要展示的端口、
  两份令牌的困惑，且没有隔离收益——同一进程、同一存储、同一令牌。
- **草稿自动保存但标记为未完成。** 否决：列表里一个填了一半的供应商
  比没有更糟——它会出现在 `/v1/models` 的对话和组选择器里，仿佛
  真实存在。

# Agent Note: 分享链接下载不再被文件名卡死

Status: implemented

[English](2026-11-10-share-link-download-survives-any-filename.md) | 中文

## Problem

在浏览器里打开分享链接可能在返回任何内容之前就死掉。
`_serveDownload` 把文件名直接插值进 `Content-Disposition` 响应头，而
HTTP 头值至多是 latin-1：像 `报告 final.pdf` 这样的名字会让
`headers.set` 抛出 `FormatException`。异常发生在任何响应字节写出之前，
`HttpRequest` 始终没有被关闭，接收方浏览器报「打不开」——链接本身是
完全有效的。

同一条路径上还有两个较小的缺陷：`/info/` 手工拼 JSON，名字里带 `"`
或控制字符会产出无法解析的输出；处理器里任何异常都会让请求挂起而
不是返回错误。

## Decision

`Content-Disposition` 改由 `_contentDisposition` 构造：UTF-8 文件名
按 RFC 5987 `filename*` 参数做百分号编码——attr-char 字节原样保留，
其余一律 `%XX`——`filename` 携带 ASCII 兜底名，其中 `"`、`\` 与不可
打印字符替换为 `_`。下载同时用文件 stat 设置 `Content-Length`，响应
不再依赖 chunked 结束来收尾。

`/info/` 的响应体改走 `jsonEncode`，文件名里有什么都能正确转义。
`_handleRequest` 则把整个分发包进 try/catch：处理器抛错时返回 500 并
关闭响应——服务器看得懂的请求，绝不该得到一条死连接。

`start()` 还不再上报「请求的」端口：`preferredPort: 0`（或任何落到
其它端口的绑定）时 `actualPort` 会报 0，而 socket 实际监听的是临时
端口，`createLink` 会生成 `http://<ip>:0/download/<token>` 这种链接。
现在 `actualPort` 始终读 `_server.port`。

## Consequences

- 中日韩字符、emoji 或任何非 latin-1 名称的文件链接都能正常下载；
  支持 `filename*` 的浏览器（目前全部）保存真实文件名，其余退回净化
  后的 `filename`。
- 全是非 ASCII 的名字退化为下划线兜底名而不是失败；`filename*` 仍携
  带真实名字。
- 处理器 bug 现在表现为接收方能看到的 500，而不是挂到超时的连接。
- `LinkTransferServer(preferredPort: 0)` 可以用于测试，生成的链接
  携带真实绑定端口。

## Alternatives considered

**直接剥掉非 ASCII 字符。** 否决：这等于「修好」崩溃的同时让每个
中文名文件在接收方那里静默变成下划线——比正确实现 `filename*` 更差
的产品结果，而编码是已有标准而非自创机制。

**只在 `headers.set` 周围加 try/catch。** 否决：同样的「抛错即挂起」
存在于每个处理器（`/info/` 的 JSON、流式传输失败），所以防护应该
放在分发边界，一处 catch 覆盖全部。

**让 `/download/<token>` 返回索引页而不是文件。** 否决：现有契约——
打开链接即下载——在所有浏览器和聊天应用里都最简单可用；索引页的
token 提取脚本本来也只在 `/` 上运行过。

## Testing

`test/link_transfer/link_server_test.dart` 在临时端口上跑真实服务
器并通过 HTTP 断言：ASCII 下载保留文件名；非 latin-1 名称返回 200、
头里带 `filename*` 参数且不含原始非 ASCII；`/info/` 对中文名返回可解
析 JSON；未知 token 返回 404。非 latin-1 用例在修复前的代码上会以
现场复现的 `FormatException` 失败。

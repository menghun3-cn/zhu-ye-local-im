# Agent Note: A download that went to the blocked host

Status: implemented

[English](2026-10-13-a-download-that-went-to-the-blocked-host.md) | 中文

## Problem

有人在一个正在运行的版本上点了「关于」页的「下载并更新」，得到的是「下载没有完成。请检查网络后重试。」——`UpdateInstallFailure.download`。而就在同一张卡片上，「检查更新」刚刚回答过「有新版本 v0.1.2。」。正是这一前一后，让这件事成了一条缺陷而不是一句关于网络的陈述：**本程序**能连上 GitHub，却拿不到那个文件。

两者是两个主机，而本程序此前从未注意到这件事。问题问在
`api.github.com/repos/…/releases/latest`（`GitHubUpdateChecker`，`update_check.dart`）；文件取在资产的 `browser_download_url` 上，也就是
`github.com/…/releases/download/<tag>/<file>`（`_download`，`update_install.dart`）。在开发机上对着真实的 `v0.1.2` 发布实测，代理变量全部清空，使被测的那份代码与「双击启动的构建」处在同样的隔离状态：

| 请求 | 结果 |
| --- | --- |
| `api.github.com` 上的 latest-release 接口 | 200，`tag_name` 为 `v0.1.2` |
| `github.com/…/releases/download/v0.1.2/LocalTransfer-0.1.2-windows-x64-portable.zip` | 一直没有响应：在请求允许的 15 秒后 `TimeoutException` |
| 同一个资产的 API 地址（`…/releases/assets/636200087`）配 `Accept: application/octet-stream` | 200，13,375,776 字节，sha256 `b4e6cbd5…17294` —— 与发布方公布的校验值一致，即逐字节就是那个产物 |
| 上面任意一条，经由可用的 HTTP 代理 | 200，整个文件 |

于是失败是精确的：**本程序问问题的主机连得上，而它取答案的主机连不上。** 检查永远成功，安装永远做不到，重试改变不了其中任何一件。

有三件事让这个结论一直没有露面：

- **用户看到的那句话把责任指向了网络，而网络是好的。** 对一个连接掉了的人说「请检查网络后重试」是对的，对一个连接好着、只是地址被拒的人说这句话是错的——它引导人去做的，恰恰是唯一帮不上忙的那件事。
- **所有失败都收敛成了同一个名字。** `_download` 里的 `on Object` 是刻意的——`UpdateInstallFailure.download` 是对「没取到」最诚实的回答——但它同时意味着：被拒的主机、超时、404，在屏幕上和任何报告里都分不出来。
- **仓库里从没有任何东西跑过这条路径。** 六道门禁不会去下载一个发布产物，也写不出这样一条测试：`test/` 不许用网络。这条下载第一次被真正执行，就是用户在已发布的版本上按下了那个按钮。

## Decision

**一个发布文件有两个地址，两个都试。** `UpdateAsset` 现在除了原有的 `browser_download_url`，还带上 `apiUrl`——资产自己的 `url` 字段，一个 `api.github.com` 地址——而 `downloadAddresses(asset)` 按「API 地址在前」返回二者，并去重：

```dart
List<String> downloadAddresses(UpdateAsset asset) {
  final addresses = <String>[];
  final apiUrl = asset.apiUrl;
  if (apiUrl != null && apiUrl.isNotEmpty) addresses.add(apiUrl);
  if (asset.url.isNotEmpty && !addresses.contains(asset.url)) {
    addresses.add(asset.url);
  }
  return addresses;
}
```

`_download` 依次走这个列表，每次尝试用一个独立的 `HttpClient`，哪个地址把整个文件交齐就返回。

**API 地址排在第一，而它不是「兜底」。** 它正是检查那一步**已经**连上过的主机——一个走到「愿意安装」这一步的副本，已经证明了自己到得了 `api.github.com`——所以这个顺序让下载恰好在「检查能通」的那些网络上也能通，不需要任何配置，也用不着先失败一次。把该地址从「一份文件的描述」变成「那个文件」的是 `getUrl` 配上的 `Accept: application/octet-stream`；下载地址会忽略这个头，于是一种请求形态同时服务两者。

**200 还不够：公布的字节数在校验值之前先核一遍。** 被拒是响亮的那种失败，安静的那种是中间盒子用 200 回答了它自己的一页内容。没有字节数这一道，那种回答就会终止整次尝试，第二个地址永远轮不到；有了它，长度不对的地址和什么都没给的地址被同样对待。文件**对不对**仍然由校验值裁决——字节数只决定要不要继续试。

**失败的名字和它那句话都没变。** 两个地址都失败仍然是 `UpdateInstallFailure.download`，仍然是「下载没有完成。请检查网络后重试。」要再说第三句话，得是一句用户能据此行动的话，而「提供文件的那个主机拒绝了这台机器，另一个也是」讲的是本程序的管路，不是接下来该怎么办。

## Alternatives considered

**只用 API 地址取。** 否决：那是靠让整条链路依赖同一个主机来修好这一个网络。一个过滤 `api.github.com`、放行 `github.com` 的网络——正好相反的一种配置，也一样容易想象——就会彻底装不了，而它现在检查与安装都没问题。两个地址的代价是一个纯函数加一个循环。

**保留唯一地址，重试它。** 否决：重试一个被拒的地址，正是用户已经做过两次的事，而且是本程序提示他做的。它不可能有用。

**读本机的代理设置。** 这次不做，但值得在有证据时回头看。Dart 的 `HttpClient` 本来就会从 `http_proxy` / `https_proxy` / `no_proxy` 解析代理——`findProxyFromEnvironment` 就是它自己 `findProxy` 的默认值——上表最后一行之所以成立正是靠这一点。它不读的是 Windows 注册表里的 WinINET 配置，而在系统设置里配了代理、又靠双击启动构建的人，手上恰恰是那个。要读它就得读注册表或者在原生侧动手，而这是本机自己的配置；何况它修不了这条缺陷——本次实测到的失败发生在完全没有配代理的情况下。

**改走镜像发布。** 否决：本程序不带后端，只发布在源码本来就在的地方。第三方 GitHub 前端代理是横在用户与发布之间的别人的机器，而 API 自己的资产地址根本不是第三方——它就是同一个 GitHub，只不过走的是那个答得出来的名字。

**告诉用户去点「打开下载页」。** 否决：浏览器在同一台机器上，到的是同一批主机；报告这件事的人，本来就是从卡片上把地址抄走的。

## Consequences

- **这台机器上的下载现在通了，而且字节就是发布方公布的那些。** 一个用完即弃的探针脚本手动对着真实发布跑了一遍——`test/` 不许用网络，所以套件里没有任何东西能充当这个证据——在没有代理配置的情况下经 API 地址取
  `LocalTransfer-0.1.2-windows-x64-portable.zip`：200，重定向到
  `release-assets.githubusercontent.com`，13,375,776 字节，sha256
  `b4e6cbd5…17294`——与发布元数据里那个校验值相等。安装器现在优先走的那条路，就是被测出来能通的那条。
- **到 `release-assets.githubusercontent.com` 那一跳依然存在。** API 回 302 到那个主机，由 Dart 跟随；产物并不是从 `api.github.com` 本身回来的。本网络到得了它，而一个在放行 `api.github.com` 的同时封掉它的网络会让两个地址一起失败——那是一种可能的配置，也正是不可能从这里核实的一种。换到的是：要被拒的是两个**主机名**，而不是一个。
- **第一次尝试是 API 会计数的一次请求，第二次是一次重定向。** 检查一次再安装一次到不了任何限流，这件事也没有用固定名别名来做——能拿校验值核的只有带版本号的那个产物。
- **字节数守卫是安装器新掌握的一条信息。** 长度与发布方公布的不符的回答，现在成了「去试另一个地址」的理由，而不是「把下载丢掉」的理由；两个都失败时用户看到的那句话没变，所以这件事会一直看不见，直到它救下一次下载的那天。
- **六道门禁仍然看不见这条路径。** `test/ui/update_install_test.dart` 现在覆盖了那个决策——哪个地址在前、第一个被拒或答得太短时会不会走到第二个、两个都失败是否仍是同一个失败——用的是它自己临时起的 loopback 服务器。门禁覆盖不到的是：GitHub 真实的地址是否真如这里实测的那样表现；那正是上面那个探针的用途，而它靠手工运行。

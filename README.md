# 局域网传输工具（Local Transfer）

一款点对点的局域网传输工具，用于在局域网内的设备之间传输文本、文件和剪贴板内容。无需服务器、无需账号、无需云端。

- 支持平台（v1）：Windows、Android
- 产品术语表：[CONTEXT.md](CONTEXT.md)
- 仓库约定（分支、提交、质量门禁）：[AGENTS.md](AGENTS.md)
- 架构与平台决策：[.agents/notes/](.agents/notes/)
- 基于真实硬件验证的平台事实：[docs/](docs/)

## 截图

> 注意：截图中已对敏感信息（如 IP 地址、设备名称等）进行打码处理。

![局域网传输工具首页](design-preview/_shots/index.png)

![设备列表](design-preview/_shots/device.png)

![会话界面](design-preview/_shots/conversation.png)

![文件传输](design-preview/_shots/transfers.png)

![剪贴板同步](design-preview/_shots/clipboard.png)

![设置界面](design-preview/_shots/settings.png)

## 开发

开发环境需要当前稳定版 Flutter（3.47.x / Dart 3.13.x）。

`sh
flutter pub get
flutter analyze
dart format --set-exit-if-changed .
flutter test
`

Windows 和 Android 构建检查：

`sh
flutter build windows --debug
flutter build apk --debug
`
1 + # 局域网传输工具（Local Transfer）
2 + 
3 + 是一款点对点的局域网传输工具，用于在局域网内的设备之间传输文本、文件和剪贴板内容。无需服务器、无需账号、无需云端。
4 + 
5 + - 支持平台（v1）：Windows、Android
6 + - 产品术语表：[CONTEXT.md](CONTEXT.md)
7 + - 仓库约定（分支、提交、质量门禁）：[AGENTS.md](AGENTS.md)
8 + - 架构与平台决策：[.agents/notes/](.agents/notes/)
9 + - 基于真实硬件验证的平台事实：[docs/](docs/)
10 + 
11 + ## 截图
12 + 
13 + > 注意：截图中已对敏感信息（如 IP 地址、设备名称等）进行打码处理。
14 + 
15 + ![首页](design-preview/_shots/index.png)
16 + 
17 + ![设备列表](design-preview/_shots/device.png)
18 + 
19 + ![会话界面](design-preview/_shots/conversation.png)
20 + 
21 + ![文件传输](design-preview/_shots/transfers.png)
22 + 
23 + ![剪贴板同步](design-preview/_shots/clipboard.png)
24 + 
25 + ![设置界面](design-preview/_shots/settings.png)
26 + 
27 + ## 开发环境
28 + 
29 + 开发环境要求 Flutter 版本 >= 3.47.x 和 Dart 版本 >= 3.13.x。
30 + 
31 + 常用命令：
32 + ```sh
33 + flutter pub get
34 + flutter analyze
35 + dart format --set-exit-if-changed .
36 + flutter test
37 + ```
38 + 
39 + Windows 和 Android 调试构建检查：
40 + 
41 + ```sh
42 + flutter build windows --debug
43 + flutter build apk --debug
44 + ```
1 + # 局域网传输工具（Local Transfer）
2 + 
3 + 是一款点对点的局域网传输工具，用于在局域网内的设备之间传输文本、文件和剪贴板内容。无需服务器、无需账号、无需云端。
4 + 
5 + - 支持平台（v1）：Windows、Android
6 + - 产品术语表：[CONTEXT.md](CONTEXT.md)
7 + - 仓库约定（分支、提交、质量门禁）：[AGENTS.md](AGENTS.md)
8 + - 架构与平台决策：[.agents/notes/](.agents/notes/)
9 + - 基于真实硬件验证的平台事实：[docs/](docs/)
10 + 
11 + ## 截图
12 + 
13 + > 注意：截图中已对敏感信息（如 IP 地址、设备名称等）进行打码处理。
14 + 
15 + ![首页](design-preview/_shots/index.png)
16 + 
17 + ![设备列表](design-preview/_shots/device.png)
18 + 
19 + ![会话界面](design-preview/_shots/conversation.png)
20 + 
21 + ![文件传输](design-preview/_shots/transfers.png)
22 + 
23 + ![剪贴板同步](design-preview/_shots/clipboard.png)
24 + 
25 + ![设置界面](design-preview/_shots/settings.png)
26 + 
27 + ## 开发环境
28 + 
29 + 开发环境要求 Flutter 版本 >= 3.47.x 和 Dart 版本 >= 3.13.x。
30 + 
31 + 常用命令：
32 + ```sh
33 + flutter pub get
34 + flutter analyze
35 + dart format --set-exit-if-changed .
36 + flutter test
37 + ```
38 + 
39 + Windows 和 Android 调试构建检查：
40 + 
41 + ```sh
42 + flutter build windows --debug
43 + flutter build apk --debug
44 + ```
1 + # 局域网传输工具（Local Transfer）
2 + 
3 + 是一款点对点的局域网传输工具，用于在局域网内的设备之间传输文本、文件和剪贴板内容。无需服务器、无需账号、无需云端。
4 + 
5 + - 支持平台（v1）：Windows、Android
6 + - 产品术语表：[CONTEXT.md](CONTEXT.md)
7 + - 仓库约定（分支、提交、质量门禁）：[AGENTS.md](AGENTS.md)
8 + - 架构与平台决策：[.agents/notes/](.agents/notes/)
9 + - 基于真实硬件验证的平台事实：[docs/](docs/)
10 + 
11 + ## 截图
12 + 
13 + > 注意：截图中已对敏感信息（如 IP 地址、设备名称等）进行打码处理。
14 + 
15 + ![首页](design-preview/_shots/index.png)
16 + 
17 + ![设备列表](design-preview/_shots/device.png)
18 + 
19 + ![会话界面](design-preview/_shots/conversation.png)
20 + 
21 + ![文件传输](design-preview/_shots/transfers.png)
22 + 
23 + ![剪贴板同步](design-preview/_shots/clipboard.png)
24 + 
25 + ![设置界面](design-preview/_shots/settings.png)
26 + 
27 + ## 开发环境
28 + 
29 + 开发环境要求 Flutter 版本 >= 3.47.x 和 Dart 版本 >= 3.13.x。
30 + 
31 + 常用命令：
32 + ```sh
33 + flutter pub get
34 + flutter analyze
35 + dart format --set-exit-if-changed .
36 + flutter test
37 + ```
38 + 
39 + Windows 和 Android 调试构建检查：
40 + 
41 + ```sh
42 + flutter build windows --debug
43 + flutter build apk --debug
44 + ```
1 + # 局域网传输工具（Local Transfer）
2 + 
3 + 是一款点对点的局域网传输工具，用于在局域网内的设备之间传输文本、文件和剪贴板内容。无需服务器、无需账号、无需云端。
4 + 
5 + - 支持平台（v1）：Windows、Android
6 + - 产品术语表：[CONTEXT.md](CONTEXT.md)
7 + - 仓库约定（分支、提交、质量门禁）：[AGENTS.md](AGENTS.md)
8 + - 架构与平台决策：[.agents/notes/](.agents/notes/)
9 + - 基于真实硬件验证的平台事实：[docs/](docs/)
10 + 
11 + ## 截图
12 + 
13 + > 注意：截图中已对敏感信息（如 IP 地址、设备名称等）进行打码处理。
14 + 
15 + ![首页](design-preview/_shots/index.png)
16 + 
17 + ![设备列表](design-preview/_shots/device.png)
18 + 
19 + ![会话界面](design-preview/_shots/conversation.png)
20 + 
21 + ![文件传输](design-preview/_shots/transfers.png)
22 + 
23 + ![剪贴板同步](design-preview/_shots/clipboard.png)
24 + 
25 + ![设置界面](design-preview/_shots/settings.png)
26 + 
27 + ## 开发环境
28 + 
29 + 开发环境要求 Flutter 版本 >= 3.47.x 和 Dart 版本 >= 3.13.x。
30 + 
31 + 常用命令：
32 + ```sh
33 + flutter pub get
34 + flutter analyze
35 + dart format --set-exit-if-changed .
36 + flutter test
37 + ```
38 + 
39 + Windows 和 Android 调试构建检查：
40 + 
41 + ```sh
42 + flutter build windows --debug
43 + flutter build apk --debug
44 + ```
1 + # 局域网传输工具（Local Transfer）
2 + 
3 + 是一款点对点的局域网传输工具，用于在局域网内的设备之间传输文本、文件和剪贴板内容。无需服务器、无需账号、无需云端。
4 + 
5 + - 支持平台（v1）：Windows、Android
6 + - 产品术语表：[CONTEXT.md](CONTEXT.md)
7 + - 仓库约定（分支、提交、质量门禁）：[AGENTS.md](AGENTS.md)
8 + - 架构与平台决策：[.agents/notes/](.agents/notes/)
9 + - 基于真实硬件验证的平台事实：[docs/](docs/)
10 + 
11 + ## 截图
12 + 
13 + > 注意：截图中已对敏感信息（如 IP 地址、设备名称等）进行打码处理。
14 + 
15 + ![首页](design-preview/_shots/index.png)
16 + 
17 + ![设备列表](design-preview/_shots/device.png)
18 + 
19 + ![会话界面](design-preview/_shots/conversation.png)
20 + 
21 + ![文件传输](design-preview/_shots/transfers.png)
22 + 
23 + ![剪贴板同步](design-preview/_shots/clipboard.png)
24 + 
25 + ![设置界面](design-preview/_shots/settings.png)
26 + 
27 + ## 开发环境
28 + 
29 + 开发环境要求 Flutter 版本 >= 3.47.x 和 Dart 版本 >= 3.13.x。
30 + 
31 + 常用命令：
32 + ```sh
33 + flutter pub get
34 + flutter analyze
35 + dart format --set-exit-if-changed .
36 + flutter test
37 + ```
38 + 
39 + Windows 和 Android 调试构建检查：
40 + 
41 + ```sh
42 + flutter build windows --debug
43 + flutter build apk --debug
44 + ```
1 + # 局域网传输工具（Local Transfer）
2 + 
3 + 是一款点对点的局域网传输工具，用于在局域网内的设备之间传输文本、文件和剪贴板内容。无需服务器、无需账号、无需云端。
4 + 
5 + - 支持平台（v1）：Windows、Android
6 + - 产品术语表：[CONTEXT.md](CONTEXT.md)
7 + - 仓库约定（分支、提交、质量门禁）：[AGENTS.md](AGENTS.md)
8 + - 架构与平台决策：[.agents/notes/](.agents/notes/)
9 + - 基于真实硬件验证的平台事实：[docs/](docs/)
10 + 
11 + ## 截图
12 + 
13 + > 注意：截图中已对敏感信息（如 IP 地址、设备名称等）进行打码处理。
14 + 
15 + ![首页](design-preview/_shots/index.png)
16 + 
17 + ![设备列表](design-preview/_shots/device.png)
18 + 
19 + ![会话界面](design-preview/_shots/conversation.png)
20 + 
21 + ![文件传输](design-preview/_shots/transfers.png)
22 + 
23 + ![剪贴板同步](design-preview/_shots/clipboard.png)
24 + 
25 + ![设置界面](design-preview/_shots/settings.png)
26 + 
27 + ## 开发环境
28 + 
29 + 开发环境要求 Flutter 版本 >= 3.47.x 和 Dart 版本 >= 3.13.x。
30 + 
31 + 常用命令：
32 + ```sh
33 + flutter pub get
34 + flutter analyze
35 + dart format --set-exit-if-changed .
36 + flutter test
37 + ```
38 + 
39 + Windows 和 Android 调试构建检查：
40 + 
41 + ```sh
42 + flutter build windows --debug
43 + flutter build apk --debug
44 + ```

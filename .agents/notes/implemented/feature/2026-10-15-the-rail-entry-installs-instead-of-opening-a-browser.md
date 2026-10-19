# Agent Note: The rail entry installs instead of opening a browser

Status: implemented

English | [中文](2026-10-15-the-rail-entry-installs-instead-of-opening-a-browser.zh.md)

Partially supersedes [an update entry pinned under the rail](2026-10-12-an-update-entry-in-the-rail.md),
which added this button and had it open a browser: what a press *does* here is the
opposite of what that note decided, and the two are cross-linked for that reason.
Everything that note says about where the entry sits and why it is pinned is
unchanged and still current.

## Problem

左侧菜单（`NavigationRail`）最下方有一个「更新」按钮：发现新版本时出现，鼠标悬停显示版本号。它是这个版本唯一
一个**不请求就出现**的升级入口，本意是让用户在自己想到要去查之前就知道有新版本。

但它此前做的事情只是 `LinkResolution.opener.open(url)` —— 打开浏览器跳到下载页。用户的原话是
「当左侧菜单最下面出现更新按钮，点击时自动安装，不要跳到下载页面」。

这不是一个细节。它把一件事分成了两步：按钮告诉用户有新版本，用户还要自己去下载页、下载、解压、替换、
重启。而这个应用里**已经有完整的安装实现** —— `lib/ui/update_install.dart` 的 `UpdateInstaller`
（portable 自替换 + installer 静默升级两条路径）与 About 页 `_install()` 的下载/校验/解压/确认/交接
流程，`packaging/local_transfer.iss` 的 `[Run]` 里也有 `/update` 触发的重启条目。也就是说：能力早就
有了，入口没接上。

### 第二件事：更新完了程序要自己回来

用户说「如果是更新前工具是运行的，更新完后也启动」。

这一条**本来就是实现的**，不需要改：
- portable（绿色包）：`update_handoff.dart` 的 `UpdateHandoffScreen._finish()` 在 `Isolate.run`
  把新 build 落位之后 `startDetached(executable)` 拉起 exe，然后 `exit(0)`。
- installer（安装包）：`local_transfer.iss` 的 `[Run]` 第二条，`Check: UpdateWasRequested`，
  即「静默安装且带 `/update`」时启动 exe。这条正是为了补上 `skipifsilent` 会让第一条被跳掉的问题。

顺带确认它是**有意留着的**：`main.cpp` 里 `applying_update` 时跳过单实例检查，否则第二个进程会
被判定为重复启动而直接退出。

## Decision

**把 rail 上的更新按钮接到已有的安装流程上，安装过程放在 About 页面上。**

shell 里加一个 `_installRequests` 计数器，rail 按钮按下时 `_index = _aboutSurface` 并自增；About 页
通过 `didUpdateWidget` 观察计数的变化，用 `offeredUpdate`（应用启动时那次检查的答案）启动 `_install()`。

为什么把活儿放到 About 页而不是 rail 上自己做：rail 只有 72px 宽，放不下载进度条、放不下「关闭并更新？」
这个确认框、也放不下失败时那句话。这三样 About 页全都有，而且就是同一个 `_install()`
—— 第二次实现一遍是不可能的，两个实现之间必然漂移。

为什么 rail 按下去要切到 About 页：装的时候用户需要看见进度。不切过去的话，用户点在 rail 上、然后看到
什么都没有发生（当前停在对话页或设备页），只会再点一次。

`_updateEntry` 的 `url` 参数被删除，改成 `onInstall: VoidCallback` 回调：widget 在 rail 深处，
没有道理让它知道 shell 的 `_index`。按钮的职责止于「用户说想装」，去哪是 shell 的决定。

## Alternatives considered

**在 rail 上放一个进度指示器** —— 72px 只够放一个圆环，放不下百分比、放不下「正在校验」、
放不下失败原因。失败时用户还得自己去 About 页看是什么原因，那不如一开始就在能说清楚的地方做。

**弹一个对话框放进度** —— shell 需要自己管一个 dialog 的开与关，而且确认框（「关闭并更新？」）本来
就是 About 页的 `_ConfirmUpdateDialog`，两处各有一个确认框比两处各有一个进度条更糟。

**rail 按钮直接调 installer，不经过 About 页** —— 确认框不能省：`apply()` 会 `exit(0)` 关掉正在用的
程序，一个不打招呼就消失的程序是不可接受的。而确认框在 About 页里，所以必然要经过它。

**保留「打开下载页」作为备选按钮** —— About 页右侧的「打开下载页面」按钮一直在，哪里需要手动下载
都还能去。rail 上 72px 放不下两个按钮。

### 顺手带上的第三条需求

「切换到对话菜单时，默认选中最后一次对话的列表项，并聚焦该对话的输入框」。这条在工作区里是半成品，
本次补齐并加测试守住：

- `home_shell.dart` 的 `_conversationArrivals` 计数 + `ConversationsPage.focusRequest`：
  shell 是唯一知道 tab 被按下的东西，而输入框归页面所有，所以计数器往下传，页面响应边沿
  （`didUpdateWidget` 里 counter 变化 → `_focusComposer = true`），再经 `autoFocusComposer` 到
  composer。用 counter 而不是 bool，这样「离开再回来」是第二次到达而不是同一次。
- 选中最后对话：`controller.lastConversation` + `_untouched` 守卫本已存在，本次补测试确认
  「切走再切回来仍选中 Bob 且 row.selected」。

工作区里还有一批**与本次需求无关**的改动（composer 改版：图标 `attach_file` → `add`、
高度 40 → 34/44、focus-within 描边）与 README 中文化，一并留在工作区，未在本次处理。

## Follow-up: 更新执行期间所有入口置灰，确认按钮改口「更新并重启」（2026-10-19）

### Problem

更新执行期间按钮仍然可点。About 页的「下载并更新」在下载时本来就置灰（`_busy`），但
同一张卡上的「检查更新」和「打开下载页」仍可点；更重要的是**左侧菜单的「更新」按钮**
没有禁用的概念 —— 进入 About 页后用户还能再点它，第二次点击再次触发 `_install()`。
虽然 `didUpdateWidget` 的 `if (_asking || _busy) return;` 会挡住第二次下载，但对应的是
「点了等于没点」，不是「看得出不能点」。用户在漫长的下载、校验、解压过程中会反复点它，
然后得到一个看起来什么都没发生的按钮。

另外，确认对话框按钮叫「关闭并更新」：用户要知道的是更新完之后程序会不会自己回来，
而这句话把动作序号反了 —— 已经下载好的前提就摆在那里，这一刻唯一的动作是**重启**。

### Decision

- About 页把更新过程当成**一个不可再进入的状态**：`_asking` 或 `_busy` 期间，检查更新、
  下载并更新、打开下载页三个按钮全部置灰；失败后 `_busy` 清零，三个按钮恢复 —— 同一
  个按钮就是重试。
- 左侧菜单的「更新」按钮由 shell 用 `_updateLocked` 状态置灰：About 页通过新的
  `onUpdateBusyChanged` 回调把「进入更新」「退出更新」报给 shell，rail 的 `_UpdateEntry`
  在 `enabled: false` 时 `onPressed: null`。
- 状态同步放在 `addPostFrameCallback` 里而不是 `_install()` 开头：rail 点击经由
  `didUpdateWidget` 到达 About 页，而那一次仍在 build 阶段，直接 `setState` 父级
  HomeShell 会触发 `setState() called during build`。
- 下载完成后（`_prepared != null`）到确认框打开之间 `_busy` 为空，shell 不置灰：
  这是为了让用户在确认框打开时再点 rail 的「更新」能命中正在等着的同一个确认框，
  而不是静默丢弃。确认框确认后到进程结束前再次置灰。
- 文案：确认框标题/正文/按钮从「关闭并更新」改为「更新并重启」；按钮下方那段说明里
  的指引也同步改名。

### Alternatives considered

**点击一次后永远置灰** —— 失败后用户需要重试，置灰到底等于把重试入口藏起来；失败瞬间
恢复由 `_busy` 清零自然完成。

**把 busy 状态放进 `UpdateNotice` 里让 rail 直接听** —— rail 和 About 页共用通知，但
notice 的职责是「启动时问一次」的答案；更新动作是从 About 页发起的，通知本身并不感知下载。
让 notice 兼任会把它变成一个四处都是的全局状态。

**确认框打开期间也置灰** —— 会丢掉一次「再点一次 rail 入口打开同一个确认框」的机会；
用户双击 rail 按钮时第二次点击不应成了空气。置灰的窗口期是「真正有工作在跑」的窗口期，
不是「等待用户回答」的窗口期。

### Consequences

- `lib/ui/pages/about_page.dart`：`AboutPage.onUpdateBusyChanged`；`_check`/`_install`
  各阶段调用 `_reportBusy`；`_install` 开头与确认后经 `addPostFrameCallback` 同步，
  避免 build 阶段 setState 父级。
- `lib/ui/home_shell.dart`：`_updateLocked`、`_setUpdateLocked`；`_UpdateEntry`
  增加 `enabled`，置灰时 `onPressed: null`（Material 的 disabled 样式就是置灰）。
- `lib/l10n/app_zh.arb` / `app_en.arb`：确认框三句 + 安装说明改为「更新并重启」。
- `test_flutter/ui/update_rail_test.dart`：新增「下载中 rail 入口置灰、失败后恢复」。
- `test_flutter/ui/about_page_test.dart`：新增「下载中关于页三按钮全置灰、失败后恢复」。

### 门禁

- `flutter analyze`：无问题
- `dart test`：574 通过

## Consequences

- `lib/ui/home_shell.dart`：rail 更新按钮改为安装；新增 `_installUpdate()`；About 页接两个新参数；
  删除未使用的 `external_links.dart` import。
- `lib/ui/pages/about_page.dart`：`AboutPage` 加 `offeredUpdate` 与 `installRequest`；
  加 `didUpdateWidget`；`_install({UpdateCheck? offered})` 支持从外部答案启动。
- `test_flutter/support/ui_harness.dart`：新增 `aboutSurface` 常量。
- `test_flutter/ui/update_rail_test.dart`：两个「打开浏览器」测试改写成三个安装测试
  （切到 About 页并调 installer、先问再关、失败时显示原因）。
- `test_flutter/ui/pages_test.dart`：新增「切回对话菜单重新打开最后一次对话并可立即输入」。

### 已知失败（与本次改动无关）

`test_flutter/e2e/two_window_e2e_test.dart` 有三个 e2e 测试失败，卡在 `pairDevices` 等待配对应答。
已在干净 HEAD 的 worktree 上复现同样失败，确认是本机环境的既有失败。

### 门禁

- `flutter analyze`：无问题
- `dart test`：573 通过
- `flutter test test_flutter`：除上述三个既有 e2e 失败外全绿

# Agent Note: 内网自动连接与剪贴板白名单

Status: implemented

## Problem

六条意见来自在实机 Windows 打包版上的使用，拆开看，一条是同意问题，三条是界面问题。

**一台拨不进来的机器，恰恰是需要主动拨出去的那台。** 从 A 点「连接」到 B 报
`Connection timed out`，反方向一点就通。代码层面修不了：失败那一侧的入站端口不可达，连
ICMP 都被丢掉，是那台的防火墙在拒绝连接。代码能修的是——干脆不需要那个方向：两台已经
同意共享同一个 Owner Group、且都能在局域网上看见对方的机器，没有任何理由再等一个人去点。

**「已配对」被当成了「可读剪贴板」。** Owner Group 曾是剪贴板镜像唯一的门，于是为了给一台
机器发文件而接纳它，顺带把本机此后每一次复制都交了出去。用户点「配对」时并不是这个意思。

**三处界面把同一件事说错了地方。** 传输菜单把文本消息和文件列在一起，可文本是对话，菜单
显示不了它的上下文。文本气泡带着 `文本 · 已完成` 一行——那是传输的记账，而文本不是传输。
导航栏里的「对话」没有图标；对话列表里没公布过名字的设备叫 `Unnamed device`，这个占位符
在两台都没名字的设备之间起不到任何区分作用。

## Decision

**同一个 Owner Group 内、被内网发现的设备自动建立连接。** `PeerRegistry.changes` 上新增
一个监听，调用 `_autoConnectPeers`：凡是 `profile.group` 里的、尚未连接的、也没有正在连接
的对端，就直接拨。两端都会拨，于是两个拨号会撞车，输的那个被会话层以「已经持有该对端的
Session」拒绝——这是撞车撞对了，不是故障。未配对的设备永不自动拨：发现不能成为「未经询问
即可加入」的通道，配对流程才是收集那个同意的地方。

自动连接故意比按钮安静：试三次，间隔 400 ms，然后收手。按钮仍留在行上，供人想再试一次时
用；防火墙不值得每次启动都报一次。

**剪贴板新增第四道门：共享白名单。** `ClipboardMirror` 现在依次检查 Owner Group、白名单、
平台能力、来源标签。白名单是持久化在 `DeviceProfile.clipboardPeers` 上的一组指纹，
**默认为空**，且**双向**检查：条目只发往本机名单上的对端，而条目只在来源位于名单上时才被
应用。所以两台机器共享剪贴板，当且仅当各自添加了对方。剪贴板界面把这份名单渲染成已配对
设备上的勾选框，让这个决定有地方可做；`setClipboardPeer` 同时写 profile **和**正在运行的
镜像——只改一边的开关，会在下次重启之前一直对自己的状态撒谎。

**传输菜单只列文件。** `TransfersPage` 把 `controller.transfers` 过滤到
`PayloadKind.file`。文本属于它被说出的那段对话，剪贴板条目是被镜像而不是被搬运；两者走的
是同一套底层，都出现在 controller 的列表里，又都在这里被滤掉，这样这个菜单就不会把另两个
界面已经展示过、却丢了上下文的东西再说一遍。

**文本气泡不再带状态行。** `MessageBubble` 只对非文本类型绘制 `类型 · 状态` 那一行。聊天气泡
说什么就是什么，方向也早已由它贴在窗格的哪一侧表达；`文本 · 已完成` 是把传输的记账套在了
不是传输的东西上。文件保留这一行，因为那是用户要看的回执。

**没公布名字的对端用指纹命名，而不是用地址。** 这推翻了
`2026-10-08-a-nameless-peer-shows-its-address.md` 定下的顺序：`PeerView.displayName` 回到
`alias ?? fingerprint.short()`，并把 `DeviceDescriptor.fallbackAlias` 当作「没有名字」而不是
「一个名字」来对待。`PeerView.hasRealAlias` 用来区分二者，`describePeerFacts` 用它。
地址是「在哪里」，与「是哪一台」是两回事；而每个显示名字的地方本来就在副标题里并排显示
地址——兜底值不必再兼任它，两台没名字的设备也就能靠双方都没选过的东西区分开。

## Alternatives considered

**去修拨号方向，而不是自动连接。** 没得修：拒绝来自对端防火墙，而应用自身的错误文案已经说
清楚了。自动连接才是让用户的问题消失的东西，手动地址那条路也还在，供屏蔽了发现的网络使用。

**配对时就用 Owner Group 预置白名单。** 这实际上就是旧行为，也正是这次要求叫停的行为。
原话——「只有在剪贴板内添加的设备，才可以共享」——是一条安全要求，配对即授权等于换个名字
重建同一个默认放行。

**白名单只按 Owner Group 加一个开关，而不是按对端列表。** 更省，但表达不了「这台笔记本
行、那台不行」，而那恰恰是用户真正要做的决定。

**给「对话」换一个别的图标。** 图标从来没错：代码要的就是 `Icons.forum_outlined`，有史以来
每一版带这个入口的代码用的都是它。错的是字体，见下面 Consequences。

**文本留在传输菜单里，只把空状态改掉。** 菜单列出用户在其中无法操作的东西——传输行上没有
可以打开的对话——比不列出它更糟。

## Consequences

**打包版里的 Material Icons 字体是过期的、且被 tree-shake 过，修法是让 assets 步骤失效
——不是 clean。** 出货的 `data/flutter_assets/fonts/MaterialIcons-Regular.otf` 只有
4848 字节、36 个字形，对话功能引入的每一个图标都不在里面（`forum`、`forum_outlined`、
`notes`、`send`、`attach_file`、`description_outlined`），而所有更早就存在的图标都在。
字体的 mtime 比那段工作早八天：`flutter build windows --release` 是增量构建，图标的
tree-shaker 一直没重跑。代码从来无辜——那些字形根本没被切进字体。第一反应的
`flutter clean` 在本机行不通：沙箱的 safe-delete 会拦下批量删除，工具打印
"Failed to remove ...\build" 却照样 exit 0，那个过期字体原封不动。有效的办法是摸一下
`pubspec.yaml` —— assets 步骤的缓存键里有它，光改 mtime 就能逼整步重跑，图标子树化
跟着重做。绿色包脚本现在每次构建前都摸一下该文件，并且打包验证会解析字体的 cmap、
缺任何一个必备字形就报错（尺寸阈值分不出好的 5404 字节和坏的 4848 字节）。

**自动连接改变了测试能假定的东西。** 已配对的对端不再停留在「已发现但未连接」的状态，
所以断言过该状态的测试、以及手动拨号的辅助函数，都必须容忍一个已经存在的 Session。而
「已经连上了」会以两种形态回来，取决于哪一端赢了那场竞争：controller 在拨号前先检查，抛
`AppStateException`；LinkManager 发现 Session 已建立，抛 `HandshakeException`。`connect`、
`connectDevices`、`openTab` 都得学会这件事，最后那个还得等一个正在淡出的配对询问——模态
遮罩会吞掉瞄向导航栏的点击，并把它报成一条关于坐标的命中测试失败。

**多一道门，就多一处需要记得的地方。** 白名单在构造时从 profile 读入，并在 profile 变化的
每处重读；任何在 `LocalTransferController.start` 之外构造 `ClipboardMirror` 的代码，都会
从一个空名单开始——这是安全的读法，但也是无声的。

**白名单是按设备存的，所以构造上并不对称。** 只有各自添加了对方，两台才共享剪贴板。这是
「同意」的本意，也意味着只勾了一边、没勾另一边的用户得到的是安静，而不是半个传输。

## Testing

`test/clipboard/clipboard_mirror_test.dart` 新增「the sharing whitelist」一组：名单为空时
什么都不镜像、添加对端后条目才流出、把对端移出名单会立刻安静下来且不丢 Session、来源不在
名单上的入站条目被拒绝且通知里带 `whitelist`。该文件里所有更早的测试现在都请求
`allowEveryoneInGroup`，这样一条关于 group 门通过的断言，就不可能是空名单造成的。

`test/app/app_controller_test.dart` 新增「connecting to a peer as soon as it is
discovered」——两端在无人要求下各自建立 Session，未配对的对端则不会——以及「the
clipboard-sharing whitelist」——在双方互相添加之前什么都不流动。

`test/profile/device_profile_test.dart` 钉住往返、默认空，以及非字符串条目被拒绝而非忽略。

`test_flutter/ui/pages_test.dart` 钉住文本气泡不带状态行、剪贴板界面列出设备组且勾选框全空、
没名字的设备按指纹列出且占位符永不出现。`test_flutter/e2e/two_window_e2e_test.dart` 在一个
真实窗口里勾选一个真实复选框，然后让一次真实复制跨越一个真实套接字。

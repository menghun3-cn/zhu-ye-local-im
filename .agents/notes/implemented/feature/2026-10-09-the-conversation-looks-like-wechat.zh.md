# Agent Note: 会话看起来像微信了

Status: implemented

[English](2026-10-09-the-conversation-looks-like-wechat.md) | 中文

## Problem

会话能用，但看起来像一张表单。

一条消息就是一个扁平的灰色矩形，里面是正文，下面一行写着「文本 · 已发送」。会话两边
用的是同一个矩形，所以唯一说明「这话是谁说的」的，只有它贴着这一列的哪一边。产品里
没有头像、没有小尾巴、没有气泡，也没有任何一处品牌色——主题来自
`ColorScheme.fromSeed(seedColor: Colors.deepPurple)`，那是 Material 的默认值，跟
这个应用毫无关系。输入区是一个 `TextField` 加一个图标按钮，没有任何分组，所以「我
在哪儿打字」和「我按哪个键」在视觉上没有答案。

发送能做的事也比被发送的东西窄。文件能发，图片不能发，也没有任何东西能被拖到窗口
上。选文件走的是我们自己造的一个对话框，在一个文本框里问路径——这是比每台桌面本来
就有的那个更差的文件选择器，而且它让最常见的那件事（把刚拍的照片发出去）变得不可能。
把截图拖到窗口上的用户什么也得不到，因为 Flutter 自己的 `DragTarget` 根本看不见一个
来自应用外部的拖放。

## Decision

会话相关的界面被拉到与微信对齐，同时产品拿到了桌面用户最先会去用的两种发图方式。

### 视觉语言只住在一个地方

`lib/ui/wechat/theme.dart` 定义了 `class WeChat`：一个私有 const 构造函数，持有会话
界面用到的每一种颜色、字号和尺寸，以及 `static ThemeData theme()`，它从一个显式的
`ColorScheme.light(primary: brand, …)` 构建出应用的 `ThemeData`。

**显式而不是 seeded，这就是这个决定的实质。** `ColorScheme.fromSeed` 用一个算法从
一种颜色推出一整套调色板，而那个算法可以自由地选一个跟参照物不同的色阶——这正是
「对齐微信的颜色」所不能容忍的。每一个要紧的 token 都被写了下来：品牌绿 `#07C160`、
发出气泡 `#95EC69`、收到气泡白色、气泡文字 `#1A1A1A`、页面 `#EDEDED`、侧栏
`#F7F7F7`、分隔线 `#E7E7E7`、次要文字 `#888`、选中行 `#C9C9C9`、悬停 `#E9E9E9`、
角标 `#FA5151`；正文 15 配 1.4 行高、预览 13、次要信息 12、头像 40、气泡圆角 6、
气泡内边距 12×9、气泡最大宽度 60%、消息间距 16、列表宽 250、行高 64。

两个 `MaterialApp`——在跑的那个和 `StartupFailureApp`——都用 `WeChat.theme()`。
启动失败窗口故意用同一套样式：一个启动失败的窗口，恰恰是用户最可能第一次盯着这个
应用看的地方，在那儿递给他一个 Material 紫，就是应用在把自己介绍错。

### 气泡两边都是气泡，都带脸和小尾巴

`lib/ui/wechat/bubble.dart` 里放着 `Avatar` 和 `MessageBubbleShape`。发出的气泡是
品牌绿、小尾巴在右边；收到的是白色、小尾巴在左边；两边共同持有同一份近黑的正文、
同一个圆角和内边距。小尾巴是一个旋转 45° 的小方块塞在气泡角后面
（`Transform.rotate(angle: 0.785398)`，偏移 `_tail * 0.7`），而不是一个
`CustomPainter` 三角形：旋转是引擎本就知道怎么抗锯齿的一个变换，而手搓的三角形
路径得自己把边角接缝处理对，而且会在拐角处和气泡之间露出一道缝。

回执行——「种类 · 状态」——现在**只为文件**画。文本消息没有什么可汇报的：它到达即
被接受，没有 sink 也没有 digest，而每个气泡下面都来一行「文本 · 已发送」，是同一条
噪声重复在每一个气泡上。文件才是可以被拒绝、可以失败、可以停在等待答复的那种，
所以文件才是读者需要知道状态的那种。`_showsReceipt` 就是
`view.kind == PayloadKind.file`，它是决定这件事的唯一判断。

### 图片是一种载荷种类，而图画本身就是消息

`PayloadKind` 增加了 `image('image')`。这在协议上是**增量**的，而且是刻意的：图片
的走法和文件完全一样——offer 里一个 digest，字节过一个 sink——所以引擎里没有任何
地方按种类分支，一个在本次改动之前构建的接收方也仍然能把字节放到正确的位置。
`wireProtocolVersion` **没有**被提升，因为不存在一条旧对端会误读的消息。

新的种类改变的是字节被**展示**在哪儿。`TransferView` 增加了一个可空的 `localPath`，
只为图片设置：发送方自己的文件在被 offer 之后，以及接收方落盘的副本在被写入并校验
之后。图片气泡在拿到路径时画出图画，并在点击时打开一个大图查看器；还没有路径时——
一个尚未被答复的 offer——它退回到和文件一样的名字行，因为除此之外没有诚实的画法。

### 选择器是一道缝，因为原生对话框没法测

`file_selector` 打开的是操作系统自己的对话框，`desktop_drop` 把 `WM_DROPFILES`
桥接进 Flutter 的拖放系统。两者对用户来说都是正确的选择，也都无法从 widget 测试里
驱动：原生对话框跑在 Flutter 事件循环之外，永远不会返回到一个 `testWidgets` 函数体。

所以选择器经过 `lib/ui/pickers.dart` 解析：`abstract interface class FilePicker`、
`final class SystemPicker`（唯一调用 `openFiles`/`openFile` 的地方），以及一个静态
替换点 `PickerResolution.picker`，带 `reset()`。测试装上一个 `ScriptedPicker` 并
驱动真正的按钮，这意味着「拿回来的东西被怎么分类」、offer、上线、落盘全都仍在被
测的路径上——被换掉的只有对话框本身。

### 一个放置目标，而且它会说出自己要做什么

历史被包在一个 `DropTarget` 里，只在有对端可发时启用。拖拽进入时会染色并显示提示；
放下时会被分类成图片和其他文件，各自按本来的样子发出去。分类逻辑住在
`pickers.dart` 里、挨着选择器，而不是住在页面里，所以「什么算图片」对对话框和拖放
只有一个答案。

## Alternatives considered

**保留 seeded 配色，只覆盖那几个看着不对的颜色。** 拒绝：推出来的调色板不只是一个
主色。它是每一个表面、描边、容器色阶和禁用态，而每一个都是一处应用可能偏离参照物的
地方。把 token 写下来，意味着「跟微信对比」变成「对比一组被写下来的值」，那是审查者
真能检查的东西。

**用 `CustomPainter` 三角形画小尾巴。** 拒绝：三角形路径得手工接到气泡的圆角上，
接缝处在拐角会露出来，因为两条抗锯齿的边在那儿相遇。旋转方块是放到气泡后面的，所以
眼睛看到的是气泡自己的圆边。

**保留应用内的路径对话框来发文件。** 拒绝：操作系统的选择器在一个文件选择器能好的
每一个方面都比我们自己的好——它记得用户上次在哪儿、能浏览、能显示缩略图、能按类型
过滤。那个对话框存在，是因为产品没有路子到达真正的那个，而不是因为「问一个路径」是
件好事。

**把选择器放到 controller 后面而不是 UI 里面。** 拒绝：controller 正是那个不知道
对话框为何物的东西，把一个选文件的依赖穿过去，会让传输引擎的测试背上一个 UI 关注点。
缝应该开在对话框被打开的地方。

**把图片当 `file` 发，让 UI 决定要不要画缩略图。** 拒绝：种类正是接收方用来知道
自己拿到了什么的东西。收到 `file` 的接收方得从扩展名去猜，而一旦猜得跟发送方不一致，
就是一张图被显示成了一个文件名。枚举是那个答案被写下来一次的地方。

**为新的种类提升 `wireProtocolVersion`。** 拒绝：版本号是为「旧对端会误读的改动」
准备的，而这个不是。旧接收方处理一张图片，和一个知道该种类的接收方一样好——它收到
的是配着 digest 的字节。提升版本会拒绝一个本来能工作的对端，把一处显示差异变成一次
连接失败。

## Consequences

- `lib/ui/wechat/theme.dart`、`lib/ui/wechat/bubble.dart` 和
  `lib/ui/wechat/image_bubble.dart` 是新增的。会话的颜色、尺寸和形状现在来自一个类，
  而不是每个调用点上的 `Theme.of(context)`。
- `PayloadKind.image` 是一个新的枚举成员，于是每一个对种类的穷举 `switch` 都得为它
  作答：`lib/ui/labels.dart` 里的 `iconForKind` 和 `labelForKind`，以及
  `lib/core/transfer/transfer_limits.dart` 里的种类分支。那些写成 `if` 而不是
  `switch` 的分支——`transfer_engine.dart`、`conversation_view.dart`、
  `transfers_page.dart`、`app_controller.dart`、`messages.dart`——是手工核对的，
  因为编译器不会指着它们。
- `TransferEngine.sendFiles` 现在是一个私有
  `_sendStreams(PayloadKind, items)` 的薄包装，而 `sendImages` 就是用另一种种类调
  同一次。一种走法像文件的新种类，代价是一个枚举成员加一行，而不是把 digest 和 offer
  的逻辑抄第二份。
- `app_controller.dart` 里的 `_Tracked` 带上了一个可变的 `localPath`，在发出图片时
  被写入、在收到的图片被写入并校验之后被写入。`acceptInto` 记下它落在的路径，这正是
  让接收方的气泡能显示它刚收到的图画的原因。
- `ConversationComposer` 变成了一个持有 `FocusNode` 的 `StatefulWidget`，并在发送
  之后重新请求焦点。回车发送、Shift+回车换行，通过一对包在输入框外面的
  `Shortcuts`/`Actions` 实现，而不是输入框上的按键处理器——所以无论光标恰好在哪儿，
  行为都一样。
- 被重新配色的按钮是带显式 `ButtonStyle` 的 `TextButton`，而不是 `Material` 加
  `InkWell`。手搓按钮会丢掉焦点环、键盘激活和 tooltip 语义，而那些再也找不到发送
  按钮的 widget 测试，报告的是一个真实的回退，而不是一个需要更新的测试。
- `file_selector` 和 `desktop_drop` 是新增依赖，`pubspec.yaml` 记下了原因：选择器
  是操作系统自己的，而一个外部拖放是以 `WM_DROPFILES` 到达、永远不会变成一个
  Flutter 拖拽的。
- widget 套件增加了一个 `ScriptedPicker`，以及按名字定位行和发送按钮的 finder。
  会话列表行不再是 `ListTile`，所以那些通过它去够某个对端的辅助函数被改接到一个
  带对端名字的 `ConversationRow` 上。

# Agent Note: 气泡皮肤是 profile 里的用户数据，不是调色板槽位

Status: implemented

## Problem

会话气泡此前只有一个自由度：`WeChatColors` 里的四个颜色槽位
（`bubbleOut`、`bubbleOutText`、`bubbleIn`、`bubbleText`），全部是设计好
并且固定的。用户提出了可自定义气泡的需求——渐变、图片、自己的图片——
收发两侧各自独立、只作用于文字气泡、并且选择只存在于本机。

两条既有约束决定了答案的形状。`theme.dart` 刻意不给 `WeChatColors` 提供
`copyWith`：调色板是一个被设计出来的对象，变更接口会邀请出没人
设计过的组合。另外，用户挑选的图片不能存选择器返回的路径——在
Android 上那是 `content://` URI 或随时可能被系统清掉的缓存文件——所以
「记住路径」在两个发布平台之一上根本不是持久答案。

## Decision

**皮肤是 `DeviceProfile` 里的 `BubbleSkin` 值，在渲染时按气泡解析。**
`lib/core/profile/bubble_skin.dart` 是纯 Dart：一个密封类型，带两种填充
——`GradientBubbleSkin`（2–4 个 ARGB 颜色、一个方向、可选 stops）和
`ImageBubbleSkin`（asset 名或绝对文件路径、scrim、墨色）。两侧在
`outgoingBubbleSkin` / `incomingBubbleSkin` 下独立持久化；键缺失时解码为
null，即「主题自己的颜色」——每个 profile 的初始状态。序列化双向宽容：
未知 `kind`、畸形颜色、或更新版本写入的填充类型，都会读作「没有自定义
皮肤」而不是 profile 损坏——一个偏好不值得为了它拒绝打开设备的身份文件。

**皮肤由 controller 而非主题送达气泡。** `MessageBubble` 本来就持有
`LocalTransferController`，所以 `bubblePaintFor` 按方向读取
`controller.outgoingBubbleSkin` / `incomingBubbleSkin`，解析出
`BubblePaint`——一个 `BoxDecoration` 加一个墨色加一个可选 scrim——由
`MessageBubbleShape` 绘制，气泡内所有文字继承同一墨色。`WeChatColors`
从不被修改，也没有新增 `copyWith`；主题保住了「设计好的调色板」这条契约。
墨色是二值（深/浅）而非自由取色，这正是让用户挑的填充不会意外产生
不可读文字的原因。

**资格是消息的属性，不是绘制的属性。** 只有 `PayloadKind.text` 和
`PayloadKind.emoji` 的气泡会查询 profile；文件和图片传输保留主题，因为
它们的气泡是传输的回执。裸本地图从来就没有气泡，现在也不会有。文件
皮肤的副本图片被删掉时回退到主题绘制——一个白字压在对话背景上的空
矩形比普通气泡更糟。

**用户图片只复制、不引用。** 选择图片时调用
`LocalTransferController.importBubbleSkinImage`，把它复制进
`<数据目录>/bubble_skins/`，文件名是时间戳加随机数，profile 存的是副本
路径。于是 profile 持有的是这个设备自己拥有的路径，在 Windows
（`%APPDATA%/LocalTransfer/bubble_skins`）和 Android（平台 channel 已提供
的应用私有目录）上行为一致。选择器在复制前先执行文档写明的规则：
只收 PNG/JPG/WebP/BMP（GIF 即使 `imageExtensions` 收它也被拒绝——皮肤
是静态图）、不超过 `bubbleSkinMaxImageBytes`（2 MB），裁剪方式、构图、
scrim 与最小宽度的说明直接显示在对话框里。

**选择器在「完成」之前都是草稿。** `BubbleSkinPicker` 编辑的是本地草稿
——预设、基于 `flutter_colorpicker` 的自定义渐变编辑器、内置图片、带
墨色/scrim 选项的用户图片——只有确认时 `setBubbleSkin` 才持久化，所以
拖动取色器滑块不会每 tick 重写一次 profile。历史消息在下次重建时就换上
新皮肤，与微信行为一致，在这里零成本，因为皮肤是绘制时解析的，而不是
烘焙进消息记录的。

## Alternatives considered

**通过 `ThemeExtension` 注入皮肤。** 否决：这会把用户数据塞进代码库刻意
保持为「设计调色板」的主题层，逼出 `lerp`/`copyWith` 语义来处理一个并非
调色板的值，并且让「哪张皮肤生效」成为主题状态的函数而不是消息方向的
函数。直接读 controller 保持了分层干净，改动收敛在一个调用点。

**两侧共用一套皮肤。** 用户否决：对话的两侧读法不同——自己发的是
「我的」、对方发的是「对方的」——单一选择无法表达「我发绿的、收粉的」。

**存选择器路径、渲染时做解码检查。** 否决：Android 的选择器应答活不
下来；而且 `BoxDecoration` 里的 `FileImage` 失败时没有 `errorBuilder`
可以回退——失败会画成损坏的填充，而不是普通气泡。导入时复制让存储
路径从构造上就是持久的，`bubblePaintFor` 里的缺失文件检查覆盖剩下的情
形（用户手动或系统清理应用数据）。

**按图片平均亮度自动推导墨色。** 否决：为每次气泡重建解码每张皮肤图来
算均值是在忙图上经常出错的数字上花真实 IO。二值墨色选择加选择器里的实
时预览，把可读性决定放在用户看得见的地方。

**GIF 皮肤。** 否决：`BoxDecoration` 图片只显示一帧，GIF 永远只会显示
第一帧——那是用户没选的那张图。该格式与其它规则一起在对话框处被拒绝。

## Consequences

**得到。** 一次交付三种皮肤来源——六个设计好的渐变预设、六张内置图片、
带明确规则的用户图片——两侧独立、实时预览、重启后仍在，且在两个平台
行为一致。协议、Owner Group 和所有对端可见的表面都没动：皮肤是本地用户
数据，永远不离开这台设备。

**代价。** `conversation_view.dart` 现在把解析好的 `BubblePaint` 透传给
`_contents`/`_body`/`_image`/`_BubbleAction`，而不是每次调用重算
`_bubbleInk(colors)`——用更宽的签名换每个气泡只解析一次。设置页新增了一
个分区和约 1000 行的选择器；`flutter_colorpicker` 成为自定义渐变编辑器
的新依赖。`assets/bubble_skins/` 下随包发布六张生成的 PNG。

**测试。** `test/profile/bubble_skin_test.dart` 覆盖模型的 JSON 往返和每
种畸形输入回退；`device_profile_test.dart` 覆盖两个槽位的独立性与宽容
解码；`app_controller_test.dart` 覆盖跨重启持久化和导入复制契约；
`test_flutter/ui/bubble_skin_test.dart` 覆盖按类型、按方向、按来源的渲染
结果、缺失文件回退，以及选择器的草稿—确认流程。

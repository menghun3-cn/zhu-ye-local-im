# 自定义对话气泡皮肤 — 设计文档

日期：2026-11-12
状态：待评审

## Intent / Why

用户想自定义聊天气泡的外观：不只是换一个颜色，而是能用渐变、内置图片或
自己选择的图片作为气泡背景。目标是「像微信皮肤/聊天气泡美化」那样的
观感自定义，范围收敛到文字气泡、收发两侧各自独立、只在本机生效。

## 现状（已核实）

- 气泡颜色是一条「颜色管道」：`WeChatColors` 的 4 个槽位
  （`bubbleOut` / `bubbleOutText` / `bubbleIn` / `bubbleText`）写死在
  `light` / `dark` 两套 const 调色板里；`MessageBubble.build` 取出一个
  `Color` 传给 `MessageBubbleShape(colour:)`，后者画
  `BoxDecoration(color:)`（`lib/ui/wechat/bubble.dart`）。
- 墨色由 `_bubbleInk(colors)` 按收/发方向返回；文字、文件图标、文件名、
  进度条轨道（`_bubbleInk().withValues(alpha: progressTrackAlpha)`）全部
  从它派生——墨色一处改，全部跟随。
- 气泡形状固定：圆角 14 + 朝头像一角收 3（`WeChat.bubbleRadius` /
  `bubbleTuckRadius`）。接收方气泡额外有一条 `divider` 发丝线描边。
- 接收方描边、`_BubbleAction` 次要按钮的前景（`colors.bubbleText`）也
  依赖主题色。
- 图片消息（本地已有字节的 `PayloadKind.image`）走 `_bareImage`，**没有
  气泡**；文件与传输中的图片走气泡但带进度条和回答按钮。
- 会话列表只显示 `text` / `emoji` / `file` / `image`；`clipboard` 消息
  被过滤在外（`conversation_view.dart` 的消息来源处），不存在
  「clipboard 气泡保持主题色」这条路径。
- 持久化：`DeviceProfile.toJson/fromJson` 是唯一的 profile 序列化点；
  设置项（`closeBehaviour`、`updateCheckInterval` 等）都是
  profile 字段 + `LocalTransferController` getter/setter + `_persist()`。
- 选图接缝：`PickerResolution.picker`（`lib/ui/pickers.dart`）目前只有
  `files()` 与 `directory()`，底层是 `file_selector` 的 `openFiles` /
  `getDirectoryPath`；`file_selector` 支持 `acceptedTypeGroups`。
- 会话列表在 controller `changes` 通知时整体 rebuild
  （`ControllerScope` 监听 → `setState`），气泡里 `controller` 已可用。
- `WeChatColors` 明确不提供 `copyWith`：「调色板必须是设计出来的」
  （theme.dart 注释）。自定义皮肤是用户数据，不是调色板——这条立场
  决定了皮肤不走主题层。

## 方案（已选定）

**路线：Controller 直读 + `BubbleSkin` 数据模型。** 皮肤作为用户偏好
存在 profile 里，`MessageBubble`（已持有 `controller`）按收/发方向取
对应皮肤；解析结果（填充 + 墨色）在气泡 `build` 里算一次，往下传。
不引入 ThemeExtension——那会把用户数据塞进主题层，且与「调色板必须
是设计出来的」冲突。

### 决策记录（用户已拍板）

- **收/发两侧各选各的**：profile 存 `outgoing` / `incoming` 两份皮肤。
- **只支持文字气泡**：皮肤只作用于纯消息气泡（`PayloadKind.text` 与
  `PayloadKind.emoji`——两者都是「内容即消息」的气泡）；`file`、
  `image`（含传输中）保持主题配色不变。`clipboard` 消息不进会话
  列表，无需考虑。
- **只在本机生效**：不同步到 Owner Group 其他设备，不动协议。
- **三种来源一次做完**：内置渐变预设、自定义渐变、内置图片皮肤、
  用户图片皮肤。
- **bare image 不套皮肤**：本地已有字节的图片消息没有气泡，维持现状。

## 设计

### 1. `BubbleSkin` 模型（纯 Dart，可 `dart test`）

新文件 `lib/core/profile/bubble_skin.dart`，sealed class 或 enum 分发：

```dart
sealed class BubbleSkin {
  BubbleSkinInk ink;          // 深字 / 浅字
}

// 渐变：2~4 个颜色 + 可选 stops + 方向（水平/垂直/对角线枚举）
final class GradientBubbleSkin extends BubbleSkin { ... }

// 图片：asset（内置预设）或 file（用户选择的绝对路径）+ 可选 scrim
final class ImageBubbleSkin extends BubbleSkin {
  BubbleSkinImageSource source; // asset(name) | file(path)
  double scrim;                  // 0..0.6，默认 0.25
}
```

- `BubbleSkinInk`：`dark` / `light` 二值。渐变皮肤由用户在选择器里
  直接看到效果后挑；图片皮肤同理。不做自动亮度推导（解码图片算
  平均亮度成本高且不可靠）。
- JSON：`toJson`/`fromJson` 容错——未知 `kind`、缺字段、非法颜色
  值一律回退 `null`（= 默认主题气泡），不让一个坏皮肤拖垮整个
  profile 读取（与 `DeviceProfile.fromJson` 现有风格一致）。
- `ink` 映射：`dark` → `colors.bubbleText`（近黑），`light` →
  `Colors.white`。不新引入颜色常量。

### 2. Profile 与 Controller

- `DeviceProfile` 新增 `BubbleSkin? outgoingBubbleSkin`、
  `BubbleSkin? incomingBubbleSkin`；`toJson` 写
  `'bubbleSkins': {'out': ..., 'in': ...}`（null 不写键），
  `fromJson` 容错解析。
- `LocalTransferController`：两个 getter +
  `setBubbleSkin({required bool outgoing, required BubbleSkin? skin})`
  （或对称的两个 setter），内部改 profile + `_persist()`，与
  `setCloseBehaviour` 同模式。

### 3. 渲染

- `MessageBubbleShape`：`colour: Color` 参数泛化为接受
  `BoxDecoration`（或新增 `decoration` 参数，`colour` 保留给默认路径）。
  圆角/收角逻辑不动。**自定义皮肤不画发丝线**——渐变和图片自带边界，
  再叠 `divider` 线会显脏；默认路径行为不变。
- `MessageBubble.build`：先判定 `view.kind` 是否为 text/emoji 且方向
  对应皮肤非 null；是则把皮肤解析成
  `({BoxDecoration decoration, Color ink})` 记录，连同 `controller`
  已有的参数一起往下传。
- `_bubbleInk(colors)` → 接收解析后的墨色（默认路径仍返回
  `bubbleOutText`/`bubbleText`）。文字、图标、文件名、进度条轨道全部
  自动跟随。
- `_BubbleAction` 次要按钮前景从 `colors.bubbleText` 改为解析后的墨色
  （现在它在自己发出的气泡上用的是接收方墨色，本就是个小瑕疵，借这次
  一起修）；主按钮保持 `brandStrong`/`onBrandStrong` 不变。
- 表情气泡（`_isEmoji`）套皮肤：emoji 字形是彩色的，不吃墨色，只换
  背景。
- 解析出的 decoration 需要处理：
  - gradient → `BoxDecoration(gradient: ...)`；
  - image asset → `AssetImage`；image file → `FileImage(File(path))`，
    用 `ResizeImage` 限制解码宽度（气泡最宽 = 聊天区 60%，取一个
    上限如 1024 逻辑像素 × devicePixelRatio 封顶），加载失败/文件
    不存在 → 回退默认气泡（不报错，静默回退；设置页该项显示
    「图片不可用」）。
  - **皮肤即时生效于全部历史消息**：渲染是实时读 profile 的，换肤
    后旧消息立刻变——与微信一致，是预期行为不是 bug。
  - scrim → decoration 内叠加 `color: Colors.black.withValues(alpha: scrim)`
    （BoxDecoration 的 color 与 image/gradient 可共存，color 画在底层——
    注意顺序：scrim 应在图片**上**、文字**下**，实现上用
    `foregroundDecoration` 或在 child 外包一层；具体由实现者定，但
    scrim 必须盖住图片不能盖住文字）。

### 4. 设置页 UI

`SettingsPage` 新增「消息气泡」区（放在「文件与位置」之前或之后，
实现者定），两行：「我发出的」「对方发出的」，各自显示当前皮肤
缩略图（默认=主题色块），点击打开皮肤选择器。

皮肤选择器（新文件 `lib/ui/pages/bubble_skin_picker.dart` 或
`lib/ui/widgets/` 下，跟随现有页面组织）：

- **默认**：恢复主题配色（写 `null`）。
- **渐变**：内置预设网格（约 6 款，设计好 stops + 方向 + 推荐墨色）
  + 「自定义渐变」入口。取色器用 **`flutter_colorpicker`**（已确认
  可加依赖；选版时遵守「发布 ≥7 天」的供应链规则，并在
  `docs/dart-dependency-baseline.md` 留评审记录）：2~4 色取色、
  方向选择、墨色二选一、实时预览一条示例气泡。
- **内置图片**：网格展示 assets 里的预设皮肤（缩略图 + 名称）。
- **从文件选择**：调 picker 接缝选图片，选中后进入确认页：预览 +
  墨色二选一 + scrim 档位 + **图片规范说明**（见 §5）。
- 所有选项带一条示例气泡预览（「这是一条消息」文字 + 当前方向的
  对齐方式）。

l10n：`app_zh.arb` / `app_en.arb` 同步新增全部文案，跑
`flutter gen-l10n`。

### 5. 用户图片皮肤规范（要写进选择器 UI 和文档）

选择器里「从文件选择」之后和确认页上都要给出规则，文案进 l10n：

- **格式**：PNG / JPG / WebP / BMP——即 `imageExtensions`
  （`lib/ui/pickers.dart`）**去掉 `gif`**：气泡里不做动画，GIF 只取
  首帧没有意义，直接不收。
- **选图即复制**：`file_selector` 在 Android 上返回的可能是
  `content://` URI 或缓存副本，原路径不可靠。因此选中图片后**先把
  文件复制进应用私有目录**（与 profile 同区的 `bubble_skins/`
  子目录，文件名用时间戳/随机串防冲突），profile 里存的是**副本
  路径**而不是用户选的原路径。两个平台行为一致；用户之后移动或
  删除原图不影响皮肤。该目录由 seams 层提供（与 profile 同区，
  具体字段名由实现者定）；复制在 controller 的 setter 里完成，
  失败则拒绝保存并提示。
- **尺寸**：建议图片宽度 ≥ 512px；气泡最宽约为聊天区 60%，过小的图
  会被放大模糊。高度任意。
- **构图**：图片按 `BoxFit.cover` 居中裁剪填满气泡——**气泡有多高
  取决于文字有多少**，长文本气泡很高、短文本气泡接近方形，所以
  重要内容放画面中心，四周留出裁剪余量；避免把关键信息贴边。
- **可读性**：气泡上要压文字，背景越简洁越好；复杂花纹会降低可读性，
  此时用 scrim（遮罩）压暗背景保证文字清晰。scrim 提供「无 / 轻 /
  重」三档，默认「轻」。
- **大小**：建议 ≤ 2 MB；过大的图会被 `ResizeImage` 降采样，原图
  分辨率高于显示尺寸没有收益。
- **稳定性**：profile 存的是应用目录里的副本路径。副本被删（例如
  清理应用数据）后该皮肤静默回退默认气泡，设置页对应项标注
  「图片不可用」，重新选择即可恢复。

### 6. 内置资源

- `assets/bubble_skins/` 目录，pubspec `assets:` 段注册。
- 内置图片需要实际素材：实现时用脚本生成几张符合规范的示例图
  （柔和渐变底 + 细纹理），或由设计提供。内置皮肤在代码里是一张
  `const` 表：`id → asset path + 默认墨色 + l10n key`。
- 内置渐变不需要资源，纯 Dart const 表达。

## 边界与非目标

- 不改气泡形状（圆角/收角不动）、不动头像、不动会话列表。
- 文件/图片/剪贴板消息的气泡保持主题配色。
- bare image（本地已有图的图片消息）不加框不套皮肤。
- 皮肤不跨设备同步；换设备/重装后回到默认。
- 不做按会话/按对端的皮肤——全局两份（收/发）足够。

## 测试

- `test/`（dart test）：`BubbleSkin` JSON round-trip、未知 kind/坏
  数据回退、profile 序列化含新字段且向后兼容（旧 profile 无字段
  读得出）。
- `test_flutter/`：带皮肤的文字气泡渲染出渐变/图片 decoration、
  墨色正确应用到文字与进度条轨道、文件气泡不受皮肤影响、图片
  文件缺失时回退默认。
- Agent Note：本特性按 AGENTS.md §4 需要 `implemented/feature/`
  三件套，与 PR 同交。

## 门禁

`verify-agent-notes.ps1`、`verify-translation-pairs.ps1`、
`flutter analyze`、`dart format --set-exit-if-changed .`、
`dart test`、`flutter test test_flutter` 全绿后提 PR。

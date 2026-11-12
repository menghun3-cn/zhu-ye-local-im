# 发送整个文件夹 — 设计文档

日期：2026-11-12
状态：待评审

## Intent / Why

用户希望像微信/LocalSend 一样，把一个文件夹作为整体发给局域网内的对端设备，
且**保留目录结构**——收到端落盘后仍是 `文件夹名/子目录/文件` 的树，而不是
一堆拍平的文件。

## 现状（已核实）

- 协议：`OfferMessage.items` 本就是多 item 列表，`PayloadItem` 只有
  `id / name / size / digest`，没有目录字段。`PayloadKind.file` 允许多个
  item，限制为 `maxItems=4096`、`maxItemBytes=4GiB`、`maxTotalBytes=8GiB`
  （`TransferLimits.defaults`）。
- 发送端：`TransferEngine._sendStreams` 对每个 item 先 `digestOfSource`
  全量哈希再发 offer；`FileByteSource.open` 每个文件占一个句柄。
- 接收端：`sanitiseIncomingName` 把 `/`、`\` 等替换为 `_`，保证名字不可能
  逃逸出目标目录；`stagingPathFor` / `incomingPathFor` 只处理单层文件名，
  staging 与 final 同目录以便 rename。
- UI：composer 的 `StagedAttachment` 只有「单文件」一种形态；
  `classifyPaths` 明确把目录过滤掉（`File.existsSync` 对目录为 false）；
  `PickerResolution.picker` 已有 `directory()` 接缝（返回路径字符串），
  目前只用于「选择接收目录」。
- `share_by_link_page`（HTTP 链接分享）是另一条独立链路，本次不动。

## 方案（已选定）

**不改协议版本，不加 `PayloadKind`。** item 的 `name` 直接编码 `/` 分隔的
相对路径，例如 `项目/src/main.dart`。约定：

- 发送端普通文件的 `name` 仍是 `fileNameOf(path)` 的结果，**永远不含
  分隔符**；凡 `name` 中含 `/` 的 item 即为「路径 item」。
- 旧版本接收端收到路径 item 时，现有消毒逻辑把 `/` 替换成 `_`，得到
  `项目_src_main.dart` 这种平铺文件——不报错、不错乱，只是没有层级。
  这是可接受的优雅降级，不需要版本协商。

### 发送端

1. **入口**：composer 回形针菜单（或附件按钮）增加「发送文件夹」，调
   `PickerResolution.picker.directory()` 取目录路径（该接缝已存在，测试可
   替换）。拖拽/粘贴路径若是目录也走同一条 staging 路径。
   `StagedAttachment` 增加文件夹形态（`isFolder` + 文件计数），tray 显示为
   一个 chip（`📁 名称（N 个文件）`），不逐文件铺开。
2. **枚举**：新增纯 Dart 模块（建议 `lib/core/transfer/folder_listing.dart`
   或 app 层），对目录做非递归-follow 的递归遍历：
   - 只收文件；空目录不产生 item（协议里 item 必须带字节流，空目录无
     内容可携带——明确不支持）。
   - 符号链接/junction **不跟随**（防环、防逃逸出所选根）。
   - 每个文件的 item name = `根目录名/相对路径`，分隔符统一为 `/`。
   - 枚举时顺带 stat 出 `count` 与 `totalBytes`；**在哈希之前**对照
     `TransferLimits.defaults`（4096 项 / 8GiB）预检，超限直接拒绝并提示，
     避免先花几分钟哈希再被拒。
3. **字节源**：新增 `ChunkedFileByteSource`（或等价物）——构造时 stat 定长，
   每次 `read()` 内部 `open → seek → read → close`，不在枚举期占用 N 个句柄。
   文件中途变化导致 digest 不匹配的行为与现状一致（接收端验证失败）。
4. **发送**：`AppController` 增加 `sendFolder`（内部仍走
   `engine.sendFiles(items)`），整个文件夹是**一个 Transfer、一次接收确认**，
   对话里是一条消息而不是 N 条。

### 接收端

1. `acceptInto` 识别含 `/` 的 item name：按 `/` 切段 → 逐段消毒 → 在所选
   目录下重建子目录树。
2. 段级消毒复用 `sanitiseIncomingName` 的规则（去控制字符、Windows 非法
   字符、尾部点/空格），但**额外**处理：空段与 `.` 段丢弃；`..` 段不得
   原样保留（逐段拼接后必须仍在根目录内，等价于把 `..` 段替换为 `_` 或
   丢弃——实现时二选一，倾向替换为 `_`，与现有「替换而非丢弃」的风格一致）。
   若所有段消毒后为空，回退为 `received` 文件（与现有兜底一致）。
3. `stagingPathFor` / `incomingPathFor` 增加「目标在子目录」的变体：先创建
   父目录，staging 文件放在**最终所在目录**里（保证同卷 rename），final
   名字仍走现有编号消歧。`_Landing` 记录目标 `Directory` + 段名。
4. `_publishLandings` / `_abandonLandings` 相应支持子目录；失败清理时删除
   已建的空目录链（best-effort，不留垃圾）。
5. UI 展示：`TransferView.names` 直接展示 `a/b/c.txt` 形式的名字即可；
   接收确认弹窗显示「N 个文件」与首个路径，不需要逐条列目录树。

### 明确不做（non-goals）

- 空目录、目录权限/时间戳等元数据。
- 符号链接/junction 的内容传输。
- `share_by_link_page` 的 HTTP 链接分享支持文件夹。
- 图片文件夹的「图片消息」形态——文件夹一律按 `PayloadKind.file` 走。
- 断点续传粒度变化（沿用现有 item/chunk 机制）。

### 平台说明

- **Windows**：`getDirectoryPath` 可用，拖拽目录由 `desktop_drop` 交付路径，
  枚举用 `dart:io` 直读。
- **Android**：`file_selector` 的目录选择与 `dart:io` 直读在 Android 11+
  scoped storage 下能力存疑。实现时先验证；若不可行，文件夹入口在 Android
  上隐藏（picker 接缝已存在，平台差异收敛在 `SystemPicker` 一处），不阻塞
  Windows 交付。此点在实现阶段用最小 spike 验证后定稿。

## Approaches considered

1. **name 编码相对路径（采用）**：零协议变更、旧端优雅降级、实现集中在
   消毒与落盘两处。代价：`name` 字段语义从「文件名」扩为「相对路径」，
   需要在文档与注释里写明约定。
2. **新增 `PayloadKind.folder` + manifest item**：语义更干净，但旧版本接收
   端会直接拒绝整个 offer（`fromWireName` 抛 `FormatException`），跨版本
   体验更差；且要为目录项发明「无字节流的 item」表达。否决。
3. **每个文件独立 Transfer**：不需要路径编码，但接收端要确认 N 次、
   丢失「这是一个文件夹」的整体语义，且 4096 项上限变成 4096 次会话。
   否决。

## 测试与门禁

- `test/`（纯 Dart）：目录枚举（嵌套、空目录、链接跳过、不可读项）、
  name 编解码与段消毒（`..`、绝对路径、Windows 非法字符、超长路径）、
  staging/final 路径计算。
- `test_flutter/`：composer 的文件夹 chip、发送循环展开为单个 Transfer。
- Agent Note 三件套（`.agents/notes/implemented/feature/`）。
- 门禁：`verify-agent-notes`、`verify-translation-pairs`、`flutter analyze`、
  `dart format`、`dart test`、`flutter test test_flutter`。

## 留给实现者的决定

- `..` 段的具体处理（替换 `_` vs 丢弃）。
- 文件夹 chip 的具体文案与图标（走 l10n，需中英双语）。
- Android 可行性 spike 的结论与入口显隐策略。

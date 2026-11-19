# Agent Note: 链接分享归入「传输」，二维码可放大，提示统一为顶部 toast

Status: implemented

[English](2026-11-19-share-link-under-transfers.md) | 中文

## Problem

「通过链接分享」页上线时挂在「我的」里，与一批低频卡片并列——但生成链接是
一次**发送**动作，和「传输」页存在的理由是同一类事；想把文件交给没有装应用
的人时，用户不会想到去「我的」里找它。顺带还有两个小摩擦：卡片上的 84px
二维码能扫，却没法截图、也没法投到另一块屏幕上展示；而且这页还在用底部
[SnackBar] 作提示，尽管应用早已为同一个理由把瞬时提示统一成了顶部 toast
（[TopToast../../../../lib/ui/top_toast.dart)）。

## Decision

页面搬了家，二维码按需放大，最后几个 SnackBar 也退场了。

- **`TransfersPage` 改为有状态。** 默认视图是传输列表，顶部放一张链接分享
  入口卡——与「我的」页卡片同一形制（图标、标题、一行说明、chevron）。点
  击后翻转一个页内标志，在 [SubPageHeader../../../../lib/ui/widgets.dart)
  返回头下切到 `ShareByLinkPage`，与「我的」页「面中之面」的模式一致。用
  标志位而不是 push 路由：「传输」tab 本来就活在 shell 的 `IndexedStack`
  里，切走再切回状态自然保留；从子视图返回时分享列表也还在。
- **`_SubPageHeader` 从 `my_page.dart` 的私有控件提升为
  `widgets.dart` 里的共享 `SubPageHeader`**，因为现在有两个面都要用。
  `MyPage` 删掉了分享卡片、`shareByLink` 子页分支和
  `myCardShareByLink*` 文案；入口复用 `shareByLinkTitle` /
  `shareByLinkDesc`。
- **点卡片上的二维码弹出 `AlertDialog`**，同一链接按 256px 白底渲染，附
  「复制二维码」「关闭」两个动作。复制仍读卡片的 `RepaintBoundary`，所以
  弹窗只是同一个码的放大窗口——不存在第二份需要同步的二维码。
- **剩下的 SnackBar 全部换成 `TopToast.show`。** `share_by_link_page.dart`
  里 6 处、`screenshot_page.dart` 里 1 处——后者原先硬编码的拒绝文案也补成
  了正式的本地化 key `screenshotHotkeyUnavailable`。`flutter analyze` 与
  对 `SnackBar(`/`showSnackBar(` 的检索现在只剩注释和测试。

## Alternatives considered

**给分享页 push 一个路由。** 否决：`Navigator.push` 会在 pop 时丢掉分享列表，
而 tab 的 `IndexedStack` 本来就让页面常驻——页内标志免费拿到同样的「链接不
丢」，又不引入第二种导航概念。

**把分享 UI 作为常驻区块嵌在传输列表上方。** 用户选择了子视图方案：这页
本身已有选择按钮、说明文字和可滚动的卡片列表，常驻在每条传输卡片之上会把
真正的传输记录压到折叠线以下。

**这页保留 SnackBar。** 否决：应用早先正是因为「底部是输入区」才把底部
snackbar 换成顶部 toast；让一页留 6 个 snackbar 不是风格选择，是漏网。

**不做放大弹窗，改成「保存二维码为图片」按钮。** 作为超出需求的范围否决：
弹窗已覆盖 stated 需求（截图、投屏展示），而写文件要多走一条保存对话框路
径，去换一张本来就能复制成 PNG 的图。

## Consequences

- 「我的」不再列出链接分享；「传输」页列出，和它概念上同属的传输记录放在
  一起。功能本身——选择器、拖放、`/s/` 分组页、复制二维码——没有变化。
- 分享卡片上的二维码现在是可点目标；弹窗里的复制按钮复用卡片 boundary，
  所以「复制二维码」在两个地方行为一致。
- `lib/` 里不再有 `SnackBar`；顶部 toast 成为唯一的瞬时消息面，与此前
  toast 改造定下的约定一致。
- `SubPageHeader` 成为共享 chrome——将来第三个子页面应复用它，而不是再长
  出一份私有拷贝。

## Testing

- `test_flutter/ui/share_by_link_page_test.dart` 改为经「传输 → 通过链接分享」
  进入页面，新增用例：点卡片二维码后断言弹窗里的 `QrImageView` 大于 200px；
  「没有可分享的文件」的断言改为在窗口 overlay 里找 toast。
- 复制二维码与拖放用例不变：它们测的是页面本身，而不是到达页面的路径。
- 入口迁移由现有传输页测试全部通过间接覆盖——列表本身没有变形。

交叉引用：本 note 搬动的这个面由
[分享链接覆盖多个文件并带二维码](2026-11-17-share-links-cover-many-files-and-a-qr.zh.md)
建成；同一次改动里把该 note 中过时的事实更新为指向这里。

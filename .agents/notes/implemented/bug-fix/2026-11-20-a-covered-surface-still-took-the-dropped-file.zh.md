# Agent Note: 被盖住的界面仍然收下了拖进来的文件

Status: implemented

[English](2026-11-20-a-covered-surface-still-took-the-dropped-file.md) | 中文

## Problem

把文件拖到「通过短链分享」页面上会同时发生两件事：生成了一条分享链接，而
文件还出现在某个会话的输入框里——那个会话根本不在用户眼前。

原因出在 `desktop_drop`，而不是页面本身。它的 `DropTarget` 全局监听操作
系统的拖放，只按坐标判定：树里每一个启用的目标都检查落点是否在自己的渲染
范围内，不做命中测试，也不关心上面实际画的是什么。插件自己的文档就警告过
这一点——被推入页面盖住的目标仍会收到拖放事件——而这个应用把目标盖住了
两层：外壳的 `IndexedStack` 让每个标签页都保持挂载，被推入的
`ConversationPage` 盖在外壳之上时也不会卸载它。

于是落在分享页上的一次拖放同时触发了所有范围覆盖窗口的目标：
`ShareByLinkPage` 生成了链接，隐藏的 `ConversationView` 则把文件暂存在它的
输入框里，等用户切回去才看得见。

## Decision

`DropTarget` 只在承载它的界面确实位于最上层时才启用，而框架本来就跟踪
着界面被覆盖的两种方式——所以修复不加参数，也不动任何调用方：

- `Visibility.of(context)` 回答 `IndexedStack` 的情形。Flutter 给栈的每个
  子节点包了一层 `_VisibilityScope`，报告它是不是被选中的那一页，而
  `Visibility.of` 读的正是它——而且是响应式的，标签页一切换，目标就在同
  一帧被启用或禁用。`ConversationView` 和 `ShareByLinkPage` 都把它 AND
  进 `enable`。
- `ModalRoute.isCurrentOf(context)` 回答路由的情形：推入的
  `ConversationPage` 或盖在外壳之上的对话框会让外壳的目标仍挂载在一个
  不再是当前路由的路由之下。被推入页面自己的 `ConversationView` 能通
  过，因为它的路由*就是*当前路由——这也让独立页面无需任何额外接线就
  保持可用。

对称的泄漏不需要第二处修复：分享页的目标由同样的两项检查把关，所以它
一旦被打开就算在其他标签页之下保持挂载，被盖住时也不收拖放。

## Testing

`test_flutter/ui/share_by_link_page_test.dart` 新增「被盖住的会话不收为本
页准备的拖放」：会话打开、分享页在最上层时，会话的 `DropTarget` 报
`enable == false`，分享页的报 `true`；切回会话标签页后两者对调，因为分享
页在 `IndexedStack` 之下仍然挂载。查找以 `skipOffstage: false` 进入，因为
`find` 默认跳过 `IndexedStack` 未选中子节点——被测的正是那个「挂载但被
盖住」的部件。既有拖放测试直接调用 `onDragDone`——widget 测试驱动不了操
作系统的拖拽——所以 `enable` 标志现在也是它们钉住的契约。

## Alternatives considered

**会话在其他标签页被选中时将其卸载。** 否决：`IndexedStack` 存在的意义
正是让写了一半的会话在切换标签页后存活；为修一个输入路由的 bug 而卸载
它，等于拿这个 bug 去换栈存在的理由。

**从外壳把 `isVisible` 一路传进每个带拖放目标的页面。** 否决：能用，但
它重复了框架已经在跟踪的事实——`IndexedStack` 通过 `_VisibilityScope`
标记未选中的子节点，`Visibility.of` 正是为这个问题准备的。每页一个参数
是第二个事实来源，可能和栈自己的「谁被选中」说法不一致；路由的情形反正
也还需要 `ModalRoute.isCurrentOf`。

**不信任坐标，改为对拖放位置做 widget 树命中测试。** 否决：`desktop_drop`
已经在每个目标内部做了坐标检查；在它之上再叠一层感知可见性的命中测试，
等于为了修一个它本就暴露出来的标志去重写插件的分发逻辑。

**只在分享页打开期间禁用其他目标。** 否决：泄漏并不专属于这一对页面——
任何盖住已挂载会话的界面（另一个标签页、推入的路由、对话框）都有同样
的洞，按页面对来修会让下一个只能用同样的方式再被发现。

**在插件内部给每个 `DropTarget` 包一层路由感知的门。** 做不到：插件是
依赖，它文档写明的契约就是由*调用方*禁用被盖住的目标。

## Consequences

- 一次拖放只落在一个目标上：位于最上层的那个。
- `enable` 现在表达的是可见性，而不仅是「这个界面能不能用文件」——今后
  本应用新增的 `DropTarget` 都欠同样的两段式回答（所在界面可见、路由为
  当前）。
- 对话框盖在会话之上期间，会话的拖放目标在对话框存续期间被禁用；往模态
  上拖放本来就没有意义。
- [拖进来的文件和选好的文件一样，先在输入框里等着](../feature/2026-11-11-a-drop-stages-in-the-composer.md)
  保留其决策——一条进路、一条规则——并补上「这条路只在会话位于最上层时
  才开着」的前提；[会话长得像微信](../feature/2026-10-09-the-conversation-looks-like-wechat.md)
  在「只在有对端可发时启用」处按事实就地更新。

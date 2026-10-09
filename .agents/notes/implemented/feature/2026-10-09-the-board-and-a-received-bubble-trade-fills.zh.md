# Agent Note: 会话区的底与收到的气泡互换

Status: implemented

## Problem

会话原本是按微信的画法画的：灰色的底（`pageBackground`，`#EDEDED`），收到的消息是白气泡
（`bubbleIn`，`#FFFFFF`），发出去的是浅绿气泡。而要求正好相反 —— 白的底、灰的收到气泡，
两块底色互换 —— 代码的形状让这件事比听起来难。

`bubbleIn` 并不是「收到气泡的颜色」。它是**那个白色**，被六个角色共用：收到的气泡、卡片、
对话框、输入框、待发送附件的托盘、拖放浮层的卡片，以及 `ColorScheme` 的 `surface`、
`surfaceBright` 和三个 `surfaceContainer*` 槽位。把它改成灰，会把另外四个页面上的每一张卡片
和每一个对话框一起带走 —— 而那些页面坐在 `pageBackground` 上，正是这个气泡本该接手的那档
灰。灰卡片放在灰页面上，是一张谁都看不见的卡片。

会话区的底则是镜像的同一个问题：没有任何 token 表示「会话画在什么上面」。`ConversationView`
的历史区没有自己的底色，继承的是 `scaffoldBackgroundColor` —— 那也是设备、传输、剪贴板、
设置四个页面站的地方。改它等于为了一个窗格去重刷四个页面。

## Decision

**两块底色交换取值。** `bubbleIn` 取 `#EDEDED` —— 恰好是 `pageBackground` 原来那档灰；
会话区的底取 `#FFFFFF` —— 恰好是 `bubbleIn` 原来那个白。互换是字面意义上的。要求就是这两块
背景换个位置，所以两个 token 交换了彼此的取值，而不是各自飘到一个新灰上。

**那个白被拆成三个名字，各管一件事。** `bubbleIn` 只留收到的气泡。新的
`WeChat.surface` 是「面板」：卡片、对话框、输入框、待发送附件托盘、拖放浮层卡片、分段控件
的选中填充，以及每一个原先读 `bubbleIn` 的 `ColorScheme` 槽位。新的
`WeChat.conversationBackground` 则是会话区的底本身。

`surface` 与 `conversationBackground` 眼下同色，这是**刻意**的。把它们分开，是因为它们回答
的是不同的问题：面板是**放在**页面上的东西，而底是消息**画在**上面的东西。共用一个 token，
正是这次请求要伸进三个文件、六个控件的原因；下一次不管是「会话区调一点点色」还是「设置页的
卡片要个边」，想动的都只会是其中一个，而不是两个一起。

**底画在历史区上，不画在页面上。** `ConversationView` 用一层 `conversationBackground` 的
`ColoredBox` 包住它的历史区。页头与输入区**故意**保留各自的灰，于是动的是这个窗格，别的都不动。
会话界面那个「挑一个会话」的空窗格 —— 也就是会话本该打开的地方 —— 用同一个底，
所以空窗格和真会话在颜色上没有差别。

**图片占位跟着气泡走，不跟着页面走。** 图片气泡**内部**那两个盒子（读取中的占位、解不出的
占位）原来是 `pageBackground` —— 而现在那就是收到气泡自己的灰。灰盒子放在灰气泡里是看不见的，
偏偏还发生在最需要说点什么的那几条消息上。它们改成 `surface`，在灰气泡和绿气泡里都读作
「在填充上开了一个洞」。

## Alternatives considered

**把 `bubbleIn` 改成灰，接受灰卡片。** 一行改动，不加 token。直接否掉：另外四个页面是白卡片
放在 `pageBackground` 上，于是它们的卡片会变成灰压灰。要求点名的是会话，而这样做改掉的
是大半个应用。

**把 `scaffoldBackgroundColor` 改成白。** 也是一行，而且确实会给会话重新上色。否掉，因为它
同时给设备、传输、剪贴板、设置四个页面上色 —— 白卡片放在白页面上，是同一个错误从另一头发生。
而且收到气泡仍是白的，那就根本没有任何东西互换过。

**只命名一个白，会话区与面板共用。** token 更少，在两者恰好同色的当下也说得通。否掉，因为它
把这则笔记的起因 —— 那种耦合 —— 又装了回去：底和面板必须一起动，下次关于其中任何一个的要求
仍然是六个控件的改动。

**给 `bubbleIn` 一个全新的灰，而不是页面那档精确值。** 稍微不同的灰能让「气泡的灰」和
「页面的灰」不至于在读代码的人脑子里糊成一团。否掉，因为要求是两块底色互换：底交出
`#EDEDED`，气泡就接手它。另造第三种灰是另一个改动，而且没人要过。

**图片占位留在 `pageBackground` 上。** 它们本来不算错，也没有测试点名过它们。否掉，因为它们
坐在气泡**里面**：一旦收到气泡就是它们原来那个灰，它们就会在最需要提示「这张图读不出来」的
消息上消失。

## Consequences

**`bubbleIn` 不再在任何地方意味着「白」。** 每一个把它当「面板色」读的地方都移到了 `surface`
—— `conversation_view.dart` 四处、`theme.dart` 四处 —— 而找一个白的人现在有两个具名 token
可选，而不是一个心照不宣的。编译器在这件事上帮不上忙：这八个调用点在改动前后都完美通过类型检查。

**灰卡片从此是犯错的症状。** 面板色拆出去之后，一张卡片画成灰，就意味着某处该拿 `surface` 的
地方拿了 `bubbleIn`。这是一行 grep 的事，而不是没有这次拆分时那种六个控件的排查。

**三个 token 是同一个白，所以基于颜色的 widget 测试分不出它们。** `surface`、
`conversationBackground` 和 `ColorScheme.surface` 今天都是 `#FFFFFF`。widget 测试能断言历史区
**不是**坐在页面灰上 —— 这正是要紧的那个回归 —— 但断言不了它坐在哪一个白上。因此「某个控件
用的是哪个 token」靠 `shell_test.dart` 里的 token 断言和 review 来守，而不是靠一条 widget 层面的失败。

**收到的气泡是被当作关系钉住的，而不是钉在屏幕上。** 套件里没有一个已 pump 的窗口显示着
**收到**消息的会话：双窗口端到端用例结束时文件落在 Bob 的目录里，而不是在他的会话里。所以
`bubbleIn` 由 `WeChat.bubbleIn == WeChat.pageBackground`、由
`bubbleIn != conversationBackground`、以及 `MessageBubble` 那行没动过的
`outgoing ? bubbleOut : bubbleIn` 共同守住。要在屏幕上断言那个灰气泡，需要在已 pump 的会话里
出现一条收到的消息 —— 那是这次改动并不需要的夹具工作。

## Testing

`test_flutter/ui/shell_test.dart` 新增一条名为 `the conversation board and a received bubble
have traded fills` 的用例。它断言的是**关系**而不是取值 —— 底等于 `WeChat.surface`、气泡等于
`WeChat.pageBackground`、两者互不相等 —— 因为要求就是两块底色换了位置，而日后只动其中一个
的调整会悄悄把它撤销。接着它检查面板那几种角色没有跟着气泡走：卡片、对话框和
`ColorScheme.surface` 全是 `WeChat.surface`。主题那组里有一条断言从 `WeChat.bubbleIn` 改指到
`WeChat.surface`，因为卡片是面板。

`test_flutter/ui/pages_test.dart` 的 `picking a conversation opens it beside the list` 现在顺着
空态文字往上找那块底，断言它上面有一层 `WeChat.conversationBackground` 的 `ColoredBox`，
断言两次：一次给「挑一个会话」那格，一次给打开后的会话。按它包含的文字而不是按位置去找，
才让这条断言是在说历史区、而不是在说布局 —— 而且既然页面灰和底不同色，历史区一旦退回继承
它就会失败。`text sent from the pane arrives with no answer needed` 断言会话里那唯一一个气泡
用的是 `WeChat.bubbleOut`：那个**没有**换位的填充，钉住它，免得日后重新排布两者时把发出去的
消息一起带走。

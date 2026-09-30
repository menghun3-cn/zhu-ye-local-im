# Agent Note: 界面默认说中文

Status: implemented

[English](2026-09-30-interface-language-defaults-to-chinese.md) | 中文

## Problem

打包出来的应用是英文界面。用户能看到的每一句话都是写在 widget 里的字面量，
整个项目也没有任何本地化层：没有 ARB 文件、没有 `flutter_localizations`、
没有 delegates。要把这个构建交到真正的使用者手里，要么把每条字面量改写
成中文，要么让它学会不止说一种语言——而只有后者在下一个字符串到来时才不
会退回去。

这个问题里有两部分，光看 widget 是看不出来的。

第一，一个窗口并不只由应用自己的文字组成。每个 `TextField` 上的文本选择
菜单——剪切、复制、粘贴、全选——以及 `AlertDialog` 的语义等等，都是
Material 自己的一套词，来自 `GlobalMaterialLocalizations`。只翻译字面量
就收手，会得到一个中文界面，而里面的输入框照样弹出英文的「Paste」。只有
装上 `flutter_localizations` 才能修掉这一点。

第二，并不是每一句给用户看的话都写在能翻译的地方。`AppStateException`
携带的是一句在 `lib/app` 里拼好的英文文本，而那一层被禁止 import Flutter
——`test/app/plain_dart_test.dart` 就是守住这条线的门禁。于是像
「no address is known for 3f9a…; it has to be discovered before it can be
dialled」这样的拒绝理由天生就是英文，在 `lib/ui` 里做多少工作都碰不到它。

## Decision

界面改用 Flutter 自带的生成器做本地化，并且打开就是中文。

* `lib/l10n/app_en.arb` 是模板——每个键先落在这里，并声明占位符类型——
  `lib/l10n/app_zh.arb` 是译文。`l10n.yaml` 把类生成到
  `lib/ui/l10n/generated`，并且**入库提交**，这样分析器和格式化器看到的文件
  和构建看到的完全一致，而不是一个只有 `flutter build` 才知道的合成包。
  ARB 文件放在 `lib/l10n`、生成出来的类放在 `lib/ui`，这是有意的：ARB 不
  import 任何东西，而那个类 import Flutter。把两者分开，才能让
  `test/app/plain_dart_test.dart` 继续断言「Flutter 只存在于 `lib/ui`」——
  而且是**不需要为它开例外地**继续断言。
* `appLocale` 是 `Locale('zh')`，作为 `locale` 传给每一个 `MaterialApp`。
  它是固定的，不随平台解析：界面上没有任何语言设置，跟随平台会让语言取决于
  一个没人替这个应用选过的 Windows 设置。`appLocales` 是 `[zh, en]`——**有
  序**，这样将来若把 `appLocale` 放开为 null，两者都不是的语言**回落**到的
  是中文而不是英文（`AppLocalizations.supportedLocales` 按字母序排，会回落到
  英文）。
* `lib/ui/labels.dart` 和 `describeFailure` 保持纯函数，把查好的文案当作参数
  接进来。各页面仍然在 `build` 里读一次 `AppLocalizations.of(context)`，再
  往下传。
* `AppStateException` 不再携带一句话，而是携带一个 `AppRefusal`——调用方
  要了、而当前状态给不了的事情的**封闭集合**——外加一个可选的 `detail`，
  里面装的是**数据**：指纹、端口号、文件名。由 `lib/ui/labels.dart` 里的
  `describeRefusal` 把这两样拼成一句话。理由以 UI 能处理的形式往上走，app
  层不再写散文。
* 核心层的失败适用相反的规则。`PairingException` 与 `HandshakeException`
  原样保留它们的 `message`，由 UI 给它套一个中文框子——
  「无法连接到该设备：{detail}」。冒号后面是关于网络的事实，往往就是操作
  系统自己的 `SocketException` 文本；改写它只会让人更难据此行动，不会更好。
* 有一种核心层失败会套第二个框子，而且靠的是**种类**而不是去匹配它的文本。
  因为「拨号根本没落地」而抛出的 `PairingException` 会带上
  `unreachable: true`，`describeFailure` 用它取 `failureCannotReach`——先把
  原样的细节接上，再说明该检查什么。理由是：拨不通意味着对方程序没在运行、
  在另一个网络、或者被防火墙挡着，这三件事本应用既修不了，也无法从操作
  系统那句话里推断出来。用一个标记而不是去匹配某个短语，是为了不让这个判断
  在操作系统换一次措辞之后无声地失效。

## Alternatives considered

**直接就地把这些字面量改成中文，到此为止。** 否决：它会留下 Material 自己的
词——每个输入框的选择菜单、对话框语义——仍是英文。一个处处中文、唯独问你
要输入的那个框不是中文的界面，不算翻译过的界面。

**跟随平台语言，中文作兜底。** 对这个构建否决：界面上没有任何地方能改语言，
于是语言会取决于一个用户从未与这个应用产生关联的操作系统设置；一台配置成
英文的机器会显得这个需求根本没被满足。等有了语言设置，把 `appLocale` 改成
null 就是那一行改动。

**把 `app_zh.arb` 当作模板，好让生成的 `supportedLocales` 把中文排在最前。**
考虑过，它确实能解决回落顺序。否决：模板是维护键名、说明和占位符元数据
的地方，这些应该用写代码的那门语言来写。顺序改在消费它的那一个地方处理。

**保留 `AppStateException` 上的散文 `message`，靠一张表把英文原文查成译文。**
否决：以句子为键的查表，在有人改掉一个词的那一刻就会静默失效，而且失效的
表现是「少了一句翻译」，不是编译错误。

**手写一个 strings 类，不用代码生成。** 否决：复数、插值和 Material 的
delegates 恰恰是生成器已经在做的事，手写版得为每个字符串把这几样重新推导
一遍。

## Consequences

- 应用打开就是中文；英文是完整的、已生成的，离成为默认只差一行。
- `lib/ui/l10n/generated` 是入库的源码。重新生成它用 `flutter gen-l10n`，
  而 `flutter pub get`、`flutter build`、`flutter test` 都会依据
  `pubspec.yaml` 里的 `generate: true` 自动做一次。
- 新增两个依赖：`flutter_localizations`（随 SDK）与 `intl`。`lib/core`
  没有新增任何依赖，两者都与它无关。
- app 层不再拼给用户看的文字。`AppRefusal` 是「拒绝」与「说法」之间的契约：
  新增一个拒绝项之后，`describeRefusal` 不处理它就是一个编译错误。
- `test_flutter` 构造窗口时用的是与真实应用相同的 locale 和 delegates，
  并把加载好的 `l10n` 暴露出来给测试驱动标签。因此一个点「配对」的测试，
  断言的就是这个构建的用户真正看到的字；而双窗口 E2E 测试会在界面以没人
  要过的语言启动时失败。

# Agent Note：用错斜杠拼出的目录，打开了「文档」

状态：implemented

[English](2026-10-10-a-folder-spelled-with-the-wrong-slash-opened-documents.md) | 中文

## Problem

收到一个文件，右键选 **打开所在目录**，Explorer 打开的却不是那个文件所在的目录——而且不是报错：它打开的是用户的「文档」。一个全部职责就是回答「这东西跑哪儿去了」的动作，回答的是别处，并且一声不吭。

路径本身没错。`LocalTransferController.acceptInto`（`lib/app/app_controller.dart`）记下的正是 sink 真正写进去的那个文件，`folderOf` 从它上面取下目录部分，而针对一条真实接收路径的形状所做的探针把这两半都确认了：

```
incoming      = C:\Users\admin/Downloads/LocalTransfer
file          = C:\Users\admin/Downloads/LocalTransfer\WinDirStat (2).exe
parent        = C:\Users\admin/Downloads/LocalTransfer
parent == incoming? true
```

`parent` 就是文件所在的目录。它同时**是用 `/` 拼的**，而这就是整个 bug：`explorer.exe` 会把参数里的 `/` 解析成它自己的某个命令行开关的开头。有文档的是 `/e`、`/select`、`/root`，而这个解析发生在任何东西被当作路径解析之前——于是 `C:\Users\admin/Downloads/LocalTransfer` 被读成盘符 `C:` 后面跟着两个没人发过的开关，没有任何一个路径 token 活下来，Explorer 退回它的默认外壳目录。「文档」是症状；参数里一个正斜杠是原因。这是 Explorer 自己的解析器独有的脾气，别的东西都没有：macOS 的 `open`、Linux 的 `xdg-open`、以及 Windows 上任何一个代码编辑器都好好接受 `/`。这是 Windows 上广为人知的坑，不是猜的——一份 Python `subprocess` 年代的 Stack Overflow 回答，和一个在 Windows 桌面应用里修同一件事的 GitHub PR（`explorer.exe "D:/Projects/x"` → 文档，`explorer.exe "D:\Projects\x"` → 该目录），用的是同一套说法。

本项目之所以递给它一个 `/` 拼的目录，是刻意的且有文档：`defaultIncomingDirectory` 在所有平台上都用 `/` 拼路径，因为它必须用同一个函数回答 Android 的问题，而一个按*宿主*惯例拼分隔符的函数做不到这件事。随后 `incomingPathFor` 用 `Platform.pathSeparator` 追加文件名，所以一条接收路径是真正的混合体——目录之前是 `/`，文件名之前是 `\`——而 `folderOf` 把 `/` 的那一半原样交给了 Explorer。

实践里被击中的只有默认目录（`Downloads/LocalTransfer`），这也解释了为什么发送方那边、以及手打的 `D:\inbox` 看起来都正常：用户用 `\` 打的目录里没有斜杠可被误读。

## Decision

在目录不再是一个 Dart 字符串、而变成别人解析器的参数的那一刻做转换——一个函数，一个调用点：

```dart
// lib/ui/reveal.dart
await Process.run('explorer', [explorerArgument(folder)]);

/// The one argument [folder] becomes on `explorer`'s command line.
String explorerArgument(String folder) => folder.replaceAll('/', r'\');
```

转换的只有参数。目录本身继续是应用其余部分使用的那个字符串，因为 `\` 不是关于目录的事实——同一个字符串在一切平台上都被 `Directory`、`File` 和选择器正常打开——它是关于 Explorer 的事实。放在这里也顺便覆盖了用户在接收对话框里手打 `/` 的目录，那是路径构造函数再小心也够不到的：转换发生在出去的路上，那时应用里每一条路径都已经定好了。

测试断言的是那个参数，不是一个窗口：`explorerArgument` 是纯 Dart，所以 `test/ui/reveal_test.dart` 端到端钉住这次回归——一条接收文件的完整路径进去，一个反斜杠目录出来——另外两个平凡用例（`/` 拼的目录被转换、Windows 拼的目录原样不动）也一并钉住。

## Alternatives considered

**在 `defaultIncomingDirectory` 里用 `Platform.pathSeparator` 拼目录。** 否决：那个函数把 `platform` 当作*输入*，并在不跑在任何一方的前提下被 Android 和 Windows 两个平台的测试覆盖，所以它不能问宿主任何问题。它的调用者需要的是「每个平台一个答案」，不是「每台机器一个答案」。

**在 `incomingPathFor` 里做归一化。** 考虑过——它确实能治好观察到的那一例，因为接收路径会变成完全原生。但作为*唯一的*修法被否决，有两个理由：它对用户在接收对话框里手打 `/` 的目录毫无帮助；而且它会把这条规则留在构造文件名的函数里，而不是留在需要它的边界上。混合分隔符的路径对本应用除 Explorer 之外的每一个消费者都无害，所以该被局部化的例外是 Explorer，不是路径。

**在 `folderOf` 里转换。** 否决：`folderOf` 回答的是*哪一个*目录，它的答案在任何平台上都被当作纯字符串测试。让它交回一个 Windows 拼法的路径，等于把一个关于某个外壳解析器的事实折进一个与该外壳无关的函数。

**顺手用 `explorer /select,<文件>` 高亮文件。** 否决，维持
`2026-10-09-images-arrive-on-their-own-and-a-file-can-be-shown-in-its-folder` 记录的决定：那个开关和它的参数共用一个 token，所以带空格的路径需要整个 token 被引号包住，而带空格是本项目里 Windows 上的寻常情况。值得一提：上面的开关解析正是同一根因从另一面看过去——`/select,` 是 Explorer *本就该*收到的开关，而一个裸路径里的 `/` 是它从没打算看见的。

**像 `external_links.dart` 打开网址那样，走 `cmd /c start` 打开目录。** 否决：那是拿 Explorer 的解析器换 `cmd` 的解析器，而 `cmd` 会把自己那套引号陷阱（`&`、`^`、空格）带到一个部分受对端影响的路径上（经由文件名）。斜杠修好之后，`explorer <目录>` 没有任何东西需要引、需要转义。

## Consequences

- 接收文件上的 **打开所在目录** 现在打开的确实是文件所在的目录——包括默认的 `Downloads\LocalTransfer`，那正是坏掉的那一例。
- 用户在接收对话框里手打 `/` 的目录同样可用，因为转换发生在他的回答之后，而不是之前。
- `folderOf` 与发送方那条路径都没动，所以「哪一个目录」这个答案没有任何变化：变的只是它为一个读不懂它的程序怎么拼。
- 「把错误的分隔符交给另一个程序」现在有了名字（`explorerArgument`）和测试，而不再是一个谁脑子里都不装的风险点——此前回避 `/select,` 的那个决定，是在完全不知道 Explorer 把 `/` 读成开关的情况下记下的。
- 纯 Dart：`dart test` 覆盖新函数，而 `test_flutter` 里的 reveal 缝依然替换整个 revealer，所以套件里 `ScriptedRevealer` 的那些断言不受影响。

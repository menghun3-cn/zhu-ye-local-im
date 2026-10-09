# Agent Note: 一个非 ASCII 的注释弄坏了 Windows 构建

Status: implemented

## Problem

`windows/runner/main.cpp` 由 MSVC 编译，而本机上的 MSVC 在没人告诉它别的情况下，会把源文件
按系统代码页（936）来读。

改名把产品名以 `\u` 转义写进了标题栏 —— 这是对的，也是纯 ASCII。但它旁边那行注释把名字用
散文写了出来，还用了两个破折号（`U+2014`）。每个破折号是三个 UTF-8 字节，而三个 UTF-8 字节
按 GBK 读不成一个合法字符：MSVC 给出 **C4819**（「文件包含在当前代码页中无法表示的字符」），
而 runner 自己的 CMake 设置把警告提升为错误（**C2220**），于是构建在产出 exe 之前就停了。

合并之前没有任何东西拦下它。`flutter analyze`、`dart format`、`dart test`、`flutter test`
都不编译 `windows/**`；唯一会编译它的只有 `scripts/pack-windows-portable.ps1`，而那是一个
打包步骤 —— PR 合并时它还没被跑过。唯一能抓到它的那道门禁，只在打包时才跑。

## Decision

**这个文件是纯 ASCII 的，而且现在自己写明了这一点。** 两个破折号去掉了，注释里写清了它遵守的
规则 —— 这里一个非 ASCII 字节就是按 CP936 读出来的 C4819，会被 runner 的构建提升为错误 ——
于是下一个想在 C++ 源码里直接写「竹叶局域网传输」的人，会被告诉要用转义。标题本来就是转义的；
出问题的只有它周围那段散文。

**对 `windows/` 下的任何改动，Windows 构建本身就是门禁的一部分。** 六道门禁对 runner 一无所
知，所以那里的改动在合并前必须用 `scripts/pack-windows-portable.ps1`（至少也要
`flutter build windows --release`）验过 —— 因为别的东西不会发现它已经编不过了。

## Alternatives considered

**给 runner 的编译选项加 `/utf-8`。** 这是针对这一整类问题的通解，而且能让源码直接持有那些
字符。否掉，因为这是比缺陷本身更大的改动：它要改生成的 CMake 列表，而将来一次
`flutter create` 重新生成会把它覆盖掉；而且它会让下一个非 ASCII 字节悄悄通过，而不是变成一个
文件本身会警告你的事情。

**保留注释，把文件存成带 BOM 的 UTF-8。** MSVC 认 BOM，所以这样也能工作。否掉，因为文件的
编码从此在 review 里看不见、下次保存也很容易丢掉 —— 同一个故障会在某个编辑器重写文件的瞬间
回来。

**把注释删掉。** 它下面那行转义本身就说明了问题。否掉，因为**为什么要转义**恰恰是读者需要的
信息；没有它，下一次编辑就会把名字写出来，再一次弄坏构建。

## Consequences

`windows/runner/main.cpp` 重新是纯 ASCII，于是它在工具链挑中的任何代码页下都能编译，而那条
规则被写在改它的人最可能去看的那一个地方。

更深一层的后果是关于流程的，所以它写在**这里**而不是只写在文件里：**六道门禁不编译 Windows
runner。** `windows/` 下的改动，只有把它构建出来才算被证明过。

## Testing

`scripts/pack-windows-portable.ps1` 现在还把「关于」页引入的四个字形 —— `Icons.info`、
`Icons.info_outline`、`Icons.system_update_alt`、`Icons.open_in_new` —— 放进了它的必备集合，
并把「关于」页的两句整句放进了文案探针。端到端跑一遍它，就是证明 runner 能编译、图标真的进了
字体（10/10）、新文案真的在 `app.so` 里（17/17）的东西；它的冒烟步骤会启动打好的 exe，确认它
能应答、并绑上 UDP 47654 与 TCP 47656/47655。

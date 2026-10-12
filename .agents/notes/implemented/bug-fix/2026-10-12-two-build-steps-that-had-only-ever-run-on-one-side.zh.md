# Agent Note: Two build steps that had only ever run on one side, and a third that had never run at all

Status: implemented

[English](2026-10-12-two-build-steps-that-had-only-ever-run-on-one-side.md) | 中文

## Problem

`v0.1.0` 是这个仓库推过的第一个 tag，所以发布工作流的首次执行也就是这条流水线的首次执行。这一次：校验版本号通过，**两个构建作业全红**。什么都没发出去 —— `release` 作业依赖那两个作业，所以没有建出 Release，没有上传任何产物。

两处失败都不在产品里，都在工具里，而且都是**只在写它的那台机器上**被行使过的假设 —— 有一个则从未被行使过。

| 位置 | 它假设了什么 | 这个假设为什么不再成立 |
| --- | --- | --- |
| [`scripts/pack-windows-portable.ps1`](../../../../scripts/pack-windows-portable.ps1) | zip 条目名用 `\` 拼 | 分隔符跟着**跑脚本的 PowerShell 版本**走：Windows PowerShell 5.1（.NET Framework）写 `data\app.so`，PowerShell 7（.NET 5+）归一成 `data/app.so`。本地每一次跑脚本都是 5.1；工作流里的 `shell: pwsh` 是 7 |
| [`android/app/build.gradle.kts`](../../../../android/app/build.gradle.kts) | `java.util.Properties()` 指的是 JDK 那个包 | 在 Gradle Kotlin DSL 脚本里 `java` 是 Java 插件扩展，于是 `java.util` 被当成对它的成员查找 —— `Unresolved reference 'util'`，紧接着 `'io'` 一样 |
| [`scripts/fetch-sources.ps1`](../../../../scripts/fetch-sources.ps1) | 这个文件自己的字节是 UTF-8 | 没有 BOM 时，PowerShell 5.1 按本机 ANSI 代码页（这里是 936）解 `.ps1`，乱码即语法错误。一共 9 个 |

前两条是拦住发布的那两处失败。第三条是去找同类问题时发现的；它从没在任何地方跑过，所以也从没有谁报过它。

**Kotlin 那一条是怎么进去的。** 流水线需要的签名段由 `4f702ea`（*build the three release packages from a tag*）引入，而本机最后一次 Android 构建是 2026-10-10 的模拟器那一次 —— 早了五天。`git log -S 'java.util.Properties' -- android/app/build.gradle.kts` 返回的就是那一个提交。也就是说这段代码第一次被编译是在 CI 上：这个缺陷表现为一个红的作业、而不是一个坏掉的本地构建，原因就是本地从来没有构建包含过它。

**zip 那一条更值得记，因为坏掉的那个校验本来在干正事。** `data\app.so` 与 `data\icudtl.dat` 都在包里。校验看不见它们，于是报它们缺失。**用产出者的词汇拼出来的校验，与产出者共享同一个盲区** —— 这和「没有校验」是两回事，而且更难察觉。

## Decision

**zip 条目名在进入字典那一处归一，而不是在每个查找点上。** `$entries` 现在按 `$e.FullName -replace '/', '\'` 存键。三处调用点继续问 `data\app.so` —— 探针文案、图标字体、`app.so` 哈希 —— 而答案不再取决于哪个 PowerShell 产出了这个包。

**`.kts` 脚本用到什么就 import 什么。** `android/app/build.gradle.kts` 开头是 `import java.io.FileInputStream` 与 `import java.util.Properties`，正文用短名。在构建脚本里把 `java.` 写全不是「省掉一个 import」，而是让一个恰好叫这个名字的插件扩展把你遮住。

**`scripts/fetch-sources.ps1` 带上它兄弟们都带的 BOM。** `scripts/` 下四个脚本现在都以 `EF BB BF` 开头 —— 正是这个前缀让一份带中文注释的脚本能被两个 PowerShell 版本都解析，而不是只有代码页恰好对得上的那一个。

**只有 CI 能看见的缺陷，必须在本地被复现，而不只是被修掉。** 分隔符那一条是在本机复现的：造一个条目名用前斜杠的 zip（正是 PowerShell 7 产出的字节），拿旧逻辑和新逻辑分别去查。旧逻辑报出的正是 CI 报的那两个文件，新逻辑一个都不缺。这个复现是本机唯一能触及 CI 条件的办法，因为本机没装 PowerShell 7。

## Alternatives considered

**把 CI 钉回 Windows PowerShell 5.1（`shell: powershell`）。** 否决：这等于把一个只剩维护的宿主当成契约。PowerShell 7 是这门语言的方向，工作流得永远拒绝它，而绿的结果从此依赖于旧引擎不被退役 —— 同一类脆弱，只是搬到了更难看见的地方。

**在每个调用点上把两种拼法都问一遍。** 否决：三处查找各自都要记得，将来每一个新键也都要记得。在填字典那唯一一处归一，就只有一处要写对。

**删掉 zip 内容校验，反正把作业弄红的就是它。** 否决：它全项目唯一在读**交付物本身**、而不是读产出它的那棵树，而且它已经抓到过两件构建抓不到的事 —— 还在找一个已被删掉的句子的探针，以及不再被重新生成的图标字体。包就是用户拿到的东西；打开它的校验是最后一道诚实的门。

**只把 `java.` 前缀去掉，不加 import。** 否决：`Properties` 与 `FileInputStream` 都不在脚本的默认 import 里，失败只会往下挪一行，改名叫 `Unresolved reference 'Properties'`。

**加一条在 PR 上跑打包脚本的工作流，让它在发布存在之前就被抓到。** 推迟，不是否决：那是明摆着的下一步，也比这一改动大。这里要紧的是**两个缺陷都仍然需要 CI 才能发现**，所以发布作业并不是抓这一类问题的错误位置，只是太晚。

**升到 `0.1.1`，失败的那个 `v0.1.0` tag 留着不动。** 否决：`v0.1.0` 是这个项目切过的第一个发布版，它名下什么都没发布，而[拥有流水线那篇 note](2026-10-12-a-tag-builds-the-three-packages.md) 已经写明了这种情况该怎么做。把 `0.1.1` 当作**第一个**发布版发出去，等于把一个人人问不出所以然的版本号摆到每个用户面前。

## Consequences

- zip 那处修复由上面的本地复现验证；Kotlin 那处由 Gradle 的配置阶段验证（在 `android/` 下 `gradle --dry-run help`），它编译两个 `.kts` 脚本而不构建 APK —— 正是 Android 作业死掉的那个错误。
- `scripts/fetch-sources.ps1` 在 5.1 下 0 个 PowerShell AST 解析错误，原为 9 个。它从没被跑过，所以也从没被察觉。
- **门禁依旧看不见这一类缺陷。** `AGENTS.md` §5 里没有任何一项会跑构建脚本，而本机没有 PowerShell 7 —— 所以一个在两个版本之间不同的分隔符或编码假设，仍然只有推一个 tag 才能抓到。这篇 note 记录这个缺口，而不是关掉它。
- **`v0.1.0` 被重推到含本修复的 `master` tip 上。** tag 会移动，版本号不动。已经取过那个失败 tag 的树的人，会为同一个 tag 名拿到另一个提交 —— 这就是「第一个发布版用它自己的号发出去」的代价，只有在它名下什么都没发布过时才可接受。
- 三个产物当时都只是部分被证明 —— 此后各自都被行使过了。portable zip 一路走到抛错的那一步校验；APK 在 `v0.1.0` 的第三次执行上编译成功；而同一次执行里，Inno Setup 在解析 `packaging/local_transfer.iss` 之前就拒收了参数列表 —— 那是[第四个、属于它自己那一类的缺陷](2026-10-12-a-define-that-was-spelled-without-its-d.zh.md)，而不是这三个的第四个实例。

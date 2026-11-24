# Agent Note: 备注弹窗的说明文字被省略号截断

Status: implemented

[English](2026-11-24-the-remark-helper-ellipsized.md) | 中文

## Problem

「修改备注」弹窗里的说明句——「只在本机显示，代替对方自报的名称或地址，
对方看不到。留空即清除。」——实际显示成「只在本机显示，代替对方自报的
名…」：整句解释的后半截，包括「留空即清除备注」这条最需要用户提前知道
的行为，被省略号截掉了。

根源是 `InputDecoration` 的一个默认值，不是弹窗宽度。`helperText` 字符
串以 `overflow: TextOverflow.ellipsis` 和 `maxLines: helperMaxLines` 绘
制，而 `helperMaxLines` 默认为 null——框架文档写明此时「软换行被省略号
截断，硬换行（\n）保留」。应用里其余的说明句都短到一行放得下，备注这句
是第一个长到暴露这个截断的。

## Decision

备注弹窗的说明从 `helperText` 挪到了 `helper`——`InputDecoration` 为这
种场景准备的 widget 槽位：一个承载 `l10n.remarkHelper` 的 `Text`，样式取
主题的 `inputDecorationTheme.helperStyle`，于是字号、颜色、字体与其它说
明文字一致，同时能按需换到任意多行。`helper` 占据字段下方同一个位置，
让位给 `errorText` 的方式也与 `helperText` 相同；这个弹窗没有错误态，字
段其余行为不变。

`helperMaxLines` 是另一个可调的旋钮，这里否决了：它仍然限制行数、超过
即省略，把截断换成了更高的截断。选一个数字等于在猜两个语言版本将来最
长会有多少行——英文那句已经是两者中较长的，在弹窗宽度下要占好几行。

## Alternatives considered

**把 `helperMaxLines` 设成固定行数。** 否决：只是把一种截断换成另一种
更高的截断。任何有限上限都会在某个语言版本或更长的句子需要再多一行时
把同一个缺陷请回来，而「正确」的数字是翻译的属性，不是控件的属性。

**把弹窗加宽。** 否决：省略号是按行截断的，不是按整段——加宽只是推迟截
断，而且英文那句长到任何合理的弹窗宽度都放不进一行。

**把句子改短。** 否决：「留空即清除」是用户在输入前最需要知道的行为，
且两种语言都得保住这层意思；框架对长说明文字的答案是换行，不是为迁就
默认值去改文案。

## Consequences

- 备注弹窗的说明在两种语言下都能完整换行显示，「留空即清除」始终可见。
- 今后任何长说明文字的范式是 `helper:` 加主题的 `helperStyle`，而不是调
  大 `helperMaxLines`。
- 其余弹窗继续用 `helperText`：它们的句子一行放得下，换成 widget 只会
  多出样式样板而没有任何可见变化。

## Testing

- 手工验证：对某个对端打开「修改备注」，确认说明文字换成多行且没有省
  略号；中文与英文界面各看一遍。

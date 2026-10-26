# Agent Note: 打包字形清单必须与源码用到的图标一致

Status: implemented

[English](2026-10-26-pack-glyph-list-must-match-source-icons.md) | 中文

## Problem

`scripts/pack-windows-portable.ps1` 点名必须出现在包内
`MaterialIcons-Regular.otf` 里的字形。这份清单是项目对图标子集陈旧的真实防线，
但当源码停用其中一个图标时，它自己也会变成过时检查。移除关于页单独的
「下载并更新」按钮，同时移除了 `Icons.download_outlined` 在源码里的唯一使用；
tree-shaker 正确地把 `0xeff2` 从字体里裁掉，发布时的冒烟检查就因一个源码不再
需要的字形而失败。

## Decision

必需字形清单只包含当前源码用到的 code point。移除源码图标时，在同一次改动里
移除它的清单项，让每个列出的字形旁边的注释描述的是当前源码，而不是过去界面的
记录。单按钮用的 `Icons.system_update_alt`（`0xe637`）仍保留在清单里。

## Alternatives considered

**把已移除的字形留在清单里。** 它不再对应源码中的任何使用，只要图标子集跟着源码
走，它就会让之后每一次构建失败。

**把清单缺项从报错降级为警告。** 这条检查的存在就是为了不让画出来全是空图标
的包发出去；为过时条目放宽它，也会为真正缺失的字形放宽它。

## Consequences

- 关于页的操作不再让打包字形清单落后源码一个条目。
- 剩余清单仍是这份发布必须画出的图标集合的完整陈述，它要抓的「源码图标与字体
  分叉」问题仍然被抓得住。

## Testing

这是一条与被保留的单按钮图标对应的清单项变更；存在构建产物后
`.\scripts\pack-windows-portable.ps1 -Smoke` 通过。

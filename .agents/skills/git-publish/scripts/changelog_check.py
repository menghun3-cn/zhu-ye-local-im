#!/usr/bin/env python3
"""git-publish 的 CHANGELOG 格式校验脚本。

校验 Keep a Changelog 风格的 CHANGELOG：
- 必须存在 `## [Unreleased]`，且其与下一个版本条目之间没有遗留内容
- 第一个版本条目标题必须形如 `## [A.B.C] - YYYY-MM-DD`
- 日期必须是真实存在的 ISO 日期
- 分类只允许：新增、修复、变更、移除、安全
- 每个分类下至少有一个列表项
- 可选校验目标版本号是否与标题一致
"""

from __future__ import annotations

import argparse
import datetime
import re
import sys
from pathlib import Path

ALLOWED_CATEGORIES = {"新增", "修复", "变更", "移除", "安全"}
VERSION_TITLE_RE = re.compile(r"^##\s+\[(?P<version>[^\]]+)\]\s+-\s+(?P<date>\d{4}-\d{2}-\d{2})$")
UNRELEASED_RE = re.compile(r"^##\s+\[Unreleased\]\s*$")
CATEGORY_RE = re.compile(r"^###\s+(?P<category>新增|修复|变更|移除|安全)\s*$")
BULLET_RE = re.compile(r"^\s*-\s+")


def fail(message: str) -> None:
    print(f"✗ {message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    # Windows 控制台默认 GBK，显式用 UTF-8 输出，避免 ✓/中文提示触发编码错误。
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass

    parser = argparse.ArgumentParser(description="校验 CHANGELOG 格式")
    parser.add_argument("--file", default="CHANGELOG.md", help="CHANGELOG 文件路径")
    parser.add_argument("--version", default="", help="期望的目标版本号（可选）")
    parser.add_argument("--require-unreleased-empty", action="store_true", help="强制 [Unreleased] 为空")
    args = parser.parse_args()

    path = Path(args.file)
    if not path.is_file():
        fail(f"{args.file} 不存在")

    lines = path.read_text(encoding="utf-8").splitlines()
    unreleased_index: int | None = None
    release_indices: list[int] = []

    for index, line in enumerate(lines):
        if UNRELEASED_RE.match(line) and unreleased_index is None:
            unreleased_index = index
        if line.startswith("## [") and index != unreleased_index:
            release_indices.append(index)

    if unreleased_index is None:
        fail("缺少 `## [Unreleased]` 标题")

    if not release_indices:
        fail("`[Unreleased]` 之后没有版本条目")

    if args.require_unreleased_empty:
        pending = [line for line in lines[unreleased_index + 1 : release_indices[0]] if line.strip()]
        if pending:
            fail("`[Unreleased]` 与下一个版本条目之间存在未归档内容")

    first_release = release_indices[0]
    title = lines[first_release]
    match = VERSION_TITLE_RE.match(title)
    if not match:
        fail(f"版本条目标题格式应为 `## [A.B.C] - YYYY-MM-DD`，实际为：{title}")

    version = match.group("version")
    date_text = match.group("date")
    try:
        datetime.date.fromisoformat(date_text)
    except ValueError:
        fail(f"版本日期不是有效日期：{date_text}")

    if args.version and version != args.version:
        fail(f"版本号不一致：CHANGELOG 为 {version}，期望 {args.version}")

    section_end = release_indices[1] if len(release_indices) > 1 else len(lines)
    section_lines = lines[first_release + 1 : section_end]
    category_indices: list[int] = []

    for index, line in enumerate(section_lines):
        category_match = CATEGORY_RE.match(line)
        if category_match:
            category_indices.append(index)

    if not category_indices:
        fail("版本条目下没有任何分类")

    categories_found: set[str] = set()
    for pos, index in enumerate(category_indices):
        category = CATEGORY_RE.match(section_lines[index]).group("category")
        categories_found.add(category)
        end = category_indices[pos + 1] if pos + 1 < len(category_indices) else len(section_lines)
        body = section_lines[index + 1 : end]
        if not any(BULLET_RE.match(line) for line in body):
            fail(f"分类 `{category}` 下没有列表项")

        unknown = [
            line
            for line in section_lines[:index]
            + section_lines[end:]
            if line.strip().startswith("### ") and CATEGORY_RE.match(line) is None
        ]
        if unknown:
            fail(f"存在不认识的分类标题：{unknown}")

    for category in ALLOWED_CATEGORIES - categories_found:
        print(f"提示：分类 `{category}` 为空，已省略（允许）")

    print(f"✓ CHANGELOG 校验通过：{version} - {date_text}")


if __name__ == "__main__":
    main()

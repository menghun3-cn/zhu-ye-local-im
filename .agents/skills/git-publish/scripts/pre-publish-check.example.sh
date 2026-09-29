#!/usr/bin/env bash
# git-publish 发布前检查模板（不自动安装）
# 环境变量配置：
#   VERSION_FILE            主版本文件，默认 Cargo.toml
#   VERSION_PATTERN         版本行正则，默认匹配 Cargo.toml 的 version = "x.y.z"
#   CHANGELOG_FILE          CHANGELOG 路径，默认 CHANGELOG.md
#   CHANGELOG_CHECK_SCRIPT  CHANGELOG 校验脚本路径，默认本技能模板脚本
#   EXTRA_VERSION_FILES     额外版本文件，逗号分隔，默认空
#   EXPECTED_VERSION        期望版本号，可选；设置后强制所有版本文件包含该值
set -euo pipefail

VERSION_FILE="${VERSION_FILE:-Cargo.toml}"
VERSION_PATTERN="${VERSION_PATTERN:-^\\s*version\\s*=\\s*\"[^\"]+\"}"
CHANGELOG_FILE="${CHANGELOG_FILE:-CHANGELOG.md}"
CHANGELOG_CHECK_SCRIPT="${CHANGELOG_CHECK_SCRIPT:-.agents/skills/git-publish/scripts/changelog_check.py}"
EXPECTED_VERSION="${EXPECTED_VERSION:-}"

# 1. 工作树必须干净
if [ -n "$(git status --porcelain)" ]; then
  echo "✗ 工作树不干净，请先提交或暂存后再发布" >&2
  exit 1
fi

# 2. CHANGELOG 必须存在
if [ ! -f "$CHANGELOG_FILE" ]; then
  echo "✗ $CHANGELOG_FILE 不存在（如项目不使用 CHANGELOG 请调整配置）" >&2
  exit 1
fi

# 3. CHANGELOG 格式必须通过自动校验
CHECK_ARGS=("$CHANGELOG_CHECK_SCRIPT" "--file" "$CHANGELOG_FILE" "--require-unreleased-empty")
if [ -n "$EXPECTED_VERSION" ]; then
  CHECK_ARGS+=("--version" "$EXPECTED_VERSION")
fi
if ! python3 "${CHECK_ARGS[@]}"; then
  echo "✗ CHANGELOG 格式校验失败，请按脚本输出修正" >&2
  exit 1
fi

# 4. 主版本文件必须匹配版本规则
if ! grep -qE "$VERSION_PATTERN" "$VERSION_FILE"; then
  echo "✗ $VERSION_FILE 未匹配版本规则" >&2
  exit 1
fi

# 5. 可选：主版本文件必须包含期望版本
if [ -n "$EXPECTED_VERSION" ] && ! grep -qF "$EXPECTED_VERSION" "$VERSION_FILE"; then
  echo "✗ $VERSION_FILE 中未找到期望版本 $EXPECTED_VERSION" >&2
  exit 1
fi

# 6. 额外版本文件必须全部一致
IFS=',' read -ra files <<< "${EXTRA_VERSION_FILES:-}"
for file in "${files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "✗ 额外版本文件不存在: $file" >&2
    exit 1
  fi
  if ! grep -qE "$VERSION_PATTERN" "$file"; then
    echo "✗ 版本未同步: $file" >&2
    exit 1
  fi
  if [ -n "$EXPECTED_VERSION" ] && ! grep -qF "$EXPECTED_VERSION" "$file"; then
    echo "✗ $file 中未找到期望版本 $EXPECTED_VERSION" >&2
    exit 1
  fi
done

echo "✓ 发布前检查通过"

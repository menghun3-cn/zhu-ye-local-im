#!/usr/bin/env bash
# git-publish 通用 pre-push hook 模板（不自动安装）
# 作用：禁止直接推送受保护分支，强制发布走 release 分支 + PR
set -euo pipefail

protected_branches=("main" "master" "develop")

while read -r local_ref local_sha remote_ref remote_sha; do
  [ -z "$local_ref" ] && continue
  ref_name="${remote_ref#refs/heads/}"
  for branch in "${protected_branches[@]}"; do
    if [ "$ref_name" = "$branch" ]; then
      echo "✗ 禁止直接推送受保护分支: $branch（请走 release 分支 + PR）" >&2
      exit 1
    fi
  done
done

echo "✓ pre-push 检查通过"

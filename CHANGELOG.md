# Changelog

本文件记录本项目的所有重要变更，格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

分类仅限：新增、修复、变更、移除、安全。发布时由
`.agents/skills/git-publish/scripts/changelog_check.py` 自动校验格式。

## [Unreleased]

### 修复

- 修复「打开会话」显示空白窗口的问题。`ControllerScope` 此前只包住 `home`，
  而被推到根 Navigator 上的会话页构建在 Navigator 的 overlay 里——那是 `home`
  的兄弟节点而非子孙——因此读不到作用域。release 构建把该异常画成了纯灰窗口。

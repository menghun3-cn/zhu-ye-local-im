# Agent Note: Build the transfer stack from scratch rather than fork LocalSend

Status: implemented

[English](2026-09-29-build-from-scratch-not-fork-localsend.md) | 中文

## Problem

LocalSend 采用 Apache-2.0 许可，成熟度高（约 9.2 万 star，撰写本笔记时数日内仍有提交），且已经具备本项目所需的大部分能力：局域网发现、TLS 传输、六大平台、传输引擎与国际化。fork 它原本是最顺理成章的路径，产品最初也被描述为「类似 LocalSend 的工具」。

但真正让这个产品成立的两个功能，恰恰是 LocalSend 多年未解决的两个：剪贴板同步（issue #163，2023 年 2 月开放至今）与跨子网发现（issue #1840，2024 年 9 月开放至今）。一个严格「类似 LocalSend」的工具，会原样继承它本要修复的那两个缺陷。

## Decision

本项目自行编写客户端与自有线协议，并**刻意不实现** LocalSend 协议兼容。LocalSend 只作为**形态参照**——「发现 → 选设备 → 发送」的交互，以及功能集（文件、文件夹、文本、多接收方、收藏、历史），既不是代码基座，也不是线上契约。

Owner 身份层（见 owner-identity 笔记）在 LocalSend 仅面向 Device 的模型中没有位置；而迁就它的线上格式，会让传输设计被迫去解决一个本项目并不存在的问题。

## Alternatives considered

**fork LocalSend。** 可直接继承协议 v2.2、TLS 客户端证书、六大平台、传输引擎，以及其 CHANGELOG 中约 200 个已修复的缺陷（文件名净化、路径穿越、2 GB 大小溢出、Android SAF、macOS 沙盒、Wayland 托盘）。否决理由：其架构是 Dart UI 叠在 Rust 协议核心之上、以 `flutter_rust_bridge` 桥接并含 1.1 MB Rust，身份层因而变成对外来核心的侵入式改动而非新增；且它的两个缺口正是本项目存在的理由。

**自研客户端 + LocalSend 兼容协议。** 可让既有 LocalSend 用户第一天就能互通，缓解冷启动。否决理由：把设计钉死在一个没有 Owner 概念的协议上，并把上游的选择变成本项目的约束。

**自研客户端 + 自有协议。** 采纳。

## Consequences

- LocalSend CHANGELOG 记录的缺陷类别会被重新继承。文件名净化、路径穿越、大文件传输的整数溢出，必须从一开始就设计进去，而不是事后修补。
- 跨子网发现与剪贴板同步成为一等设计问题而非外挂功能，这正是本项目的目的所在。
- 日后若要兼容 LocalSend，需要新增第二套协议实现，而不是改造现有实现。这扇门是被刻意关上的。
- 作为形态参照，LocalSend 的 UX 决策仍可作为先例参考；其代码则不然。

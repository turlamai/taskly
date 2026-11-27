# Taskly

一款专注、键盘友好的跨平台任务管理器，覆盖 macOS、Windows 和 Linux——一个 Racket 核心驱动单一第一方 glaze 宿主（web UI），附带面向 agent 的 CLI，数据就是单个本地 SQLite 文件。

[![release](https://img.shields.io/github/v/release/turlamai/taskly)](https://github.com/turlamai/taskly/releases/latest) ![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey) ![built with](https://img.shields.io/badge/built%20with-Rivet-9333ea) [![CI](https://github.com/turlamai/taskly/actions/workflows/ci.yml/badge.svg)](https://github.com/turlamai/taskly/actions/workflows/ci.yml) [![License](https://img.shields.io/badge/license-BUSL--1.1-blue)](LICENSE)

[English](README.md) · **中文**

Taskly 构建在 [Rivet](https://github.com/turlamai/rivet)（类型化 RPC 契约）与 [glaze](https://github.com/turlamai/glaze)（窗口/托盘/热键运行时）之上：全部领域逻辑——SQLite 存储、排程、自然语言日期、校验、CLI——都在一个 Racket CS 核心里，每个桌面通过类型化 RPC 获得同一个轻薄的第一方宿主。共享领域逻辑归后端（提醒判定也在核心，见 #62）。

| 桌面平台 | 宿主 |
|---|---|
| macOS 14+（Apple Silicon + Intel） | glaze web UI（WKWebView） |
| Windows 10+（x64） | glaze web UI（WebView2） |
| Linux（x64 + ARM64） | glaze web UI（WebKitGTK） |

移动端处于设计阶段、尚未交付：owner 于 2026-11-22/23 定线，移动端为平台原生 app（iOS/iPadOS 用 Swift，Android 启动时用 Kotlin），设计契约在 `design/`（[DESIGN.md](design/DESIGN.md)）。glaze 宿主不扩展到移动端，目前没有移动工程，也不承诺时间。

## 开始使用

开发预览，尚未开放付费购买。未来官方桌面版开售时再公布实际交付条款。 提供 macOS、Windows、Linux 桌面预览版。按发布附件标注选择系统与 CPU；移动端和手表端尚未交付。

[安装、首次使用、隐私与备份恢复](docs/USER-GUIDE.zh-CN.md) · [English](docs/USER-GUIDE.md)

## 功能

- **Reminders 风格界面**——智能视图（今天 / 计划 / 全部 / 已完成），emoji 图标 + 12 色板的自定义清单，明暗主题跟随系统，中英双语实时切换。
- **自然语言快速添加**——输入 `明天买菜` 或 `standup @9am +1d`，引擎解析排程；行内编辑器随输入实时更新日期/优先级 chip。
- **对齐 Reminders 的交互**——Return 行内展开（标题、日期/时间 chip、备注），Esc 收起且不丢草稿，点击外部即提交；已完成任务收进可折叠分组；删除进入一键撤销横幅，可恢复原行。单一 web 宿主意味着三平台同一套交互（[对标笔记](docs/UX-BENCHMARKS.md)）。
- **锚定任务详情弹层（三平台）**——ⓘ 打开一层集中编辑：完成状态、标题、日期/时间、优先级、标签、子任务、备注、链接与所属清单；所有更改即时保存，关闭不会丢弃。
- **提醒（staged）**——提醒字段可编辑并持久化，但 OS 通知投递仍在 [#131](https://github.com/turlamai/taskly/issues/131) 跟进，暂不承诺横幅。
- **单文件数据，位置由你选**——首次启动请你在自选文件夹创建数据库（`taskly.sqlite`）或打开已有数据库；不会静默指定默认位置，设置页显示当前位置并提供所在文件夹、迁移与备份操作。文件为 SQLite（WAL）。退出应用后再备份；云文件夹复制不提供安全的数据库并发同步。格式文档化且稳定：[DATA-FORMAT](shared/spec/DATA-FORMAT.md)。
- **面向 agent 的 CLI**——`taskly list|add|update|done|rm|search|mklist…`，`--json` 输出稳定、退出码固定、跨平台字节级一致（63 例 golden 套件钉死）。规格：[CLI-SPEC](shared/spec/CLI-SPEC.md)。
- **在线更新（三平台）**——启动时静默检查（最多每四小时一次，可关闭）+ 设置 → 关于 里手动检查；后端验证 [更新清单](shared/spec/UPDATE.md)（Ed25519）。发现新版本时应用会提示并打开发布页——当前桌面宿主不做应用内下载与原地安装。

## 诚实差距

- **发布包暂不含独立 CLI 二进制**——CLI 目前从源码运行（见下节），打包分发在路线图上。
- **多选/批量操作、↑/↓ 行导航与共享应用快捷键（Ctrl/⌘+1…4、N、F、⇧C）**是对标目标，glaze 宿主尚未落地（[笔记](docs/UX-BENCHMARKS.md)）。
- **OS 通知投递 staged**（#131）：提醒字段持久化但暂不触发。
- **macOS 包为 ad-hoc 签名**——Developer ID 签名与公证尚未完成（[#80](https://github.com/turlamai/taskly/issues/80)）。

## 安装

到 [Releases](https://github.com/turlamai/taskly/releases/latest) 下载你的版本：

| 平台 | 便携 zip | 安装器 |
|---|---|---|
| macOS Apple silicon | `taskly-<version>-macos-arm64.zip` | `taskly-<version>-macos-arm64.dmg` |
| macOS Intel | `taskly-<version>-macos-x64.zip` | `taskly-<version>-macos-x64.dmg` |
| Windows x64 | `taskly-<version>-windows-x64.zip` | `taskly-<version>-windows-x64.msi` |
| Windows ARM64 | 通过 Windows on ARM 的 x64 模拟运行 x64 包 | — |
| Linux x64 | `taskly-<version>-linux-x64.tar.gz` | `taskly-<version>-linux-amd64.deb` / `taskly-<version>-1-linux-x86_64.rpm` / `taskly-<version>-linux-x86_64.AppImage` / `taskly-<version>-linux-x64.flatpak` |
| Linux ARM64 | `taskly-<version>-linux-arm64.tar.gz` | `taskly-<version>-linux-arm64.deb` / `taskly-<version>-1-linux-aarch64.rpm` / `taskly-<version>-linux-aarch64.AppImage` / `taskly-<version>-linux-arm64.flatpak` |

每个版本都带 `SHA256SUMS` 清单和签名的 `update-manifest.json`（更新检查的 feed）。应用只做检查并打开发布页；安装由你手动完成（下载、对照 `SHA256SUMS` 校验、运行安装器或解压）。

macOS 包为 ad-hoc 签名，未做 Developer ID 签名与公证。预览版被 Gatekeeper 拦截属预期：不要关闭系统防护；请核对发布校验和并使用可信构建。安装后的 bundle 是 `/Applications/Taskly.app`。

Linux 需要 WebKitGTK 4.1 桌面运行时（解压后运行 `Taskly`；webview 引擎及其系统库是仅有的运行时依赖，其余全部内置）。

## 从源码使用 CLI

```bash
git clone https://github.com/turlamai/taskly.git
cd taskly
raco pkg install --auto --no-docs https://github.com/turlamai/rivet.git
racket racket/taskly/cli.rkt add "买牛奶" --due tomorrow --json
racket racket/taskly/cli.rkt install-cli   # 安装到 ~/.local/bin/taskly
```

## 从源码构建

需要 Racket CS 9.3+、Node 22 / pnpm（web UI），以及对应桌面的 glaze 运行时依赖（Windows 用 WebView2，macOS 用 WKWebView，Linux 用 WebKitGTK 4.1）：

```bash
raco pkg install --auto --no-docs https://github.com/turlamai/glaze.git
pnpm install && pnpm check && pnpm build   # web UI
raco glaze build --entry backend/main.rkt --name Taskly \
  --version "$(cat VERSION)" --identifier app.taskly.Taskly --out dist
racket scripts/acceptance/run-suites.rkt   # 当前平台完整产品验收证据
raco test racket/       # 契约测试
python3 shared/cli-golden/runner.py --binary scripts/taskly-cli.sh   # 63 例 golden 套件
```

## 架构

```
┌─────────────────────────────┐            ┌────────────────────────────┐
│ glaze 宿主（单一）           │            │ Racket CS 核心              │
│  web UI + 托盘/热键/         │◀── 类型化 ──▶│  db · 排程 · 校验 · 提醒    │
│  捕获窗/自启动               │  RPC (RVT1)│  agent CLI（同一领域层）    │
│  内嵌 Racket CS 运行时        │            │                            │
└─────────────────────────────┘            └────────────────────────────┘
```

一套规格保证所有端一致：产品行为（[PRODUCT-SPEC](shared/spec/PRODUCT-SPEC.md)）、数据格式、CLI 契约、设计令牌、更新契约——都在 [shared/spec/](shared/spec/) 下。CI 在每次推送时用 golden 套件和字节级一致的 i18n 强制执行 CLI 契约；源码中的 `rivet-acceptance.rktd` 还要求 Windows、macOS arm64/x64、Linux 分别通过真实 RVT1、glaze 构建与真窗 §6 旅程验收（由 `scripts/acceptance/run-suites.rkt` 执行）。

## 反馈

Taskly 本地优先、无遥测，反馈统一走 [GitHub issues](https://github.com/turlamai/taskly/issues)：[Bug 报告](https://github.com/turlamai/taskly/issues/new?template=bug_report.md)和[功能请求](https://github.com/turlamai/taskly/issues/new?template=feature_request.md)都有模板。设置 → 关于 里也有同一入口。

## 许可证

[BUSL-1.1](LICENSE)——源码可得；每个版本在其变更日转为 MIT（发布四年，最迟 2030-09-28）。

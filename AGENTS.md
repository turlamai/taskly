# AGENTS.md

## 家族设计（必读入口）

- 设计/UI 任务先加载 `tlai-product`，必读 `references/policy.md` 与 `references/design-standard.md`（理念、决策规则、UI 验收）。技能缺失时读取 ZCode 真源：macOS/Linux `~/Sync/ZCode/skills/tlai-product/`；Windows `D:/ZCode/skills/tlai-product/`。无法读取须报告规范未核验，不凭记忆跳过。
- 家族规范管共性；本仓现有设计、行为与 token 真源管具体值和产品差异。例外记回原契约，不复制家族规则或新增数值表；已有界面按下一次相关切片渐进对齐。
- 改界面先改原型、落账后实现；按家族 UI 清单与本仓当前技术线的既有门禁验收，原型对照和真实交互证据都要保留；对外宣传使用验收后的实物截图。

## Current owner decision — 2026-11-18 quality-first

This is a **non-commercial development product**. The previous 2026-10 authorization, pricing, trial, Pro and Permit/Commerce rollout decisions are canceled. Do not implement or restore checkout, activation, subscription, paid feature gates, trial expiry or update-entitlement windows. Keep source licenses, release-signature verification, privacy protections and tested data migration intact. Focus only on real product functionality, cross-platform parity (single glaze host), recovery, clear bilingual READMEs and honest website status. Read the [current family policy](https://github.com/turlamai/turlamai.github.io/blob/master/PORTFOLIO.md) before every development slice.

## Required policy discovery at each slice

Before starting the next bounded slice, refresh remote state safely and re-read
this root AGENTS file, the repository's canonical implementation handoff, and
the current [family delivery standard](https://github.com/turlamai/turlamai.github.io/blob/master/docs/PRODUCT-STANDARD.md),
[documentation language policy](https://github.com/turlamai/turlamai.github.io/blob/master/docs/DOCUMENTATION-LANGUAGES.md)
and [portfolio decisions](https://github.com/turlamai/turlamai.github.io/blob/master/PORTFOLIO.md).
Follow the corresponding Chinese links when preferred; both public user paths
must express the same promises. Product-specific plans and technical protocol
owners remain in their owning repositories.

Record the repository starting SHA and the central-policy commit/revision
actually read in the PR or handoff. A link's presence is not an acknowledgement
that an agent has read it. Existing conversations and stale checkouts do not
receive policy updates automatically: refresh these inputs at slice boundaries.
Preserve other agents' dirty worktrees; use an isolated checkout when needed,
without stashing, resetting or overwriting their work. Missing/offline policy
inputs must be reported as unverified, not silently claimed current.

**Historical only — canceled by the 2026-11-18 decision above:** the desktop purchase/trial/update design in [PR #60](https://github.com/turlamai/taskly/pull/60) and the split-Pro candidates it superseded are not to be implemented; nothing in a design document activates runtime restrictions or removes existing gates.


指引给 AI agent（及开发者）：如何理解、构建、运行、改动 Taskly。

## 这是什么

Taskly 是 Rivet 架构的待办应用（monorepo）：**一个 Racket CS 领域核心 + 单一 glaze 宿主（web UI）**。宿主只渲染和交互，全部业务逻辑在核心，两端经 Rivet 的类型化 RPC（RVT1）通信；glaze 适配器把 RVT1 进程内 pipe 对暴露为 typed 路由（native GLZ1 carrier 或显式 HTTP dev adapter）。

| 组件 | 技术 | 目录 | 验证状态 |
|---|---|---|---|
| 领域核心 + CLI | Racket CS 9.3 | `racket/taskly/`（+ `racket/tests/`） | ✅ 契约测试 + 63 例 golden CLI 全绿 |
| glaze 适配器 + 薄宿主 | Racket（glaze pin） | `backend/` | ✅ 三平台 CI + 真窗 verify |
| Web UI（唯一界面） | TypeScript + Vite | `apps/desktop/`（+ `packages/core/` 生成客户端） | ✅ 三平台真窗 §6 全旅程 |

`packages/core/src/rpc.ts` 由 `scripts/gen-rpc-types.py` 从 `rivet-schema.json` 生成，`glaze-schema.json` 由 `raco glaze schema write` 生成，**都不要手改**；`scripts/check-rpc-surface.py` 门禁路由/生成客户端/契约三者对齐。架构决策记录：`ARCHITECTURE.md`；三平台原生宿主迁移史只在 git 历史（原生线止于 `51c9c1c`，glaze 换线见 issue #141）。发现 rivet/glaze 能力缺口直接提上游 issue/PR。

## 快速命令

```bash
# 核心（任何平台）
raco test racket/         # 契约测试
racket scripts/acceptance/run-suites.rkt  # 当前平台完整验收：契约、RVT1、glaze 构建、真窗 §6 旅程、更新
racket verify.rkt         # 真窗冒烟 + §6 全旅程（需图形会话；Linux CI 用 dbus+xvfb）
scripts/taskly-cli.sh list --json                          # dev CLI（系统 racket）
python3 shared/cli-golden/runner.py --binary scripts/taskly-cli.sh   # 63 例 golden 套件（--record 重录）

# UI / 适配器
pnpm install && pnpm check && pnpm build   # web UI 类型检查 + 构建
raco glaze schema write   # 重生成 glaze-schema.json（路由变更后）
python3 scripts/gen-rpc-types.py           # 重生成 packages/core/src/rpc.ts
raco glaze build --entry backend/main.rkt --name Taskly --version "$(cat VERSION)" --identifier app.taskly.Taskly --out dist

# 发布链
bash scripts/check-release-version.sh [tag]   # VERSION == rivet.rktd == version.rkt == info.rkt == package.json == tag；另核 CHANGELOG 段、build 号、更新 key id
scripts/make-update-manifest.sh v<ver> <dist-dir>   # 签名更新清单（Ed25519，需 OpenSSL 3）

# i18n / emoji 单源同步
python3 scripts/gen-web-i18n.py   # shared/i18n → apps/desktop/src/i18n.ts（生成物）
scripts/sync-i18n.sh --check    # CI 模式：校验 zh/en 键齐 + emoji.json 可解析
```

开始修改已有 checkout 前，必须先检查 `git status`，再以 fast-forward-only
方式更新 tracked remote。工作树非干净、分支已分叉或远端不可达时，保留现场并
报告，不得用 stash/reset/清理生成目录掩盖状态。记录本次工作的起始 commit。

`rivet-acceptance.rktd` 是可执行的完成定义，由 `scripts/acceptance/run-suites.rkt`
按平台执行（逐 suite 日志 + summary + evidence 校验）。Agent 不得通过删除
requirement、放宽断言、改 golden 期望或用 CLI 代替 GUI 行为来让变更变绿；
required suite 只要在声明平台未执行、超时、失败或没有生成本次运行的新证据，
就不能称为完成。真窗旅程的门禁与平台例外声明在 PRODUCT-SPEC §6。

发布 = 改 `VERSION` + `rivet.rktd` + `racket/taskly/version.rkt` + `package.json` + `CHANGELOG.md`（同值）→ 推 tag `v*`，release.yml 自动打包三平台 + SHA256SUMS + 签名 update manifest（馈送保持 rivet 格式，`raco rivet sign-manifest` 签名）。

## 实现路由（agent 按任务读真源）

- **实现界面**：以 `design/prototype/` 为准——对照 HTML/CSS/JS 与实物截图验收，不依赖散文复述。原型里契约与脚手架混用（假数据、`TODAY` 常量）；行为拿不准时以 `shared/spec/PRODUCT-SPEC.md` 为准，不要从 JS 反推契约。
- **Token/几何值**：唯一真源 = `design/prototype/shared.css`；web UI 经 `apps/desktop/src/style.css` 的 `@import` 单源引用（database-flow.css 同）。单一 web 宿主后无跨宿主常量门禁（旧三腿门禁已退役）；改值 = 只改 shared.css。
- **行为契约**：`shared/spec/PRODUCT-SPEC.md`（§6 场景表 = 验收测试计划，覆盖映射见表后 Coverage map）；视觉语义 = `shared/spec/DESIGN-TOKENS.md`（值已指向 shared.css，只记语义与决策）。
- **动共享层**（spec/prototype/scripts/rivet-acceptance.rktd）先 issue 声明，契约与实现同 commit 落账。

## 契约文档（改任何行为前必读，改动必须同步契约）

| 文档 | 内容 |
|---|---|
| `shared/spec/DATA-FORMAT.md` | SQLite schema、列↔字段映射、日期存储格式、WAL、`~/.taskly/config.ini`、默认「工作」列表 |
| `shared/spec/CLI-SPEC.md` | 子命令、`--json` 字段名与顺序、退出码 0/1/2/3/4、`--due` 语法全集、golden 套件对比规则 |
| `shared/spec/PRODUCT-SPEC.md` | 视图/过滤/排序、任务行交互、提醒调度、验证上限 |
| `shared/spec/DESIGN-TOKENS.md` | 色板、emoji/颜色选择器契约 |
| `shared/spec/UPDATE.md` | 更新清单格式、Ed25519 签名、逐平台更新器状态 |
| `shared/i18n/{zh,en}.json` | 全部用户可见文案，宿主副本必须逐字节一致 |
| `shared/emoji.json` | 清单图标 emoji 单源（8 分类×12，Win10 字体安全） |

## 改动契约（不要破坏）

- **golden 套件是 CLI 的字节级契约**：改 CLI 行为 → 先改 `CLI-SPEC.md`，再 `--record` 重录，人工 review diff。新 case 必须录制，禁止静默跳过；禁止空 `args` 的 case（会启动 GUI）
- **DB schema**：加列/迁移必须 bump `user_version` + 更新 DATA-FORMAT.md（核心只有 `racket/taskly/db.rkt` 一个实现）
- **CLI JSON**：task 对象 `id, listId, listName, text, completed, dueDate, dueTime, notes, createdAt`（null 省略、2 空格缩进、非 ASCII `\uXXXX` 转义）；错误走 stderr `{"ok":false,"error":…,"exitCode":N}`
- **RPC 契约**：改 `backend.rkt` 的 RPC/事件 → `scripts/gen-rpc-types.py` + `raco glaze schema write` 重生成客户端与基线 → `scripts/check-rpc-surface.py` 与 `raco glaze schema check --json` 门禁 → 适配器路由 1:1 对齐
- **提醒 staged**（#131）：reminder 字段仅 staged UI，不做 OS 通知调度；将来恢复通知时权限拒绝/传输失败不得崩溃（0.6.1 macOS 崩溃事故是永久回归教训）
- **`~/.taskly/` 路径约定**：GUI/CLI/云盘同步都依赖它

## 项目结构

```
taskly/
├── racket/taskly/      Racket CS 领域核心：db · cli · service · date-parser · validation · backend（RPC 契约）
├── racket/tests/       核心契约测试（raco test racket/）
├── backend/            glaze 适配器：typed 路由 · RVT1 pipe 对 · 薄宿主（tray/hotkey/capture/autostart）· e2e 门禁
├── apps/desktop/       唯一 web UI（Vite + TS；store/main/database-flow/settings/e2e harness）
├── packages/core/      生成客户端 rpc.ts + 双传输 bridge（native GLZ1 / HTTP fetch+SSE）
├── shared/
│   ├── spec/           五份契约文档（canonical）
│   ├── i18n/           zh/en 单源
│   ├── emoji.json      清单图标单源
│   └── cli-golden/     63 例 golden CLI 套件（cases.json + runner.py + golden/）
├── scripts/            taskly-cli.sh · sync-i18n.sh · gen-rpc-types.py · gen-web-i18n.py · check-rpc-surface.py · check-release-version.sh · make-update-manifest.sh · update-keys.sh · acceptance/run-suites.rkt
├── flatpak/            Linux Flatpak 打包（glaze payload）
├── site/               GitHub Pages 站点（taskly.jrtx.site，pages.yml 部署）
├── docs/               用户文档（USER-GUIDE 等 .md）
├── .github/workflows/  ci.yml（contract·frontend·core+golden·三平台适配器·package-smoke）· acceptance.yml（三平台真窗全 suites）· release.yml（三平台打包+签名清单）
├── VERSION + rivet.rktd + racket/taskly/version.rkt + package.json  版本同源（发版前必须同值）
├── rivet-acceptance.rktd  可执行验收契约（run-suites.rkt 执行）
├── verify.rkt          真窗冒烟 + §6 全旅程 verdicts
├── ARCHITECTURE.md     架构决策记录
└── CHANGELOG.md        发布说明来源（release 说明自动提取对应版本段）
```

## 常见任务指引

- **改共享行为**（视图过滤、CLI 语义、排程）：改 `racket/taskly/` + 同步 `shared/spec/`，跑 `raco test racket/` + golden；UI 侧只改展示层
- **加 CLI 子命令**：单点实现于 `racket/taskly/cli.rkt`，补 `CLI-SPEC.md`，`--record` 重录 golden
- **加 RPC**：`racket/taskly/backend.rkt` 定义 → `gen-rpc-types.py` + `raco glaze schema write` → `backend/main.rkt` 加 1:1 typed 路由 → 门禁绿 → UI 经 `packages/core` 调用
- **Web UI**：`apps/desktop/src/`（store 快照 + 逐字段 autosave；交互基准见 PRODUCT-SPEC §5/§6，视觉基准 `design/prototype/`）；真窗验收 `racket verify.rkt`
- **改文案**：改 `shared/i18n/`，跑 `python3 scripts/gen-web-i18n.py` 重生成 `i18n.ts`（`sync-i18n.sh --check` 校验键齐）；改清单图标：改 `shared/emoji.json`
- **发版**：见「快速命令」发布链；两 pin（`RIVET_PIN`/`GLAZE_PIN` 跨 ci/acceptance/release 对齐，`scripts/check-dependency-pins.sh` 门禁）只能有意 bump 并重新跑全套 CI；keel 是 rivet 的依赖，经 catalog 由 `--auto` 解析，不单独 pin（#129）

## 组合定位（Portfolio placement）

本产品目前是 **2026-11-18 质量与交付优先的非收费开发项目**。不重新引入旧版价格、购买、试用、Pro 或 Permit/Commerce 门禁；保持现行源码许可与更新签名安全。当前权威为 [产品组合策略](https://github.com/turlamai/turlamai.github.io/blob/master/PORTFOLIO.zh-CN.md)，不是已经删除的产品定价文件。

## Documentation languages

Public default documentation is English; maintain complete Chinese user paths in `*.zh-CN.md`, with reciprocal links. Update both languages when prices, quotas, installation, recovery, privacy or supported platforms change. API/protocol identifiers and commands remain unchanged; do not maintain a second normative protocol or implementation. Follow the [family language policy](https://github.com/turlamai/turlamai.github.io/blob/master/docs/DOCUMENTATION-LANGUAGES.md). Existing internal notes are not a claim that every document is bilingual.

## Public product documentation

The paired `docs/USER-GUIDE.md` / `docs/USER-GUIDE.zh-CN.md` own the public installation, first-use, data/recovery, privacy and availability path. Keep the homepage and both README entry points aligned with them when behavior changes. Detailed technical contracts and the current implementation queue retain their existing owners. Do not publish target prices, a purchase link or a ready/secure/platform claim before its release evidence exists.

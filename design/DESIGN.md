# Taskly DESIGN.md — 设计流程路由

视觉契约单一真源：**[shared/spec/DESIGN-TOKENS.md](../shared/spec/DESIGN-TOKENS.md)**（语义色 × 明暗、几何与组件规范、平台映射表、漂移台账全部在那里，本文件不复制）。行为契约：[shared/spec/PRODUCT-SPEC.md](../shared/spec/PRODUCT-SPEC.md)。`Theme.swift` 文件头引用的就是那份契约——不改引用方向。

## 流程（原型先行）

- 改界面 = 改 DESIGN-TOKENS / PRODUCT-SPEC → 更新 `design/prototype/` 原型 → HIG 评审 → 三腿实现。反向顺序禁止。
- 原型：本目录 `prototype/*.html`，单文件、无外部依赖，严格用 DESIGN-TOKENS 的值渲染（含明暗双主题）。
- **exit 条件**：关键屏齐（主窗 / 列表编辑器 / 设置）+ 交互逻辑对 PRODUCT-SPEC 锁定 + 漂移台账（D1–D9）逐条处置。
- 平台原生习惯保留：macOS 原生菜单栏 / Win+Linux 菜单栏、每平台图标字体；宿主特例必须**先写进 PRODUCT-SPEC** 才允许实现，不允许评审时现场发明。
- 实现切片验收：原型 vs 实物截图对照 + `raco rivet acceptance --json`。
- 共享层纪律：DESIGN-TOKENS / PRODUCT-SPEC / 本文件是共享层——改动前 issue 声明（#121 即本仓声明），单写，改完立刻 push。

## 切片账本

- **切片 1（设计门禁，2026-11-11，起始 SHA 6c6dcb9）**：DESIGN-TOKENS 增平台映射表 + 漂移台账（D1–D9）+ 流程节；原型三屏（主窗 / 列表编辑器 / 设置）。实现切片（Windows 色板漂移、Windows picker 缺失、Linux picker 升级、窗口尺寸对齐 D1）由此排队。
- **切片 2（原型落账 checkpoint 2026-11-15 → 三腿实现，起始 SHA b524b99）**：数据库生命周期（PRODUCT-SPEC §2a：启动 gate / 独占创建 / 两步迁移 / taskly-backup v1 / 恢复）+ 新任务默认清单 + 详情层披露式重组（b524b99 原型）。核心 RPC +5、Settings +2 字段（commit b3d88eb）；macOS 锚腿 7eec344（本机 acceptance 5/6，native-ui 受本机键鼠干扰，权威证据走 CI）；Linux 腿 6148ffe（Ubuntu VM：build + package + native-ui e2e 绿）；Windows 腿 dd41bed（编译由 CI 门禁）。e2e 扩展：macOS gate/恢复/设置数据三场景（真实 NSOpenPanel 驱动），Linux profile 种子化绕 gate + 披露展开辅助（GTK4 expander = AT-SPI button/activate）。


## Prototype source checkpoint — 2026-11-15

`index.html` opens the primary prototype directly. Screen-directory launchers have been removed. All local scripts, styles and referenced assets needed by this checkpoint are versioned under this directory; OpenDesign metadata is excluded. This is an editable prototype checkpoint, not a claim that the native product or external services implement these interactions.

[Prototype refinement details](DESIGN-REFINEMENT.md) describe browser-only examples. The existing shared product and token specifications remain authoritative for native implementation.

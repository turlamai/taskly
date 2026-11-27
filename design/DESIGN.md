# Taskly DESIGN.md — 设计流程路由

视觉契约单一真源：**[shared/spec/DESIGN-TOKENS.md](../shared/spec/DESIGN-TOKENS.md)**（语义色 × 明暗、几何与组件规范、漂移台账全部在那里，本文件不复制）。行为契约：[shared/spec/PRODUCT-SPEC.md](../shared/spec/PRODUCT-SPEC.md)。`apps/desktop/src/style.css` 以 `@import` 直接消费原型 CSS——不改引用方向（原 `Theme.swift` 引用随原生宿主退役）。

## 流程（原型先行）

- 改界面 = 改 DESIGN-TOKENS / PRODUCT-SPEC → 更新 `design/prototype/` 原型 → 按家族设计规范评审（入口见仓内 AGENTS.md「家族设计」）→ 单一 glaze web 宿主实现。反向顺序禁止。
- 原型：本目录 `prototype/*.html`，单文件、无外部依赖，严格用 DESIGN-TOKENS 的值渲染（含明暗双主题）。
- **exit 条件**：关键屏齐（主窗 / 列表编辑器 / 设置）+ 交互逻辑对 PRODUCT-SPEC 锁定 + 漂移台账逐条处置。
- 单一 web 宿主：无 OS 菜单栏；宿主特例（托盘 / 热键 / 捕获窗 / picker）必须**先写进 PRODUCT-SPEC** 才允许实现，不允许评审时现场发明。
- 实现切片验收：原型 vs 真窗截图对照 + `racket scripts/acceptance/run-suites.rkt`。
- 共享层纪律：DESIGN-TOKENS / PRODUCT-SPEC / 本文件是共享层——改动前 issue 声明（#121 即本仓声明），单写，改完立刻 push。

## 切片账本

- **切片 1（设计门禁，2026-11-11，起始 SHA 6c6dcb9）**：DESIGN-TOKENS 增平台映射表 + 漂移台账（D1–D9）+ 流程节；原型三屏（主窗 / 列表编辑器 / 设置）。实现切片（Windows 色板漂移、Windows picker 缺失、Linux picker 升级、窗口尺寸对齐 D1）由此排队。
- **切片 2（原型落账 checkpoint 2026-11-15 → 三腿实现，起始 SHA b524b99）**：数据库生命周期（PRODUCT-SPEC §2a：启动 gate / 独占创建 / 两步迁移 / taskly-backup v1 / 恢复）+ 新任务默认清单 + 详情层披露式重组（b524b99 原型）。核心 RPC +5、Settings +2 字段（commit b3d88eb）；macOS 锚腿 7eec344（本机 acceptance 5/6，native-ui 受本机键鼠干扰，权威证据走 CI）；Linux 腿 6148ffe（Ubuntu VM：build + package + native-ui e2e 绿）；Windows 腿 dd41bed（编译由 CI 门禁）。e2e 扩展：macOS gate/恢复/设置数据三场景（真实 NSOpenPanel 驱动），Linux profile 种子化绕 gate + 披露展开辅助（GTK4 expander = AT-SPI button/activate）。


## Prototype source checkpoint — 2026-11-15

`index.html` opens the primary prototype directly. Screen-directory launchers have been removed. All local scripts, styles and referenced assets needed by this checkpoint are versioned under this directory; OpenDesign metadata is excluded. This is an editable prototype checkpoint; since the glaze rewrite (issue #141) the single web host imports its CSS/IA as the visual single source, so prototype drift is product drift.

[Prototype refinement details](DESIGN-REFINEMENT.md) describe browser-only examples. The existing shared product and token specifications remain authoritative for the glaze host implementation.


## 移动端视图（iOS）

### 定线声明（owner 决策，2026-11-22）

- 桌面 = **glaze 载体**：一套 Web UI 跨 macOS、Windows、Linux；原生三腿已于 2026-11-20 随 issue #141 退役。
- 移动端 = **平台原生 app**（iOS/iPadOS 用 Swift；Android 需要时用 Kotlin；owner 2026-11-23 确认）。此处 HTML 只表达设计契约与交互规格，不把 glaze 载体扩展到移动端，也不复用 rivet 移动宿主；本轮不创建 Swift 工程，也不扩大到其他移动平台。
- 家族设计依据：tlai-product 的 references/design-standard.md（2026-11-20-minimal-family）。本轮明确的 owner 定线优先于旧路由；不另建 token 真源。

### 交付屏幕与入口

每屏独立单文件 HTML，内含自己的布局与交互，仅相对引用同目录 shared.css、shared.js、theme-boot.js：

- prototype/mobile-today.html：今天／即将到来、分组、完成、滑动显示操作、快捷添加。
- prototype/mobile-quick-add.html：半屏 sheet、草稿、解析预览及快捷字段。
- prototype/mobile-task-detail.html：查看／编辑、自动保存、完成、删除与撤销。
- prototype/mobile-lists.html：清单总览、清单内任务、新建与编辑。
- prototype/mobile-settings.html：主题、语言、默认清单、提醒能力与数据归属说明。
- index.html：桌面／移动分组导航；替换旧自动跳转入口，这是本轮显式需求。

### 视觉契约

- 纯内容画布，内容列最大宽度 390px，窄屏自然收缩、居中，无手机外壳、边框、灵动岛或装饰性状态栏。body 与内容使用现有中性表面 token，无大面积渐变／玻璃／发光／纹理。
- 全部颜色继续消费 shared.css 现有语义变量；仅扩展该文件中暗色 token 定义的作用域到 html.mobile-page[data-taskly-theme="dark"]，不复制颜色值、不改桌面色板。主题仍由 theme-boot.js 首帧引导及 Taskly.theme 管理。
- 系统 UI 字体栈；数字 tabular figures；正文 16px，辅助 12–13px，大标题 28px、详情标题 24px。间距用 4 基准，内容内边距 16px；圆角内嵌 4／控件 8／面板 12，分隔线 1px。
- 唯一主强调色使用现有 accent／accent-ink；每任务区域最多一个高强调主动作。状态色仅表达状态，清单颜色作为用户内容标记，不作为文字可读性的唯一线索。
- 操作只复用 Taskly.ICONS 现有内联线性 SVG，不引入图标库、emoji 操作按钮、远程字体、CDN 或图片。
- 触控命中至少 44×44；任务行至少 44。勾选图形与按钮命中分开，文字、标签和色板仍有语义标签。小动效使用现有 120ms 退出时长；prefers-reduced-motion 禁用动画。焦点使用 accent，必要功能均有可见点击与键盘入口。

### 行为与数据边界

- 底部 tab bar 仅今天／清单／设置；详情与快速添加是任务级流程，有明确返回／取消。滑动仅展开完成／删除操作，同一入口也可点击“更多操作”，不要求用户掌握手势。
- 今天包含逾期任务，即将到来只呈现未来日期。勾选后移入已完成分组；无任务与全部完成分别呈现，不能将无记录误报为全部完成。
- 快速添加严格沿用现有 #标签、@时间、+Nd、+今天、+明天；不添加自然语言识别、重复规则或新标签语法。手动快捷字段优先于解析值。截止映射现有 date 字段，不增加开始日期／截止日期双模型。
- 提醒沿用 none／0／10m／1h；有提醒时需要日期和时间。设置页不新增全局通知开关，不申请权限或假装发送通知。语言仅记录偏好，保持现有中文文案惯例。
- 五屏共享独立移动演示状态 taskly.mobile.v1；不改变桌面数据库注册表或真实文件。数据样例来自已有原型语境，空／完成样例使用独立存储命名空间，互不覆盖。浏览器本地存储不可用时尝试会话存储；均不可用时只保留当前页，不能宣称跨页保存成功。
- 记录清单选择、今天时间分段、滚动位置和快速添加草稿；详情编辑自动保存，非法标题／提醒组合保留草稿与最后有效任务。列表编辑保存才提交、取消不改原记录。
- 删除可撤销：保留最近一次删除及原位置，不用会自动消失的通知承载唯一恢复入口；撤销跨页可用，下一次删除替换上一条撤销记录。
- 保存反馈对应本地演示写入；加载／失败样例通过查询参数进入，不引入远程服务或假百分比。失败有重试路径，输入校验保留已填写内容。

### Exit 条件与验收记录

- [ ] 移动五个关键屏齐，390px 与更窄窗口无关键内容横向溢出。
- [ ] 导航返回、清单选择、滚动与草稿保持；添加／编辑／完成／删除撤销／清单保存与取消流程走通。
- [ ] 亮暗主题真实切换并跨页延续；正文对比至少 4.5:1，必要图形与控件边界至少 3:1，状态不只靠颜色。
- [x] 零外部依赖，相对资源与导航引用存在；独立 HTML 可通过本地 HTTP 打开。
- [ ] 44×44 命中、字号／间距／图标／圆角适用项通过；文字放大、焦点、读屏语义、reduced motion 按家族 UI 清单检查。
- [x] 空态／全部完成／保存中／加载／失败恢复覆盖，无独立系统通知或 SQLite 能力承诺。
- 2026-11-23 原型自查：五屏和导航的本地引用均可解析，本地 HTTP 返回页面。DOM 测试通过草稿恢复、输入解析、添加、编辑保存、完成、删除撤销、滑动事件、清单保存与取消、主题跨页初始化、默认清单及状态恢复。跨页测试以同源存储快照重新载入各页，原生触屏与浏览器历史行为仍需实测。
- 双主题令牌对比度（亮／暗）：正文对背景 16.83:1／15.31:1，辅助文字 6.56:1／9.14:1，主按钮文字 4.52:1／6.02:1，控件边界对背景 3.57:1／3.55:1。44px 命中与窄屏样式已核对源码，实际渲染尺寸、滚动恢复、字体放大、键盘焦点和触屏仍待浏览器验证。
- 当前环境无法启动无头 Chromium，现有 Edge 会话无访问权限。Swift 真机、VoiceOver、Dynamic Type 与系统 picker／通知／SQLite 行为留待原生实现切片验证。

## 家族设计基线对齐 — 2026-11-26

对齐家族设计规范修订 `2026-11-20-minimal-family`，起始 SHA `89421e0`，共享层声明见 issue #148。原型先行：`shared.css` 被 web UI `@import`，原型改动即产品样式改动；token 值仍只维护在 `shared.css`。

| 检查 | 结果 | 证据／限制 |
|---|---|---|
| 主题切换按钮 | 不适用 | 主题只是设置项（跟随系统／浅色／深色），桌面与移动都没有工具栏切换，不新增 |
| 12px 字号下限 | 通过 | `shared.css` 的 `.ldot`、`.check`、`.dacts .hint-inline` 与 `list-editor.html` 的 `.namewrap .ldot`、`.swatch` 由 11px 升到 12px，`.swatch` 高度 26→28；源码扫描低于 12px 的声明 0 处 |
| 记录的例外 | 1 项 | `ICONS.today`（`shared.js`）用 16 单位视框内 `font-size="5.5"` 的 SVG `<text>` 画当日日期。它是 `aria-hidden` 图标的图形部分而非界面文字，12px 放不进图标；渲染报告仍会把它计为 small |
| reduced motion 与焦点 | 已有，未改 | `shared.css` 在 `prefers-reduced-motion: reduce` 下禁用全部过渡与动画；全局 `:focus-visible` 为 2px `--today` 外框、offset 2 |
| 原型完整性 | 通过 | 无远程资源，本地引用全部可解析；`index.html` 列全 9 个页面并链接本文件，各链接的 `title` 为页面 `<title>`（可见文案不变） |
| 可访问名称 | 通过 | 桌面 4 屏、移动 5 屏及弹层、行内编辑器、对话框等状态：无名称控件 0，SVG 全部 `aria-hidden` |
| 布局缺陷 | 修复 4 处 | ① `body` 网格列 `minmax(0, 1fr)`：视口 901–1247px（含产品默认 1100×760）模拟窗口不再横向溢出 124px；② `.window` 高度 `min(800px, 100dvh - 64px)`：1280×800 下整窗可见；③ 侧栏隐藏断点 760→759px：声明最小宽度 760 下侧栏与设置入口保留；④ 详情层夹取到窗口底部时停在状态栏上方（`place()` 预留状态栏高度，`.dpop` 最大高度同步为 `100% - 52px`） |
| 渲染复核 | 通过 | 无头 Chromium，1280×800 与 390×844 各屏双主题，另测 1100×760、760×520：`overflowX` 0、页面错误 0、加载失败 0；`list-editor` 的 small 3→0，`task-detail` 5→1（仅图标日期） |
| web UI 同步 | 已同步 | `apps/desktop/src/style.css` 的 13 条 11／11.5／12.5px 副本对齐原型：11 条为 12px，`.segopt span`、`.keybtn` 取原型值 13px；`.swatch` 高 28px；`shared.ts` 的 `place()` 同步预留状态栏；`shared/spec/DESIGN-TOKENS.md` 的清单圆点 emoji 记为 12px。产品的窗口高度与 `body` 规则有意不同（真实窗口填满视口），未动 |
| 仓库门禁 | 通过 | `check-design-tokens.py` 已随原三腿门禁退役；`pnpm check`、`pnpm build` 通过；`racket verify.rkt` 真窗 45/45 通过（含 j06 详情层开关） |

遗留：

- 产品在 760px 以下保留 200px 侧栏而原型隐藏（真实窗口未声明最小宽度，隐藏后无处进入清单与设置）：该宽度下中文「已完成」图标格标签会折行，是否加宽待定。
- 对比度未达 4.5:1 的两处浅色主题文字：状态栏上的 ghost 按钮（accent 对 `--sidebar`，4.04:1）已由下节 `--accent-text` 解决；选中行上的中优先级 `!!`（`--warn-ink` 对 `--sel`，3.92:1）见文末「对比度落地 — 2026-11-27」。
- 移动端 tab bar「设置」用 `ICONS.theme`（半填充圆形）作导航图标，是否换成设置语义的线性图标待定。


## 气质档位声明与对齐 — 2026-11-26（家族规范 `2026-11-26-temperament-profiles`）

本轮按 owner 指令对全部产品原型过一遍新规范。做法是「声明档位 + 对齐受影响的差量 + 记录遗留」：没有重绘任何屏幕，没有改动信息架构，也没有新增 token 值表。**档位由 agent 代为判定，待 owner 确认或更正。**

### 档位

- **主档位**：静读。任务清单与任务详情，围绕一份清单做长时间整理。
- **主任务**：沿用上文 Brief，本节不复述。
- **与静读默认的差量**：无，取 §4 默认值。
- **借用档位**：无。
- **工作台结构**（§9）：沿用现有布局，本轮未调整面板；「同一时间最多一个从属面板」留到核心屏打磨轮核对。

### 本轮改动

- 字体栈：UI 栈与等宽栈在通用回退前补 CJK 回退（§9「等宽与中文」）；值仍只维护在 `shared.css`。
- 排版基线块：`body { text-autospace: normal; line-break: strict }`、亮暗成对的 `::selection`、中性 `scrollbar-color`（§10 中文排版、状态齐全）。
- 新增 `--accent-text`（亮 `#B8432A`，暗同 `--accent`），ghost 按钮改用它：浅色工具栏底上原为 4.04:1。**`shared.css` 被产品 web UI 直接 `@import`，这一项会进产品界面，`shared/spec/DESIGN-TOKENS.md` 已登记该 token。**

### 测量

无头 Edge 1280×800（移动页 390×844），亮暗各渲染一次，逐页统计；对比度为脚本近似计算（半透明高亮底、彩色 emoji、content 里的符号会被误计）。

低对比文字 15→14，剩余全部是清单的表情符号 `.ldot`（用户内容色，按规范不受对比度约束）；正文超版心 2→2（本地评审导航页）。

### 遗留（本轮未处理）

- 行内文字链接的命中区不足 24px（上轮基线遗留，面广）：本轮未动，需逐页裁决是加内边距还是改成按钮。
- 上文已记的尺度待办（圆角、字号、字重）不变，继续渐进对齐。
- §10 核心屏打磨轮：每轮须 owner 裁决；本轮只有 agent 的测量与自评，不计入打磨轮次。


## 对比度落地 — 2026-11-27（家族规范 `2026-11-20-minimal-family` §5 / `2026-11-26-temperament-profiles`）

起始 SHA `c19e3af`。接 issue #150 留下的两处浅色主题低对比文字。`shared.css` 被 web UI `@import`，改动随合并直接进产品界面，没有待同步的实现侧。

| 项 | 亮色 | 暗色 | 依据（按公式计算，底色取合成后的实际颜色） |
|---|---|---|---|
| `--warn-ink` | `#B25E00` → `#964F00` | 不变 | 选中任务行上的中优先级 `!!`（`--sel` 叠在 `--bg` 上）3.92 → 5.16；白底上 6.15；暗色原值 5.21 已达标 |
| `.tile[aria-current="true"] .count` | 新规则：用 `--ink2` | 同 | 选中磁贴的底色从 `--surface` 换成 `--sel`，叠在侧栏上：计数用 `--ink3` 亮 4.16 / 暗 4.32 → `--ink2` 亮 4.93 / 暗 5.80 |

没有做的：`--accent`（亮 `#C94F30`）保持不变。状态栏 ghost 按钮那一处已由 `--accent-text`（上节，4.85:1）解决，不再压暗主强调色；主按钮白字 4.52:1 已过 4.5 的底线，留待核心屏打磨轮一并看。`!!` 是纯符号字形，不进渲染脚本的文字对统计，数值按公式单独核对。

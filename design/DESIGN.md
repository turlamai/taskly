# Taskly DESIGN.md — 设计流程路由

视觉契约单一真源：**[shared/spec/DESIGN-TOKENS.md](../shared/spec/DESIGN-TOKENS.md)**（语义色 × 明暗、几何与组件规范、漂移台账全部在那里，本文件不复制）。行为契约：[shared/spec/PRODUCT-SPEC.md](../shared/spec/PRODUCT-SPEC.md)。`apps/desktop/src/style.css` 以 `@import` 直接消费原型 CSS——不改引用方向（原 `Theme.swift` 引用随原生宿主退役）。

## 流程（原型先行）

- 改界面 = 改 DESIGN-TOKENS / PRODUCT-SPEC → 更新 `design/prototype/` 原型 → HIG 评审 → 单一 glaze web 宿主实现。反向顺序禁止。
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

- 桌面 = **glaze 载体**：一套 Web UI 跨 macOS、Windows、Linux；原生三腿已退役换线 glaze（issue #141，原生线止于 `51c9c1c`，版本重置 0.1.0）。本文历史账本中的原生三腿只描述历史，不改变当前定线。
- 移动端 = **原生 iOS app（Swift）**。此处 HTML 只表达设计契约与交互规格，不把 glaze 载体扩展到移动端；本轮不创建 Swift 工程，也不扩大到其他移动平台。
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
- [ ] 零外部依赖，相对资源与导航引用存在；独立 HTML 可通过本地 HTTP 打开。
- [ ] 44×44 命中、字号／间距／图标／圆角适用项通过；文字放大、焦点、读屏语义、reduced motion 按家族 UI 清单检查。
- [ ] 空态／全部完成／保存中／加载／失败恢复覆盖，无独立系统通知或 SQLite 能力承诺。
- 原型自查记录在本节补充；Swift 真机、VoiceOver、Dynamic Type 与系统 picker／通知／SQLite 行为留待原生实现切片验证，HTML 自查不替代这些证据。

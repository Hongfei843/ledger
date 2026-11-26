# 轻账 · 交接文档（v1.0 收尾版）

> 最后更新：2026-11-25
> 用途：开新对话时，把这份文档整段发给下一个 AI / 未来的自己，就能无缝接手。

---

## 0. 一分钟接手

- 仓库：`https://github.com/Hongfei843/ledger`（公开，避免构建额度）
- 本机工程：`D:\开发\记账App`
- 构建：GitHub Actions 产出未签名 IPA，本地用全能签/Sideloadly 重签
- 推送：`pwsh -File .gh/push.ps1 -Message "..."`
- 构建：`pwsh -File .gh/ci.ps1`（会自动等结果并抓失败日志）
- 令牌：`.gh/token.txt`（仓库外，7 天过期）
- 测试：161 个用例，CI 每次真跑
- 项目状态：**开发期（尚未定稿）**。现阶段不保留旧数据迁移包袱，正式使用前会清库重来；定稿时会明确提醒
- 最近绿色构建：2026-11-26 run 45787548051（`macos-15-intel`，161 测试全绿，导入兼容专项/旧版备份）

## 1. 产品定位

自用记账 App：多账户、报销、贷款、对账。数据只在本机。
核心不是「记得多」，而是**账面和现实对得上**。

## 2. 当前功能全景

**记账**：支出/收入/转账；金额、分类、账户、日期、商家、备注、可报销；账户按使用频次排序并显示余额/可用额度，数字键盘长按退格清空、保存键显示金额；快捷日期（今天/昨天/前天）、记住上次账户与分类；截图识别预填金额、商户、日期和**付款方式（银行 + 卡类型 + 后四位）**，账户里没有这张卡时提示一键添加；右滑编辑、左滑删除（5 秒撤销）。

**首页**（摘要 + 明细）：周期切换收进左上角菜单，顶栏显示紧凑标题（11月 / 3月5日 / 区间），菜单里有上一期/下一期、日/周/月/年/自定义，并记住上次选择；收支双卡 + 结余/昨日/净资产；7 天内到期提醒（信用卡带待还金额）；未对账提醒；搜索（关键词/金额区间/时间范围/可报销/退款）。账户卡片已移到「资产」Tab。

**账户**：9 种类型（新增「投资理财」）；投资账户可填持仓成本，详情/资产页显示市值、浮动盈亏、收益率；银行/平台品牌图标（32 个）；卡号后四位；余额校准；信用卡账单日/还款日/额度；账单登记与还款核销。资产总览含近 6 个月净资产趋势（按月末重算余额）。

**资金计划**：未来 30/60/90 天现金流入流出时间线；当前可用资金 + 期末预计；含贷款还款、信用卡还款（已登记账单优先、未登记按账单周期估算）、周期记账、有到期日的借入借出。

**信用卡账单联动**：账户详情显示账单周期、出账日、App 估算、已登记账单对比、最低还款未还与还款倒计时；转账到信用卡会自动按「最早到期优先」核销未结清账单。

**分类**：27 个支出分类 + 9 个收入分类（水费/电费/燃气费拆分；新增物业费、运动健身、捐款、利息收入等；刻意不做买菜/零食/外卖/咖啡奶茶这类和餐饮重叠的小类）；开发期只保证全新安装分类完整，升级时只补缺失、不做历史迁移；记账页分「常用 6 个」与「全部」；分类管理可改名、换图标、归档、查看条目。

**统计**：三种口径（现金流/个人消费/垫付）；洞察 5 条规则；环形图（百分比标签）；分类排行下钻；6 个月趋势；**月度报告**（收支/结余、环比、储蓄率、分类排行、每日趋势、本月最大几笔、一键分享文字版）。

**报销**：报销单全流程；月度报表（汇总/分类小计/明细/超期）；CSV/PDF 导出。

**贷款**：7 种类型；5 种还款方式；摊销计划；一键记还款（本金转账 + 利息支出）；提前还款测算；公积金月冲；IRR 实际年化。

**退款**：支出详情里「记一笔退款」，退款挂到原支出上：统计冲减支出、不算收入；列表/详情有退款标记，删支出会连带删退款。

**常用组合**：记一笔时点模板一键套用（类型/金额/账户/分类/商家/备注），在「我的 → 常用组合」里增删改。

**对账**：一页填实际余额；差异自动生成调整；每次对账留痕（ReconciliationRun）。

**导入导出**：Cookie CSV 导入（自动归类）；支付宝/微信账单比对（漏记/多记）；AI 分析包（ZIP）；完整备份 JSON v2（一键恢复，恢复前自动留副本）。导入兼容：兼容旧版 v1 备份、缺失字段自动补默认；CSV 编码支持 UTF-8(带 BOM)/UTF-16/GB18030/GBK，表头支持全角括号与新别名，分隔符支持逗号/分号/Tab。

**其他**：周期记账自动生成；借入借出（应收/应付跟踪）；截图识别记账（本地 OCR，可接快捷指令/操作按钮）；**桌面快捷菜单**（长按 App 图标 → 记一笔 / 截图记账，零配置）；**App Intents / Siri**（内置「记一笔」「截图记账」「本月支出」三个动作，快捷指令 App 搜「轻账」即可用，Siri 可说「用轻账记一笔」「轻账本月支出」）；数据健康度；面容 ID / 触控 ID 锁（先走系统生物识别，失败才退设备密码）；隐私遮罩；极简应用图标（固定单图标）；一键初始化（倒计时 + 二次确认）。

## 3. 页面结构

```
明细 | 统计 | 报销 | 资产 | 我的
```

- **明细**：只放摘要 + 明细。左上角周期菜单（上一期/下一期、日/周/月/年/自定义，顶栏显示 11月 / 3月5日 等紧凑标题）；摘要（收支双卡 + 结余/昨日/净资产）；即将到期/未对账提醒；按天分组的流水。
- **统计**：月份切换、口径、洞察、环形图、分类排行、6 个月趋势；右上角进「月度报告」。
- **报销**：报销单列表与报表导出。
- **资产**：净资产卡、投资持仓（市值/成本/盈亏/收益率）、账户列表（含信用卡待还）、负债与往来（贷款/信用卡/借入借出）、快捷入口（资产总览、资金计划、对账）。
- **快速启动**：长按桌面「轻账」图标可直接选「记一笔」「截图记账」（Info.plist UIApplicationShortcutItems + AppDelegate 处理，冷启动会暂存动作）。
- **系统集成**：App Intents 自动注册到「快捷指令」与 Spotlight（记一笔 / 截图记账 / 本月支出），Siri 可直接调用（见 `App/LedgerIntents.swift`）。
- **我的**：按功能分组
  - 记账：分类管理、常用组合、周期记账、截图记账、导入账单、账单比对
  - 资产：账户管理、资产总览、资金计划、对账、借入借出
  - 数据：流水/账户数、数据健康、导出分析包、备份与恢复
  - 维护：初始化数据
  - 外观：分类图标风格、主题色
  - 提醒：还款提醒
  - 安全：面容 ID / 密码锁
  - 关于：版本

## 4. 代码结构

```
Ledger/
├─ App/       LedgerApp、RootTabView（5 Tab + 引导 + 隐私遮罩 + 应用锁）
├─ Core/      Money、AppCalendar、Theme、Haptics、CategoryIcon、BankPreset、
│             PeriodRange、ZipWriter、NotificationService、DocumentPicker、BiometricLock
├─ Data/
│  ├─ Models/ 14 个 @Model
│  └─ Store/  ModelContainerFactory、SeedData、ImportService、RecurringService
├─ Domain/    BalanceService、StatsEngine、InsightEngine、MonthlyReport、InvestmentService、
│             CreditCardCycle、ClaimReport(+PDF)、RecurringEngine、Loan/LoanCalculator、
│             Backup/(BackupDTOs、BackupService)、
│             Import/(CookieCSVImporter、BillCSV、BillMatcher、CategoryMatcher)、
│             Export/AIExportBuilder
├─ OCR/       OCRService、ScreenshotParser
├─ Features/  Entry、Transactions、Stats(含 MonthlyReportView)、Reimbursement、Loans、Accounts、Assets、
│             Categories、Reconciliation、Recurring、Health、Onboarding、Settings
└─ Resources/ Info.plist、ASSETS_SOURCE.md、Assets.xcassets
```

约定：
- `Domain/` 禁止 `import SwiftUI`（保证可单测）
- 金额一律 `Int64` 分；软删除；UUID 外键；枚举存 String
- 颜色一律走 `Theme`，禁止写死 `.white/.black`（深色会看不见）

## 5. 构建与发布

```
project.yml --XcodeGen--> Ledger.xcodeproj --xcodebuild--> .app --zip--> IPA
```

要点：
- 不手写 `.xcodeproj`，由 `project.yml` 生成
- 应用图标固定为「极简」单图标：`AppIcon.appiconset` 必须带完整尺寸矩阵（20/29/40/60/76/83.5/1024，含 @2x/@3x），只放 1024 单尺寸时重签安装后桌面可能空白
- 构建脚本（scripts/build-ipa.sh）会把完整图标 PNG 以传统文件名再拷一份到 App 根目录，并补 `CFBundleIconFiles`：重签工具/系统图标缓存只认 loose png 时靠它兜底
- 不要再加多套备用图标（`CFBundleAlternateIcons`）：重签设备上部分备用图标会被 iOS 渲染成空白，已在设置里移除切换入口
- 面容 ID 必须在 Info.plist 保留 `NSFaceIDUsageDescription`，否则系统只弹密码；`BiometricLock` 先尝试 `.deviceOwnerAuthenticationWithBiometrics`，失败才退 `.deviceOwnerAuthentication`
- 版本号由 CI 注入 `1.0.<run_number>`
- 只在 workflow_dispatch 触发；推送后跑 `.gh/ci.ps1` 主动构建（push 不再自动跑，避免重复排队）
- 标准 runner 合法标签（见 `actions/runner-images` README）：`macos-15-intel`（**默认，x64 池，2026-11-25 实测可用**）、`macos-15`（arm64 池，容量紧张）、`macos-26`（arm64）、`xcode-27-arm64`
- ⚠️ `macos-15-arm64` / `macos-26-arm64` 是镜像目录名，**不是合法标签**，写了 job 会永远排队
- 2026-11 起 macOS 托管 runner 容量长期紧张（尤其 arm64）：job 排队后 `cancelled` 且 0 步执行 = 平台容量问题，不是编译失败；跑 `.gh/ci-race.ps1` 自动轮换标签重试并抓包

## 6. 测试覆盖（161）

Money、Balance、AccountUsage、BackupRestore、ImportCompatibility、PeriodPreference、MonthlyReport、
Investment、StatsEngine、NetWorthHistory、CashFlowForecast、CreditCardBill、StatementSettlement、
LoanCalculator、CreditCardCycle、Statement、Debt、Refund、ScreenshotImport、PaymentMethodDetector、
CategorySeed、QuickTemplate、TxnSearch、CookieCSVImporter、BillCSV、CategoryMatcher、PeriodRange、
RecurringEngine、ScreenshotParser、InsightEngine、ZipWriter、Smoke。

## 7. 已知限制

1. 无 iCloud 同步（自签无 entitlement）
2. 无多账本 UI（模型有 bookId）
3. 银行图标来自 Cookie 素材，上架前必须替换（见 `Resources/ASSETS_SOURCE.md`）
4. 组合贷需手动录两笔
5. 快捷指令需要手动建一次（见「我的 → 截图记账」里的步骤），iOS 不允许 App 自动安装快捷指令
6. 无预算、无二级分类
7. 金额字号已全量统一到 `Theme.Fonts`；个别二级页面内边距还可以继续微调
8. 提前还款重算是 O(n²)，单次无感
9. 退款按退款发生月冲减支出：跨月退款不会回改原月份的统计（原月份仍是当时花的钱）
10. 投资账户只记「市值 + 成本」，不做逐笔持仓/交易流水；成本需在账户编辑里手动更新
11. 月度报告是本地汇总，不生成 PDF（可分享文字版）

## 8. 下一轮建议（按优先级）

1. **分享扩展**：任意 App 里分享截图直接进轻账（需要新 extension target，自签时要确认重签包含 appex）。
2. **多账本 UI**：模型已有 bookId，差切换入口与全量按账本过滤。
3. **投资进阶**：逐笔持仓/交易、成本自动更新、收益曲线。
4. **信用卡账单进阶**：账单分期、最低还款提醒。
5. 收尾打磨：空状态、引导、文案、初始化数据自检。
6. 银行图标补地方银行（素材库有 300+ 家）。
7. 小组件（需额外 target，自签会复杂）。
8. 上架准备：换素材、隐私政策、CloudKit 同步（付费账号可用）。

## 9. 排查手册

| 现象 | 位置 |
|---|---|
| 构建失败 | CI 日志搜 `error:`；常见 API 名笔误、参数顺序 |
| job `cancelled` 且 0 步 | macOS runner 容量问题，非编译失败；`.gh/retry-ci.ps1` 重试或换 runner 标签 |
| 单测失败 | 搜 `LedgerTests/.*swift` |
| 文件选不中 | 已用 `DocumentPicker(asCopy: true)`，仍失败查 UI |
| 深色看不见 | 颜色必须走 Theme |
| 图标空白 | 检查 IPA 里 AppIcon 完整尺寸 loose png 与 CFBundleIconFiles；见 `scripts/build-ipa.sh` |
| 面容 ID 不弹 | 查 Info.plist `NSFaceIDUsageDescription`、设备是否录入面容；锁屏页应提示「面容 ID 或设备密码」 |
| 分类没更新 / 数据乱了 | 开发期直接「我的 → 初始化数据」清库重来（seed 版本当前 7，不做历史迁移）；正式使用后不要再依赖迁移逻辑 |
| 长按图标没有快捷菜单 | 查 Info.plist `UIApplicationShortcutItems` 与 `AppDelegate.performActionFor` |
| 截图不识别付款方式 | 取决于截图里是否含银行名 + 卡类型 + 4 位尾号；识别到但账户不存在时会提示添加 |
| 导入旧备份失败 | 兼容 v1（AI 分析包里的 backup.json）与 v2；缺字段自动补默认，已向后不兼容的格式会提示版本不兼容 |
| CSV 导入乱码/没数据 | 编码 UTF-8/UTF-16/GB18030/GBK 自动识别；表头需含「交易时间」「金额」类列；分隔符支持逗号/分号/Tab |
| 余额对不上 | 对账页 / 数据健康 |
| 卡顿 | 避免 body 里遍历全表（已改两处：首页余额、分类计数） |

## 10. 截图记账 / 快捷指令

三条入口都走本地 OCR，图片不上传：

1. **快捷指令 + 操作按钮（推荐，零权限）**
   - 快捷指令 App → 新建： 「截屏」→「存储文件」（位置选 我的 iPhone → 轻账，关闭「询问保存位置」）→「打开 URL」填 `ledger://import-screenshot` → 命名
   - 设置 → 操作按钮 → 快捷指令 → 选它；也可以放进控制中心/锁屏
   - 付款页、账单页按操作按钮：截屏 → 自动打开预填的「记一笔」
2. **分享 / 文件打开**：App 注册了 `public.image`，从相册分享或在文件 App 里点开截图 → 选轻账，直接识别
3. **App 内相册**：明细页右上角取景框按钮

实现：`OCR/ScreenshotInbox.swift`（收「轻账」目录最新截图）、`OCR/ScreenshotImportService.swift`（OCR→草稿）、`Domain/ScreenshotImportDraft.swift`（草稿存取、10 分钟过期）、`RootTabView`（URL 与 pending 草稿）、`EntrySheetPrefill`（预填；没识别出金额会让用户手填）。

## 11. 开新对话的开场话术

> 这是一个 iOS 记账 App（SwiftUI + SwiftData），代码在 GitHub 仓库 Hongfei843/ledger，
> 本地在 D:\开发\记账App，用 GitHub Actions 出未签名 IPA。
> 先读 D:\开发\记账App\DEV.md 和 Ledger/Resources/ASSETS_SOURCE.md，再开始改动。
> 改完用 .gh/push.ps1 推送、.gh/ci.ps1 构建验证，测试必须全绿。

## 12. 定稿计划（给用户看）

目标：功能闭环后进入冻结，再让用户导入真实数据。

- **batch 41（已完成）**：导入兼容专项（旧版备份 v1、缺失字段、CSV 编码/表头/分隔符）。
- **batch 42**：多账本 MVP（账本切换 + 按账本过滤）＋ 投资进阶（逐笔持仓/收益曲线）。
- **batch 43**：分享扩展（任意 App 分享截图直接进轻账）＋ 收尾打磨（空状态、引导、文案、初始化数据自检）。
- **batch 44（定稿候选）**：全量回归测试 + 真机路径自查清单 + 版本定稿。届时会明确提醒：「可以导入数据开始正式使用」。

定稿前不保证旧数据兼容：开发期数据可随手清库。

# 开发与交接文档

> 面向：接手迭代的人、未来的你、排查问题时的自己。
> 最后更新：2026-11-24 · 版本 1.0.x

---

## 1. 一句话定位

自用的 iOS 记账 App：多账户、报销、贷款、对账，数据只在本机，靠自签安装。
目标不是「记了多少笔」，而是**账面和现实对得上**。

## 2. 环境与构建

| 项 | 值 |
|---|---|
| 语言/框架 | Swift + SwiftUI + SwiftData + Charts + Vision |
| 语言模式 | Swift 5（编译器 Swift 6），`SWIFT_STRICT_CONCURRENCY = minimal` |
| 部署目标 | iOS 18.0 |
| 第三方依赖 | **零**（自签与 CI 都要少失败点） |
| 工程生成 | XcodeGen（`project.yml`），**不手写 .xcodeproj** |
| 构建 | GitHub Actions `macos-26` → 未签名 IPA |
| 签名 | 本地用全能签 / Sideloadly 自签，7 天有效 |

```
project.yml ──XcodeGen──> Ledger.xcodeproj ──xcodebuild──> Ledger.app ──zip──> Ledger-unsigned.ipa
```

CI 步骤：选最新 Xcode → `brew install xcodegen` → 生成工程 → `scripts/build-ipa.sh` → **跑单测** → 上传 artifact。
版本号由 CI 注入 `1.0.<run_number>`。

推送（无 Mac，走 API）：
```powershell
pwsh -File .gh/push.ps1 -Message "..."   # 推送
pwsh -File .gh/ci.ps1                    # 触发构建 + 等结果 + 失败抓日志
```

## 3. 完整目录结构

```
Ledger/                                   # 仓库根
├─ project.yml                            # XcodeGen 配置
├─ .github/workflows/build.yml            # CI：构建 + 单测 + 上传 IPA
├─ scripts/build-ipa.sh                   # 未签名 IPA 打包
├─ DEV.md                                 # 本文档
├─ 01-需求规格说明书.md / 02-给AI的开发提示词.md / 03-无Mac出包指南.md / 04-工程结构与接口契约.md
├─ Ledger.xcodeproj                       # 由 CI/本地生成，不入库
│
├─ Ledger/
│  ├─ LedgerApp.swift                     # 入口，容器失败时显示错误页
│  ├─ App/RootTabView.swift               # 5 Tab、引导、分享导入、周期任务调度
│  │
│  ├─ Core/                               # 无 UI 依赖或仅设计 token
│  │  ├─ Money.swift                      # Int64 分 <-> Decimal，格式化/解析
│  │  ├─ AppCalendar.swift                # 周一为首日、月份区间、日期标题
│  │  ├─ Theme.swift                      # 颜色/间距/圆角/主题色
│  │  ├─ Haptics.swift                    # 触感统一入口
│  │  ├─ CategoryIcon.swift               # 分类图标风格（Emoji / SF Symbol）
│  │  ├─ BankPreset.swift                 # 银行/平台预设 + 品牌标记视图
│  │  ├─ PeriodRange.swift                # 日/周/月/年/自定义区间
│  │  ├─ ZipWriter.swift                  # 自实现 ZIP（store + CRC32）
│  │  └─ NotificationService.swift        # 还款/对账本地通知
│  │
│  ├─ Data/
│  │  ├─ Models/                          # 12 个 @Model
│  │  │  Account / Category / Txn / Claim / Loan / LoanScheduleItem
│  │  │  Statement / Book / MerchantRule / CaptureRecord / RecurringRule / ReconciliationRun
│  │  └─ Store/
│  │     ├─ ModelContainerFactory.swift   # Schema 注册；失败返回 nil 不崩溃
│  │     ├─ SeedData.swift                # 初始分类 + 版本化迁移（零食→餐饮）
│  │     ├─ ImportService.swift           # Cookie CSV 落库（externalId 去重）
│  │     └─ RecurringService.swift        # 周期交易补记
│  │
│  ├─ Domain/                             # 纯逻辑，禁止 import SwiftUI
│  │  ├─ BalanceService.swift             # 余额/净资产
│  │  ├─ StatsEngine.swift                # 三种口径、分类/月度聚合
│  │  ├─ InsightEngine.swift              # 5 条本地洞察规则
│  │  ├─ CreditCardCycle.swift            # 账期与还款日推算
│  │  ├─ ClaimReport.swift                # 报销月报聚合 + CSV
│  │  ├─ ClaimReportPDF.swift             # 报销月报 PDF（A4）
│  │  ├─ RecurringEngine.swift            # 周期日期推算
│  │  ├─ Loan/LoanCalculator.swift        # 摊销/IRR/提前还款
│  │  ├─ Import/CookieCSVImporter.swift   # Cookie CSV 解析
│  │  └─ Export/AIExportBuilder.swift     # AI 分析包（ZIP）
│  │
│  ├─ OCR/
│  │  ├─ OCRService.swift                 # Vision 本地识别
│  │  └─ ScreenshotParser.swift           # 金额/商户规则解析
│  │
│  ├─ Features/
│  │  ├─ Entry/EntrySheet.swift           # 记一笔（键盘/分类/账户/日期/报销）
│  │  ├─ Transactions/TransactionListView.swift   # 首页（周期切换 + 账户卡片）
│  │  ├─ Transactions/SearchView.swift            # 搜索（备注/金额/分类/账户）
│  │  ├─ Transactions/TxnDetailView.swift         # 详情 + 同类别对比
│  │  ├─ Stats/StatsView.swift            # 统计 + 洞察
│  │  ├─ Stats/CategoryTxnListView.swift  # 分类下钻
│  │  ├─ Reimbursement/ClaimListView.swift / ClaimDetailView.swift / ClaimReportView.swift
│  │  ├─ Loans/LoanListView.swift / LoanDetailView.swift
│  │  ├─ Accounts/AccountsView.swift / AccountDetailView.swift
│  │  │          AccountEditView.swift / AssetOverviewView.swift
│  │  ├─ Categories/CategoryManageView.swift
│  │  ├─ Reconciliation/ReconciliationView.swift
│  │  ├─ Recurring/RecurringListView.swift
│  │  ├─ Health/DataHealthView.swift      # 数据健康度
│  │  ├─ Onboarding/OnboardingView.swift
│  │  └─ Settings/SettingsView.swift / ImportView.swift / ExportView.swift
│  │
│  └─ Resources/
│     ├─ Info.plist                       # 文档类型（CSV 分享打开）
│     └─ Assets.xcassets/
│        ├─ AppIcon.appiconset
│        ├─ AccentColor.colorset
│        └─ BankLogos/                    # 10 家银行/平台的 Logo（@1x/2x/3x）
│
└─ LedgerTests/                           # 12 个测试文件，55+ 用例
   Money / Balance / StatsEngine / LoanCalculator / CreditCardCycle
   Statement / CookieCSVImporter / ZipWriter / ScreenshotParser
   InsightEngine / RecurringEngine / Smoke
```

## 4. 数据模型要点

- 金额一律 `Int64` 存「分」，字段以 `Minor` 结尾；**禁止 Double 参与金额计算**。
- 每表都有 `id / createdAt / updatedAt / deletedAt`，删除一律软删除。
- **不用 `@Relationship`**，只用 UUID 外键（查询简单、避免级联删除坑）。
- 枚举以 `String` 原始值存储（`typeRaw` + computed 属性），避免迁移问题。
- 流水模型叫 `Txn`，避免与 SwiftUI 的 `Transaction` 撞名。

## 5. 业务规则速查

| 编号 | 规则 | 关键点 |
|---|---|---|
| R1 | 余额 | `opening + income − expense + transferIn − transferOut + adjustment`；资产正、负债负 |
| R2 | 转账 | 不进收入、支出、分类统计 |
| R3 | 信用卡还款 | 必须走转账；目标是 credit/bnpl 时显示「还款」 |
| R4 | 余额校准 | `adjustment` 不进收支统计 |
| R5 | 报销口径 | 现金流 / 个人消费（默认）/ 垫付，同一个 StatsEngine 传参 |
| R6 | 报销到账 | 自动生成「报销收入」流水，不允许手动关联 |
| R7 | 报销月报 | 垫付/已提交/已到账/未到账 + 分类小计 + 回款天数 |
| R8 | 导入去重 | `externalId` 优先（Cookie 的 UUID） |
| R10 | 贷款=负债 | 每个贷款自动建 `isSystem` 负债账户 |
| R11 | **月供拆分** | 本金走转账、利息走支出；整笔记支出是错的 |
| R12 | 摊销 | 全 Decimal，尾差入末期，本金合计精确等于合同本金 |
| R14 | 提前还款 | 缩期取「第一个满足月供≤原月供」的期数 |
| R16 | 实际年化 | 二分法 IRR；12000/12 期/1080 → 15.44% |
| R19 | 账单核销 | 登记银行账单金额 → 还款累加 → 状态自动推导 |
| R20 | 对账 | 超过 30 天未对账且有钱进出的账户才提示 |

## 6. 测试覆盖（55+ 用例）

| 文件 | 覆盖 |
|---|---|
| MoneyTests | 格式化、解析、四舍五入、往返一致 |
| BalanceTests | 收支、转账、信用卡还款不计支出、软删除忽略 |
| StatsEngineTests | 三种口径差异、报销剔除、关闭后回补、分类分组 |
| LoanCalculatorTests | 等额本息/本金/先息后本、本金合计精确、IRR、提前还款省息 |
| CreditCardCycleTests | 同月/跨月还款日、账期、月末收敛 |
| StatementTests | 待还金额、已还/部分/逾期状态 |
| CookieCSVImporterTests | 表头跳过、引号内逗号、金额格式、卡包推断 |
| ZipWriterTests | CRC32、EOCD 结构、中文文件名 |
| ScreenshotParserTests | 取最大金额、排除余额行、商户提取、置信度 |
| InsightEngineTests | 异常大额、订阅识别、空数据不出洞察 |
| RecurringEngineTests | 月末收敛、每日补记、暂停、未来规则、上限 |
| PeriodRangeTests | 周一为周首、自定义区间含结束日、跨月/跨年切换 |

## 7. 已知问题与限制

1. **无 iCloud 同步**：自签拿不到 entitlement，数据只在本机，靠导出备份。
2. **无多账本**：数据模型有 `bookId`，但 UI 未做切换（有意推迟）。
3. **银行/平台图标来自 Cookie 素材**（32 个），上架前必须替换，见 `Ledger/Resources/ASSETS_SOURCE.md`。
4. **组合贷**需手动录两笔贷款。
5. **OCR 只支持从相册选图**，未接捷径 / App Intents。
6. **提前还款重排是 O(n²)**，单次操作感知不到，但做方案对比时需要优化。
7. **对账差异不落报告**：目前只记录调整流水，没有「本月差异几笔、原因」的归档。
8. 支付宝/微信账单导入：解析器为 Cookie 定制，通用 CSV 映射还没做。

## 8. 排查手册

| 现象 | 先看这里 |
|---|---|
| 构建失败 | CI 日志搜 `error:`；常见是 API 名笔误（`startOfNextMonth`）、参数顺序 |
| 单测失败 | 日志搜 `LedgerTests/.*swift`，断言信息里有期望/实际值 |
| 文件选择器点不动 | 用「从剪贴板粘贴」，或先在文件 App 存到「我的 iPhone」 |
| 版本号不变 | 检查 CI 是否注入 `MARKETING_VERSION` |
| 装完闪退 | 没开「开发者模式」，或签名过期（7 天） |
| 数据没了 | 覆盖安装不丢；卸载会丢，用导出包恢复 |
| 余额对不上 | 设置 → 对账，逐账户填实际余额；或看数据健康度 |
| 周期账没生成 | 检查规则是否暂停 / 未开自动生成 / 开始日期在未来 |
| **构建排队后被取消** | GitHub 托管 macOS runner 容量不足（`not acquired by Runner`）。跑 `.gh/retry-ci.ps1` 自动重试，或稍后手动重跑；与代码无关 |

## 9. 迭代路线

**P0（账实相符）**
1. 对账差异归档（本月差异几笔、原因分类）
2. 账单出账提醒（账单日次日）

**P1（效率）**
3. 支付宝/微信账单通用导入 + 对账比对（找出漏记/多记）
4. 周期性交易支持转账类型
5. 多账本切换

**P2（上架准备）**
6. CloudKit 同步（有付费账号后，数据层已按同步设计）
7. 隐私政策、App 隐私声明、图标、截图
8. 补齐银行 Logo

## 10. 交接须知

- **GitHub 令牌**：`.gh/token.txt`（仓库外，不入库），7 天过期，用完可撤销。
- **不要**引入需要付费开发者能力的 API（iCloud / Push / App Group），否则自签装不上。
- **改数据模型请加可选字段**，否则 SwiftData 迁移可能失败。
- 每次推送 CI 会跑单测；**红了一定要修**，这些用例都是踩过坑换来的。
- **深色模式**：颜色一律走 `Theme`（页面/卡片背景用系统动态色），不要在视图里写死白/黑，否则深色下文字会消失。
- **第三方素材**：新增任何来源非自有的图标/插画，都要登记进 `Ledger/Resources/ASSETS_SOURCE.md`。

## 11. 设计参考（来自 Cookie 记账）

| 借鉴点 | 我们的落地 | 说明 |
|---|---|---|
| 时间感知的问候/插画 | 首页空状态按早/中/晚打招呼 | 成本低，温度高 |
| 记账成功的庆祝反馈 | 保存后顶部「✓ 分类 金额」浮层 + 成功触感 | 用 SwiftUI 实现，不引 Lottie |
| 银行/平台图标 | 32 个图标 + 品牌色回退 | Cookie 用整包图标，我们保留回退方案 |
| Emoji 分类体系 | 50 个常用 Emoji 网格 | 未做分组搜索，后续可扩展 |
| 自定义字体（Antonio/Lato/Ubuntu） | **不采用** | 增加包体积与授权问题，SF Rounded 更贴合 iOS |
| 时间主题插画（dawn/noon/dusk…） | **未采用** | 需自绘素材，且与「工具型」定位不完全匹配 |

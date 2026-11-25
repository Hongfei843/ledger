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
- 测试：76 个用例，CI 每次真跑

## 1. 产品定位

自用记账 App：多账户、报销、贷款、对账。数据只在本机。
核心不是「记得多」，而是**账面和现实对得上**。

## 2. 当前功能全景

**记账**：支出/收入/转账；金额、分类、账户、日期、备注、可报销；右滑编辑、左滑删除（5 秒撤销）。

**首页**：日/周/月/年/自定义周期切换；收支双卡 + 结余/昨日/净资产；账户横滑卡；7 天内到期提醒；未对账提醒；搜索。

**账户**：8 种类型；银行/平台品牌图标（32 个）；卡号后四位；余额校准；信用卡账单日/还款日/额度；账单登记与还款核销。

**分类**：22 个宽口径分类（餐饮/交通/购物/日用/居住/房租/水电燃气/通讯/娱乐/医疗/教育/人情/旅行/宠物/母婴/订阅服务/利息支出/手续费/保险/税费/报销差额/其他）；记账页分「常用 6 个」与「全部」；分类管理可改名、换图标、归档、查看条目。

**统计**：三种口径（现金流/个人消费/垫付）；洞察 5 条规则；环形图（百分比标签）；分类排行下钻；6 个月趋势。

**报销**：报销单全流程；月度报表（汇总/分类小计/明细/超期）；CSV/PDF 导出。

**贷款**：7 种类型；5 种还款方式；摊销计划；一键记还款（本金转账 + 利息支出）；提前还款测算；公积金月冲；IRR 实际年化。

**对账**：一页填实际余额；差异自动生成调整；每次对账留痕（`ReconciliationRun`）。

**导入导出**：Cookie CSV 导入（自动归类）；支付宝/微信账单比对（漏记/多记）；AI 分析包（ZIP）；完整备份 JSON。

**其他**：周期记账自动生成；借入借出（应收/应付跟踪）；截图 OCR；数据健康度；面容 ID 锁；隐私遮罩；四套可切换图标；一键初始化（倒计时 + 二次确认）。

## 3. 页面结构

```
明细 | 统计 | 报销 | 负债 | 我的
```

「我的」下的二级页面：账户管理、分类管理、对账、资产总览、周期记账、数据健康、导入账单、账单比对、导出分析包、初始化数据、外观（主题色 + 图标风格）、应用图标、安全、提醒。

## 4. 代码结构

```
Ledger/
├─ App/       LedgerApp、RootTabView（5 Tab + 引导 + 隐私遮罩 + 应用锁）
├─ Core/      Money、AppCalendar、Theme、Haptics、CategoryIcon、BankPreset、
│             PeriodRange、ZipWriter、NotificationService、DocumentPicker、BiometricLock
├─ Data/
│  ├─ Models/ 12 个 @Model
│  └─ Store/  ModelContainerFactory、SeedData、ImportService、RecurringService
├─ Domain/    BalanceService、StatsEngine、InsightEngine、CreditCardCycle、
│             ClaimReport(+PDF)、RecurringEngine、Loan/LoanCalculator、
│             Import/(CookieCSVImporter、BillCSV、BillMatcher、CategoryMatcher)、
│             Export/AIExportBuilder
├─ OCR/       OCRService、ScreenshotParser
├─ Features/  Entry、Transactions、Stats、Reimbursement、Loans、Accounts、
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
- 必须保留 `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`，否则备选图标变空白
- 版本号由 CI 注入 `1.0.<run_number>`
- 只在 workflow_dispatch 触发；推送后跑 `.gh/ci.ps1` 主动构建（push 不再自动跑，避免重复排队）
- CI 默认跑 `macos-15-arm64`；Intel 的 `macos-15` 池在 2026-11 容量极差（图片停在 8 月，基本拿不到 runner）
- dispatch 时可用 `inputs.runner` 换标签（`macos-15-arm64` / `macos-26-arm64` / `macos-15`）
- **job 排队约 15 分钟后 `cancelled` 且 0 步执行 = runner 容量问题，不是编译失败**；跑 `.gh/retry-ci.ps1` 自动重放（会轮换 runner 标签）

## 6. 测试覆盖（76）

Money、Balance、StatsEngine、LoanCalculator、CreditCardCycle、Statement、Debt、
CookieCSVImporter、BillCSV、CategoryMatcher、PeriodRange、RecurringEngine、
ScreenshotParser、InsightEngine、ZipWriter、Smoke。

## 7. 已知限制

1. 无 iCloud 同步（自签无 entitlement）
2. 无多账本 UI（模型有 bookId）
3. 银行图标来自 Cookie 素材，上架前必须替换（见 `Resources/ASSETS_SOURCE.md`）
4. 组合贷需手动录两笔
5. OCR 只能从相册选图，未接捷径
6. 无预算、无二级分类
7. 统计页/报销页/贷款页的字号与内边距未完全统一
8. 提前还款重算是 O(n²)，单次无感

## 8. 下一轮建议（按优先级）

1. **账单退款**：退款与原账单关联，而不是只记一笔收入。
2. **全局字号规范**：三档金额字号（26/17/13）+ 统一卡片内边距。
3. 常用组合一键复用（账户+分类+金额）。
4. 银行图标补地方银行（素材库有 300+ 家）。
5. 小组件（需额外 target，自签会复杂）。
6. 上架准备：换素材、隐私政策、CloudKit 同步（付费账号可用）。

## 9. 排查手册

| 现象 | 位置 |
|---|---|
| 构建失败 | CI 日志搜 `error:`；常见 API 名笔误、参数顺序 |
| job `cancelled` 且 0 步 | macOS runner 容量问题，非编译失败；`.gh/retry-ci.ps1` 重试或换 runner 标签 |
| 单测失败 | 搜 `LedgerTests/.*swift` |
| 文件选不中 | 已用 `DocumentPicker(asCopy: true)`，仍失败查 UI |
| 深色看不见 | 颜色必须走 Theme |
| 图标空白 | 检查 INCLUDE_ALL_APPICON_ASSETS |
| 余额对不上 | 对账页 / 数据健康 |
| 卡顿 | 避免 body 里遍历全表（已改两处：首页余额、分类计数） |

## 10. 开新对话的开场话术

> 这是一个 iOS 记账 App（SwiftUI + SwiftData），代码在 GitHub 仓库 Hongfei843/ledger，
> 本地在 D:\开发\记账App，用 GitHub Actions 出未签名 IPA。
> 先读 D:\开发\记账App\DEV.md 和 Ledger/Resources/ASSETS_SOURCE.md，再开始改动。
> 改完用 .gh/push.ps1 推送、.gh/ci.ps1 构建验证，测试必须全绿。

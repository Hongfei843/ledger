# 开发与交接文档

> 面向：接手迭代的人、未来的你、以及排查问题时的自己。
> 最后更新：2026-11-24（v1.0.x 迭代期）

---

## 1. 项目概览

个人记账 App，iOS 27，自签安装，无服务器、无账号、零联网。
仓库：`https://github.com/Hongfei843/ledger`（公开，避免占用私有仓库构建额度）

| 项 | 值 |
|---|---|
| 语言/框架 | Swift + SwiftUI + SwiftData + Charts + Vision |
| 语言模式 | Swift 5（编译器 Swift 6），`SWIFT_STRICT_CONCURRENCY = minimal` |
| 部署目标 | iOS 18.0 |
| 第三方依赖 | **零**（刻意为之：自签 + CI 都要少一个失败点） |
| 构建 | GitHub Actions `macos-26` + XcodeGen，产出未签名 IPA |
| 签名 | 用户本地用全能签 / Sideloadly 自签 |

## 2. 构建链路

```
project.yml ──XcodeGen──> Ledger.xcodeproj ──xcodebuild──> Ledger.app ──zip──> Ledger-unsigned.ipa
```

- 不手写 `.xcodeproj`（pbxproj 太脆），改由 `project.yml` 生成。
- CI 步骤：选最新 Xcode → `brew install xcodegen` → `xcodegen generate` → `scripts/build-ipa.sh` → 跑单测 → 上传 artifact。
- 版本号由 CI 注入：`MARKETING_VERSION = 1.0.<run_number>`，每次构建都不同。
- 本地（无 Mac）推送方式：`.gh/push.ps1` 走 GitHub REST API，不依赖 git。

## 3. 目录结构

```
Ledger/
├─ App/          LedgerApp（入口）、RootTabView（5 Tab）、SharedFile
├─ Core/         Money、AppCalendar、Theme、Haptics、CategoryIcon、ZipWriter
├─ Data/
│  ├─ Models/    10 个 @Model 实体
│  └─ Store/     ModelContainerFactory、SeedData（含版本化迁移）、ImportService
├─ Domain/       BalanceService、StatsEngine、Loan/LoanCalculator、Import/、Export/
├─ OCR/          OCRService（Vision）、ScreenshotParser（规则解析）
├─ Features/     Entry、Transactions、Stats、Reimbursement、Loans、Accounts、Settings
└─ Resources/    Info.plist、Assets.xcassets
```

**硬规则**：`Domain/` 不允许 `import SwiftUI`，保证业务逻辑可单测。

## 4. 数据模型要点

- 金额一律 `Int64` 存「分」，字段名以 `Minor` 结尾；**禁止 Double 参与金额计算**。
- 每表都有 `id / createdAt / updatedAt / deletedAt`，删除一律软删除。
- SwiftData **不用 `@Relationship`**，只用 UUID 外键（查询简单、避免级联删除坑）。
- 枚举以 `String` 原始值存储（`typeRaw` + computed 属性），避免迁移问题。
- 实体命名为 `Txn` 而非 `Transaction`（与 SwiftUI 同名类型冲突）。

## 5. 业务规则清单

| 编号 | 规则 | 关键点 |
|---|---|---|
| R1 | 余额 | `opening + income − expense + transferIn − transferOut + adjustment`；资产正、负债负 |
| R2 | 转账 | 不进收入、不进支出、不进分类统计 |
| R3 | 信用卡还款 | 必须走转账；目标是 credit/bnpl 时文案显示「还款」 |
| R4 | 余额校准 | `adjustment` 不进收支统计 |
| R5 | 报销口径 | A 现金流 / B 个人消费（默认）/ C 垫付，同一个 `StatsEngine` 传参 |
| R6 | 报销流程 | 到账时自动生成「报销收入」流水，不让用户手动关联 |
| R7 | 月报 | 垫付/已提交/已到账/未到账 + 分类小计 + 回款天数 |
| R8 | 导入去重 | `externalId` 优先，其次内容哈希 |
| R10 | 贷款=负债 | 每个贷款自动建一个 `isSystem` 负债账户 |
| R11 | **月供拆分** | 本金走转账、利息走支出；**整笔记为支出是错的** |
| R12 | 摊销 | 全 Decimal，尾差入末期，本金合计必须精确等于合同本金 |
| R13 | 一键还款 | 生成两条记录 + 标记期次 + 更新剩余本金 |
| R14 | 提前还款 | 缩期取「第一个满足月供≤原月供」的期数 |
| R16 | 实际年化 | 二分法 IRR；12000/12 期/1080 → 15.44% |

## 6. 测试覆盖（30 个用例）

`MoneyTests`、`BalanceTests`、`StatsEngineTests`、`LoanCalculatorTests`、`CookieCSVImporterTests`、`ZipWriterTests`、`ScreenshotParserTests`。

CI 会真的启动模拟器跑测试，**不是只编译**。测试失败会阻断构建。

## 7. 已知限制

1. **无 iCloud 同步**：自签拿不到 iCloud entitlement，这是硬限制。数据只在本机，靠导出备份。
2. 多账本：数据模型已带 `bookId`，但 UI 还没有切换器。
3. 分类管理页、余额校准 UI 还没做（逻辑已具备）。
4. 报销月报 PDF 未做（CSV 导出也还没接）。
5. 截图 OCR 目前只能从相册选图，未接捷径/App Intents。
6. 分期实际年化在 UI 上还没展示（算法与测试已有）。
7. 贷款仅支持单笔录入，组合贷需要手动录两笔。

## 8. 排查手册

| 现象 | 先看这里 |
|---|---|
| 构建失败 | CI 日志搜索 `error:`；常见是 API 名写错、并发行 |
| 单测失败 | 日志搜索 `LedgerTests/.*swift`，断言信息里有期望值与实际值 |
| 导入点不动文件 | 用「从剪贴板粘贴」，或先在文件 App 存到「我的 iPhone」 |
| 版本号不变 | 检查 CI 是否注入了 `MARKETING_VERSION` |
| 装完闪退 | 没开「开发者模式」，或签名失效（7 天） |
| 数据没了 | 覆盖安装不丢；卸载重装会丢，只能从导出包恢复 |

## 9. 迭代路线（下一步）

1. 报销月报 CSV / PDF 导出
2. 多账本切换器
3. 分类管理页（增删改、隐藏、排序）
4. 余额校准 UI
5. 截图 OCR 接 App Intents（捷径「记一笔」）
6. 消费洞察规则引擎（负债全景、订阅识别、异常支出）
7. 周期性交易自动生成
8. 备份自动导出到 iCloud Drive

## 10. 交接须知

- **GitHub 令牌**：`.gh/token.txt`（仓库外，不会提交），7 天过期，用完可撤销。
- **推送**：`pwsh -File .gh/push.ps1 -Message "..."`；**跑 CI**：`.gh/ci.ps1`。
- **构建产物**：在本机 `D:\开发\dist\`；CI 上在 artifact。
- **不要**在代码里加入任何需要付费开发者能力的东西（iCloud、Push、App Group）。

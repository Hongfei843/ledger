# 轻账 · 开发与交接文档

> 面向：接手迭代的人、未来的你、排查问题时的自己。
> 最后更新：2026-11-25

---

## 1. 一句话定位

自用记账 App：多账户、报销、贷款、对账，数据只在本机，自签安装。
目标不是「记了多少笔」，而是**账面和现实对得上**。

## 2. 环境与构建

- Swift + SwiftUI + SwiftData + Charts + Vision，**零第三方依赖**
- 语言模式 Swift 5（编译器 Swift 6），部署目标 iOS 18
- 工程由 `project.yml` 经 XcodeGen 生成，不手写 .xcodeproj
- CI：GitHub Actions `macos-15`，构建未签名 IPA + 跑单测
- 推送/构建脚本：`.gh/push.ps1`、`.gh/ci.ps1`（走 GitHub API，无 git）

## 3. 页面结构

**5 个 Tab**

```
明细 | 统计 | 报销 | 负债 | 我的
```

**明细（首页）**
- 周期切换：日 / 周 / 月 / 年 / 自定义
- 收支双卡 + 结余/昨日/净资产
- 账户横滑卡片
- 即将到期提醒（7 天内信用卡/贷款）
- 未对账提醒条
- 按日分组的流水；左滑删除（5 秒撤销）、右滑编辑
- 右上角搜索；右下角「记一笔」胶囊按钮

**统计**
- 月份切换 + 口径切换（现金流 / 个人消费 / 垫付）
- 洞察卡片、环形图（含百分比标签）、分类排行（可下钻）
- 近 6 个月柱状图

**报销**
- 本月垫付汇总、进行中/已完成列表
- 月报（汇总/分类小计/明细/超期）+ CSV/PDF 导出

**负债**
- 总负债、本月应还、今年利息
- 贷款卡片 → 详情（还款计划、记还款、提前还款测算）

**我的**
- 账户管理、分类管理、对账、资产总览、周期记账、数据健康
- 导入账单、账单比对、导出分析包、初始化数据
- 外观（主题色、分类图标）、应用图标、安全（面容 ID 锁）、提醒

## 4. 数据模型（12 张表）

Account / Category / Txn / Claim / Statement / Loan / LoanScheduleItem
Book / MerchantRule / CaptureRecord / RecurringRule / ReconciliationRun

约定：
- 金额一律 `Int64` 分，字段 `*Minor`
- 软删除 `deletedAt`；UUID 外键，不用 `@Relationship`
- 枚举存 String 原始值

## 5. 核心业务规则

1. **余额**：`期初 + 收入 − 支出 + 转入 − 转出 + 调整`；资产正、负债负。
2. **信用卡还款走转账**，绝不用支出，否则支出翻倍。
3. **月供拆分**：本金转账、利息支出。
4. **三种统计口径**由同一个 `StatsEngine` 传参，不写多套查询。
5. **对账**生成 adjustment，不进收支统计，并留一条 `ReconciliationRun`。
6. **导入自动归类**：外部分类名按关键词落到已有分类（`CategoryMatcher`）。

## 6. 测试（74 个用例）

Money / Balance / StatsEngine / LoanCalculator / CreditCardCycle / Statement
CookieCSVImporter / BillCSV / CategoryMatcher / PeriodRange / RecurringEngine
ScreenshotParser / InsightEngine / ZipWriter / Smoke

CI 每次都会真的跑测试，红了一律先修。

## 7. 已知限制

1. 无 iCloud 同步（自签无 entitlement），靠导出备份。
2. 无多账本 UI（模型有 `bookId`）。
3. 银行图标来自 Cookie 素材，上架前需替换（见 ASSETS_SOURCE.md）。
4. 组合贷需手动录两笔。
5. OCR 只能从相册选图，未接捷径。
6. 无预算、无二级分类、无借入借出。

## 8. 排查手册

| 现象 | 看这里 |
|---|---|
| 构建失败 | CI 日志搜 `error:`（常见：API 名笔误、参数顺序） |
| 单测失败 | 搜 `LedgerTests/.*swift`，断言里带期望/实际 |
| 文件选不中 | 已改用 `DocumentPicker(asCopy: true)`；仍有问题找 UI 层 |
| 深色看不清 | 颜色必须走 `Theme`，不要写死 `.white` / `.black` |
| 余额对不上 | 对账页填实际余额；或看数据健康 |
| 量级卡顿 | 避免在 body 里遍历全表（如分类频次已改为异步缓存） |

## 9. 设计参考（来自 Cookie）

已借鉴：收支双卡、胶囊「记一笔」、日分组卡片、时间问候、保存反馈、银行图标。

未采纳：自定义字体（体积/授权）、时间主题插画（缺素材）、二级分类（选择成本高）。

Cookie 会员功能清单里值得后续做的：
- 面容 ID 锁（**已做**）
- 借入借出（人情债追踪）
- 账单退款单独处理
- 自定义收支类型
- 每月预算 / 分类预算
- 智能快捷记账（常用组合一键复用）

## 10. 下一步路线

**P0**
1. 常用组合一键复用（账户+分类+金额）
2. 借入借出（谁欠我 / 我欠谁）
3. 退款与原账单关联

**P1**
4. 银行图标补地方银行
5. 预算（如果重新需要）
6. 小组件

**P2**
7. iCloud 同步（上架后）
8. 多账本

## 11. 交接须知

- 令牌在 `.gh/token.txt`（仓库外），7 天过期
- 不要引入需要付费开发者能力的 API（自签装不上）
- 改模型只加可选字段
- 新增第三方素材必须登记 `ASSETS_SOURCE.md`
- 深色模式下任何写死颜色都会变成「看不见的字」

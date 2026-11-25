# 第三方素材来源与替换说明

> ⚠️ **上架 App Store 前必须处理本文件列出的素材。**

## 1. 当前使用的素材

### 银行 / 支付渠道图标

| 项 | 说明 |
|---|---|
| 位置 | `Ledger/Resources/Assets.xcassets/BankLogos/bank_<id>.imageset` |
| 数量 | 32 个（20 家银行 + 12 个支付/信用平台） |
| 来源 | **Cookie 记账 App 资源包**（由用户从 IPA 中提取，经裁切与重采样到 @1x/@2x/@3x） |
| 状态 | 仅个人自用 |

对应 id：`cmb icbc ccb abc boc bocom psbc citic spdb cmbc cib ceb hxb cgb pab bosh bob nbcb webank mybank`（银行）、`alipay wechat qq yeb lqt szrmb huabei jdbt douyin dywallet meituan pdd`（平台）。

### 未使用的 Cookie 素材

`Cookie素材库/` 下还有界面图标、插画、动效、字体、位图等，**目前一个都没有引入**。
如果将来引入，请同样登记到本文件。

## 2. 法律状态

- 银行与支付机构的 Logo 属于其**注册商标**，使用权通常授予合作方。
- Cookie 记账已上架且内含这些图标，说明平台当前接受度较高，但**不构成对第三方的授权**。
- 个人自签自用不涉及公开分发，风险极低。
- **上架 App Store 属于公开分发**，届时需要：
  1. 替换为自有绘制素材，或
  2. 取得各机构授权，或
  3. 退回「品牌色 + 单字缩写」方案（代码已支持，删掉对应 imageset 即可）。

## 3. 如何替换

代码通过 `UIImage(named: "bank_<id>")` 查找图标，**没有图标时自动回退到品牌色单字**，所以替换或删除都不需要改代码。

### 换成自己的素材

1. 准备 512×512 透明 PNG；
2. 覆盖 `bank_<id>@1x/@2x/@3x.png`（60/120/180 像素）；
3. 或直接删除整个 `bank_<id>.imageset` 目录，即可回退到单字。

### 一次性全部回退

```bash
rm -rf Ledger/Resources/Assets.xcassets/BankLogos/*.imageset
```

App 会立刻全部显示为「品牌色 + 单字」，无需重新构建业务代码。

## 4. 上架前检查清单

- [ ] 删除或替换 `BankLogos/` 下的全部第三方图标
- [ ] 搜索项目中是否还有从 Cookie 引入的其他资源（当前：无）
- [ ] 确认 App 名称、图标、截图为自有
- [ ] 隐私政策与 App 隐私声明填写完整
- [ ] 移除截图 OCR 中「可选第三方 API」相关文案（如启用）

## 5. 记录

| 日期 | 变更 |
|---|---|
| 2026-11-25 | 首次引入 32 个银行/支付图标（来源：Cookie 记账 2.29.9） |

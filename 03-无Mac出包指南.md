# 无 Mac 如何拿到 IPA（Windows 全流程）

> 适用：你没有 Mac、没有苹果开发者账号、不打算上架，只想拿到一个能自签安装的 `.ipa`。
> 结论：**用 GitHub Actions 的 macOS 云电脑构建**。全程免费，不需要苹果账号，不需要发布注册。

---

## 一、先说清楚三件事

1. **IPA 必须在 macOS 上编译**（Xcode 只能跑在 macOS）。Windows 上没有合法可靠的本地路径，任何号称能在 Windows 直接编译 iOS 的工具都不靠谱。
2. **构建不需要苹果开发者账号**。我们要产出的是**未签名** IPA，签名这一步由你在手机上用 Sideloadly / SideStore 完成（你说你可以自签）。
3. **我一个人在这台 Windows 上无法替你编译出 IPA**。我能做的是：把整个工程和云端构建脚本准备到「你上传 → 点一下 → 下载」的程度。

---

## 二、三条路，选第一条

| 方案 | 成本 | 时间 | 需要苹果账号 | 说明 |
|---|---|---|---|---|
| **A. GitHub Actions**（推荐） | 免费 | 首次约 20 分钟，之后每次 1 分钟 | 否 | 云端 macOS 跑 `xcodebuild`，产出 artifact |
| B. 借一台 Mac | 免费 | 10 分钟 | 否 | 装上 Xcode 直接跑脚本 |
| C. 租云 Mac（MacinCloud 等） | 约 $1/小时 | 30 分钟 | 否 | 不划算，仅备选 |

---

## 三、方案 A 全流程（8 步）

### 第 1 步：注册 GitHub（免费）

访问 `https://github.com` → Sign up → 邮箱注册。
**这只是代码托管网站的普通账号，不是苹果开发者账号，不收费、不需要公司信息、不需要审核。**

### 第 2 步：新建仓库

右上角 `+` → New repository：
- Repository name：`ledger`（随便）
- 可见性：**Private**（推荐，代码私密）
  - 免费额度：私有仓库每月 2000 分钟，macOS 按 10 倍计费 → 约 **200 分钟**，一次构建 4–8 分钟，够用几十次。
  - 想彻底不限量就选 Public（公开仓库 Actions 免费不限时，但代码公开）。
- 勾选 `Add a README file` → Create。

### 第 3 步：把代码传上去

三种方式，任选：

**① 最省事：GitHub Desktop（Windows 客户端）**
1. 装 `GitHub Desktop` → 登录 → File → Clone repository → 选刚建的 `ledger`
2. 把 AI 给你的整个项目文件夹内容复制进本地仓库目录
3. 左下角填一句提交信息 → `Commit to main` → `Push origin`

**② 网页拖拽（适合文件不多）**
仓库页 → `Add file` → `Upload files` → 把项目文件夹整体拖进去 → Commit。
注意：必须确保 `.github/workflows/build.yml` 这个路径**原样保留**（网页拖拽文件夹会保留结构，但不要拖成 `ledger/项目名/.github/...` 多套一层）。

**③ 命令行（如果你有 git）**
```bash
cd 项目目录
git init && git add . && git commit -m "init"
git branch -M main
git remote add origin https://github.com/<你的用户名>/ledger.git
git push -u origin main
```

### 第 4 步：启用 Actions

进入仓库 → 顶部 `Actions` 标签。
私有仓库首次会显示「Workflows aren't being run on this repository」→ 点 **I understand my workflows, go ahead and enable them**。

左侧应能看到 `Build unsigned IPA`。

### 第 5 步：点一下运行

`Build unsigned IPA` → 右侧 `Run workflow` → 选 `main` → **Run workflow**。

构建过程：
1. 启动 macOS 26 云电脑（约 30 秒）
2. 自动选择最新的 Xcode
3. `xcodebuild` 编译（约 3–6 分钟）
4. 打包成 `Ledger-unsigned.ipa`
5. 上传为 artifact

### 第 6 步：下载 IPA

构建完成后进入该次运行页面 → 拉到最底部 `Artifacts` → 点 `Ledger-unsigned-ipa` 下载一个 zip。
解压 → 得到 `Ledger-unsigned.ipa`。

> artifact 保留 90 天，过期就重新跑一次（点 Run workflow 即可）。

### 第 7 步：Windows 上自签安装

用 **Sideloadly**（Windows 版）：
1. 下载安装 Sideloadly，数据线连 iPhone，信任电脑
2. 把 `Ledger-unsigned.ipa` 拖进 Sideloadly 的 IPA 框
3. Apple ID 填你的免费账号（会用于生成 7 天有效的签名）
4. 点 `Start`，输入 Apple ID 密码（如开了双重认证，需要用 App 专用密码）
5. 安装完成后在手机上：**设置 → 通用 → VPN与设备管理 → 信任你的开发者证书**
6. **设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启手机**（iOS 16 以后必须开，否则闪退）

### 第 8 步：续签（必须知道）

免费账号签的 App **7 天过期**，过期后打不开。
- 到期前用 Sideloadly 重新签一次（**同一 Bundle ID 覆盖安装，数据不丢**）
- 或用 SideStore 做自动续签，省得每周手动弄

---

## 四、每次改代码后怎么更新

```
改代码 → Push 到 GitHub → Actions 自动/手动跑一次 → 下载新 IPA → Sideloadly 覆盖安装
```
数据不会丢（同一 Bundle ID + 同一 App 容器）。

---

## 五、常见失败与解决

| 现象 | 原因 | 解决 |
|---|---|---|
| Actions 页面没有 workflow | `.github/workflows/build.yml` 路径不对，或被多套了一层文件夹 | 检查仓库根目录下是否真的有 `.github/workflows/build.yml` |
| `xcodebuild: error: The project does not contain a scheme named "Ledger"` | 没提交 shared scheme | 工程必须含 `Ledger.xcodeproj/xcshareddata/xcschemes/Ledger.xcscheme` |
| 构建成功但 Artifacts 为空 | 产物路径与 `scripts/build-ipa.sh` 不一致 | 检查脚本输出路径 `dist/Ledger-unsigned.ipa` |
| 编译报 SDK/API 不存在 | 用了 iOS 26+ 专有 API | 已在需求里禁止；让 AI 改成 iOS 18 可用 API |
| 手机上装完闪退 | 没开「开发者模式」，或签名失败 | 设置 → 隐私与安全性 → 开发者模式；重新签 |
| 安装报 `Unable to install` | IPA 未签名直接装 / 证书问题 | 必须经 Sideloadly 重签，不能直接装未签名 IPA |
| 每月构建次数不够 | 私有仓库 macOS 分钟数用尽 | 改 Public 仓库，或等下月重置 |

---

## 六、给 AI 的一句话要求（必须写进提示词）

> 你必须交付可直接用于 GitHub Actions 的 `.github/workflows/build.yml`，工程必须提交 `Ledger.xcodeproj` 与 shared scheme，不得依赖 CocoaPods / XcodeGen / iOS 26 专有 API，确保在 `macos-26` 镜像上一条命令构建出未签名 IPA。

这句话我已经写进 `02-给AI的开发提示词.md` 的硬约束里了。

---

## 七、如果你想更省事

- **第 1 批代码一到就先跑一次 CI**，别等全部写完才发现云端构建起不来。这是最容易踩的坑。
- 把仓库设成 Private，但**别把任何 Apple ID 密码写进仓库**（我们不需要，构建是未签名的）。
- 想要「改一下就能出包」的体验：Actions 里已经配了 `push` 到 `main` 自动触发，连按钮都不用点。

---

## 八、我这边能替你做到哪一步

我可以：
- 生成完整工程骨架与 `build.yml`、`build-ipa.sh`、README
- 保证 CI 配置可直接跑
- 陪你逐条排查构建日志

我不能：
- 在这台 Windows 上直接编译出 IPA（没有 macOS 与 Xcode）

所以最短路径就是：**代码 → GitHub → 点一下 → 下载 IPA → Sideloadly 签名**。

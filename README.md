# 截图账本 · ScreenshotLedger

**截图 = 记账。** 你把微信 / 支付宝 / 银行的付款截图存进相册，打开这个 App，它自己认金额、认商户、认时间，记成账。
不用手输，不上传照片，不上架 App Store，只装在你自己手机上。

---

## 一、这东西到底怎么用（人话版）

1. 付完钱，像平常一样截一张图。**这就是全部动作。**
2. 下次打开「截图账本」，顶部会闪一条进度条：「正在识别 3/5 张」。
3. 几秒后，账目页出现新记录：`-25.00  幸福小面  餐饮  12:47`。
4. 认错了（金额不对、商户是「未知商户」）→ 点那一条 → 改 → 保存。两下。
5. 每月 1 号上午 9 点，手机弹一条通知：`支出 ¥3,842，餐饮最多占 41%，最大一笔 ¥680（某某酒店）`。
6. 换手机：设置 → 导出账本（JSON）→ 存到 iCloud 或发给自己 → 新手机装好 App → 设置 → 导入账本。

**它不会做的事**（说清楚免得你等）：现金支出、别人代付、没截图的消费，它变不出来。这类走右下角「+」手工补记。

---

## 二、装到 iPhone 上的四条路（选一条）

| | A：Xcode + 免费 Apple ID | B：付费开发者账号 | C：TrollStore | **D：GitHub 云编译 + AltStore（推荐给没 Mac 的人）** |
|---|---|---|---|---|
| **需要什么** | 一台 Mac + 你的 Apple ID | 同 A + 每年 $99 | iOS 14.0–17.0 的 iPhone，不用电脑 | 一个免费 GitHub 账号 + Windows 电脑 + 你的 Apple ID |
| **一次能撑多久** | **7 天**，到期 App 打不开，要重新连 Mac 装一次 | **1 年** | 永久（不升级系统） | **7 天**，AltStore 在同一个 Wi-Fi 下自动帮你续 |
| **要不要电脑** | 要，每 7 天一次 | 要，每年一次 | 不要 | 要，但 7 天那次是**自动**的（AltServer 常驻托盘） |
| **花钱** | 0 | 约 ¥700/年 | 0 | 0 |
| **技术门槛** | 装 Xcode（10 GB）+ 点几下 | 同 A | 装一个 App，点一下 | 传代码到 GitHub（网页点几下）+ 装 AltStore |
| **能装几台设备** | 每 7 天 3 台 | 100 台 | 1 台 | 每 7 天 3 台 |
| **掉签后账目会丢吗** | **不会**。账本是 App 沙盒里的 `Documents/ledger.json`，同 Bundle ID 覆盖安装数据保留 | 不会 | 不会 | 不会（同上，另可用「导出 JSON」双保险） |

### 推荐

**你现在是 Windows 电脑、一个人用、还要给一两个朋友装 —— 走 D。**

D 的完整动作只有三步，全在浏览器和一次安装里完成：

1. 把这个文件夹推到你的 GitHub（网页上拖拽上传就行，仓库设为 Private）。
2. 仓库里已经放好了 `.github/workflows/build-ipa.yml`。你 push 完，GitHub 自动开一台云 Mac 编译，**不需要你有 Mac**，约 5–8 分钟。
3. 进仓库的 **Actions** 页 → 点进最新那次运行 → 底部 **Artifacts** 下载 `ScreenshotLedger-ipa`，解开得到 `ScreenshotLedger.ipa`。

拿到 ipa 之后，装到 iPhone 上有两种方式：- **AltStore / SideStore**（推荐）：Windows 上装 AltServer，手机装 AltStore，把 ipa 拖进去签名安装。之后每 7 天，同一个 Wi-Fi 下 AltServer 自动帮你续签，你什么都不用做。
- **Sideloadly**（更简单，但不自动续）：Windows 上打开 Sideloadly，拖 ipa 进去，填 Apple ID，点 Start。7 天后要再点一次。
- **给朋友装**：把 ipa 发给他，他自己用 Sideloadly 配自己的 Apple ID 签名。**不要**用你的 Apple ID 给他签（免费账号每 7 天只有 3 台设备额度，且证书是同一个）。

其它三条什么时候选：

- **你有 Mac**（自己的或借的）→ 走 A，最快，README 第四节有手把手步骤。
- **你打算长期用、还要给多人装** → 走 B，一年 $99，一次签 1 年、100 台设备，省掉所有续签烦恼。
- **你的 iPhone 系统 ≤ 17.0 且有 TrollStore** → 走 C，永久不掉签，一劳永逸。
- **不要**花时间搞 PWA 或"网页版记账"——iOS 网页拿不到相册权限、也调不了 Vision，自动扫描这条就没了，整个产品的前提不成立。

---

## 三、工程结构（每个文件干什么）

```
screenshot-ledger/
├── project.yml                     ← XcodeGen 工程描述（相当于 .xcodeproj 的源文件）
├── .github/workflows/build-ipa.yml ← 路线 D：推上来就自动编译出 .ipa 的云 Mac 配方
├── ScreenshotLedger/
│   ├── Info.plist                  ← App 的门牌：名字、相册权限说明、只支持竖屏
│   ├── Assets.xcassets/            ← 图标（12 个尺寸）+ 主题色（墨绿）
│   ├── App/
│   │   └── ScreenshotLedgerApp.swift    ← 入口。冷启动扫一遍，从后台切回来再扫一遍
│   ├── Model/
│   │   ├── Transaction.swift            ← 一笔账：多少钱、收支、商户、分类、时间、来源截图ID
│   │   └── Categories.swift             ← 12 个分类 + 「商户名里有关键词就猜分类」的规则表
│   ├── Recognition/
│   │   ├── OCR.swift                    ← 苹果 Vision 框架，本地把图片转成文字行
│   │   ├── ReceiptParser.swift          ← 核心：从一堆文字行里挑出金额/商户/时间/收支
│   │   └── LibraryScanner.swift         ← 翻相册，挑出截图，逐张丢给上面两个，去重
│   ├── Store/
│   │   ├── LedgerStore.swift            ← 账本读写：Documents/ledger.json，导出 JSON/CSV，导入合并
│   │   ├── MonthlyReport.swift          ← 月报算法：总额、分类占比、最大一笔、一句话结论
│   │   └── ReportNotifier.swift         ← 每月 1 号 9 点的本地通知
│   └── Views/
│       ├── RootView.swift               ← 三个 Tab + 顶部扫描进度条
│       ├── TimelineView.swift           ← 账目页：按天分组、左滑删、下拉刷新
│       ├── EntryEditor.swift            ← 改账 / 补记一笔
│       ├── ReportView.swift             ← 月报页：大数字 + 分类进度条
│       └── SettingsView.swift           ← 设置：扫描、通知、导出导入、清空
└── tests/
    ├── parser_check.py             ← 识别逻辑的回归测试（9 个真实截图样本，Python 镜像）
    ├── swift_lint.py               ← 静态检查：括号配对、iOS 17 API 误用、双 .sheet、漏 import
    └── make_icon.py                ← 生成 App 图标各尺寸
```

**为什么必须做成原生 App**：iOS 里只有 App 能申请相册权限、只有 App 能调 Vision 做 OCR。网页（PWA）两样都做不到，所以"截图自动变成账目"这件事，网页版从第一行代码起就不可能实现。

**为什么不后台常驻自动扫描**：iOS 不允许 App 在关闭/后台时监听相册变化。所以策略是"每次你打开 App（或从后台切回来）扫一次增量"，已经处理过的截图记在本地，不会重复记账。

---

## 四、在你的 Mac 上编译（路线 A，手把手）

前置：macOS 13+，装好 Xcode（App Store 免费下载，约 10 GB）。

```bash
# 1. 装 XcodeGen（把 project.yml 变成 .xcodeproj，只用装一次）
brew install xcodegen

# 2. 进工程目录，生成 Xcode 工程
cd screenshot-ledger
xcodegen generate

# 3. 打开
open ScreenshotLedger.xcodeproj
```

然后在 Xcode 里：

1. 左边点蓝色的 **ScreenshotLedger** 项目 → TARGETS 选 **ScreenshotLedger** → **Signing & Capabilities**
2. 勾上 **Automatically manage signing**
3. **Team** 选你的 Apple ID（没有就点 Add an Account 登录，免费账号就行）
4. 如果报 Bundle ID 冲突，把 **Bundle Identifier** 改成 `com.你的名字.screenshotledger`
5. 手机用数据线连 Mac，iPhone 上弹「信任此电脑」→ 信任
6. iPhone 打开 **设置 → 隐私与安全性 → 开发者模式** → 打开 → 重启手机
7. Xcode 顶部设备选你的 iPhone → 按 **⌘R**
8. 手机上首次打开会提示"不受信任的开发者" → **设置 → 通用 → VPN与设备管理 → 你的 Apple ID → 信任**

装好了。之后每 7 天，插上线按一次 ⌘R。

---

## 五、没有 Mac：路线 D 手把手（推 GitHub → 云 Mac 编译 → 出 ipa）

这一节是给你的：Windows 电脑、不想买 Mac、还要给一两个朋友装。

### 第一步：把代码传到 GitHub

1. 注册/登录 [github.com](https://github.com)（免费）。
2. 右上角 **+** → **New repository** → 名字填 `screenshot-ledger` → 选 **Private** → **Create repository**。
3. 在新仓库页面点 **uploading an existing file**，把 `screenshot-ledger` 文件夹里的**所有内容**拖进去（包括 `.github` 文件夹 —— 这是关键，它是自动编译的配方）。拖不进去的话，用 GitHub Desktop（免费客户端）打开本地文件夹 → Commit → Publish，更稳。
4. 点 **Commit changes**。

传完的一瞬间，GitHub 就自动开始编译了。

### 第二步：等 5–8 分钟，下载 ipa

1. 进仓库 → 顶部 **Actions** 标签。
2. 左边看到 **build-ipa**，点进去 → 最新那条（黄色转圈 = 编译中，绿色勾 = 成功，红色叉 = 失败）。
3. 绿色勾之后，拉到底部 **Artifacts** → 点 **ScreenshotLedger-ipa** 下载。
4. 得到一个 zip，解开里面是 `ScreenshotLedger.ipa`。

> 编译失败的话，点进那次运行 → 点红色那一步 → 把报错贴给我，我改代码。这一步通常只发生在第一次。

### 第三步：装到 iPhone

**方式一：Sideloadly（最快，一次到位）**

1. Windows 上装 [Sideloadly](https://sideloadly.io/)。
2. iPhone 用数据线连电脑，解锁，点「信任」。
3. 打开 Sideloadly：IPA 处拖入 `ScreenshotLedger.ipa`，Apple ID 填你的，点 **Start**，输密码。
4. 手机上 **设置 → 通用 → VPN与设备管理 → 你的 Apple ID → 信任**。
5. 打开 App，允许访问照片（**建议选「完全访问」**，选「仅部分照片」的话每次新增截图都要手动放行）。

> **注意**：这个 ipa 是「未签名」的（CI 上没有证书，也故意不签——省得你在仓库里放私钥）。Sideloadly / AltStore 会用它自己的签名流程重新打包，所以未签名不影响安装。但它**不能**用「爱思助手一键安装」「苹果配置描述文件」这类方式直接装。

**方式二：AltStore（多花 10 分钟，换来"永远不用管"）**

1. Windows 装 [AltServer](https://altstore.io/)，iPhone 装 AltStore（AltServer 托盘图标 → Install AltStore → 选你的手机）。
2. AltServer 托盘 → **Sideload .ipa** → 选 `ScreenshotLedger.ipa`。
3. 之后只要电脑和手机在同一个 Wi-Fi、AltServer 在托盘里跑着，**每 7 天的续签它会自己完成**，你完全不用管。

**给朋友装**：把 `ScreenshotLedger.ipa` 发给他（微信/网盘都行），让他用**自己的** Apple ID 走上面方式一。别用你的 ID 给他签。

### 关于「7 天」

免费 Apple ID 签的 App 只有 7 天有效期，到期点开闪退。这不是 bug，是苹果的规则，任何免费路线都躲不过。三个解法按省事程度排：

1. AltStore 自动续签（方式二）——你不用动手。
2. 每 7 天用 Sideloadly 重装一次（30 秒，**数据不丢**）。
3. 花 ¥700/年买付费开发者账号（路线 B）——一次性解决，一年签一次。

---

## 六、识别逻辑改坏了怎么自测（不用开 Xcode）

改 `ReceiptParser.swift` 的同时，把同样的改动同步到 `tests/parser_check.py`，然后：

```bash
# Windows / macOS 都行，只要装了 Python 3
python tests/parser_check.py
python tests/swift_lint.py
```

- `parser_check.py`：9 个真实截图样本，全 PASS 才算没把识别改坏。覆盖微信付款、支付宝收款、银行动账短信、工资入账、滴滴行程、退款到账、带大额余额的消费、有优惠的订单、转账给朋友。
- `swift_lint.py`：Windows 上没有 swiftc，这个脚本兜底抓「编译器一定会报错」的低级问题——括号不配对、字符串没闭合、误用 iOS 17 才有的 API（工程是 16.0）、同一个 View 挂两个 `.sheet`、用了 UIKit/Photos 类型却没 import。

两个都通过，再交给 Mac 或 GitHub 编译，能省掉大半轮"推上去才发现编译失败"。

---

## 七、已知的边界（诚实交代）

- **只在中文界面下调过**。微信/支付宝的英文版截图认不出来。
- **银行的语音播报截图、短信截图**能认（测试样本里有），但如果银行连商户名都不给，商户会显示「未知商户」，分类落到「其他」。
- **一次性付款码、自动续费、跨月退款**：金额能抓对，分类可能要你手改一次。
- **相册里的极大量截图**首次扫描会慢（每张几百毫秒），第二次打开就是秒开。
- **iCloud 优化存储**打开时，很久以前的截图可能要先从云端下载，第一次扫会慢一点，属正常。

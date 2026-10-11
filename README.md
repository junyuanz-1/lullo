# Lullo 摇摇

**Lullo（摇摇）** 是一个类似 Huckleberry 的 iOS 宝宝记录 App：记录睡眠、喂养、尿布、吸奶、生长、健康和日常活动。数据通过 iCloud 同步和备份，可以与家人实时共享，支持锁屏 / 灵动岛实时计时（Live Activity）和桌面小组件。

界面支持 **简体中文** 和 **English**，跟随系统语言。

---

## 功能

| 模块 | 功能 |
|---|---|
| **睡眠** | 一键计时或补录；小睡 / 夜间睡眠自动区分（夜间时段可设置）；睡眠地点；跨午夜自动拆分统计 |
| **SweetSpot 小睡预测** | 按月龄的清醒时长（wake window）推算下次小睡 / 入睡时间；有 5 次以上记录后会结合宝宝自己的作息个性化调整；可设提醒 |
| **亲喂** | 左 / 右侧分别计时，随时切换、暂停；自动建议下次从哪一侧开始；也可以补录每侧分钟数 |
| **奶瓶** | 奶量（ml / oz）、常用量快捷按钮、配方奶 / 母乳 / 混合 / 牛奶 |
| **辅食** | 食物名称、量、喜好反应（含过敏提醒） |
| **吸奶** | 左右侧奶量、计时 |
| **尿布** | 湿 / 便便 / 混合 / 干爽；便便颜色和性状（异常颜色会提示就医）；尿布疹 |
| **生长** | 体重、身长、头围；**WHO 0–24 个月生长曲线**和百分位 |
| **健康** | 用药（可设下次服药提醒）、体温（发烧提示，3 个月以下会特别提醒）、症状、疫苗 |
| **活动** | 洗澡、趴卧练习、户外、玩耍、讲故事、看屏幕、肌肤接触、刷牙、抚触、如厕 |
| **备注 / 照片** | 每条记录都可以加备注和照片 |
| **趋势** | 7 / 14 / 30 天：Huckleberry 风格的 24 小时作息图、睡眠（夜间 / 小睡，对比推荐睡眠时长）、喂养次数与奶量、亲喂时长、尿布、吸奶、每日平均 |
| **多宝宝** | 支持多个孩子，随时切换 |
| **家人共享** | 通过 iCloud 邀请伴侣 / 长辈 / 保姆（不同 Apple ID），所有人实时看到同一份数据；可设只读或可编辑；每条记录显示记录人 |
| **iCloud 同步与备份** | 数据自动保存到你的私有 iCloud；换新手机后登录同一 Apple ID 即可自动恢复 |
| **导出 / 导入 / 迁移** | 导出完整备份（JSON），通过隔空投送、"文件"或 iCloud 云盘发到另一部手机再导入（不同 Apple ID 也可以）；导出 CSV 表格给医生或用 Excel 查看 |
| **Live Activity** | 睡眠、亲喂、吸奶、活动计时会显示在锁屏和灵动岛上，并可直接 **停止**、**换边**、**暂停 / 继续** |
| **小组件** | 主屏幕小 / 中 / 大三种尺寸 + 锁屏小组件：距上次喂奶 / 换尿布多久、睡着或醒着多久、下次小睡时间、今日统计；中 / 大尺寸带 **一键开始睡眠、开始亲喂、记录尿布** 按钮 |
| **提醒** | 喂奶间隔、换尿布间隔、小睡最佳时间、用药 |
| **摇摇支持者（订阅）** | 月付 $0.99（约 ¥1）/ 年付 $9.99，支持家人共享；解锁 4 款替换图标、5 种主题配色和支持者徽章。**所有记录、同步、共享、小组件功能对所有人免费** |
| **打赏（Tip Jar）** | 三档自愿打赏（咖啡 / 蛋糕 / 午餐），通过苹果 App 内购买支付，带感谢页；不解锁任何功能，所有功能对所有人免费 |
| **Siri / 快捷指令** | "用摇摇开始睡眠""宝宝醒了""开始亲喂""记录尿布" |

---

## 运行要求

- macOS + **Xcode 16** 或更新版本
- **iOS 17.0+** 真机（iCloud、共享和 Live Activity 需要真机测试；模拟器可以跑基础功能）
- 付费的 **Apple Developer Program** 账号（iCloud / CloudKit 和 App Group 需要）

---

## 第一次配置（约 10 分钟）

### 1. 设置你的 Team 和 Bundle ID

编辑 `Config/Shared.xcconfig`：

```
DEVELOPMENT_TEAM = ABCDE12345          // 你的 Team ID（developer.apple.com → Membership）
APP_BUNDLE_ID = com.yourname.Lullo
```

App Group（`group.<Bundle ID>`）和 iCloud 容器（`iCloud.<Bundle ID>`）会根据 Bundle ID 自动生成，一般不用改。

### 2. 打开工程

```bash
open Lullo.xcodeproj
```

> 工程文件由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 根据 `project.yml` 生成，并且已经提交到仓库，所以不需要安装 XcodeGen 也能直接打开。
> 如果之后修改了 `project.yml`，或者新增 / 删除了源文件，执行 `brew install xcodegen && xcodegen generate` 重新生成即可。

### 3. 确认 Capabilities

在 Xcode 中选择 **Lullo** target → **Signing & Capabilities**，确认以下几项都在，并且没有红色报错（自动签名会在你的开发者账号下注册这些标识符）：

- **iCloud**：勾选 CloudKit，容器为 `iCloud.<你的 Bundle ID>`
- **App Groups**：`group.<你的 Bundle ID>`
- **Push Notifications**（CloudKit 静默推送需要）
- **Background Modes** → Remote notifications

**LulloWidgets** target 需要同一个 App Group。

如果 iCloud 容器显示红色，点刷新按钮，或者在 Capabilities 里取消勾选后再重新勾选。

### 4. 运行

选择你的 iPhone 运行。第一次添加宝宝后，数据就会开始同步到 iCloud。

### 5. 订阅与打赏（App 内购买）

在模拟器里**不需要任何配置**：scheme 已经关联了 `Config/Lullo.storekit`，运行后进入 **更多 → 支持摇摇** 就能测试订阅和打赏（Xcode → Debug → StoreKit → Manage Transactions 可以查看和退款测试交易）。

上架前，**订阅**：在 App Store Connect → 你的 App → **订阅** 中创建订阅组 "Lullo Supporter"，组内放两个同级的自动续期订阅，并开启 **家人共享**：

| 产品 ID | 周期 | 建议价格 |
|---|---|---|
| `lullo.supporter.monthly` | 1 个月 | $0.99 / ¥1 |
| `lullo.supporter.yearly` | 1 年 | $9.99 / ¥10 |

订阅需要隐私政策链接。官网在 [junyuanz1/lullo-site](https://github.com/junyuanz1/lullo-site)（GitHub Pages），App Store Connect 里填写：

| 字段 | 网址 |
|---|---|
| 营销网址 | https://junyuanz1.github.io/lullo-site/ |
| 隐私政策网址 | https://junyuanz1.github.io/lullo-site/privacy/ |
| 技术支持网址 | https://junyuanz1.github.io/lullo-site/support/ |

App 内的隐私政策链接来自 `Config/Shared.xcconfig` 里的 `PRIVACY_POLICY_URL`；使用条款链接用的是苹果标准 EULA。

**打赏**：在 **App 内购买项目** 中创建 3 个 **消耗型** 项目，产品 ID 必须和代码一致：

| 产品 ID | 建议价格 | 英文名 | 中文名 |
|---|---|---|---|
| `lullo.tip.small` | $0.99 / ¥6 | A cup of coffee | 请喝一杯咖啡 |
| `lullo.tip.medium` | $2.99 / ¥18 | A slice of cake | 请吃一块蛋糕 |
| `lullo.tip.large` | $6.99 / ¥45 | A nice lunch | 请吃一顿午餐 |

第一次提交审核时，需要把这些订阅和内购项目和 App 版本一起提交。

### 6. 上架 / TestFlight 前：部署 CloudKit Schema

开发环境（Debug）下，CloudKit 会自动创建数据结构。但 **TestFlight 和 App Store 使用生产环境**，所以发布前必须部署：

1. Xcode → Product → Scheme → Edit Scheme → Run → Arguments，添加启动参数 `-InitializeCloudKitSchema`，运行一次（只在 Debug 构建中生效），然后删掉这个参数
2. 打开 [CloudKit Console](https://icloud.developer.apple.com/) → 选择你的容器 → **Deploy Schema Changes** 到 Production

> 不部署的话，TestFlight 版本的同步和家人共享不会工作。

---

## 使用说明

### 家人共享
**更多 → 家人与看护人 → 共享 [宝宝名字]**，通过信息、邮件等方式发送邀请。对方需要：
1. 在 iPhone 上安装这个 App（开发阶段可以用 TestFlight 分发）
2. 点开邀请链接并接受

之后，被共享的宝宝会出现在对方的 App 中，双方实时同步。在同一页面可以查看成员、修改权限或停止共享。

### 换新手机
- **同一个 Apple ID**：在新手机上登录 iCloud 并安装 App，数据会自动下载。
- **不同 Apple ID / 不想用 iCloud**：在旧手机 **更多 → 备份与迁移 → 导出备份文件**，隔空投送到新手机，在新手机上 **导入备份文件**。导入会按记录 ID 合并，不会产生重复记录。

### Live Activity 与小组件
- 开始任何计时后，锁屏和灵动岛会自动显示（可以在 **更多 → 偏好设置 → 实时活动** 中关闭）。
- 长按主屏幕 → 添加小组件 → 摇摇。如果有多个宝宝，长按小组件 → 编辑小组件，选择要显示哪个宝宝。

---

## 项目结构

```
project.yml                 XcodeGen 工程定义
Config/Shared.xcconfig      Team ID、Bundle ID、App Group、iCloud 容器
Config/Lullo.storekit       本地 StoreKit 测试配置（打赏）
Packages/BabyCore/          纯 Swift 核心逻辑（无 UI 依赖，有单元测试）
  ├─ Records.swift          BabyRecord / EventRecord 值类型
  ├─ NursingTimer.swift     左右侧亲喂计时逻辑
  ├─ Statistics.swift       每日汇总、24 小时作息图数据、平均值
  ├─ NapPredictor.swift     SweetSpot 小睡预测
  ├─ GrowthStandards*.swift WHO LMS 数据与百分位计算
  ├─ Backup.swift           备份文件格式与合并策略
  ├─ CSVExporter.swift      CSV 导出
  └─ WidgetSnapshot.swift   小组件 / Live Activity 用的数据快照
App/
  ├─ Persistence/           Core Data 模型（代码定义）+ NSPersistentCloudKitContainer（私有库 + 共享库）
  ├─ Services/              TrackerStore（所有写操作的入口）、Live Activity、提醒、备份、同步状态
  ├─ Intents/               Siri / 快捷指令
  └─ Views/                 首页、记录、趋势、生长、设置、编辑器
Shared/                     App 与小组件共用：App Group、显示名称、格式化、Live Activity 属性、App Intents、本地化
Widgets/                    主屏幕 / 锁屏小组件、Live Activity 界面
Tests/LulloTests/   App 层单元测试
.github/workflows/ci.yml    CI
```

### 架构要点
- **Core Data + NSPersistentCloudKitContainer**，有两个 store：`private.sqlite`（自己的数据）和 `shared.sqlite`（别人共享给你的数据）。共享以宝宝为单位：宝宝和它的所有记录一起放进一个 CloudKit share zone。
- 所有写操作都经过 `TrackerStore`。每次修改后会重新计算 `WidgetSnapshot`，写入 App Group，然后由它刷新小组件、Live Activity 和提醒通知。
- 小组件和 Live Activity 上的按钮使用 `LiveActivityIntent`，系统会在 **App 进程** 中执行这些操作，所以数据库写入和 iCloud 同步都只发生在 App 里，小组件本身只读快照。

### 测试

| 测试 | 内容 |
|---|---|
| `Packages/BabyCore/Tests` | 核心逻辑：亲喂计时、每日统计、24 小时作息、WHO 百分位（与官方数值核对）、小睡预测、备份格式与合并、CSV、Widget 快照、单位换算 |
| `Tests/LulloTests` | App 层（内存 Core Data）：TrackerStore 计时器 / 亲喂换边 / 保存 / 删除级联、备份导出→导入往返和去重、Core Data 模型的 CloudKit 兼容性、中英文翻译完整性 |

```bash
cd Packages/BabyCore && swift test     # 核心逻辑，macOS / Linux 都能跑
```

在 Xcode 中按 ⌘U 会运行全部测试。

### CI

`.github/workflows/ci.yml` 会在每次 push 到 `main` 和每个 PR 时运行：
1. **BabyCore unit tests**：`swift test`
2. **Build and test iOS app**：用 XcodeGen 生成工程，在 iOS 模拟器上不签名编译 app 和小组件，并运行全部测试

### 本地化
界面文字以英文作为 key，中文翻译在 `Shared/Resources/zh-Hans.lproj/Localizable.strings`。Siri 短语的翻译在 `App/Resources/zh-Hans.lproj/AppShortcuts.strings`。

---

## 隐私

- `PRIVACY.md`：中英文隐私政策，已发布在 https://junyuanz1.github.io/lullo-site/privacy/ 。修改时请同步更新网站。
- `App/PrivacyInfo.xcprivacy`、`Widgets/PrivacyInfo.xcprivacy`：苹果要求的隐私清单。声明 App 不追踪用户、不收集数据，只因为保存设置而使用 UserDefaults。
- 在 App Store Connect 的 **App 隐私** 问卷中，可以选择"不收集数据"。

## 许可证

本项目为**专有软件，保留所有权利**，详见 [`LICENSE`](LICENSE)。"Lullo"、"摇摇"及其图标为版权所有者的商标。第三方数据和工具的声明见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

## 免责声明

睡眠预测、生长百分位、发烧和便便颜色提示等仅供参考，不构成医疗建议。有任何健康问题请咨询儿科医生。

生长曲线数据来自 [WHO Child Growth Standards](https://www.who.int/tools/child-growth-standards)（经 CDC 发布的 LMS 参数）。

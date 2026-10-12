# 上架清单 / Release checklist

上架 App Store 要做的事都在这里。完成一项就把 `[ ]` 改成 `[x]` 并提交，这样进度就记录在 Git 里。

这个文件夹和 `fastlane/` 都不在 Xcode 工程里，不会被打包进 App。CI 里的 `scripts/check_store_metadata.py` 会检查这一点。

## 东西都在哪

| 内容 | 位置 |
|---|---|
| App Store 文案（9 种语言：名称、副标题、描述、关键词、推广文本、网址） | `fastlane/metadata/<语言>/` |
| 给审核员的说明 | `fastlane/metadata/review_information/notes.txt` |
| 上架截图 | 运行 `bundle exec fastlane screenshots`，或 GitHub Actions → **App Store screenshots** |
| 隐私政策 | 网站 `https://tinytide.app/privacy/`（仓库 tinytide-site），App 仓库里的 `PRIVACY.md` 与它保持一致 |
| 帮助页 | `https://tinytide.app/support/` |
| 上传文案 / 截图 | `bundle exec fastlane upload_metadata` / `upload_screenshots`，见 `fastlane/README.md` |

## 一次性设置（Apple 后台）

- [x] Apple Developer Program 账号，Team ID 已填进 `Config/Shared.xcconfig`
- [x] App ID `app.tinytide.ios`，iCloud 容器 `iCloud.app.tinytide.ios`，App Group `group.app.tinytide.ios`
- [x] 网站与邮箱：tinytide.app、support@tinytide.app
- [ ] **协议、税务和银行业务**：签署“付费 App 协议”，填写银行和税务信息（不签就不能上架内购，审核需要几天，越早做越好）
- [ ] **CloudKit 正式环境**：CloudKit Console → `iCloud.app.tinytide.ios` → Deploy Schema Changes。部署前先在开发版里把每种记录（宝宝、各种事件、共享）都创建一次。**TestFlight 和正式版用的是正式环境，没部署的话同步和共享都会失败**
- [x] **App Store Connect 里新建 App**：平台 iOS，名称 `Tinytide: Baby Tracker`，主要语言 English (U.S.)，Bundle ID `app.tinytide.ios`，SKU 随意（例如 `tinytide-ios`）
- [x] **App Store Connect API 密钥**（给 fastlane 用）：用户和访问 → 集成 → App Store Connect API，权限选 App 管理，保存为 `fastlane/asc_api_key.json`（已被 git 忽略）
- [x] **欧盟交易者身份**（DSA）：App 信息 → 交易者身份。不声明就不能在欧盟上架；个人开发者的联系方式会公开显示

## App Store Connect 里要填的

- [x] **文案**：`bundle exec fastlane upload_metadata` 上传 9 种语言的文案和审核说明
- [x] **截图**：`bundle exec fastlane upload_screenshots`（6.9 英寸，9 种语言）
- [x] **版权**：`fastlane/metadata/copyright.txt` 目前写的是 `2026 Tinytide`，可以改成你的法定姓名或公司名
- [x] **类别**：主要“健康健美”，次要“生活”（`primary_category.txt` / `secondary_category.txt`，上传文案时一起设置）
- [x] **年龄分级**：问卷全部选“无”，结果应为 4+。不要勾选“儿童”类别：这个 App 是给家长用的
- [x] **App 隐私**：选“我们不会从此 App 中收集数据”（没有分析、广告、第三方 SDK，数据只在设备和用户自己的 iCloud）
- [x] **价格**：免费
- [x] **审核联系人**：姓名和电话在 App Store Connect 里填（不存在仓库里）；邮箱用 support@tinytide.app
- [ ] **内购项目**（每个都要填价格、9 种语言的显示名称和描述，并上传一张审核截图）：

  | 产品 ID | 类型 | 价格 |
  |---|---|---|
  | `tinytide.tip.small` | 消耗型 | $0.99 |
  | `tinytide.tip.medium` | 消耗型 | $2.99 |
  | `tinytide.tip.large` | 消耗型 | $6.99 |
  | `tinytide.supporter.monthly` | 自动续期订阅（订阅组 “Tinytide Supporter”） | $0.99 / 月 |
  | `tinytide.supporter.yearly` | 自动续期订阅（同一订阅组） | $9.99 / 年 |

  价格以 `Config/Tinytide.storekit` 为准；如果改了价格，两边一起改。第一次提交时，内购要和 App 版本一起提交审核。

## 测试

- [ ] **真机**：一键计时和停止（含锁屏、灵动岛）、各种记录、小组件、Siri（中英文）、倒计时闹钟（首次授权）、自动备份和恢复、导出导入、深色模式和最大字号
- [ ] **TestFlight 内部测试**（先做完 CloudKit 正式环境部署）：
  - [ ] 两个 Apple ID 之间邀请共享，双方记录、实时同步、只读权限、停止共享
  - [ ] 换一台设备登录同一个 Apple ID，数据自动下载
- [ ] **沙盒购买**：三档打赏、月付和年付订阅、恢复购买、订阅到期后主题和图标恢复默认
- [ ] **截图对比 CI 是绿的**，App Store 截图里没有奇怪的数据或文字截断

## 每次发版

- [ ] `Config/Shared.xcconfig`：`MARKETING_VERSION`（例如 1.0.1）和 `CURRENT_PROJECT_VERSION`（每次上传都要 +1）
- [ ] 从 1.1 起，在 `fastlane/metadata/<语言>/release_notes.txt` 写“新功能”，9 种语言
- [ ] 界面有变化就重新生成截图并上传
- [ ] Xcode → Product → Archive → Distribute App → App Store Connect
- [ ] 隐私相关的功能有变化时，同时更新网站隐私政策和 `PRIVACY.md`
- [ ] 提交审核；第一次提交时把内购项目一起勾上

## 审核常见问题（提前准备）

- **4.2 功能过少 / 2.1 无法测试**：审核说明里写清楚了不需要账号、怎么试每个功能
- **3.1.2 订阅**：订阅页（SubscriptionStoreView）显示价格、续期说明、恢复购买、使用条款和隐私政策；描述末尾也有这两个链接
- **1.4.1 医疗**：描述和帮助页都写了“不是医疗器械，健康问题请咨询儿科医生”
- **5.1.1 隐私**：不收集数据，隐私政策写明了 iCloud、共享和本机自动备份

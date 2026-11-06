# Handscroll — App Store submission pack

Prepared 2026-11-05. Everything here is copy-paste ready; the only steps that need your Apple account are marked **[你]**. The Xcode upload path is what you chose — the repo is otherwise ready.

- App: **Handscroll**
- Bundle ID: `com.weiniverse.handscroll`
- Version: **1.0 (build 1)**
- Repo: <https://github.com/weirui828/handscroll>
- Privacy: <https://weiniverse.com/handscroll/privacy/>
- Support: <https://weiniverse.com/handscroll/support/>

---

## 0. Before you start

- [ ] **[你]** 付费 Apple Developer Program 账号可用（个人或公司）。
- [ ] **[你]** Xcode › Settings › Accounts 登录**付费账号**。目前 Xcode 里只有免费的 `Wei Rui (Personal Team)`，免费团队不能上传 App Store；Archive 时选付费团队即可自动生成发布证书。
- [ ] **[你]** 注册 App ID：developer.apple.com › Certificates, Identifiers & Profiles › Identifiers › **+** › App IDs › App，Bundle ID 填 `com.weiniverse.handscroll`。
- [ ] `demo.jpg` 的授权：这张演示照片会出现在商店截图里（也打进 bundle）。若不是你自己的照片，换成自己的照片后重新截图（见 §4）。
- [ ] 名称 `Handscroll` 在 ASC 建 App 时若被占用，见 §7 备选名。

## 1. 构建并上传（Xcode）

```sh
cd ~/dev/seamless
git pull
xcodegen generate            # 重新生成 Seamless.xcodeproj
open Seamless.xcodeproj
```

1. 选中 `Seamless` target → **Signing & Capabilities** → Team 选付费团队；确认 Bundle Identifier 是 `com.weiniverse.handscroll`、勾选 *Automatically manage signing*。
2. 顶部 destination 选 **Any iOS Device (arm64)**，菜单 **Product › Archive**。
3. Archive 完成后 Organizer 自动弹出 → **Distribute App › App Store Connect › Upload**，一路默认（自动签名）直到 Upload。
4. 等 10–30 分钟，App Store Connect › TestFlight 里能看到 build `1.0 (1)` 处理完成。

> 以后每次改版本号：改 `project.yml` 里的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`，`xcodegen generate`，再 Archive。
>
> 也可以用命令行打包（可选，签名沿用 Xcode 账号）：
>
> ```sh
> xcodebuild -project Seamless.xcodeproj -scheme Seamless -configuration Release \
>   -destination 'generic/platform=iOS' -archivePath build/Handscroll.xcarchive archive \
>   -allowProvisioningUpdates
> xcodebuild -exportArchive -archivePath build/Handscroll.xcarchive \
>   -exportOptionsPlist appstore/ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
> xcrun altool --upload-app -f build/export/Seamless.ipa --type ios -u <apple-id> -p <app-specific-password>
> ```
>
> 若 `-exportArchive` 报 `method` 无效，把 `appstore/ExportOptions.plist` 里的 `app-store-connect` 改成 `app-store`（旧版 Xcode 的写法）。Release 配置已在本地验证过能编译通过，签名交给 Xcode GUI 最稳。

## 2. 建 App 记录 **[你]**

<https://appstoreconnect.apple.com> › My Apps › **+** › New App：

| 字段 | 值 |
| --- | --- |
| Platform | iOS |
| Name | `Handscroll` |
| Primary Language | English (U.S.) |
| Bundle ID | `com.weiniverse.handscroll` |
| SKU | `HANDSCROLL001` |
| User Access | Full Access |

## 3. 填表内容（直接复制）

### Name（30 字符内）

```
Handscroll
```

### Subtitle（30 字符内）

```
Split wide photos into slides
```

### Promotional Text（170 字符内，可随时改）

```
One wide photo, a few good ways to post it. Split it into slides, fit it to a tall frame, or turn it into a slow pan — all on device, no account, no analytics.
```

### Description

```
One wide photo. Split it into slides, fit it to a tall frame, crop it for the feed, or turn it into a slow pan video — all on your iPhone.

Handscroll is a small, quiet photo tool for people who post one wide photo and want it to look right.

SPLIT
Cut one wide photo into 2–5 slides that line up exactly across a post.

FIT
Put the whole photo inside a tall 4:5 frame. Fill the empty space with a blur, a solid colour, black, or white.

CROP
A tall crop with the composition you choose.

DRIFT
A slow pan across the photo, exported as an 8-second video.

BATCH
Apply the same steps to up to 10 photos, then export them all at once.

HELP
A built-in manual — Basics, Split, Fit, Crop, Drift, Batch, Settings — that explains every control.

PRIVATE BY DESIGN
Everything is processed on your device. No account, no sign-in, no analytics, no advertising, no third-party SDKs, and no network access. Photos are reached only through the system picker; finished files are saved to your photo library or shared by you.

Fine details
• 11 hand-tuned accent colours (Pantone-calibrated), plus a custom colour
• A 4:5 warning when a frame is taller than most apps and scheduling tools accept
• Works offline
• Portrait and landscape

Made for iOS 17 and later.
```

### Keywords（100 字符内，逗号分隔，不要有空格）

```
wide photo,split,crop,carousel,slides,pan,panorama,aspect ratio,4:5,photo editor
```

### URLs

| 字段 | 值 |
| --- | --- |
| Support URL | `https://weiniverse.com/handscroll/support/` |
| Privacy Policy URL | `https://weiniverse.com/handscroll/privacy/` |
| Marketing URL（可选） | `https://weiniverse.com/handscroll/` |

### Category

Primary: **Photo & Video**（Secondary 不填）

### Age Rating

问卷全部选 **None / No** → 结果 **4+**。

### Price

**Free**。可用区：默认全部；如果要限定，就在 Pricing and Availability 里改。

### App Privacy

- *Do you or third-party partners collect data from this app?* → **No**
- Data types：**None**（页面显示 **Data Not Collected**）
- Tracking：**No**
- 说明（给审核看的逻辑）：无账号、无网络、无第三方 SDK；本机偏好（主题色、提示已读）存在 `UserDefaults`，不离开设备。

### Export Compliance

`project.yml` 已加 `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`，Info.plist 会带上该键，上传后 ASC 一般不再提问。若仍出现 *Does your app use encryption?* → **No**。

### Copyright

```
2026 Wei Rui
```

### What's New in This Version（1.0）

```
First release.
```

### App Review Information

- Sign-in required：**No**（不需要账号）
- Contact：填你的邮箱和电话（审核员可能联系）
- Notes：

```
Handscroll is a local, offline photo tool. There is no account, no login, and no network access, so no demo credentials are needed.

To review:
1. Launch the app and tap "Select a Photo". Pick any wide photo (a panorama or a 16:9 photo works best).
2. The four modes are Split, Fit, Crop and Drift.
3. Split cuts the photo into 2–5 slides; Fit and Crop place it in a tall 4:5 frame; Drift exports an 8-second pan video.
4. The download button saves to Photos; the share button opens the system share sheet.
5. The "?" button opens the built-in manual.

Photo selection uses the system photo picker, which needs no photo library permission. The app requests add-only Photos access only when saving finished files; it never reads your library. The app collects no data and contains no third-party SDKs.
```

### Screenshots

上传 `appstore/screenshots/` 里的 6 张到 **6.9" 显示** 槽位（1320 × 2868，顺序就是文件名顺序）：

| 顺序 | 文件 | 画面 |
| --- | --- | --- |
| 1 | `01-split.png` | Split，3 张滑片 |
| 2 | `02-drift.png` | Drift，播放态 + Pan/Zoom/Length |
| 3 | `03-fit.png` | Fit，4:5 + Blur 填充 |
| 4 | `04-crop.png` | Crop，4:5 |
| 5 | `05-help.png` | Help › Basics（内置手册） |
| 6 | `06-settings.png` | Help › Settings（11 色 + Custom） |

App 图标已经在 asset catalog 里（1024 × 1024、无 alpha），不需要单独上传。6.5"/5.5" 槽位可留空。

### Version Release

先选 **Manually release this version**，审核通过后自己按发布。

## 4. 重新截图（换 demo 照片 / 想改文案时）

```sh
cd ~/dev/seamless
xcodegen generate
xcodebuild -project Seamless.xcodeproj -scheme Seamless -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -derivedDataPath .build/dd build

xcrun simctl boot "iPhone 18 Pro Max" 2>/dev/null
xcrun simctl install booted .build/dd/Build/Products/Debug-iphonesimulator/Seamless.app
xcrun simctl status_bar booted override --time "9:41" --batteryState charged \
  --batteryLevel 100 --wifiBars 3 --cellularBars 4

shot () { # name, args…
  xcrun simctl terminate booted com.weiniverse.handscroll 2>/dev/null
  xcrun simctl launch booted com.weiniverse.handscroll "${@:2}" >/dev/null
  sleep 5
  xcrun simctl io booted screenshot "appstore/screenshots/$1.png" 2>/dev/null
}

shot 01-split    -demoPhoto -demoClean -demoMode Split -demoSlides 3 -demoShape 4:5
shot 02-drift    -demoPhoto -demoClean -demoMode Drift
shot 03-fit      -demoPhoto -demoClean -demoMode Fit  -demoShape 4:5
shot 04-crop     -demoPhoto -demoClean -demoMode Crop -demoShape 4:5
shot 05-help     -demoPhoto -demoClean -demoBasics
shot 06-settings -demoPhoto -demoClean -demoSettings -demoColor
```

拍照前把 `Seamless/demo.jpg` 换成你自己的照片即可（同一尺寸，宽图最佳）。

## 5. 提交审核 checklist

- [ ] Archive 成功，上传成功，TestFlight 里能看到 build 1
- [ ] 真机装一个 TestFlight 版本跑一遍：选照片 → Split 导出 → Fit/Crop 导出 → Drift 导出 → Batch
- [ ] 隐私政策 / 支持 URL 能打开（改名后确认是 `/handscroll/` 路径）
- [ ] 6.9" 截图上传完整，顺序对
- [ ] App Privacy 填 **Data Not Collected**
- [ ] Export compliance = No
- [ ] 年龄分级 4+
- [ ] 审核备注已粘贴
- [ ] 点 **Submit for Review**

审核一般 24–48 小时；第一次提交建议选 Manual release，通过后自己控制上线时间。

## 6. 已知的坑

| 坑 | 处理 |
| --- | --- |
| 免费账号不能上传 | 当前 Xcode 只有 Personal Team；需要登录付费账号并在 Archive 时选它 |
| 名称被占 | 备选：`Handscroll — Split Photos`、`Handscroll: Wide Photo`（副标题另算） |
| 截图路径 | App Store 要求 URL 直接能打开；改名后是 `weiniverse.com/handscroll/...`，不要再引用旧的 `/seamless/` |
| 相册权限 | 选照片走系统 picker，不需要相册权限；只有保存结果时请求“添加到相册”（Info.plist 里只有 `NSPhotoLibraryAddUsageDescription` 一段） |
| 4:5 警告 | 文案已中性化，不提第三方平台 |
| 演示照片版权 | 截图会展示 `demo.jpg`，确认你有权使用，否则换图 |

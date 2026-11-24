# 踩过的坑

每条写明在哪看到的：**模拟器**（iPhone 17，iOS 26.0，Xcode 27.2）、**本机**（macOS 上的 `swift test`）、或**推断**。真机上还没有验过任何一条。

## 签名

- **命令行签不了名：`No Accounts`**（本机，2026-11-25）。`xcodebuild -allowProvisioningUpdates -destination generic/platform=iOS` 报 `No Accounts: Add a new account in Accounts settings` 和 `No profiles for 'app.keepessence.ios' were found`。原因是 Xcode 里没有登录 Apple ID，新包名的描述文件没人去建。App Group 和钥匙串共享这两项能力有没有问题，还没走到那一步，不知道。
- 不签名的真机构建（加 `CODE_SIGNING_ALLOWED=NO`）是过的，所以代码本身能编给真机。
- 这台电脑上原型（`today.yan.allkeep`）的描述文件有效期是一年，带 App Group 和 `52Z7K6JY2S.*` 的钥匙串组。免费的个人团队只给 7 天，所以这个团队多半不是免费的那种（推断）。

## 凭据放在哪

- 凭据放钥匙串，访问组是 `$(AppIdentifierPrefix)app.keepessence.ios.shared`，App 和分享扩展都能读。组名带团队前缀，代码里拿不到前缀，所以写进两个目标的 Info.plist（`KEKeychainGroup`），运行时读出来。
- 模拟器上钥匙串共享是通的：分享扩展读到了 App 存的凭据（模拟器）。
- 钥匙串拒绝这个组时（没签名的构建会这样），退到 App Group 目录里的一个文件，不进备份。用的是哪一处记在 App Group 的设置里（`credentialPlace`）。这条退路只在模拟器不签名构建时可能用到；真机上会不会用到，没验。

## 分享扩展

- **面板的大小不归扩展管**（模拟器）。系统给分享扩展的是一整页的面板。在扩展里设 `preferredContentSize` 和 `sheetPresentationController.detents` 都不起作用。所以现在是：一整页的面板，上面一张小卡片写那一句话，两三秒后自己关。想要真正的小面板，要么换成 Action 扩展，要么等系统给接口。
- **扩展的语言跟系统走，不跟 App 的启动参数走**（模拟器）。界面测试给 App 传了 `-AppleLanguages (zh-Hans)`，扩展里出来的还是英文的 `Saved.`。
- 扩展的 `Bundle.main` 是扩展自己的包，不是 App 的。Info.plist 里的东西要两边各写一份。
- 没登录时扩展发不出去：内容先排进 App Group 的队列，说「排着队，接入后自动存入」，下面一行小字说先打开 App 登录。App 登录后自己发。这一条只有单元测试，没在模拟器里走过。

## 图片

- **ImageIO 写不了 WebP**（本机和模拟器，`CGImageDestinationCopyTypeIdentifiers()` 里没有 `org.webmproject.webp`，只能读）。所以图片编码成 JPEG。代码在运行时问系统：哪天系统能写 WebP 了，自动改用 WebP，不用改代码。
- 缩图用 `CGImageSourceCreateThumbnailAtIndex` 加 `kCGImageSourceThumbnailMaxPixelSize`：只缩不放，顺带按 EXIF 把方向转正。

## 文案

- `swift build` / `swift test` 不编译 String Catalog（`.xcstrings`），只是原样拷进包里，所以在 `swift test` 里 `L("…")` 返回的是键名。文案的测试直接读 `.xcstrings` 这个 JSON。用 `xcodebuild` 构建时是正常的。
- 包里的文案要跟系统语言走，App 的 Info.plist 里得列出支持的语言（`CFBundleLocalizations`），不然只出英文（推断，没有反过来验过）。

## 界面测试

- **给容器加 `accessibilityIdentifier`，里面所有元素的标识都会被盖掉**（模拟器）。之后 `app.staticTexts["内容概述"]` 就找不到了。先加 `.accessibilityElement(children: .contain)`，再加标识。
- iOS 26 的 Safari 没有单独的分享按钮了，在右下角的 More 菜单里（模拟器）。
- 模拟器里的界面测试能直接往电脑的磁盘上写截图，路径用 `TEST_RUNNER_` 前缀的环境变量传进去。

## 网络

- 调试版要连本机的 `http://127.0.0.1:…`，得在 Info.plist 里加 `NSAllowsLocalNetworking`。发布版不该有这一项，所以不写在 plist 里，由一个只在 Debug 配置下跑的构建脚本加进去（`project.yml` 的 `postBuildScripts`）。这个脚本要求关掉 `ENABLE_USER_SCRIPT_SANDBOXING`。
- `JSONDecoder` 的 `convertFromSnakeCase` 会把字典的键也一起改掉。`GET /v1/meta` 里的 `shared_rules` 是自由格式的对象，所以它用不带键转换的解码器另解。

## 这台电脑

- 这里的 `rm` 和 `cp` 是带确认的（`-i`），脚本里要写 `command rm -f`、`command cp -f`，不然会停在那里等输入。
- 提交前有 gitleaks 检查。像密码内容的识别测试里那些编的例子会被它拦下，逐行加了 `// gitleaks:allow`。

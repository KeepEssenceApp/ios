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

## 图片的告知（QA #87）

- **压缩的说明是分享界面底部的一行静态小字，不进存入的那一句，也不弹窗。** `share.image_note`（市场主稿 `14726f8` 的原话：「图片会先在手机上处理再存入，原图不上传。」），分享来的内容里有图片时才有（`ShareSheetView`，不在「问是不是密码」的时候出现）。这个入口核实过：iPhone 的分享菜单。App 里没有自己的选图入口，别的入口不写。
- **「太大」和「读不出来」只在代码确切知道的时候分开。** `ImagePrep.prepareDetailed`：图片数据打不开是 `unreadable`；每一档质量都还超过上限是 `tooLarge`；编码器自己失败是 `failed`，不说是前两种，用通用的「这张图片没能存入。」（不写原因）。`prepare` 还是原来的样子（只给图或 nil）。「太大」那句里的数字取的是核心给的 `asset_max_bytes`，和压缩用的同一个值，不另存常量。单位是 MiB：3,145,728 字节是 3 MiB，不是 3 MB（3 MB 是 3,000,000 字节），所以句子写「%lld MiB」，数字是 `ImageNote.mebibytes`，向下取整，保证「超过 N」对每一张被拒的图都成立（网页同样写 MiB）。
- **图片没存成，同时分享了链接或文字：存的是链接或文字，要说。** `ImageNote.instead` 把成功那句换成「图片没能存入，只存入了链接/文字。」；**在离线队列里等着的，只说手机本地知道的事**：「图片不会存入，排队的只有链接/文字。」（`queuedInstead`，`share.image_only_*_queued`）接在「排着队」那句后面。不说「只会存入」「会改存」：那是在替核心保证以后一定存入（Project 7213889512 / Marketing 7213864126）。不能把已经存入的那句接在队列那句后面：队列那句说「还没存入」，后面再说「存入了」是自相矛盾（QA 复验抓到的，原来的测试还把它当成对的）。`duplicate` 和失败仍然是核心原来的那句。
- **动图的「只保留了一帧」要三条同时成立才说：核心答了 `saved`、`image_stored == true`、源图是多帧。** queued、`duplicate`、失败、超出配额都不说，queued 也不改说另一句（Project 7213889512，取代 7212067866 的「stored 或 queued」）。超出配额时核心答的仍是 `status: saved`（`message_key: saved_image_skipped_quota`），条目存进去了、图片没有，所以只看 `.saved` 不够：`SaveOutcome.imageStored` 带着核心的 `image_stored`，`ImageNote.apply` 只在它为 `true` 时追加；`nil`（核心没说）也不追加，不去猜。
- **动图要看文件，不看类型。** `ImagePrep.isAnimation`：GIF 或 PNG，并且 `CGImageSourceGetCount` 大于 1。静态的 GIF 什么都没丢，不说。说「动图只保留了一帧」，不说「第一帧」：已知的只有留下了一张。

## 主题和 spec 的比较（#107）

- **这条比较在 CI 里从来没真正跑过**（本机，2026-11-28，QA 在 `33804c7` 上复现）。`testThemeMirrorsTheTokens` 找不到旁边的 `spec/design/tokens.css` 就 `XCTSkip`，而 `swift test` 在只有跳过、没有失败时退出 0；CI 只检出本仓，所以一直是绿的。旁边放上 spec 时，旧色表有 18 处不一致。现在 CI 把 spec 钉在 `SPEC_REF` 那一版检出到 `../spec`，并设 `KE_REQUIRE_SPEC=1`：缺 spec 是失败，不是跳过。CI 还单独复制一份只有 `KeepCore` 的目录、不放 spec，确认这时 `swift test` 失败，并且失败信息是「缺 spec」。
- `actions/checkout` 的 `path` 不能指到工作区外面（推断，它只接受工作区之内的路径），而测试按自己的源文件路径找 `../spec`，所以 CI 用 `git fetch --depth 1 <仓库> <完整 SHA>` 自己检出。按完整 SHA 取，不用缩写。
- 圆角不是一个基础常量。每个画圆角的组件在 `Theme.Surface` 里有自己的一项，视图只写 `Theme.shape(.card)` 这样的调用；`testEachComponentTakesItsOwnToken` 读视图源码，检查每个组件取的是自己的那一项，`testNoViewNamesARadiusOutsideTheTable` 检查没有视图自己写 `RoundedRectangle(`、`Capsule(` 或 `Theme.Radius.base` 之类（弹层的 `presentationCornerRadius` 只许用 `Theme.Radius.sheet`）。新加一个有圆角的组件，要在 `Surface` 和测试的两张表里各加一项。
- 按钮、选项和状态标记是胶囊（`Capsule`，对应 `--ke-radius-control: 999px`）；`RoundedRectangle(cornerRadius: 999)` 在 44 pt 高的控件上看起来一样，但表里写的是 `Capsule`，测试也按 `Capsule` 比较。
- 还没做：spec 写「手指按的东西至少 44 高」（`--ke-control-height`）。这次只改了圆角和色表，按钮的高度没动（也没有量过现在是多少）。验证：只有 macOS 上的 `swift test` 和不启动模拟器的 `xcodebuild build`；界面没有在模拟器或真机上看过。

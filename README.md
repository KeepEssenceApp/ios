# KeepEssence iOS

KeepEssence 的 iPhone 原生 App 和分享扩展。

- **App**：读的界面。四个入口，顺序固定：今天、每日摘要、笔记、助手设置。
- **分享扩展**：在别的应用里点分享，选 KeepEssence，一个动作存入，不跳到 App。

接口只照 [`contract/openapi.yaml`](contract/openapi.yaml) 做（从 spec 仓库同步来的副本，不在这里改）。

## 目录

| 目录 | 内容 |
|---|---|
| `KeepCore/` | 本地 Swift 包，App 和分享扩展共用：接口客户端、数据类型、凭据存放、主题、文案、像密码内容的识别、离线队列、图片处理 |
| `App/` | App 的界面（SwiftUI） |
| `ShareExtension/` | 分享扩展 |
| `Shared/` | 两个目标共用的图（logo） |
| `UITests/` | 界面测试 |
| `fake/server.mjs` | 测试用的假核心，只在本机跑 |
| `scripts/` | 生成文案表和共用规则副本的脚本 |
| `project.yml` | 工程定义。`KeepEssence.xcodeproj` 由它生成 |

## 需要什么

Xcode 27、[xcodegen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。跑测试还要 Node 22。没有第三方依赖。

## 生成工程

```
xcodegen generate
```

改了 `project.yml`、加了或删了源文件之后都要再跑一遍。

## 构建和运行（模拟器）

```
xcodebuild build -project KeepEssence.xcodeproj -scheme KeepEssence \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' -derivedDataPath build/dd
```

或者用 Xcode 打开 `KeepEssence.xcodeproj`，选一个模拟器，点运行。

服务器地址缺省是 `https://keepessence.app`。登录页最下面有一行「服务器」，点开可以改，自己部署的人和本机测试用它。调试版允许连本机的 `http://` 地址，例如本机的核心 `http://127.0.0.1:8801`；发布版只走 HTTPS。

## 测试

单元测试（不需要模拟器）：

```
cd KeepCore && swift test
```

界面测试对着假核心跑。先起假核心（端口 8795，验证码永远是 `123456`，内容都是编的）：

```
node fake/server.mjs &
curl -X POST http://127.0.0.1:8795/__reset
xcodebuild test -project KeepEssence.xcodeproj -scheme KeepEssence \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' -derivedDataPath build/dd
```

这一条会把单元测试在模拟器里再跑一遍，加上三个界面测试：登录 → 今天 → 做动作 → 读每日摘要；批准一个短码；从 Safari 分享存入。

要截图、换语言，加环境变量（前缀 `TEST_RUNNER_`）：

```
TEST_RUNNER_KE_LANG=en TEST_RUNNER_KE_SCREENSHOT_DIR=$PWD/build/screens xcodebuild test …
```

深色的截图先跑 `xcrun simctl ui booted appearance dark`。`docs/screens/` 里有一份浅色中文和一份深色英文的截图。

提交前另有两个检查：

```
python3 scripts/strings.py --check       # 文案表齐全，没有词表里不用的词
ruby scripts/gen-shared-rules.rb --check # 共用规则的副本和契约一致
```

## 装到自己的手机上

1. 在 Xcode 的 Settings › Accounts 里登录你的 Apple ID。没有登录的话，命令行会报 `No Accounts`，签不了名。
2. 把 `project.yml` 里的 `DEVELOPMENT_TEAM` 换成你的团队编号，包名（`app.keepessence.ios`）换成你自己的，再 `xcodegen generate`。App Group 和钥匙串共享组跟着包名一起改（`project.yml` 和 `KeepCore/Sources/KeepCore/Store.swift` 里的 `group.app.keepessence.ios`）。
3. 手机用线连上电脑，解锁，点「信任」。
4. 构建并安装：

```
xcodebuild build -project KeepEssence.xcodeproj -scheme KeepEssence -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build/dd-device -allowProvisioningUpdates
xcrun devicectl list devices
xcrun devicectl device install app --device <设备编号> \
  build/dd-device/Build/Products/Debug-iphoneos/KeepEssence.app
```

免费的个人团队签的包 7 天后过期，要重装。第一次打开前，在手机的 设置 › 通用 › VPN 与设备管理 里信任开发者。

## 文案和颜色

- 文案只有一份：`scripts/strings.py` 里的表（中、英），生成 `KeepCore/Sources/KeepCore/Resources/Localizable.xcstrings`。词取自 spec 的 `design/terms.md`。语言跟系统走。
- 存入完的那一句话（已存入、之前存过了、排着队、没存入的原因、像密码的那一问）不在表里，由核心给；离线时用 `GET /v1/meta` 缓存下来的那一份。
- 颜色、圆角、字号只在 `KeepCore/Sources/KeepCore/Theme.swift`，和 spec 的 `design/tokens.css` 一一对应，有测试比对。

## 踩过的坑

见 [docs/pitfalls.md](docs/pitfalls.md)。

## 许可证

[AGPL-3.0](LICENSE)。

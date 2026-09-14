# FORK.md — 本仓库相对 upstream 的差异

本仓库跟踪 [vinzdg/codenotch](https://github.com/vinzdg/codenotch)（下称 **upstream**），
在其之上保留若干本地改动（下称 **fork**）。upstream 更新时本地用 rebase 跟上：

```sh
git fetch upstream                              # remote 是 SSH：本机 HTTPS:443 连不上
git branch -f backup/pre-rebase main            # 变基前留退路
git rebase --onto upstream/main <fork 基点> main   # 注意 --onto，理由见下
```

这份文档的唯一目的：**下次 rebase 时不必重新推导「这条改动为什么存在、还需不需要」。**
每节按同一格式写——为什么存在 / 涉及文件 / rebase 时怎么判断。

> 写入时的基线：`upstream/main = 6c28672`（1.11.0），本机 **macOS 14.3 + Xcode 15.4（Swift 5.10）**。
> 上游在 1.11.0 之前重写过全部历史（见「上游重写过历史」），旧 hash `abccf0e` 已不在 upstream。
> 每次 rebase 后请更新这一行和文中已过期的结论（见末尾「维护」）。

## 目录

- [两个约束推导出大部分差异](#两个约束推导出大部分差异)
- [上游重写过历史](#上游重写过历史)
- [rebase 流程与验证基线](#rebase-流程与验证基线)
- [1. macOS 14.3 部署目标与 SDK shim](#1-macos-143-部署目标与-sdk-shim)
- [2. ad-hoc 签名、DEV_RESIGN 与安装路径](#2-ad-hoc-签名dev_resign-与安装路径)
- [3. SwiftNIO 固定在 2.86.x](#3-swiftnio-固定在-286x)
- [4. Claude provider 不交给 UsageStore](#4-claude-provider-不交给-usagestore)
- [5. 关闭 Sparkle 自动更新](#5-关闭-sparkle-自动更新)
- [6. XyToken provider（fork 独有功能）](#6-xytoken-providerfork-独有功能)
- [7. 浏览器会话 provider 的登录提示修复](#7-浏览器会话-provider-的登录提示修复)
- [8. 玻璃样式测试在 macOS 26 以下跳过](#8-玻璃样式测试在-macos-26-以下跳过)
- [冲突热点（真实踩到过的）](#冲突热点真实踩到过的)
- [旧工具链编译错误的常见形态](#旧工具链编译错误的常见形态)
- [已被 upstream 吸收的本地改动](#已被-upstream-吸收的本地改动)
- [维护](#维护)

## 两个约束推导出大部分差异

1. **本机是 macOS 14.3 + Xcode 15.4**，而 upstream 的部署目标是 **15.0**，代码直接用 macOS 26
   才有的 API（`glassEffect`、`pointerStyle`）。符号在旧 SDK 里根本不存在，`#available(macOS 26)`
   也救不了——编译器连符号都看不到。
2. **本机钥匙串里没有签名证书**，所有构建都是 ad-hoc 签名。ad-hoc 签名每次构建都变，
   钥匙串的 "Always Allow" 授权留不住；且 ad-hoc + hardened runtime 会让 dyld 拒绝加载 Sparkle。

其余差异（XyToken、关闭自动更新、Claude provider 处理）是功能与偏好层面的**主动决策**，
不是约束逼出来的——rebase 时的判断方式也因此不同。

## 上游重写过历史

**1.10.0 → 1.11.0 的同步发现：upstream 重写了*全部*历史**——不是新增提交，而是重建了每一个
commit（作者邮箱从 `raphaelvinz.rv@gmail.com` 换成 `vincentpangwindra.vp@gmail.com`）。**两边的
commit hash 全不一样，本地旧基线与 upstream 之间没有共同祖先**（`git merge-base` 输出为空）。

- 旧基线 `abccf0e`（Merge PR #172）在新历史里对应 **`85fc743`**：message、日期、**tree 完全相同**。
- 后果：**`git rebase upstream/main` 会试图重放整个上游历史**（当时 333 个提交）。必须用下面的
  `--onto` 形式。
- 新历史里找旧基点对应 commit 的办法——比对 tree，不要比对 hash：

```sh
T=$(git rev-parse <旧基点>^{tree})
git rev-list upstream/main | while read c; do
  [ "$(git rev-parse $c^{tree})" = "$T" ] && git log -1 --oneline "$c"
done
```

同一棵树若有多个 commit，再对 message 和日期（本轮 `85fc743` 是唯一命中）。
**上游若再重写一次，重复这个映射即可，不要因为「没有共同祖先」而放弃 fork 的提交。**

## rebase 流程与验证基线

```sh
git fetch upstream                              # remote 是 SSH：本机 HTTPS:443 连不上
git branch -f backup/pre-rebase main            # 变基前留退路

# <fork 基点> = 上一次同步后的 upstream 顶点，即本仓库第一个 fork 提交的父亲。
# 传旧 hash 也可以：--onto 只把它当「到这里为止不算 fork」的范围边界，
# 不要求它是 upstream/main 的祖先——历史被重写后它本来就不是。
git rebase --onto upstream/main <fork 基点> main

# 解冲突 → 处理旧工具链编译错误 → 验证 → 提交一笔 fixup
make test                 # 期望 0 failures
Scripts/install-app.sh    # 装到 /Applications，并确认进程真的起来
```

1.10 → 1.11 那轮的实际命令：`git rebase --onto upstream/main abccf0e main`。

macOS 14.3 + Xcode 15.4 上的实测基线：**1531 个测试通过、4 个跳过**（1.10.0 时是 1387）。
测试总数会随 upstream 增长，**要盯的是「0 failures」，不是具体数字**。
1.11.0 那轮 `Scripts/install-app.sh` 装出 **1.11.0 (13)**、ad-hoc 签名，进程正常起来。

## 1. macOS 14.3 部署目标与 SDK shim

**为什么存在**：见上。upstream 的 `deploymentTarget` 是 15.0，本机要在 14.3 上跑。

**涉及文件**

- `project.yml`：`deploymentTarget: 14.3`、`projectFormat: xcode15_0`
- `Sources/Info.plist`：`LSMinimumSystemVersion` = 14.3
- `Sources/Compatibility/MacOS26Shims.swift`：`compatGlassEffect(in:interactive:)`、
  `compatPointerStyle(active:)`
- 调用点：`SettingsView`、`NotchRootView`、`MoveHandle`、`SettingsHandle`、`TooltipCard`、`UsageResetCard`

**rebase 时怎么判断**：本机还在 macOS 14 / Xcode 15.4 上就留着。shim 用
`#if swift(>=6.2)` 判断「这个工具链里有没有 macOS 26 SDK」（Xcode 26 = Swift 6.2，
Xcode 15.4 = 5.10）：新工具链编译真正的修饰符，旧工具链永远看不到那个符号。

每次 upstream 新增 `glassEffect` / `pointerStyle` 调用点，**编译期就会报错**，照既有形态改：
把 `#available(macOS 26.0, *)` 分支换成无条件的 `compat*` 调用（`.regular.interactive()`
对应 `interactive: true`）。**不要**在旧 SDK 里保留「`#available` 包着新符号」的写法。

排查命令：

```sh
grep -rn 'glassEffect\|pointerStyle' Sources/ | grep -v 'Compatibility/MacOS26Shims.swift'
```

1.11.0 复核：上游新增的 Kiro / MiniMax / 日进度环代码**没有**新的 `glassEffect` / `pointerStyle`
调用点（这两个词只出现在注释里），上面那条 grep 是干净的。

## 2. ad-hoc 签名、DEV_RESIGN 与安装路径

**为什么存在**：本机没有证书时，`make` 的三个签名分支是
Developer ID → Apple Development → **ad-hoc**（见 `Makefile` 顶部的 `HAS_DEVELOPER_ID` /
`DEV_IDENTITY` / `DEV_TEAM`）。ad-hoc 下 Xcode 会用**带 hardened runtime** 的 ad-hoc 签名给
Release 产物签名，而它旁边的 Sparkle 框架也是 ad-hoc、没有 Team ID，dyld 因此在启动时拒绝加载
（`Library not loaded: @rpath/Sparkle.framework`）。**这个失败在构建期、`codesign --verify` 期都看不出来，
只在启动那一刻出现。**

**处理方式**：`DEV_RESIGN` 在构建之后把 Sparkle 框架和 App **一次性重签**（`codesign --force --sign -`，
重签会去掉 runtime 标志，这正是能启动的原因）。`DEV_RESIGN` 以 $(1) 接收配置名：
`build` / `test` 传 Debug，`install` 传 Release。

**涉及文件**

- `Makefile`：`DEV_SIGN` 三段分支、`define DEV_RESIGN`、`install` 目标
- `Scripts/install-app.sh`：构建 Release → 复制到 `/Applications` → 回读版本 → **确认进程真的起来**

**rebase 时怎么判断**：upstream 也在这块加东西（例如 SwiftPM 解析相关逻辑），冲突时**两边都留**。
签名逻辑是 fork 独有的，不会与 upstream 合并成同一件事。

**装到 /Applications 后必须验证**：进程真的在跑（脚本已经做这一步）。
只看到 `.app` 存在不算成功——dyld 失败就是这么表现的。

```sh
Scripts/install-app.sh     # 退出码非 0 就是没起来
```

## 3. SwiftNIO 固定在 2.86.x

**为什么存在**：upstream 用 SwiftNIO 实现 phone link。**2.87.0 起要求 Swift 6.1 tools**，
Xcode 15.4 的 5.10 连解析都做不到（`package 'swift-nio' @ 2.102.0 is using Swift tools version 6.1.0`）。
而 upstream 现在把 `from: "2.102.0"` 写进 `project.yml`，**并且提交了 `Package.resolved`**，
等于把版本下限钉在一个本工具链没有可用版本的位置。

**涉及文件**

- `project.yml`：`from: "2.86.0"`（不是 2.102.0）
- `Package.resolved`：fork 自己解析的结果——swift-nio 2.86.2、swift-collections 1.2.1、
  swift-atomics 1.3.1、swift-system 1.6.6、Sparkle 2.9.6
- `Makefile`：`make gen` 会把**仓库根目录**的 `Package.resolved` 拷进工程

**rebase 时怎么判断**：upstream 每次改这两个文件，fork 的 pin 都会被盖掉 → 解析到 2.102.0 → 直接报错。
处理步骤：

1. `project.yml` 改回 `from: "2.86.0"`
2. 删掉工程里的 `Package.resolved`（`Codenotch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`）重新解析
3. 把解析结果拷回仓库根目录 `Package.resolved` 并提交

SwiftPM 会跳过自己读不了的版本，所以 `from: "2.86.0"` 会落在 2.86.2。

**离线提示**：本机到 GitHub 时常不通。SwiftPM 缓存（`~/Library/Caches/org.swift.swiftpm/repositories/`）
里有全部 tag，可以用 `git config url.<file://…>.insteadOf https://github.com/…` 把 GitHub URL
重写到缓存目录做离线解析（注意工具链的 `swift-tools-version` 检查仍然生效）。
本机现状：**HTTPS:443 到 github.com 不通，SSH:22 通**——所以 `upstream` remote 已指向
`git@github.com:vinzdg/codenotch.git`；SwiftPM 解析走缓存，`make gen` 从仓库根的
`Package.resolved` 起手，不需要联网。1.11.0 那轮 `project.yml` 是干净合并（upstream 只改了
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`），pin 没被盖掉——但每次仍要核对上面三个文件。

## 4. Claude provider 不交给 UsageStore

**为什么存在**：`ClaudeOAuthProvider` 要读钥匙串里的 "Claude Code-credentials"。ad-hoc 签名下
每次重建都算新 App，授权留不住 → 每次构建后都弹窗要密码。fork 的选择：**Claude 的 ring 不进 store**，
但 provider 仍然构造并保留，供 token 刷新使用。

**涉及文件**：`Sources/App/AppDelegate.swift`——`storeProviders` 过滤掉 `ClaudeOAuthProvider`；
`preferences.reconcile(discoveredIDs:)` 仍传全集（否则它的设置会被当成已消失而清掉）。

**rebase 时怎么判断**：upstream 重构过 provider 组装（`allProviders` + reconcile）。
冲突时**保留 upstream 的结构**，只在交给 `UsageStore` 的那一处继续过滤。
想恢复 Claude ring，就是去掉那行 filter。

1.11.0 复核：上游把 `allProviders` 又加长了一截（MiniMax、Kiro），filter 那一行仍在原位，
`preferences.reconcile(discoveredIDs:)` 依旧拿全集。

## 5. 关闭 Sparkle 自动更新

**为什么存在**：这是本地定制构建，不能被 upstream 的 appcast 静默替换掉——即使 upstream
自己也「允许用户阻止更新」，fork 的意图是**永不替换**。

**涉及文件**

- `Sources/Info.plist`：`SUEnableAutomaticChecks` / `SUAutomaticallyUpdate` = `false`，`SUFeedURL` 为空
- `project.yml`：`SUFeedURL: ""` 及其注释

**rebase 时怎么判断**：upstream 若改了这些键的默认值，继续保持 false / 空。

1.11.0 复核：upstream 的 `Info.plist` 依然是 `true` / `true` / `https://hivinz.com/appcast.xml`，
本地仍是 `false` / `false` / 空——保持。

## 6. XyToken provider（fork 独有功能）

**为什么存在**：XyToken 的用量在网页会话里，refresh cookie 是 HttpOnly 且每次调用都轮换，
所以「刷新 + 查询」必须在 App 自己的 WKWebView 里带着用户登录态跑。

**涉及文件**

- `Sources/Providers/Sites.swift`：`static let xytoken`（紧挨着 upstream 的 `static let deepSeek`）
- `Sources/Providers/XyTokenUsage.swift`、`Tests/XyTokenUsageTests.swift`
- `Sources/App/AppDelegate.swift`：`webProviders` 里注册

**rebase 时怎么判断**：upstream 也在加同类 provider——DeepSeek、以及 1.11.0 的 MiniMax、Kiro 都是
`WebSessionProvider`。冲突时**两边都留**。1.11.0 那轮 `AppDelegate` 的合并结果是三份：
`let webProviders = [deepSeek, xytoken]`（各画一个 ring）、MiniMax 单独持有（`miniMaxWeb`，注释说明
它的 ring 是 `MiniMaxProvider`，两个同 id 的适配器会抢同一个 archive key），
`fleet.signInItems = [deepSeek, miniMaxWeb, xytoken]`。
`Sites.swift` 里相邻的 `static let`／`static func`（xytoken 紧挨 MiniMax 的 `minimax(region:)`）
仍然是最常见的冲突点。

## 7. 浏览器会话 provider 的登录提示修复

**为什么存在**：`WebSessionProvider` 没有账号元数据。upstream 的设置页把「没有 account」
当成「没登录」，于是在正常取到用量时仍显示登录提示和按钮（本地提交 `fc037d8`）。
fork 在 `ProviderSummary` 上区分：借用凭据的 provider 仍看 `account()`，
浏览器会话 provider（`route == .modal`）只在最近一次请求被判重新认证时才需要登录。

**涉及文件**：`Sources/Providers/ProviderAccount.swift`（`needsSignIn`）、
`Sources/Model/UsageStore.swift`、`Sources/Settings/SettingsView.swift`、
`Tests/ProviderSummaryTests.swift`

**rebase 时怎么判断**：先查 upstream 是否已经修了同一件事
（`grep -rn needsSignIn Sources/`，并翻 upstream 近期的 fix 提交）。**修了就删掉本地版本**——
这类「上游迟早会修」的补丁是 rebase 成本的主要来源。

1.10.0 与 1.11.0 两次复核结论都是**上游没修**：`ProviderAccount` 里只有 `needsSignInRenewal`，
`UsageStore` 组装 `ProviderSummary` 时也不传 `needsSignIn`。所以本地版本继续留着。

## 8. 玻璃样式测试在 macOS 26 以下跳过

**为什么存在**：upstream 新增的 `NotchRenderTests.testTheFoldedPillIsTransparentInTheGlassStyle`
假定 Liquid Glass 存在。macOS 14.3 上 `NotchSurfaceStyle` 会把 glass 样式解析成纯色，
该断言不可能成立——纯色下 pill 本来就是不透明的，旁边的兄弟测试钉的正是这个行为。

**涉及文件**：`Tests/NotchRenderTests.swift`（`XCTSkipUnless(NotchSurfaceStyle.glassAvailable, …)`）

**rebase 时怎么判断**：这是**测试适配，不是决策**。upstream 若自己加了 `glassAvailable` 门禁，
本地这行就该删。

1.11.0 复核：upstream 自己在别的两个测试里用了 `NotchSurfaceStyle.glassAvailable`，但
`testTheFoldedPillIsTransparentInTheGlassStyle` 仍然没有门禁 → 本地这行继续留着。

## 冲突热点（真实踩到过的）

| 位置 | 现象 | 处理 |
| --- | --- | --- |
| 整个仓库 | upstream 重写了全部 commit（hash 全变），没有共同祖先 | 见「上游重写过历史」：用 `--onto`，别用 `git rebase upstream/main` |
| `ProviderGlyph.swift` / `GlyphOutline.swift` | git **自动合并成功**，但 enum 出现重复的 `case kimi` / `static let kimi` | 回退到 upstream 版本 |
| `README.md` | 同上：表格行重复 | 回退到 upstream 版本 |
| `AppDelegate.swift` | provider 组装被 upstream 重构 | 见第 4 节 |
| `Sites.swift` | 两个相邻的 site 定义 | 见第 6 节 |
| `Info.plist` | `LSMinimumSystemVersion` 15.0 vs 14.3 | 保留 14.3 |
| `Makefile` | upstream 的 SwiftPM 逻辑与 fork 的签名逻辑在同一块 | 两边都留 |
| `Package.resolved` | upstream 新增的锁定文件会盖掉 fork 的 pin | 见第 3 节 |

**教训**：`git rebase` 打出「Auto-merging」**不等于**没问题。enum case、README 表格这类
「追加一行」的改动会被自动合并成重复定义，**只有编译期才发现**。所以 rebase 之后必须
编译 + 跑测试，不能只确认「冲突都解完了」。

## 旧工具链编译错误的常见形态

这类改动每轮 rebase 都会出现，统一提交为 `Fix old-toolchain fallout from the upstream sync`。
历史上出现过的形态：

- **新 API**：macOS 26 才有的修饰符 → 走 `Sources/Compatibility/MacOS26Shims.swift`（见第 1 节）
- **Swift 5.10 的并发限制**：不能在嵌套的并发闭包（`Task {}`、`MainActor.run {}`）里读取
  捕获的 `weak self` 变量 → 在**外层**先绑定（见 `PhoneLinkServer`、`LMStudioMetrics`）
- **actor 隔离**：upstream 声明为 isolated 的方法，5.10 下需要 `nonisolated`（见 `ClaudeTokenRefresher.run`）
- **测试里的可变捕获**：`var` 被并发闭包捕获 → 换成 `final class Box`（见 `ClaudeOAuthProviderTests`）
- **类型推断差异**：字面量需要显式类型，例如 `[TimeInterval(18000), …]`（见 `OpenCodeUsageTests`）。
  5.10 不会把整数算术折叠成 `Double`，所以 `[5 * 3600, 7 * 86400]` 匹配不上 `[TimeInterval?]`，
  要写成 `[TimeInterval(5 * 3600), TimeInterval(7 * 86400)]`（1.11.0 的 `Tests/MiniMaxUsageTests.swift`）。

## 已被 upstream 吸收的本地改动

**Kimi provider**：本地提交 `c0aeaf0` 已被 upstream 收编，并被 upstream 演进过——
从读 `config.toml` 的 API key 改成读 `~/.kimi-code/credentials/*.json` 的 OAuth token，
多了 plan 与 weekly 窗口。2026-09 的 rebase 里整个提交被丢弃。
代价：upstream 没有 fork 那条 `case "kimi"` 的设置提示文案，走默认提示。

**判断方法**

```sh
# 全部差异文件
git diff upstream/main HEAD --name-status

# 单个提交是否已被上游吸收（按 patch-id）
git cherry -v upstream/main main
```

`git cherry` 显示 `-` 才是真正被吸收。**upstream 改写过的同一功能会显示 `+`**，
仍然需要人工比对——Kimi 就是这种情况（功能已在上游，patch-id 不同）。

1.11.0 复核：**没有新增被吸收的条目**，`git cherry -v upstream/main main` 全部为 `+`。
历史重写不影响这个判断——`cherry` 比的是 patch 内容，不是 commit hash。

## 维护

每次 rebase 完成后：

1. 逐节复核是否还成立；顶部基线行更新到新的 `upstream/main`
2. 从「仍然保留」移到「已被吸收」的条目，写清原因**和代价**
3. 新出现的差异补一节，格式保持一致
4. 这一节里提到的命令、文件路径以实际仓库为准，**改了要一起改**
5. 若 upstream 又重写了历史，把新的「旧基点 → 新 commit」映射记进「上游重写过历史」
   （`git merge-base main upstream/main` 为空就是信号）

不复核的文档比没有文档更糟：它会让下一次 rebase 照着过期结论删掉还需要的东西。

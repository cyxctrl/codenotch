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

> 写入时的基线：`upstream/main = 3251208`——版本号 **1.12.0 (14)**，本轮只有 3 个提交（发版、appcast、
> notch 空转 CPU 优化），本机 **macOS 14.3 + Xcode 15.4（Swift 5.10）**。
> 上游在 1.11.0 之前重写过全部历史（见「上游重写过历史」），旧 hash `abccf0e` 已不在 upstream；
> **这一轮没有重写**：`git merge-base main upstream/main` 有值，就是上轮的基点 `a42c777`。
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
- [9. Kimi OAuth token 自主续期](#9-kimi-oauth-token-自主续期)
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

1.11.0 → 1.11.0（52 个提交）复核：**历史没有重写**，`git merge-base main upstream/main` 输出
`6c28672`（正是上轮的基点）。
1.11.0 → 1.12.0（3 个提交）复核：**仍然没有重写**，输出 `a42c777`（上轮的基点）。
所以**下次先跑这一条判断**：有输出就走普通 rebase / `--onto` 都行，输出为空才需要去比对 tree。

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

1.11.0 那轮（52 个提交、仍是 1.11.0）的命令：`git rebase --onto upstream/main 6c28672 main`。
冲突集中在两处：`project.yml`（upstream 新增 `- uk` 本地化，本地是 `LSMinimumSystemVersion`）
和六个玻璃调用点（见第 1 节），其余 12 个 fork 提交干净落地。

1.12.0 这轮（3 个提交）的命令：`git rebase --onto upstream/main a42c777 main`。**没有冲突**——
upstream 只碰了 `project.yml` 的版本号，与 fork 在那里的改动（`projectFormat`、`deploymentTarget`、
`packages:` 段、`SU*` 键）落在不同区段；15 个提交全部干净落地，
`git range-diff a42c777..backup/pre-rebase upstream/main..main` 全为 `=`，**0 行内容差异**。

macOS 14.3 + Xcode 15.4 上的实测基线：**1575 个测试通过、5 个跳过、0 失败**（1.10.0 是 1387，
1.11.0 首发 1531/4，1.11.0 同步后 1566/5，本轮 1575/5——upstream 的 `FullScreenAutoFoldTests` 与
`SpinningArcTests` 是这 9 个的来处）。5 个跳过是 3 个 opt-in live check（Devin、LM Studio、Ollama）
加 2 个玻璃测试（见第 8 节）。测试总数会随 upstream 增长，**要盯的是「0 failures」，不是具体数字**。
1.12.0 这轮 `Scripts/install-app.sh` 装出 **1.12.0 (14)**、ad-hoc 签名，`/Applications` 那个进程正常起来。

## 1. macOS 14.3 部署目标与 SDK shim

**为什么存在**：见上。upstream 的 `deploymentTarget` 是 15.0，本机要在 14.3 上跑。

**涉及文件**

- `project.yml`：`deploymentTarget: 14.3`、`projectFormat: xcode15_0`
- `Sources/Info.plist`：`LSMinimumSystemVersion` = 14.3
- `Sources/Compatibility/MacOS26Shims.swift`：`compatGlassEffect(_ style: NotchSurfaceStyle,
  in:interactive:)`、`compatPointerStyle(active:)`
- `Sources/Settings/NotchSurfaceStyle.swift`：`var glass: Glass` 连同它的文档整段在
  `#if swift(>=6.2)` 里（理由见下）
- `Tests/NotchLayoutTests.swift`：唯一比较 `glass` 值的那个测试同样在 `#if swift(>=6.2)` 里
- 调用点：`SettingsView`、`NotchRootView`、`MoveHandle`、`SettingsHandle`、`TooltipCard`、`UsageResetCard`

**rebase 时怎么判断**：本机还在 macOS 14 / Xcode 15.4 上就留着。shim 用
`#if swift(>=6.2)` 判断「这个工具链里有没有 macOS 26 SDK」（Xcode 26 = Swift 6.2，
Xcode 15.4 = 5.10）：新工具链编译真正的修饰符，旧工具链永远看不到那个符号。

每次 upstream 新增 `glassEffect` / `pointerStyle` 调用点，**编译期就会报错**，照既有形态改：
把 `#available(macOS 26.0, *)` 块换成无条件的 `compat*` 调用。**不要**在旧 SDK 里保留
「`#available` 包着新符号」的写法。

`#if swift(>=6.2)` 卡的是**两条**边界，不只是修饰符：

1. 修饰符本身（`glassEffect`、`pointerStyle`）——不过 `#if` 的话编译器看不到符号。
2. **类型本身**：`NotchSurfaceStyle.glass` 返回 macOS 26 的 `Glass`，而 `@available` 门禁不了
   「返回类型在这个工具链里根本不存在」的声明，所以那个属性——以及唯一比较它的测试——
   整段进 `#if`。

因此 shim 收的是 `NotchSurfaceStyle` 而不是 `Glass`，**`Glass` 这个名字只允许出现在
`Sources/Compatibility/MacOS26Shims.swift`**，调用点永远不写它。darkGlass 把这条逼了出来：
upstream 从 `.glassEffect(.regular, …)` 改成 `.glassEffect(surfaceStyle.glass, …)`（`.regular`
或 `.clear`），shim 若还把 `.regular` 写死，macOS 26 上 fork 的暗色玻璃就画错了。

排查命令：

```sh
grep -rn 'glassEffect\|pointerStyle' Sources/ | grep -v 'Compatibility/MacOS26Shims.swift'
```

1.11.0 同步复核：上面那条 grep 干净。改动落在六处——MoveHandle / SettingsHandle / TooltipCard /
UsageResetCard / NotchRootView 换成 `compatGlassEffect(surfaceStyle, in: …)`，SettingsView 的
`glassBackground(in:)` 传 `.glass`（正是 upstream 在那儿要的 `.regular`；它的 `glassDim` 是 nil，
不会往设置页底下铺东西）。
1.12.0 复核：upstream 这轮没新增 `glassEffect` / `pointerStyle` 调用点（它改的是 `ProviderRing`
的弧线绘制与 `NotchWindowController` 的空转优化），grep 仍干净，六个调用点、shim 和
`#if swift(>=6.2)` 的两条边界原样落地，本轮没有旧工具链 fallout。

upstream 自己的 `.background { if let dim = surfaceStyle.glassDim { … } }`（暗色玻璃底下的那层 wash，
只是个 `Color`）**留在调用点**，不搬进 shim。

NotchRootView 多一层：upstream 新加了 `if headlessGlass { … } else { … }`（像素测试要「走玻璃路径、
但没有材质」的那一层）。**保留 upstream 的 if/else 结构**，只把 else 分支里的 `glassEffect` 换成
shim——不要像上一轮那样把整块压成一次调用，压掉就丢了 headless 路径。

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

1.11.0 同步复核：`Makefile` 上 fork 的 `DEV_RESIGN` / `install` 与 upstream 的 SwiftPM 逻辑仍然各占一块、
原样共存；`Scripts/install-app.sh` 无 upstream 改动。本轮装出 1.11.0 (13)、ad-hoc，进程起来了。
1.12.0 复核：upstream 这轮没碰 `Makefile`、`Scripts/install-app.sh`，上段格局原样；本轮装出
1.12.0 (14)、ad-hoc，进程起来了。

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
`Package.resolved` 起手，不需要联网。**每轮仍要核对上面三个文件**，不过两轮 1.11.0 都是干净合并：
1.11.0 同步复核：upstream 只改过 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`，那轮 52 个提交没碰
`packages:` 段、也没碰 `Package.resolved`，fork 的 pin 原样落地。
1.12.0 复核：同样只改版本号（`1.12.0` / `14`），`packages:` 段与 `Package.resolved` 都没动
（`git diff --name-only a42c777 upstream/main -- Package.resolved` 为空），pin 仍是 swift-nio 2.86.2。

## 4. Claude provider 不交给 UsageStore

**为什么存在**：`ClaudeOAuthProvider` 要读钥匙串里的 "Claude Code-credentials"。ad-hoc 签名下
每次重建都算新 App，授权留不住 → 每次构建后都弹窗要密码。fork 的选择：**Claude 的 ring 不进 store**，
但 provider 仍然构造并保留，供 token 刷新使用。

**涉及文件**：`Sources/App/AppDelegate.swift`——`storeProviders` 过滤掉 `ClaudeOAuthProvider`；
`preferences.reconcile(discoveredIDs:)` 仍传全集（否则它的设置会被当成已消失而清掉）。

**rebase 时怎么判断**：upstream 重构过 provider 组装（`allProviders` + reconcile）。
冲突时**保留 upstream 的结构**，只在交给 `UsageStore` 的那一处继续过滤。
想恢复 Claude ring，就是去掉那行 filter。

1.11.0 初轮复核：上游把 `allProviders` 又加长了一截（MiniMax、Kiro），filter 那一行仍在原位，
`preferences.reconcile(discoveredIDs:)` 依旧拿全集。
1.11.0 同步复核：`allProviders` 再长一截（Claude Desktop、日进度环等），结构未变——Claude 的 provider 仍
在 store 之外构造并保留，只有交给 `UsageStore` 的那一处过滤。
1.12.0 复核：upstream 这轮没碰 `AppDelegate.swift`；`storeProviders` 的 filter 仍在原处
（`AppDelegate.swift:169`），`preferences.reconcile(discoveredIDs:)` 仍拿全集。

## 5. 关闭 Sparkle 自动更新

**为什么存在**：这是本地定制构建，不能被 upstream 的 appcast 静默替换掉——即使 upstream
自己也「允许用户阻止更新」，fork 的意图是**永不替换**。

**涉及文件**

- `Sources/Info.plist`：`SUEnableAutomaticChecks` / `SUAutomaticallyUpdate` = `false`，`SUFeedURL` 为空
- `project.yml`：`SUFeedURL: ""` 及其注释

**rebase 时怎么判断**：upstream 若改了这些键的默认值，继续保持 false / 空。

1.11.0 初轮复核：upstream 的 `Info.plist` 依然是 `true` / `true` / `https://hivinz.com/appcast.xml`，
本地仍是 `false` / `false` / 空——保持。
1.11.0 同步复核：三项键值 upstream 依旧未变，本地依旧 `false` / `false` / 空；`project.yml` 里
`SUFeedURL: ""` 及其注释也没被 upstream 动过。
1.12.0 复核：三项键值仍未变——upstream 这轮只动 `project.yml` 的版本号，`SU*` 三行与
`Sources/Info.plist` 都没进它的改动集。

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

1.11.0 同步复核：`Sites.swift` 干净合并（fork 的 `static let xytoken` 仍追加在 MiniMax 之后，upstream 那轮
没往这个文件加新 site）；`AppDelegate` 里 `webProviders = [deepSeek, xytoken]` 与
`fleet.signInItems = [deepSeek, miniMaxWeb, xytoken]` 都在原位。
1.12.0 复核：upstream 这轮两个文件都没碰，三处注册原样；fork 又给 `XyTokenUsage` 的窗口补上了
`duration`（从 limit 自己的 `period_value` / `period_unit` 推周期），token 提示条的 pace 行
对 XyToken 也生效——这是本节功能范围内的本地演进，不是新的 divergence。

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
1.11.0 同步复核仍是**上游没修**：`grep -rn needsSignIn Sources/` 只命中 `needsSignInRenewal`，
`UsageStore.swift` 组装 `ProviderSummary` 的那一处依旧只传它。
1.12.0 复核仍是**上游没修**：grep 命中的 `needsSignIn` 全部来自 fork 自己——
`ProviderAccount.needsSignIn`、`UsageStore.needsSignIn(_:account:)` 与 `SettingsView` 的两处读取；
upstream 侧仍然只有 `needsSignInRenewal`。本地版本继续留着。

## 8. 玻璃样式测试在 macOS 26 以下跳过

**为什么存在**：upstream 新增的 `NotchRenderTests.testTheFoldedPillIsTransparentInTheGlassStyle`
假定 Liquid Glass 存在。macOS 14.3 上 `NotchSurfaceStyle` 会把 glass 样式解析成纯色，
该断言不可能成立——纯色下 pill 本来就是不透明的，旁边的兄弟测试钉的正是这个行为。

**涉及文件**：`Tests/NotchRenderTests.swift`（`XCTSkipUnless(NotchSurfaceStyle.glassAvailable, …)`）

**rebase 时怎么判断**：这是**测试适配，不是决策**。upstream 若自己加了 `glassAvailable` 门禁，
本地这行就该删。

1.11.0 初轮复核：upstream 自己在别的两个测试里用了 `NotchSurfaceStyle.glassAvailable`，但
`testTheFoldedPillIsTransparentInTheGlassStyle` 仍然没有门禁 → 本地这行继续留着。
1.11.0 同步复核：upstream 把这个测试重写了（改走 headless glass，加了「三格尺寸」的注释），但**仍然没有
门禁**，所以本地那行继续留。跟着 upstream 的新签名，它现在是 `throws` + 方法体第一行的
`try XCTSkipUnless(NotchSurfaceStyle.glassAvailable, …)`。upstream 自己新增的
`testTheFoldedPillCarriesTheDimInTheDarkGlassStyle` 用 `#available` 自行跳过——那是它自己的门禁，
在 macOS 14 上表现为「跳过数从 4 变成 5」，不是本地要删的东西。
1.12.0 复核：upstream 这轮没碰 `NotchRenderTests.swift`，本地那行继续留；实测跳过仍是 5 个，
且原因与上段一一对上（3 个 opt-in live check + 上述两个玻璃测试）。

## 9. Kimi OAuth token 自主续期

**为什么存在**：upstream 的 `KimiProvider` 只**读** `~/.kimi-code/credentials/kimi-code.json`，
注释里假定「token 会被 CLI 在正常使用中续期」。这个假定对 Kimi 不成立：

- access token 只有 **900 秒**（`expires_in: 900`）；
- refresh token 是**一次性**的——CLI 的 `tokenFromResponse` 在响应缺少 `refresh_token` 时直接抛
  `OAuth response missing refresh_token`，也就是说服务端每次刷新都换发新的，旧的作废；
- 唯一会续期的是 CLI 自己，且**只在它运行时**：任何一次 API 请求（含 TUI 的 `/usage`）都走
  `OAuthManager.ensureFresh()`，把结果原子写回同一个文件。不跑 `kimi` 就没有任何东西续期。

于是：登录后 15 分钟内能读到 1~3 次，之后每次轮询都在 `credentials.isExpired` 处抛
`credentialExpired`；`UsageStore` 把它当成「陈旧」而保留上一份读数，那份读数的窗口重置时间早已
过去 → `ResetCopy` 对所有「已过期」的窗口输出「正在重置…」，而它等的那次重取永远不会来。
2026-09 实测时间线：10:27:04 重新登录写入 token → 10:42:04 过期 → 此后每 5 分钟一次
`credentialExpired`；「只能登出再登录、且只正常一次」就是这么来的。

**处理方式**：fork 自己发 CLI 那笔 refresh 请求，并按 CLI 的文件形态写回。每一步都是**逆向出来的
私有协议**（`@moonshot-ai/kimi-code@0.42.0` 的 `dist/main.mjs`），不是 Kimi 承诺的接口，所以按
「兼容机制、看结果」对待，与 `ClaudeTokenRefresher` 对待 `claude -p` 同类：

1. 取 CLI 自己的跨进程锁 `<home>/oauth/kimi-code.lock`（proper-lockfile：`mkdir` 即持有、
   `stale: 5000`、释放 `rmdir`、重试 120×500ms）。**必须**用同一把锁——refresh token 一次性，
   两次并发刷新会让输的那一半作废，等于把用户的 CLI 踢下线。
2. 拿到锁后**重读文件**：若已被 CLI 续期就直接用它、不发请求（CLI 自己的 `doEnsureFresh` 同样如此）。
3. `POST https://auth.kimi.com/api/oauth/token`，form 为 `client_id`（CLI 内置的公开 id
   `17e5f671-d194-4dfb-9706-5516cb48c098`）、`grant_type=refresh_token`、`refresh_token`，带
   `X-Msh-*` 设备头（device_id、版本等全部读本机或 CLI 数据，读不到就省略该头）。
4. 200 → 按 CLI 同样的严格度校验 `access_token`/`refresh_token`/`expires_in`，原子写回（6 个
   snake_case 键、0600、`tmp`+`rename`）。

失败时的行为是**有意选的，且都不比 upstream 更糟**：端点拒绝（`invalid_grant` / 401 / 403）→ 抛
`needsAuth`（不写 tombstone，那是 CLI 的决定）；网络失败或取不到锁 → 抛 `credentialExpired`，
**凭证原样不动**。

续期时机照 CLI 的阈值：`max(300, expires_in / 2)`，即 900 秒的 token 在剩 7m30s 时续（对应 CLI 的
`MIN_REFRESH_THRESHOLD_SECONDS = 300` 与 `REFRESH_THRESHOLD_RATIO = .5`），既不会比 CLI 更早
浪费一笔请求，也不会留下「token 已死、这一轮读数被跳过」的窗口。

**涉及文件**

- `Sources/Providers/KimiTokenRefresher.swift`（新增）：`KimiTokenRefresher`（周期判断、锁、grant、
  写回）、`KimiRefreshLock`（CLI 的锁协议）、`KimiAuthHost`（大陆/国际两个 auth host 的选择）、
  `KimiDeviceIdentity`（`X-Msh-*` 头）
- `Sources/Providers/KimiCredentials.swift`：新增 `homeURL`（`KIMI_CODE_HOME` 覆盖上移到此）、
  `expiresIn` / `scope` / `tokenType`、`needsRenewal(now:)`、`write(_:to:)`；`load` 多读三个字段
- `Sources/Providers/KimiProvider.swift`：`fetchSnapshot()` 改为先取 `refresher.usableCredential()`
- `Tests/KimiTokenRefreshTests.swift`（新增）：16 个测试，全部指向 `$TMPDIR` 下的临时 home

与「已被 upstream 吸收的本地改动」里那个旧 Kimi 提交 `c0aeaf0` 区分：那是读 `config.toml` 的
API key，功能已在上游；本节是上游改成读 OAuth token **之后**新出现的差异。

**rebase 时怎么判断**：

1. **上游若自己开始续期，就把这一整笔提交丢掉**（代码 + 本节），并移到「已被 upstream 吸收」。信号：

   ```sh
   git diff upstream/main HEAD -- Sources/Providers/KimiProvider.swift Sources/Providers/KimiCredentials.swift
   grep -rn "oauth/token\|refresh_token" Sources/Providers/ | grep -v KimiTokenRefresher
   ```

   上游的 `KimiProvider` 里出现写凭证、或 401 后重取的动作，就说明它修了同一件事。
2. **上游没修就留着。** 私有协议对不上时症状会自己现形：

   ```sh
   log stream --predicate 'subsystem == "com.vinz.codenotch"' --level debug | grep -i kimi
   ```

   `the token endpoint answered 4xx` 或 `could not take the CLI's refresh lock` = Kimi 改了端点或
   CLI。先确认凭证文件没被动过（`stat` 的 mtime、`expires_at` 未变即安全），再决定跟不跟。
3. 与第 4 节无关：Claude 是「跑 CLI 续期」，Kimi 是「自己发请求」。取舍在 token 寿命——Claude 的
   刷新一次管八小时，Kimi 的只有十五分钟，后者每 13 分钟起一个 node 进程不划算，而 `kimi login`
   还会顺带重写 `config.toml`。

1.11.0 同步复核：**上游没修**。信号那条 grep 干净——`oauth/token` / `refresh_token` 只出现在 fork 的
`KimiTokenRefresher.swift` 和 fork 改过的 `KimiCredentials.swift` 里；upstream 的 `KimiProvider` 仍然
只读凭证，`fetchSnapshot()` 里没有任何写回或 401 重取的动作。这一整笔提交继续留着。
1.12.0 复核：**上游仍未修**。`KimiProvider.swift` / `KimiCredentials.swift` 都没进 upstream 本轮的
改动集，信号 grep 仍只命中 fork 的那两个文件。

## 冲突热点（真实踩到过的）

| 位置 | 现象 | 处理 |
| --- | --- | --- |
| 整个仓库 | upstream 重写了全部 commit（hash 全变），没有共同祖先 | 见「上游重写过历史」：用 `--onto`，别用 `git rebase upstream/main` |
| `ProviderGlyph.swift` / `GlyphOutline.swift` | git **自动合并成功**，但 enum 出现重复的 `case kimi` / `static let kimi` | 回退到 upstream 版本 |
| `README.md` | 同上：表格行重复 | 回退到 upstream 版本 |
| `AppDelegate.swift` | provider 组装被 upstream 重构 | 见第 4 节 |
| `Sites.swift` | 两个相邻的 site 定义 | 见第 6 节 |
| `Info.plist` | `LSMinimumSystemVersion` 15.0 vs 14.3 | 保留 14.3 |
| `NotchSurfaceStyle.swift` | upstream 新增的 `glass: Glass` 在旧 SDK 里连**类型**都不存在，`@available` 救不了 | 属性与比较它的测试整段进 `#if swift(>=6.2)`，见第 1 节 |
| `MacOS26Shims.swift` 的签名 | shim 收 `Glass` 则调用点在旧 SDK 上必编译失败 | shim 只收 `NotchSurfaceStyle`，调用点不写 `Glass`，见第 1 节 |
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
- **类型不存在，而不是 API 不存在**：`@available` 门禁不了「返回类型不在这个 SDK 里」的声明——
  `NotchSurfaceStyle.glass` 返回 `Glass`，只能整段 `#if swift(>=6.2)`（见第 1 节）。同理，测试里
  比较这个值的断言要一起进 `#if`，否则**测试目标**编译失败——`make build` 仍是绿的，只有
  `make test` 会报 `enum case 'glass' cannot be used as an instance member`。

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

1.11.0 初轮复核：**没有新增被吸收的条目**，`git cherry -v upstream/main main` 全部为 `+`。
1.11.0 同步复核（52 个提交）：同样**没有**，12 个 fork 提交全为 `+`。
1.12.0 复核（3 个提交）：`git cherry -v upstream/main main` 的 15 个提交仍全为 `+`，无新增条目。
历史重写不影响这个判断——`cherry` 比的是 patch 内容，不是 commit hash。

## 维护

每次 rebase 完成后：

1. 逐节复核是否还成立；顶部基线行更新到新的 `upstream/main`
2. 从「仍然保留」移到「已被吸收」的条目，写清原因**和代价**
3. 新出现的差异补一节，格式保持一致
4. 这一节里提到的命令、文件路径以实际仓库为准，**改了要一起改**
5. 若 upstream 又重写了历史，把新的「旧基点 → 新 commit」映射记进「上游重写过历史」
   （`git merge-base main upstream/main` 为空就是信号）
6. **同步完成后把本轮改动讲清楚**：upstream 这轮带来了哪些提交、碰了哪些文件、对 fork 意味着什么
   （哪节仍成立、哪节要动），都要报给用户。只说「已同步」不算汇报。

不复核的文档比没有文档更糟：它会让下一次 rebase 照着过期结论删掉还需要的东西。

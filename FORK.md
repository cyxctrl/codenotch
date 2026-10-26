# FORK.md — 本仓库相对 upstream 的差异

本仓库跟踪 [vinzdg/codenotch](https://github.com/vinzdg/codenotch)（下称 **upstream**），
在其之上保留若干本地改动（下称 **fork**）。upstream 更新时本地用 rebase 跟上：

```sh
git fetch upstream                              # remote 是 SSH：本机 HTTPS:443 连不上
git branch -f backup/pre-rebase-<版本> main     # 变基前留退路，带版本号才好回溯
git rebase --onto upstream/main <fork 基点> main   # 注意 --onto，理由见下
```

这份文档的唯一目的：**下次 rebase 时不必重新推导「这条改动为什么存在、还需不需要」。**
每节按同一格式写——为什么存在 / 涉及文件 / rebase 时怎么判断。

> 写入时的基线：`upstream/main = 6522e9f`——版本号 **1.24.0 (26)**，本轮 **102 个提交**。
> 顶点那笔是 1.24.0 的功能发布，四件事：**菜单栏从「一个图标」变成一块面板**——里面直接排 provider
> 卡片（每张自带 Detail 开关）、按「谁还剩多少」排序、宽度可调、另有独立的 activity style 与 click action
> 偏好（`MenuUsageCard` / `MenuCommandRow` / `StatusItemWaitingBadges` / `MenuBarReading` /
> `MenuBarClickAction` / `MenuBarActivityStyle` / `RingOrder` 七个新文件）；**西班牙语本地化**（`es` 进
> `CFBundleLocalizations`，Mac 与 Windows 两端）；**Higgsfield 这个新 provider**（`HiggsfieldProvider` /
> `CLI` / `Credentials` / `Usage`，走 `.command` 登录路由、有 `account()`）；**burn-deficit 环改成
> 「先用掉快过期的」排序**。
> 其余是：Antigravity 的 ACP 支持与配额家族修复、DeepSeek Harness、Windows 端的 Claude 多账号与原生
> 任务栏指示、Qoder 走官方 agent SDK、OpenCode 2.x 读 DB 里的 Go key、agy 在 Windows 上的 ConPTY、
> Linux 在 XWayland 下的 notch、Ollama cloud 的 totals 计数、Pi 会话目录的符号链接比较。
> 本机 **macOS 14.3 + Xcode 15.4（Swift 5.10）**。
> 上游在 1.11.0 之前重写过全部历史（见「上游重写过历史」），旧 hash `abccf0e` 已不在 upstream；
> **这一轮没有重写**：rebase 前 `git merge-base main upstream/main` 有值，正是上轮的基点 `9e7cd3d`。
> **这一轮的特殊之处：编译期一处 fallout 都没有**——`make build` 与 `build-for-testing` 一次全绿，
> 所以没有新的 `Fix old-toolchain fallout` 提交（1.13.1 之后第一次）。原因是 upstream 本轮
> **一个玻璃调用点、一个 Kimi 文件、一个玻璃门禁测试都没碰**（见第 1 / 7 / 8 节的复核）。
> 冲突只有 3 处：`project.yml`（`es` 紧贴 `LSMinimumSystemVersion`）、`AppDelegate` 的 provider 链
> （`HiggsfieldProvider()`）、`UsageStore` 的 wake 观察者（`refreshNow` 变成了返回 `Task?`）。
> 每次 rebase 后请更新这一行和文中已过期的结论（见末尾「维护」）。

## 目录

- [两个约束推导出大部分差异](#两个约束推导出大部分差异)
- [上游重写过历史](#上游重写过历史)
- [rebase 流程与验证基线](#rebase-流程与验证基线)
- [1. macOS 14.3 部署目标与 SDK shim](#1-macos-143-部署目标与-sdk-shim)
- [2. ad-hoc 签名、DEV_RESIGN 与安装路径](#2-ad-hoc-签名dev_resign-与安装路径)
- [3. SwiftNIO 固定在 2.86.x](#3-swiftnio-固定在-286x)
- [4. 关闭 Sparkle 自动更新](#4-关闭-sparkle-自动更新)
- [5. XyToken provider（fork 独有功能）](#5-xytoken-providerfork-独有功能)
- [6. 浏览器会话 provider 的登录提示修复](#6-浏览器会话-provider-的登录提示修复)
- [7. 玻璃样式测试在 macOS 26 以下跳过](#7-玻璃样式测试在-macos-26-以下跳过)
- [8. Kimi OAuth token 自主续期](#8-kimi-oauth-token-自主续期)
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
   （授权留不住这件事本身**不再有代价**了：后台读取不需要授权，见「已被 upstream 吸收的本地改动」。）

其余差异（XyToken、关闭自动更新）是功能与偏好层面的**主动决策**，
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
1.12.0 → 1.13.1（61 个提交）复核：**仍然没有重写**，输出 `3251208`（上轮的基点）。
1.13.1 → 1.15.0（45 个提交）复核：**仍然没有重写**，输出 `bcd063c`（上轮的基点）。
1.15.0 → 1.16.0（68 个提交）复核：**仍然没有重写**，输出 `ec1a7e3`（上轮的基点）。
1.16.0 → 1.18.0（174 个提交）复核：**仍然没有重写**，输出 `784985e`（上轮的基点）。
1.18.0 → 1.19.0（3 个提交）复核：**仍然没有重写**，输出 `07ba1db`（上轮的基点）。
1.19.0 → 1.22.0（91 个提交）复核：**仍然没有重写**——`0083369` 是 `bcb2889` 的祖先
（`git merge-base --is-ancestor 0083369 bcb2889` 为真）。这一轮当时没记账，但历史连续性可以事后确认。
1.22.0 → 1.23.0（61 个提交）复核：**仍然没有重写**，输出 `bcb2889`（上轮的基点）。
1.23.0 → 1.24.0（102 个提交）复核：**仍然没有重写**，输出 `9e7cd3d`（上轮的基点）。
所以**下次先跑这一条判断**：有输出就走普通 rebase / `--onto` 都行，输出为空才需要去比对 tree。

## rebase 流程与验证基线

```sh
git fetch upstream                              # remote 是 SSH：本机 HTTPS:443 连不上
git branch -f backup/pre-rebase-<版本> main     # 变基前留退路（本轮是 backup/pre-rebase-1.24.0）

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

1.13.1 这轮（61 个提交）的命令：`git rebase --onto upstream/main 3251208 main`。**1 处冲突**——
`Sources/Providers/ClaudeTokenRefresher.swift` 里 upstream 新加的 `arguments` 常量与文档正好落在
fork 改成 `nonisolated` 的那个 `run` 声明上方（处理方式见「冲突热点」）。其余 15 个 fork 提交干净落地，
`git range-diff 3251208..backup/pre-rebase-1.12.0 upstream/main..main` 只有那两处上下文差异。
**本轮没有任何旧工具链 fallout**：upstream 的新代码在 Xcode 15.4 下直接编译通过——没有新增
`glassEffect` / `pointerStyle` 调用点，也没有 5.10 的并发或类型推断问题，所以没有
`Fix old-toolchain fallout` 那一笔提交。

1.15.0 这轮（45 个提交）的命令：`git rebase --onto upstream/main bcd063c main`。**2 个文件冲突**：
`Sources/App/AppDelegate.swift` 里 upstream 把新的 `qianwen` 加进 `webProviders` 与 `signInItems`，
而 fork 的 `xytoken` 在同一个列表字面量里 → 两边都留，结果见第 5 节；`SettingsView.swift` 冲突了
**两次**（最初那笔 SDK shim 提交与第三笔 `Fix old-toolchain fallout` 各一次），两处都是**已经失去
对象**的玻璃替换——upstream 这一轮把玻璃侧栏换成扁平的 `SettingsPalette.sidebar`，并删掉了
`sidebarToggle` / `collapsedSidebarToggle` / `SidebarIcon`，fork 在侧栏底与 orb 上的 `compatGlassEffect`
无处可施，所以取 upstream、不再加回（见第 1 节与「已被 upstream 吸收的本地改动」）。
其余 16 个 fork 提交干净落地；`Sources/Providers/Sites.swift` 里 upstream 的 `static let qianwen` 与
fork 的 `static let xytoken` 自动合并成功、各一份，无重复定义（见第 5 节）。
**本轮有 1 处旧工具链 fallout**：upstream 新增的 `GrokActivityMonitor.rescan()` 在两层嵌套的并发闭包里
读捕获的 `weak self`，Swift 5.10 直接报错 → 单独一笔 `Fix old-toolchain fallout`（见「旧工具链编译
错误的常见形态」）。

1.16.0 这轮（68 个提交）的命令：`git rebase --onto upstream/main ec1a7e3 main`。**3 个文件冲突、两次停**：
`UsageStore.swift` 里 upstream 给 `ProviderSummary` 加了 `customIconFilename:`，正好落在 fork 那笔
「读一次 `account()` 并传 `needsSignIn:`」的同一段 → 两边都留（见第 6 节）；`TooltipCard.swift` 与
`UsageResetCard.swift` 里 upstream 改了 tooltip 玻璃的**内容**——尾偏移换成 `clampedTailOffset`、
`surfaceStyle.glassDim` 换成 `TooltipGlassContrast.dim(...)`（本轮「Refine/Improve Liquid Glass tooltip
contrast」）——而 fork 在同一行把 `#available(macOS 26)` + `glassEffect` 换成了 shim → 取 upstream 的
新内容、只把调用换成 `compatGlassEffect`（见第 1 节）。其余 18 个 fork 提交干净落地；
`AppDelegate.swift` / `SettingsView.swift` / `ProviderAccount.swift` / `NotchRootView.swift` /
`Tests/NotchRenderTests.swift` / `project.yml` 都是自动合并成功（第 5 节的 XyToken 注册照旧各一份）。
`git range-diff ec1a7e3..backup/pre-rebase-1.15.0 upstream/main..main` 只有 `7526460` 那笔显示内容差异，
逐行看下来全是 upstream 新增行的上下文（`antigravity profiles` 日志行、`+ customProviders`），语义未变。
**本轮有 2 处旧工具链 fallout**：upstream 把 provider 组装改成一个跨十几种类型的 `+` 链，5.10 的类型
检查器在 `AppDelegate` 上超时；upstream 新增的 3 个 Liquid Glass 对比度测试在 macOS 26 以下没有可测的
玻璃。两处合为一笔 `Fix old-toolchain fallout`（见「旧工具链编译错误的常见形态」与第 7 节）。

1.18.0 这轮（**174 个提交，历轮最多**，命令：`git rebase --onto upstream/main 784985e main`）。**2 个文件冲突、各停一次**：
`project.yml` 里 upstream 往 `CFBundleLocalizations` 追加了 `id` / `ko` / `uz` / `tr`，`uz` / `tr` 正好紧贴 fork
改的 `LSMinimumSystemVersion` → 各留一份（本地化列表取 upstream，版本下限保持 14.3，见第 1 / 4 节）；
`Sources/App/AppDelegate.swift` 里 upstream 往那条 provider `+` 链中间加了 `AmpProvider()` / `ApifyProvider()` /
`KiloProvider()`，正落在 fork 1.16.0 拆成 `+=` 的那条链上 → 保留 `+=` 结构、三个新 provider 各占一句（见「冲突热点」）。
其余 21 个 fork 提交干净落地；`Sites.swift`（upstream 本轮碰了它）、`UsageStore.swift`、`ProviderAccount.swift`、
`SettingsView.swift`、`NotchRootView.swift`、`TooltipCard.swift`、`UsageResetCard.swift`、`Makefile`、`Info.plist`、
`KimiProvider.swift` 全部自动合并成功——**但其中一处自动合并的结果编不过**，见下。
`git range-diff 784985e..backup/pre-rebase-1.16.0 upstream/main..main` 只有那两笔冲突提交显示内容差异，
逐行看下来正是上面那两处的解（upstream 新增的本地化行 + 新参数、fork 的 `+=` 与注册顺序），语义未变。
**本轮有 2 处旧工具链 fallout，合为一笔**：`UsageStore.needsSignIn` 的穷尽 switch 撞上 upstream 新增的
`SignInRoute.command`（**文件自动合并干净、没有任何冲突标记**，只有编译期才会报 `switch must be exhaustive`）；
`ApifyUsage.money` 在 `en_US_POSIX` 下拿不到分组（那个 locale 的 decimal 模式 `groupingSize` 是 0），`$12,345.68`
变成 `$12345.68`——upstream 的 CI 跑在 **`macos-26`** 上，所以它在那边是绿的（见「旧工具链编译错误的常见形态」）。

1.19.0 这轮（**只有 3 个提交**，历轮最少，命令：`git rebase --onto upstream/main 07ba1db main`）。**3 个文件冲突、停两次**：
`project.yml` 里 upstream 在 `SUEnableAutomaticChecks: true` 下面新加了一段「新版本在 notch 里问、选了 Update
才装」的注释，正好紧贴 fork 改成 `false` 的那一行；而它**同时把 `SUAutomaticallyUpdate` 从 `true` 改成 `false`**（两处
文件都改，所以 fork 那半截不再独有）→ 值取 fork 的 `SUEnableAutomaticChecks: false`、注释取 upstream 的
（它讲的是它下面那行，两边现在都成立），见第 4 节；`MoveHandle.swift` 与
`SettingsHandle.swift` 里 upstream 把 notch 的拖拽整套换成了「六颗点」那套（`struct MoveHandle` 变成
`enum MoveHandle` **加** `MoveGrip`；`SettingsHandle` 的玻璃分支里新增 `.mask { GooArc(…) }`）→ 前者取
upstream（fork 改的那个 struct 已经不存在），后者取 upstream 的新结构、只把 `glassEffect` 换成 shim
（见第 1 节与「冲突热点」）。其余 24 个 fork 提交干净落地——含 `NotchRootView.swift`、`SettingsView.swift`、
`AppDelegate.swift`、`Tests/NotchRenderTests.swift`、`Tests/NotchLayoutTests.swift` 这些 fork 也改过的文件。
`git range-diff 07ba1db..backup/pre-rebase-1.19.0 upstream/main..main` 只有上面那两笔冲突提交显示内容差异，
逐行看下来正是那两处的解。**本轮有 1 笔旧工具链 fallout**：两处新的 `glassEffect` 调用点——
`MoveGrip.glassDots` 与**全新文件** `Sources/Features/UpdateCard.swift`，后者不产生冲突、只在编译期暴露，
见「旧工具链编译错误的常见形态」。**本轮没有穷尽 switch、没有旧 Foundation 的格式断言**，所以只这一笔。

1.22.0 这轮（**91 个提交、跨三个发布**——1.20.0「cost per project, and figures that keep up」、
1.21.0「Anthropic and Gemini endpoints, llama.cpp's speed, Antigravity without the IDE」、
1.22.0「Qoder, more than one Command Code account, DeepSeek's funded wallet」；命令：
`git rebase --onto upstream/main 0083369 main`——**当时只做了 rebase、没有记账**，这几行是事后从
`git reflog main` 与 `range-diff` 反推的，`backup/pre-rebase-1.22.0` = `8ccbfd7` 仍在）。那 91 个提交
把 1.19.0 推到 **1.22.0 (24)**；upstream 端除三个发布标题说的那些，还有：设置页齿轮改成几何绘制、
把 notch 的「六颗点」拖拽整套落地
（`CornerPassage`）、菜单栏条目按内容取宽、cost per project 与 Activity 窗口、Linux 端口、Windows 端的
Watch/Critical 滑杆与虚线周环、Abacus.AI 的 custom-endpoint 预设、**`qoder` 这个新的 `WebSessionProvider`**，
以及 **Command Code 支持多账号**（`commandCodeProfiles`）。**4 个 fork 提交变了形**（复现命令：
`git range-diff 0083369..backup/pre-rebase-1.22.0 bcb2889..11a7bc9`）：① SDK shim 那笔被 upstream 新加的
`NSAppTransportSecurity` 挤动（它插在 fork 改的 `LSMinimumSystemVersion` 下面，见第 1 / 4 节的冲突热点）；
② XyToken 注册那笔的 `webProviders` / `signInItems` 两个字面量跟着 upstream 的 `qoder` 各加一项 →
`[deepSeek, qianwen, qoder, xytoken]` 与 `[deepSeek, miniMaxWeb, qianwen, qoder, xytoken]`（见第 5 节）；
③ Kimi 续期那笔只重排了 `KimiProvider` 的文档注释，语义未变；④ provider 链那笔因为 upstream 新增
`commandCodeProfiles` 多起了一句 `allProviders += commandCodeProfiles.map { CommandCodeProvider(profile: $0) as UsageProvider }`。
其余 24 个 fork 提交干净落地。**这一轮没有留下 `Fix old-toolchain fallout` 提交，也没有 `make test` /
`Scripts/install-app.sh` 的任何记录**——所以 1.22.0 的编译与测试状态在 1.23.0 之前是**未证实**的；
下面的逐节复核段因此按当前现状写，一次覆盖 1.22.0 与 1.23.0 两轮 upstream 改动。

1.23.0 这轮（**61 个提交**，命令：`git rebase --onto upstream/main bcb2889 main`）。**4 个文件冲突、停三次**：
① `Sources/Notch/NotchRootView.swift`——upstream 在 `if glassy` 里又套了一层 `if #available(macOS 26.0, *)`，
同时把样式来源从 `model.surfaceStyle` 改名成 `model.drawnSurfaceStyle`、条件收紧成 `if glassy && !dock`；fork 那笔
fallout 照第 1 节的形态处理：删掉 `#available` 包装、只把调用换成 `compatGlassEffect(model.drawnSurfaceStyle, in: Rectangle())`，
**保留 upstream 的新条件与 `headlessGlass` 的 if/else 两层结构**；
② `Sources/Settings/NotchSurfaceStyle.swift`——upstream 新增 `var slabGlass: Glass`、在 `glass` 的 switch 里加了
`.dock`、还新写了一段「`dock` 取 `.regular`」的文档，正好压在 fork 的 `#if swift(>=6.2)` 与它的说明之间 →
文档两边都留，`#if` 继续包住 `glass` **和新的 `slabGlass`**；
③ `Tests/NotchLayoutTests.swift`——upstream 给同一个测试补了 `dock` 的说明并加了 `.dock` 断言 → 取 upstream 的
说明与断言，`#if swift(>=6.2)` 门禁照旧；
④ `Sources/App/AppDelegate.swift` 的 provider 链——upstream 拆出 `remoteProviders`、往链里加了
`GrokBotProvider()` / `MuseLocalProvider()` / `OMLXLocalProvider(endpoint: preferences.omlxEndpoint)` →
保留 fork 的 `+=` 结构与 upstream 的 provider 集合、顺序，`remoteProviders` 在末尾单起一句。
其余 23 个 fork 提交干净落地；`TooltipCard` / `UsageResetCard` / `SettingsHandle` / `MoveHandle` / `UpdateCard` /
`SettingsView` / `UsageStore` / `NotchRenderTests` / `UsageBandTests` / `project.yml` 全部自动合并成功。
`git range-diff bcb2889..backup/pre-rebase-1.23.0 upstream/main..main` 只有那四笔显示内容差异（`Tests/NotchLayoutTests`
那笔被标成 `<`，是 range-diff 按 patch 上下文配不上，`--stat` 与内容都是同一件事）。
**本轮 3 处旧工具链 fallout，合成一笔**（沙箱里第一次真正跑到编译器之后才齐的，见下）：
① Dock 样式的浮起玻璃板——`model.drawnSurfaceStyle.slabGlass` 与 `NotchSurfaceStyle.slabGlass` 都是新符号，
前者落在**非冲突区**、后者与 `.dock` 一起落在自动合并的地方，只有编译期才暴露 → 给 shim 加了 `slab:` 开关；
② `Sources/Sessions/OMLXMetrics.swift`（**1.23.0 全新文件**，不经过冲突）——`Task.detached { [weak self] in … await
MainActor.run { guard let self … } }`，Swift 5.10 报 `reference to captured var 'self' in concurrently-executing code`
→ 内层闭包补 `[weak self]`（同 `LMStudioMetrics` 的形态）；
③ `Tests/RemoteHostsTests.swift`（**1.23.0 全新测试**）——7 处 `var loads/renewals/commands` 被并发闭包捕获，
报 `mutation of captured var … in concurrently-executing code` → 换 `final class Box`（同 `ClaudeOAuthProviderTests`）。
**这三处都不在冲突清单里**：②③ 是新文件，① 是非冲突区段——和 1.19.0 的 `UpdateCard` 是同一类盲点，只有
`make build` 才会报。

1.24.0 这轮（**102 个提交**，命令：`git rebase --onto upstream/main 9e7cd3d main`）。**3 处冲突、停三次**：
① `project.yml`——upstream 往 `CFBundleLocalizations` 追加 `es`，正好紧贴 fork 改的 `LSMinimumSystemVersion`
→ 各留一份（本地化列表取 upstream、版本下限保持 14.3；与 1.15.0 / 1.18.0 / 1.22.0 同一个形态）；
② `Sources/App/AppDelegate.swift` 的 provider 链——upstream 在 `KiloProvider(),` 后面加了 `HiggsfieldProvider(),`
→ 保留 fork 的 `+=` 结构、新 provider 落在同一句里；它**不是** `WebSessionProvider`，所以不进
`webProviders` / `signInItems`（那两个字面量本轮没冲突，仍是 `[deepSeek, qianwen, qoder, xytoken]`）；
③ `Sources/Model/UsageStore.swift` 的 wake 观察者——upstream 把 `refreshNow()` 的返回改成 `Task?`
（`ca6d274`「Refresh all from the menu without closing it」要等那一轮跑完），fork 的 `guard !displayIsAsleep()`
正好落在被改的那一行里 → 两边都留：留 fork 的两行 guard、返回值按新签名写 `_ = self.refreshNow(freshness: .live)`。
其余 31 个 fork 提交干净落地；`SettingsView` / `TooltipCard` / `Info.plist`（只是多了 `es`）/
`Tests/ClaudeProfileTests` / `Tests/NotchLayoutTests` / `Tests/OpenCodeUsageTests` 全部自动合并成功。
`git range-diff 9e7cd3d..backup/pre-rebase-1.24.0 upstream/main..main` 34 笔里只有 **4 笔**显示内容差异：
上面那三笔 + `9074a42` 那笔（§6，`SettingsView` 的文档注释被 upstream 换了措辞，语义未变）；
`git cherry -v upstream/main main` 里重放的那 **34 行全为 `+`**（记账这笔提交之后是 35 行，见「已被 upstream 吸收」）。
**本轮 0 处旧工具链 fallout**——`make build`（`** BUILD SUCCEEDED **`）与 `build-for-testing`
（`** TEST BUILD SUCCEEDED **`）在沙箱内各自一次跑绿，所以**没有** `Fix old-toolchain fallout` 这一笔，
是 1.13.1 之后第一次。原因可查：`git diff --name-only 9e7cd3d upstream/main` 里既没有玻璃调用点文件、
也没有任何 Kimi 文件、更没有 `NotchRenderTests` / `UsageBandTests`。**但这条结论是查出来的、不是猜的**：
空 fallout 也要真的把两次 build 跑完才能说。
沙箱外实测（herdr pane，1m28s）：**2632 个测试、0 失败、33 跳过**；装机 `Scripts/install-app.sh` 装出
**1.24.0 (26)**、ad-hoc、`/Applications` 那份进程正常起来，回读 plist 仍是 14.3 + `SU*` false / false / 空。

macOS 14.3 + Xcode 15.4 上的实测基线：**1.19.0 是 2051 通过 / 11 跳过 / 0 失败；1.23.0 是 2482 个测试、
2455 通过 / 25 跳过 / 0 失败；1.24.0 是 2632 个测试、2599 通过 / 33 跳过 / 0 失败**
（都是 `** TEST EXECUTE SUCCEEDED **`；1.23.0 那次是 2026-10-20 复跑确认，中途那 2 条失败是「显示器几何」，
见第 7 节；1.24.0 那次 2026-10-26 跑在 herdr pane 里、沙箱外）。
**1.24.0 的 33 比 25 多出的那 8 个是 `FullScreenAutoFoldTests`**——指针停在 notch 区域时
`skipIfPointerOnNotch` 让整组跳过，本机跑测时鼠标正停在屏幕顶部中央；**构成本身没变**
（9 个 opt-in live check + 16 个玻璃/dock，逐条数过），所以**要盯的依旧是「0 failures」，不是具体数字**。
跑之前把指针挪离屏幕顶部中央，数字才和上一轮可比。
（1.10.0 是 1387，1.11.0 首发 1531/4，1.11.0 同步后 1566/5，1.12.0 1575/5，1.13.1 是 1603/5，1.15.0 是 1666/5，
1.16.0 是 1736/8，1.18.0 是 2038/11，1.19.0 是 2051/11，1.22.0 没记账，1.23.0 是 2482/25，1.24.0 是 2632/33。）
25 个跳过的构成（从 `xcresult` 逐条抄下来的）：**9 个 opt-in live check**（Amp、Apify、Devin、LM Studio、Muse、
OMLX 活动、OMLX 日志、Ollama 列表、`TooltipRenderTests.testLiveClaudeResetCard`）加 **16 个玻璃/dock 相关**
——其中 4 个是 fork 自己加的门禁（`NotchRenderTests.testTheFoldedPillIsTransparentInTheGlassStyle` +
`PaletteAppearanceTests` 3 个，见第 7 节），另外 12 个是 upstream 自己就带门禁的（1.23.0 新增的
`DockStyleGeometryTests` 7 个、`NotchRenderTests` 里 4 个 dock/暗玻璃渲染、`PanelSizingIntegrityTests` 1 个），
**全都在 macOS 26 以下跳过，不需要 fork 再加任何门禁**。测试总数会随 upstream 增长——整文件新增（`FullScreenAutoFoldTests`、
`SpinningArcTests`、本轮 oMLX / Muse / RemoteHost 那几组）是常见来源——**要盯的是「0 failures」，不是具体数字**。
**这一轮的编译是在 pi-sandbox 里跑通的，测试跑不了**——这件事本身值得单独记，因为踩了六个坑、每个都不是改路径能解决的。
先说要放行什么（`~/.pi/agent/sandbox.json`，本机现状，`--reload` 或重启 pi 后生效）：

```jsonc
{
  "permissionPromptTimeoutSeconds": 0,   // 可选：构建中途被 600s 提示超时打断很难受
  "allowPty": true,                      // 否则 xcodebuild 报 Pseudo Terminal Setup Error
  "filesystem": {
    "allowWrite": [
      "/private/var/folders", "/var/folders",              // Foundation 的 confstr 临时目录（忽略 TMPDIR）
      "~/Library/Developer/Xcode/DerivedData",             // DerivedData / LogStore / ModuleCache / SourcePackages
      "~/Library/Caches/org.swift.swiftpm",                // SPM 缓存（离线解析靠它）
      "~/Library/Preferences", "~/Library/Application Support",  // 测试宿主 App 的 UserDefaults 与数据目录
      "/Applications"
    ]
  },
  "network": {
    "allowMachLookup": [
      "com.apple.FileCoordination", "com.apple.ProgressReporting",
      "com.apple.testmanagerd", "com.apple.testmanagerd.control", "com.apple.dt.xctestd.target",
      "com.apple.CARenderServer", "com.apple.windowserver.active", "com.apple.windowserver",
      "com.apple.CoreDisplay.master", "com.apple.cfprefsd.agent", "com.apple.cfprefsd.daemon",
      "com.apple.lsd.open", "com.apple.lsd.modifydb", "com.apple.tccd", "com.apple.trustd.agent"
    ]
  }
}
```

六个坑，按踩到的顺序：
1. **`com.apple.FileCoordination` 不给，任何目录的原子写都失败**：`Foundation` 的 `NSData.writeToFile:options:.atomic`
   走 `NSFileCoordinator`，服务不在白名单时在**工作区、`/tmp` 里都报 EPERM**（`xcodegen` 写 `project.pbxproj`、
   `xcodebuild` 写 `LogStoreManifest.plist` 就是这么栽的）。这条最容易误判成「路径没放行」。
2. **SwiftPM 的 manifest 沙箱要嵌套 `sandbox-exec`，而嵌套在 pi-sandbox 里必然失败**
   （`sandbox-exec: sandbox_apply: Operation not permitted`，`enableWeakerNestedSandbox` 在 macOS 上是空操作）。
   绕法是把 SwiftPM 的 manifest 沙箱关掉：`defaults write xcodebuild IDEPackageSupportDisableManifestSandbox -bool YES`
   （撤销：`defaults delete xcodebuild IDEPackageSupportDisableManifestSandbox`）。`XBS_DISABLE_SANDBOXED_BUILDS=1`
   同时带上——它管的是 xcbuild 的**构建**沙箱，同样要嵌套 `sandbox-exec`。
3. **`Pseudo Terminal Setup Error`** → `allowPty: true`（runtime 会补 `(allow pseudo-tty)` 与 `/dev/ptmx`、`/dev/ttys*`）。
4. **`Sparkle.xcframework` 缺失**：SwiftPM 那次解包只写了一半（`artifacts/sparkle/Sparkle/` 里有 `bin/`、`LICENSE`，
   没有 xcframework），而它认这个状态、不会重解包。手动从 `~/Library/Caches/org.swift.swiftpm/artifacts/` 里那份官方
   zip `unzip` 进去即可。
5. **测试执行要 LaunchServices**：`xcodebuild test` 用 `IDELaunchServicesLauncher` 启动测试宿主，沙箱里报
   `-10822 kLSServerCommunicationErr`。该路径需要 `(allow lsopen)`，runtime 把它和 `coreservicesd`、
   quarantine-resolver 一起挂在 `allowAppleEvents` 下，而 **pi-sandbox 没有透传这个键**（只透传
   `allowPty` / `allowBrowserProcess` / `enableWeakerNestedSandbox` 等）——所以 **`make test` 没法在沙箱里跑**，
   除非去改 `~/.pi/agent/npm/node_modules/pi-sandbox/src/sandbox-runtime.ts` 加一行 `allowAppleEvents: config.allowAppleEvents,`
   （改 node_modules，`pi`/npm 升级会冲掉）。
6. 顺带：`log` 在沙箱里直接拒绝运行（`log: Cannot run while sandboxed`），所以**沙箱违规没法用 `log stream` 自证**——
   只能靠报错文案反推（`-10822`、`Error 159 - Sandbox restriction`、`Operation not permitted`）。

于是沙箱内能守住的验证上限是：

```sh
# 1) 完整构建（含 xcodegen、Debug 编译、DEV_RESIGN）：实测 exit 0、** BUILD SUCCEEDED **
XBS_DISABLE_SANDBOXED_BUILDS=1 make build

# 2) 测试包编译（抓 fallout 用这个最省：不跑测试，只编 app + 测试目标）
XBS_DISABLE_SANDBOXED_BUILDS=1 xcodebuild -project Codenotch.xcodeproj -scheme Codenotch \
  -destination 'platform=macOS,arch=arm64' -configuration Debug \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Automatic build-for-testing
# 期望 ** TEST BUILD SUCCEEDED **（1.23.0 这轮就是这样跑绿的，抓到了本轮 3 处 fallout）
```

**测试本身要在沙箱外的终端跑**（`make test` 会在这里停在 `-10822`）：

```sh
make test                 # 期望 0 failures
Scripts/install-app.sh    # 装到 /Applications，并确认进程真的起来
```

**你这个环境里的实操办法（agent 自己也能跑）**：用 herdr 开一个 pane——它跑在用户的终端里、不受 pi 沙箱限制：

```
herdr_layout pane_split                    → 拿到 pane id（如 w15:p2）
herdr_pane  run   "<cmd> > /tmp/agents/x.log 2>&1; echo TAG_EXIT=$?"
herdr_pane  wait_output  match='TAG_EXIT=[0-9]+' regex=true timeout=1800000
```

`wait_output` 的 match 要设成**只匹配回显命令之外的输出**（`TAG_EXIT=$?` 会跟着命令一起回显，
所以用 `regex` 锚定 `=[0-9]+$`，别用 `TAG_EXIT=` 这种前缀）。1.23.0 这轮的 `make test`（1m27s）与
`Scripts/install-app.sh`（1m45s）都是这样跑完并拿到结果的。

**这一轮「0 failures」是实测过的**（2482/25/0，见上）。下一轮仍要盯两类只在 `make test` 现形的东西：
upstream 的 CI 跑在 **`macos-26`**（`.github/workflows/ci.yml` 的 `runs-on`），它的格式化/百分比断言在旧 Foundation
上可能算出别的字符串（1.18.0 的 `ApifyUsage.money` 就是这样）；另外 **鼠标位置会影响跳过数**——upstream 的
`FullScreenAutoFoldTests.skipIfPointerOnNotch` 在指针停在 notch 区域时会让 8 个测试跳过（本轮就见过 25 与 33
两个不同的跳过数，失败数不受影响）。跑之前把指针挪离屏幕顶部中央，数字才可比。
1.13.1 这轮 `Scripts/install-app.sh` 装出 **1.13.1 (16)**、ad-hoc 签名，`/Applications` 那个进程正常起来。
1.15.0 这轮 `Scripts/install-app.sh` 装出 **1.15.0 (18)**、ad-hoc 签名，`/Applications` 那个进程正常起来；
实测回读那份 plist：`LSMinimumSystemVersion` = 14.3、`SU*` 三项为 false / false / 空（见第 4 节）。
1.16.0 这轮 `Scripts/install-app.sh` 装出 **1.16.0 (19)**、ad-hoc 签名（脚本最后那行也如实印出
`ad-hoc (no certificate in the keychain)`——它本轮修过一处 SIGPIPE 导致的空签名显示，见第 2 节），
`/Applications` 那个进程正常起来；
实测回读那份 plist：`LSMinimumSystemVersion` = 14.3、`SU*` 三项为 false / false / 空（见第 4 节）。
1.18.0 这轮 `Scripts/install-app.sh` 装出 **1.18.0 (20)**、ad-hoc 签名，`/Applications` 那个进程正常起来；
实测回读那份 plist：`LSMinimumSystemVersion` = 14.3、`SU*` 三项为 false / false / 空（见第 4 节）。
1.19.0 复核：跳过的 11 个**构成一个没变**（6 个 opt-in live check + 玻璃 5 个），总数多出来的 13 个
全是 upstream 的功能测试；`NotchRenderTests` 那两行 `XCTSkipUnless` 自动合并干净、继续留。
1.19.0 这轮 `Scripts/install-app.sh` 装出 **1.19.0 (21)**、ad-hoc 签名，`/Applications` 那个进程正常起来。
本轮值得记一笔：upstream 把 updater 改成**启动时就起**（以前只有打开设置页才起），于是 Sparkle.framework
现在真的会被 dyld 加载进进程——实测 `vmmap` 在那份进程里能看到 `Sparkle.framework/Versions/B/Sparkle`，
与第 2 节里「ad-hoc + hardened runtime 会让 dyld 拒绝加载」的老经验不同（本轮的 ad-hoc 签名没有
hardened runtime 位，`codesign -dv` 只印 `flags=0x2(adhoc)`）。实测回读那份 plist：`LSMinimumSystemVersion` = 14.3、
`SU*` 三项为 false / false / 空（见第 4 节）。

1.23.0 这轮的安装验证（2026-10-20，沙箱外跑完）：`Scripts/install-app.sh` 装出 **1.23.0 (25)**、
`Installed /Applications/Codenotch.app — version 1.23.0 (25), signed ad-hoc (no certificate in the keychain).`，
`pgrep -x Codenotch` 有 PID（进程真的起来了）。实测回读那份 plist：`LSMinimumSystemVersion` = 14.3、
`SUEnableAutomaticChecks` = false、`SUAutomaticallyUpdate` = false、`SUFeedURL` 为空；`codesign -dv` 印
`flags=0x2(adhoc)`、`Signature=adhoc`（**没有 hardened runtime 位**），`vmmap <pid>` 里 `Sparkle.framework`
命中 4 处——updater 仍在启动时就起，与 1.19.0 那条结论一致。Dock 样式是本轮唯一新加的玻璃表面，macOS 14
上它按 `solid` 落地（`effective` 的既有回退），装机后没有额外要看的。

## 1. macOS 14.3 部署目标与 SDK shim

**为什么存在**：见上。upstream 的 `deploymentTarget` 是 15.0，本机要在 14.3 上跑。

**涉及文件**

- `project.yml`：`deploymentTarget: 14.3`、`projectFormat: xcode15_0`
- `Sources/Info.plist`：`LSMinimumSystemVersion` = 14.3
- `Sources/Compatibility/MacOS26Shims.swift`：`compatGlassEffect(_ style: NotchSurfaceStyle,
  in:interactive:slab:)`、`compatPointerStyle(active:)`。`slab:` 是 1.23.0 加的，对应 upstream 的
  `slabGlass`（Dock 样式浮起那块玻璃板），见下
- `Sources/Settings/NotchSurfaceStyle.swift`：`var glass: Glass` **与 `var slabGlass: Glass`（1.23.0 起）**连同
  它们的文档整段在 `#if swift(>=6.2)` 里（理由见下）
- `Tests/NotchLayoutTests.swift`：唯一比较 `glass` 值的那个测试同样在 `#if swift(>=6.2)` 里
- 调用点（1.23.0 起，**9 个 `compatGlassEffect` + 1 个 `compatPointerStyle`**，与 upstream 的
  9 个 `glassEffect` + 1 个 `pointerStyle` 一一对应）：`SettingsView`（2：`glassBackground(in:)` 与
  `AccountRow` 的指针）、`NotchRootView`（2：dock 的 slab 与 `notchCopy` 的面板）、`MoveHandle`、
  `SettingsHandle`（2）、`TooltipCard`、`UsageResetCard`、`UpdateCard`

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

同一个理由也意味着**新属性同样要进 `#if`**：1.23.0 的 Dock 样式让 `NotchSurfaceStyle` 多了一个
`var slabGlass: Glass`（`.clear.tint(Palette.dockGlassTint)`），它与 `glass` 用同一道门禁。调用点那边的
写法也一样——**不写 `Glass`**：shim 因此多了一个 `slab: Bool = false` 参数，
`compatGlassEffect(model.drawnSurfaceStyle, in: DockSlab(…), slab: true)` 读的是 `style.slabGlass`，
而不是在调用点拼一个 `Glass` 值。加新变体时照这个形态扩参数，别把 `Glass` 泄回调用点。

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
1.13.1 复核：upstream 这轮同样没新增 `glassEffect` / `pointerStyle` 调用点，grep 仍干净；它碰了
`Sources/Features/TooltipCard.swift` 与 `Sources/Notch/NotchRootView.swift`（都是
`resetCredits` → `hasAvailableResetCredits` 那几行），与 fork 的玻璃调用点不在同一区段，自动合并干净。
六个调用点、shim、`#if swift(>=6.2)` 的两条边界原样，本轮没有旧工具链 fallout。
1.15.0 复核：upstream 这轮同样没新增 `glassEffect` / `pointerStyle` 调用点，grep 仍干净（只剩注释行）。
但它**删掉了两处玻璃表面**：侧栏从玻璃卡换成扁平的 `SettingsPalette.sidebar` + hairline，
`collapsedSidebarToggle`（那个玻璃圆盘）连同 `sidebarToggle`、`SidebarIcon` 一起被删。fork 在这两处的
`compatGlassEffect` 替换因此失去对象，rebase 时取 upstream、不再加回（SettingsView 为此冲突两次，
见「rebase 流程与验证基线」）。`NotchSurfaceStyle.glass` 上游**仍未**自带门禁，fork 的
`#if swift(>=6.2)` 与 shim 原样需要；五个 notch/feature 调用点与 `SettingsView` 的
`glassBackground(in:)` 全部照旧，本轮没有新增 fallout。
1.16.0 复核：upstream 这轮新增了**一处** `glassEffect` 调用点——`TooltipCard` 里 tooltip 的那层
玻璃（`UsageResetCard` 是同一处的旧行改写），grep 仍只剩注释，说明 fork 把它换成了 `compatGlassEffect`。
它同时改了那两处玻璃的**内容**：尾偏移从 `tailOffset` 换成 `clampedTailOffset`（`Refine Liquid Glass
tooltip contrast` 那轮的尾钳制），铺在玻璃下面的 wash 从 `surfaceStyle.glassDim` 换成
`TooltipGlassContrast.dim(surfaceStyle:colorScheme:reduceTransparency:)`（`.glass` 在深色下现在也要一层
可读性 wash，不再只有 `.darkGlass`）。两处都在冲突里按「取 upstream 的新内容、只换调用」处理。
**于是「wash 留在调用点」这句话要分开看**：notch 面板（`NotchRootView` 2 处）与两个 orb
（`MoveHandle` / `SettingsHandle` 各 2 处）仍是 `surfaceStyle.glassDim`；两个 tooltip 改用
`TooltipGlassContrast.dim(...)`。两者都不进 shim——shim 只管 `glassEffect` 本身。
`NotchSurfaceStyle.glass` 上游仍未自带门禁，fork 的 `#if swift(>=6.2)` 与 shim 原样需要；
六个 notch/feature 调用点与 `SettingsView` 的 `glassBackground(in:)` 全部照旧。
1.18.0 复核：upstream 这轮**没有新增** `glassEffect` / `pointerStyle` 调用点，grep 仍干净（只剩 shim 自身与
注释行）。它现在共 **9 处**——`MoveHandle` 2、`SettingsHandle` 2、`TooltipCard` 1、`UsageResetCard` 1、
`NotchRootView` 1、`SettingsView` 的 `glassBackground(in:)` 1 与 `AccountRow` 的 `pointerStyle` 1——与 fork 的
9 处 `compat*` **一一对应**，所以本轮没有因调用点而产生的 fallout。`NotchRootView` 这轮被 upstream 大改
（+288/-69，notch 与硬件凹口合并/分离那套重做），但 `headlessGlass` 的 if/else 结构仍在（第 194 行），
那句「保留 upstream 的 if/else、只换 else 分支里的调用」继续成立；那处自动合并干净。
`NotchSurfaceStyle.glass` 上游依旧只有 `@available`、没有自带门禁，fork 的 `#if swift(>=6.2)` 与 shim 原样需要。
**顺带记一笔**：`glassBackground(in:)` 在 upstream 自己那儿**没有调用点**（1.15.0 把玻璃侧栏换成扁平配色后留下的
孤儿，1.16.0 起就是如此，本轮也没被删）。它没有调用点但仍在源码里参与编译，所以照旧要走 shim；
哪天 upstream 把它删掉，这里就少一处，不必找替代。

upstream 自己的 `.background { if let dim = surfaceStyle.glassDim { … } }`（暗色玻璃底下的那层 wash，
只是个 `Color`）**留在调用点**，不搬进 shim。

NotchRootView 多一层：upstream 新加了 `if headlessGlass { … } else { … }`（像素测试要「走玻璃路径、
但没有材质」的那一层）。**保留 upstream 的 if/else 结构**，只把 else 分支里的 `glassEffect` 换成
shim——不要像上一轮那样把整块压成一次调用，压掉就丢了 headless 路径。

1.19.0 复核：upstream 这轮新增了**一处**调用点（全新文件 `Sources/Features/UpdateCard.swift`，notch 里的更新卡），
同时**删掉了两处**——旧的 `struct MoveHandle` 整个没了（它的两个玻璃分支随 struct 一起消失，换成 `enum MoveHandle`
的几何 + `MoveGrip` 的新代码）。于是总数仍是 **upstream 8 处 `glassEffect` + 1 处 `pointerStyle`，与 fork 的
**8 处 `compatGlassEffect` + 1 处 `compatPointerStyle` 一一对应**：`MoveHandle` 由 2 变 1（新代码里的
`MoveGrip.glassDots`）、`UpdateCard` 由 0 变 1，其余六处位置不变。两处新调用点**都不在冲突区里**——
（`UpdateCard.swift` 是新增文件、根本不会冲突；`MoveGrip.glassDots` 落在 `MoveHandle.swift` 里自动合并的那部分——
那个文件另有冲突，但不在这一处），只有 `make build` 才报 `value of type 'some View' has no
member 'glassEffect'`——这正是「新文件不冲突」那条盲点，见「旧工具链编译错误的常见形态」。
`NotchSurfaceStyle.glass` 上游依旧只有 `@available`、没有自带门禁，fork 的 `#if swift(>=6.2)` 与 shim 原样需要。

1.22.0 + 1.23.0 复核（一次跑完两轮，因为 1.22.0 那轮没记账）：grep 仍只剩注释与 shim 自身，调用点
**9 + 1，与 upstream 一一对应**。两轮合计新增 **4 处**、删除 **2 处**、改名 **1 个来源**：
① `MoveHandle` 那处随 1.22.0 的「六颗点」落成 `MoveGrip.glassDots`（已在 1.19.0 那轮处理完）；
② 1.22.0 把 `surfaceStyle` 改名为 `drawnSurfaceStyle`（**只改名字**，shim 不看这个），`NotchRootView` 两处
调用点跟着改名；③ 1.23.0 的 **Dock 样式**新增两处：`notchCopy` 之外多了一层「slab 玻璃」（
`model.drawnSurfaceStyle.slabGlass` + `DockSlab`，落在**非冲突区**，见下）与 `NotchSurfaceStyle.slabGlass`；
`if glassy` 的条件也跟着收紧成 `if glassy && !dock`（**取 upstream**，dock 的玻璃由 slab 那层负责）。
④ 1.22.0 的 `SettingsView` 里 `pointerStyle` 与 `glassBackground(in:)` 都还在原位。
`NotchSurfaceStyle.glass` / `slabGlass` 上游**依旧**只有 `@available`、没有自带门禁，fork 的 `#if swift(>=6.2)`
与 shim 两处都还需要。**新增的 `#available` 包装仍要删**：1.23.0 给 `NotchRootView` 的两处玻璃
（panel 与 slab）都套了 `if #available(macOS 26.0, *)`，fork 的形态是「删包装、换 `compat*`」，
`headlessGlass` 的 if/else 结构与 `if glassy && !dock` 的条件都保留。

1.24.0 复核：upstream 本轮**一个玻璃调用点都没碰**——`git grep -c 'glassEffect\|pointerStyle' 9e7cd3d` 与
`upstream/main` 的清单**逐行相同**（限定 `-- '*.swift'` 时 10 个文件、同一批行号；不加限定会多出一行 `TASKS.md` 里提到这个名字的文字），`git diff --name-only 9e7cd3d upstream/main`
里也没有 `NotchRootView` / `NotchSurfaceStyle` / `SettingsView` 的任何一处玻璃。fork 侧仍是
**9 个 `compatGlassEffect` + 1 个 `compatPointerStyle`**，一一对应原样；`NotchSurfaceStyle.glass` /
`slabGlass` 上游**依旧**只有 `@available`、没有自带门禁，fork 的 `#if swift(>=6.2)` 继续留。
本轮新增的 11 个 Swift 源文件（菜单栏那七件 + Higgsfield 四件）里**没有一个**用 `glassEffect` /
`pointerStyle`，所以编译期零 fallout——**这正是本轮第一次不需要 fallout 提交的原因**。

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
1.13.1 复核：`Makefile` 与 `Scripts/install-app.sh` 都没进 upstream 本轮的改动集，上段格局原样；
本轮装出 1.13.1 (16)、ad-hoc，`/Applications` 那个进程起来了。
1.15.0 复核：`Makefile` 与 `Scripts/install-app.sh` 都没进 upstream 本轮的改动集，上段格局原样；
本轮装出 1.15.0 (18)、ad-hoc，`/Applications` 那个进程起来了。
1.16.0 复核：`Makefile` 与 `Scripts/install-app.sh` 都没进 upstream 本轮的改动集，上段格局原样；本轮装出
1.16.0 (19)、ad-hoc，`/Applications` 那个进程起来了。**本轮发现并修掉了脚本自己的一处小毛病**：脚本最后
那行「signed …」在 ad-hoc 下印成空的——`codesign -dv "$APP" 2>&1 | grep -q 'Signature=adhoc'` 在
`set -o pipefail` 下，`grep -q` 一匹配就退出，`codesign` 吃到 SIGPIPE（**实测退出码 141**），整条管道
因此判为失败，于是走 else 分支，而它 sed 的 `Authority=` 在 ad-hoc 签名里本来就不存在。现在先把
`codesign -dv` 的输出读进一个变量再判断，第一行也在 `sed` 内部取（`| head -1` 有同一个坑）。签名本身
一直是对的——`codesign -dv` 直接读仍是 `Signature=adhoc`——修完重跑脚本，那行现在印的是
`signed ad-hoc (no certificate in the keychain)`。
1.18.0 复核：上一段的格局原样。`Scripts/` 整个目录**没进** upstream 本轮的改动集；`Makefile` 进了，但落在
`archive` 与 `build-ci` 两块（`make dmg` / `dmg-ci` 从 `hdiutil` 换成 create-dmg 加背景图），与 fork 的
`DEV_SIGN` / `DEV_RESIGN` / `install` 不相邻，两边都留、自动合并干净。本轮装出 **1.18.0 (20)**、ad-hoc，
`/Applications` 那个进程起来了。
**顺带记一笔（不影响这条路径）**：那两处新逻辑各自开头加了 `command -v create-dmg`，而本机**没装** create-dmg
（`which create-dmg` 为空）——所以 `make dmg` / `make dmg-ci` 现在会在这里停下并提示 `brew install create-dmg`。
`make install` / `Scripts/install-app.sh` 不碰这两个目标，装机和验证都不受影响。
1.19.0 复核：`Scripts/` 与 `Makefile` 整个**没进** upstream 本轮的改动集，格局原样；本轮装出 **1.19.0 (21)**、
ad-hoc，`/Applications` 那个进程起来了——**顺带验了一条老经验**：upstream 把 updater 改成启动时就起，于是
Sparkle.framework 这次真的进了进程（`vmmap` 能看到），说明本轮的 ad-hoc 签名没有 hardened runtime 位
（`codesign -dv` 只印 `flags=0x2(adhoc)`），上面那句「dyld 拒绝加载 Sparkle」在这里不成立。
但是——既然 updater 现在会被起，而 fork 的 `SUFeedURL` 是空的，**下一轮若 upstream 再动 `AppDelegate` 的
updater 启动，值得顺手看一眼 `log stream` 里有没有 Sparkle 的报错**（本轮没看到异常）。

1.22.0 + 1.23.0 复核：`Scripts/install-app.sh` 两轮都没进 upstream 的改动集；`Makefile` 只被 1.22.0 碰过
（`make dmg` / `dmg-ci` 那一带，与 fork 的 `DEV_SIGN` / `DEV_RESIGN` / `install` 不相邻，自动合并干净），
1.23.0 完全没碰。格局原样，**但这两轮的装机和进程启动都还没验过**——沙箱里跑不了
`Scripts/install-app.sh`（要写 `/Applications` 与 `$HOME`），见「rebase 流程与验证基线」里那段说明。
装机时顺手要看的还是那条老经验的反面：1.19.0 起 updater 在启动时就起，fork 的 `SUFeedURL` 是空的，
所以 1.23.0 新增的「在 notch 里问 Update / Later」（`UpdateCard`）在 fork 里应当**完全不可达**——装上以后
若看到那个红点或更新卡，说明 `SUFeedURL` / `SUEnableAutomaticChecks` 被谁改回去了（见第 4 节）。
1.24.0 复核：`Scripts/` 与 `Makefile` 这一轮**又都没进** upstream 的改动集（`git diff --name-only 9e7cd3d
upstream/main | grep -E 'Makefile|Scripts/'` 为空），格局原样。1.23.0 那轮欠的装机验证**这轮补上了**：
`Scripts/install-app.sh` 装出 **1.24.0 (26)**，脚本自己印 `signed ad-hoc (no certificate in the keychain)`，
`pgrep -x Codenotch` 拿到 PID；`codesign -dv` 仍是 `flags=0x2(adhoc)` / `Signature=adhoc`（没有 hardened runtime 位），
回读 plist 为 14.3 + `SU*` false / false / 空——上面那条「`UpdateCard` 应当不可达」的前提照旧成立。

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
1.13.1 复核：同样只改版本号（`1.13.1` / `16`），`packages:` 段与 `Package.resolved` 都没动
（`git diff --name-only 3251208 upstream/main -- Package.resolved` 为空），pin 仍是 swift-nio 2.86.2。
1.15.0 复核：同样只改版本号（`1.15.0` / `18`），`packages:` 段与 `Package.resolved` 都没动
（`git diff --name-only bcd063c upstream/main -- Package.resolved` 为空），pin 仍是 swift-nio 2.86.2。
1.16.0 复核：同样只改版本号（`1.16.0` / `19`），`packages:` 段与 `Package.resolved` 都没动
（`git diff --name-only ec1a7e3 upstream/main -- Package.resolved` 为空），pin 仍是 swift-nio 2.86.2。
1.18.0 复核：同样只改版本号（`1.18.0` / `20`），`packages:` 段与 `Package.resolved` 都没动
（`git diff --name-only 784985e upstream/main -- Package.resolved` 为空，`project.yml` 的 diff 里也不含 `packages:`
上下文行），fork 的 `from: "2.86.0"` 与解析结果 swift-nio 2.86.2 原样落地。
1.19.0 复核：同样的形态——只改版本号（`1.19.0` / `21`），`packages:` 段与 `Package.resolved` 都没进 upstream 的
改动集（`git diff --name-only 07ba1db upstream/main -- Package.resolved` 为空），fork 的 `from: "2.86.0"` 与解析结果
swift-nio **2.86.2**（`revision` `a18bddb0acf7`）原样落地。

1.22.0 + 1.23.0 复核：`Package.resolved` **两轮都没进** upstream 的改动集
（`git diff --name-only bcb2889 upstream/main -- Package.resolved` 为空）；`project.yml` 的 `packages:` 段也没动
（diff 里没有该上下文行）。fork 的 `from: "2.86.0"` 与解析结果 swift-nio **2.86.2**（`revision` `a18bddb0acf7`）
原样落地——不过这一轮**没在真机上解析过一次**：`make gen` 在沙箱里写不了临时目录，解析这一步要等
沙箱外第一次 `make build` 才重新验证（若那时报 3 节顶部那条 tools-version 错，说明 pin 又被盖掉了）。
1.24.0 复核：`Package.resolved` **这一轮同样没进** upstream 的改动集
（`git diff --name-only 9e7cd3d upstream/main -- Package.resolved` 为空），`packages:` 段也没有进
（`project.yml` 的 diff 只有版本号两行与 `es` 那一行）。上一段欠的「沙箱外真机解析」这次也补上了：
沙箱内 `make build` 跑完了 `xcodegen generate` + `cp Package.resolved`，没有出现 3 节顶部那条
tools-version 错，说明 pin 仍压得住。

## 4. 关闭 Sparkle 自动更新

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
1.13.1 复核：三项键值依旧未变，`Sources/Info.plist` 也没进 upstream 的改动集；装出来的 1.13.1 里
`SUEnableAutomaticChecks=false`、`SUFeedURL` 为空（实测回读 `/Applications` 那份 plist）。
1.15.0 复核：三项键值依旧未变（upstream 这轮**动了** `Sources/Info.plist`，但只往 `CFBundleLocalizations`
里加了 `zh-Hant`，`SU*` 三行没进它的改动集）；装出来的 1.15.0 里 `LSMinimumSystemVersion` = 14.3、
`SUEnableAutomaticChecks=false`、`SUFeedURL` 为空（实测回读 `/Applications` 那份 plist）。
1.16.0 复核：三项键值依旧未变（`Sources/Info.plist` 本轮**完全没进** upstream 的改动集）；装出来的 1.16.0 里
`LSMinimumSystemVersion` = 14.3、`SUFeedURL` 为空、`SUEnableAutomaticChecks` / `SUAutomaticallyUpdate`
均为 false（实测回读 `/Applications` 那份 plist）。
1.18.0 复核：**upstream 这轮动了 `Sources/Info.plist`**，但只往 `CFBundleLocalizations` 加了 `id` / `ko` /
`uz` / `tr` 四行（`project.yml` 的同一份列表也跟着改了，`uz` / `tr` 正好紧贴 fork 的 `LSMinimumSystemVersion`，
所以 `project.yml` 那里真冲突了——本地化列表取 upstream、版本下限保持 14.3，见「rebase 流程与验证基线」）。
`SU*` 三行没进它的改动集，本地依旧 false / false / 空；装出来的 1.18.0 实测回读：`LSMinimumSystemVersion` = 14.3、
`SUFeedURL` 为空、`SUEnableAutomaticChecks` / `SUAutomaticallyUpdate` 均为 false。
1.19.0 复核：**upstream 这轮改了键值，而且是往 fork 的方向改**——它把 `SUAutomaticallyUpdate` 从 `true` 改成
`false`（`project.yml` 与 `Sources/Info.plist` 两处都改：`git diff 07ba1db upstream/main -- Sources/Info.plist` 只有这一行），
理由是新的「新版本在 notch 里问」流程——它的 commit message 写着 *Never downloads unasked*。于是一分为二：

- `SUAutomaticallyUpdate: false` **两边现在一致**：fork 那笔提交的后半截等于被 upstream 吸收了（`cherry` 仍显示 `+`，
  因为整笔还含另外两键——与「已被 upstream 吸收」小节里 Claude filter 那条同一类，只能人工看）。
- fork 真正独有**只剩两处**：`SUEnableAutomaticChecks: false` 与 `SUFeedURL: ""`（外加那段说明注释）。
  `SUEnableAutomaticChecks` upstream 仍是 `true`，所以要继续压住。

冲突的成因也随之清楚：`project.yml` 里 upstream 在 `SUEnableAutomaticChecks: true` 下方插了一段注释，正好紧贴 fork
改成 `false` 的那行 → 值取 fork、注释取 upstream（它讲的是它下面那行 `SUAutomaticallyUpdate: false`，两边现在都成立）。
**代价这一轮要记清楚**：1.19.0 新增的「更新在 notch 里问（`UpdateCard`）、自己写 Sparkle user driver、updater
启动时就起」这套**在 fork 里完全不会出现**——`SUFeedURL` 为空意味着 appcast 永远取不到，`SUEnableAutomaticChecks: false`
又关掉了定时检查，所以那个红点、Update / Later、安装进度都只是死代码。这正是 fork 的意图（永不替换），不必回退；
**判断依据没变**：`SUEnableAutomaticChecks` / `SUFeedURL` upstream 只要还是 `true` / 有地址，本地就继续 `false` / 空；
`SUAutomaticallyUpdate` 既然 upstream 自己也关了，fork 不必再改它——**下轮这里会更干净**（只剩两键）。
装出来的 1.19.0 实测回读：`LSMinimumSystemVersion` = 14.3、`SUFeedURL` 为空、
`SUEnableAutomaticChecks` / `SUAutomaticallyUpdate` 均为 false。

1.22.0 + 1.23.0 复核：**`SU*` 三行两轮都没进 upstream 的改动集**——1.22.0 动过 `Sources/Info.plist`（新加
`NSAppTransportSecurity`，插在 fork 改的 `LSMinimumSystemVersion` 下方，只挤动了上下文，`SU*` 没碰），
1.23.0 **完全没碰** `Sources/Info.plist`（`git diff --name-only bcb2889 upstream/main -- Sources/Info.plist` 为空）。
`project.yml` 这边，1.22.0 只碰版本号，1.23.0 同样只碰版本号（`1.23.0` / `25`），fork 的
`SUEnableAutomaticChecks: false` + `SUFeedURL: ""` + 那段注释原样落地。所以上一段那句「下轮这里会更干净」
成立：这一轮 `SU*` 段**一次都没冲突**，只剩两键要压。装机实测（2026-10-20）：`LSMinimumSystemVersion` = 14.3、`SUEnableAutomaticChecks` = false、
`SUAutomaticallyUpdate` = false、`SUFeedURL` 为空——细节见「rebase 流程与验证基线」的安装段。
1.24.0 复核：`Sources/Info.plist` 这一轮**进了**改动集，但只有一行——`CFBundleLocalizations` 多一个 `es`
（`git diff 9e7cd3d upstream/main -- Sources/Info.plist` 就是 `+<string>es</string>`），`SU*` 三键与
`LSMinimumSystemVersion` 都没被碰；`project.yml` 这边只改了 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
（`1.24.0` / `26`）并追加同一行 `es`。fork 的 `SUEnableAutomaticChecks: false` + `SUFeedURL: ""` + 注释原样落地，
`SU*` 段又一次没冲突。装机实测（2026-10-26）：14.3 / false / false / 空，与上轮一致。

## 5. XyToken provider（fork 独有功能）

**为什么存在**：XyToken 的用量在网页会话里，refresh cookie 是 HttpOnly 且每次调用都轮换，
所以「刷新 + 查询」必须在 App 自己的 WKWebView 里带着用户登录态跑。

**涉及文件**

- `Sources/Providers/Sites.swift`：`static let xytoken`（紧挨着 upstream 的 `static let deepSeek`），
  并声明窗口角色 `headlineID: "day:1"` / `weeklyID: "week:1"`（`rule_key` 里 `|` 之前的稳定半段，
  见下面的「外观配置同步规则」）
- `Sources/Providers/XyTokenUsage.swift`、`Tests/XyTokenUsageTests.swift`
- `Sources/App/AppDelegate.swift`：`webProviders` 里注册

**外观配置同步规则（每次 rebase 都要顺带看一眼）**：设置-外观里有一批配置**不是**对所有 provider
自动生效的——它们要么按 id 解析 provider 声明的窗口角色（`ProviderSnapshot.headlineID` / `weeklyID`），
要么要窗口自带 `duration` / `resetsAt`。xytoken 的窗口 id 是 `rule_key` 里 `|` **之前**的稳定半段
（`day:1` / `week:1`；`|` 之后是重置排程，会随重置日变——见 `XyTokenUsage.windowID`），所以
upstream 新增或改动这类配置时，**回来检查 xytoken 是否也要同步声明**：

- 依赖 `weeklyID` 的（xytoken 声明它之前一律**静默不生效**）：「每周圆环」（内/外，`preferences.weeklyRing`）、
  「虚线每周圆环」、「圆环读数含每周」、「每周限额作为主圆环」，以及 `UsageLimitWatcher` 的周限额提醒
  （开关在设置-通知里：`announceWeeklyLimitReached`）；
- 依赖「窗口到没到顶」的（1.23.0 新增，读 `headline` 与 `weeklyLimitWindow` 的 `usedFraction`，
  **同样要那两个角色**）：`shutRingsWhenSpent`（任一窗口耗尽就把两个环都关掉，默认开）、
  `hideDepletedAccounts`（`ProviderSnapshot.isDepleted`，默认关）——xytoken 两个角色都声明了，**无需再加**；
- 对所有 provider 通用、只读窗口自身数值、与角色声明无关：1.23.0 的 `showsRemainingInNotch`（读剩余而非已用）
  与 `autoOrderByRemaining`（按剩余排序）、`busyIndicatorStyle`（工作指示器动画）；
- **菜单栏「显示每周限额」对 xytoken 结构性不适用**：`StatusItemSummary.canSummarise` 要求 5 小时窗口
  或 Claude/Codex（`isFiveHourFamily`），xytoken 的 day / week 都不满足——声明 `weeklyID` 只是前向兼容，
  哪天菜单栏放宽这条限制它才会自动可用；
- 依赖窗口字段的：`showUsagePace`（要 `duration`，1.12.0 已补）、`resetTimeFormat`（要 `resetsAt`，
  `window_end` 已映射）；
- 对所有 provider 通用、不必同步：每个圆环下方百分比（`showsNotchReadings`）、颜色过渡 / 观察限额 /
  临界限额，以及 notch 本体外观（可见性 / 边缘 / 尺寸 / 折叠 / 显示器 / 表面 / 移动手柄）；
- provider 专属、与 xytoken 无关：Claude 日节奏环（`claudeDailyPaceRing`）、Spark 和代码评审
  （`showCodexExtraLimits`）。

判据：**先看新配置的消费点读什么**——若读的是 provider 声明的数据（窗口角色 id、`duration`、
`resetsAt`、`plan`），就回到 `Sites.swift` 的 `static let xytoken` 与 `XyTokenUsage` 看要不要补，
并在 `Tests/XyTokenUsageTests.testSiteWindowRolesResolveToTheParsedWindows` 里钉住（该测试断言 site
声明的 id 能在 parser 实际产出的窗口 id 里解析到——它比的是 site 声明与 fixture，所以站台单独改
`rule_key` 不会让它红：按「维护」第 8 条先拿线上真实响应更新 fixture，它就会先红，不必等 App 里周环
悄悄消失才发现）。

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
1.13.1 复核：`Sites.swift` 依旧没进 upstream 的改动集；`AppDelegate` 的 provider 组装现在只差本节这
三处注册——原先 Claude 的那处 filter 本轮已删除（见「已被 upstream 吸收的本地改动」）。
1.15.0 复核：upstream 这轮**碰了**两个文件。`Sites.swift` 是纯追加（新增 `static let qianwen`，正好插在
fork 的 `xytoken` 之前），自动合并成功、各一份；`AppDelegate` 则真冲突了——upstream 把 `qianwen` 加进
`webProviders` 与 `signInItems`，与 fork 的 `xytoken` 落在同一个列表字面量里，两边都留，结果是
`let webProviders = [deepSeek, qianwen, xytoken]` 与
`fleet.signInItems = [deepSeek, miniMaxWeb, qianwen, xytoken]`（qianwen 的 `onAuthenticated` 那处
upstream 单独加，与 fork 不相邻，自动合并干净）。
1.16.0 复核：两个文件都**没进** upstream 本轮的改动集，三处注册原样（`let webProviders =
[deepSeek, qianwen, xytoken]`、`fleet.signInItems = [deepSeek, miniMaxWeb, qianwen, xytoken]`、
`Sites.swift` 的 `static let xytoken`）。真正的变动在别处：upstream 给 provider 组装加了
`customProviders`（自定义端点，见 `preferences.customEndpoints`），fork 的注册与它互不相邻，
自动合并干净。这也是本轮那处类型检查超时的由来——链上又多了一项（见「旧工具链编译错误的常见形态」）。
1.18.0 复核：upstream 这轮**碰了** `Sites.swift`，但改动落在 `qianwen` 那个 site 的定义**内部**（给它补上
`headlineID: "week"` / `weeklyID: "week"`，第 266 行附近），与 fork 的 `static let xytoken`（第 338 行）隔着几十行，
自动合并干净、各一份、无重复定义。`AppDelegate` 的三处注册原样在页：`let webProviders: [WebSessionProvider] =
[deepSeek, qianwen, xytoken]`、`fleet.signInItems = [deepSeek, miniMaxWeb, qianwen, xytoken]`、以及 `xytoken` 的构造。
本轮 `AppDelegate` 真冲突的是同一个组装里的 provider 链（upstream 加了 `AmpProvider` / `ApifyProvider` /
`KiloProvider`，见「冲突热点」）——那是与本节不同的区段，注册这部分自动合并干净。那三个新 provider 都是
`UsageProvider` actor、各有自己的 `signInRoute`（Amp / Apify / Kilo 都是 `.guidance`——在终端里跑各自的登录命令，
**没有**走本轮新的 `.command`），**不是** `WebSessionProvider`，
所以 `webProviders` 这个列表不需要再加东西。
1.19.0 复核：upstream 这轮**没碰** `Sites.swift`（`git log --oneline 07ba1db..upstream/main -- Sources/Providers/Sites.swift`
为空），三处注册原样：`let webProviders: [WebSessionProvider] = [deepSeek, qianwen, xytoken]`、
`fleet.signInItems = [deepSeek, miniMaxWeb, qianwen, xytoken]`、`xytoken` 的构造。`AppDelegate.swift` 本轮 upstream 改了
（updater 改成启动时就起），但落在 `applicationDidFinishLaunching` 那段，与注册不同区段——fork 侧只剩那三处
加上 `+=` 拆解，`git diff upstream/main HEAD -- Sources/App/AppDelegate.swift` 一眼可核。

1.22.0 复核：upstream 这轮**碰了** `AppDelegate`（`qoder` 这个新的 `WebSessionProvider`），`Sites.swift` 没碰
（`git diff --name-only 0083369 bcb2889 -- Sources/Providers/Sites.swift` 为空）。注册两处跟着 upstream 各加一项：
`let webProviders: [WebSessionProvider] = [deepSeek, qianwen, qoder, xytoken]`、
`fleet.signInItems = [deepSeek, miniMaxWeb, qianwen, qoder, xytoken]`；`qoder` 的 `onAuthenticated` 与
`preferences.$qoderRegion` 两个 sink 是 upstream 自己加的，与 fork 不相邻，自动合并干净。
1.23.0 复核：upstream 这轮**没碰** `Sites.swift`，两处注册原样（`[deepSeek, qianwen, qoder, xytoken]` 与
`[deepSeek, miniMaxWeb, qianwen, qoder, xytoken]`）。`AppDelegate` 这轮的真冲突是 provider 链（见上一段与
「冲突热点」），与注册不同区段。**本轮新增的 provider 与 fork 无关**：`MuseLocalProvider`、`OMLXLocalProvider`
是 `UsageProvider`（各有自己的 endpoint 设置），远程主机那条是 `preferences.remoteHosts.map { $0.makeProvider() }`
（`RemoteClaudeProvider` / `RemoteCodexProvider`，走 SSH）——都不是 `WebSessionProvider`，`webProviders` 不用动。
「外观配置同步规则」照上面的清单看过一遍：1.23.0 的四个新开关里有两个要窗口角色，xytoken 两个角色都已声明，
**本轮不需要给 xytoken 补任何声明**。
1.24.0 复核：`Sites.swift` **依旧没被 upstream 碰**（`git diff --name-only 9e7cd3d upstream/main | grep -i sites` 为空），
两个注册字面量原样——`AppDelegate` 这轮又冲突了一次，但冲突点仍在 provider 链（`HiggsfieldProvider()`），
`webProviders` / `signInItems` 自动合并干净。**本轮新 provider 同样与 fork 无关**：`HiggsfieldProvider` 是
`actor: UsageProvider`（`.command` 登录路由、有 `account()`），**不是** `WebSessionProvider`，所以不进这两个列表，
fork 的归类（§6「借用本地凭证的都算 true」）也不需要为它加分支。
**1.24.0 还带来一条「看着像新消费面、其实与 fork 无关」的**：菜单栏面板（`MenuUsageCard` 等七个新文件）
读的是另一套摘要，`StatusItemSummary.canSummarise`（`Sources/App/StatusItemSummary.swift:68`）只收
「有五小时窗口、或属于 Claude / Codex 家族」的 provider，而 xytoken 的窗口是 `day:1` / `week:1`，
**进不了菜单栏**。`Sites.xytoken` 里那句注释（The menu bar is out of reach either way）在 1.24.0 依然成立，
所以本轮**不需要**为它补任何角色声明；哪天 xytoken 有了五小时窗口，这条才要重看。

本节本地演进（**非 rebase**）：给 `static let xytoken` 补上窗口角色 `headlineID: "day:1"` /
`weeklyID: "week:1"`，使外观面板里依赖 `weeklyID` 的那组配置（每周圆环、虚线每周圆环、圆环读数含每周、
每周限额作为主圆环、周限额提醒）对 XyToken 生效——此前它们对它静默不生效。菜单栏那条不算：它对 xytoken
结构性不适用（见上面的「外观配置同步规则」）。

XyToken 的登录态修复（**非 rebase**，1.23.0 之后）：站点把 refresh 升级成会话绑定的轮换
（`X-Auth-Session` / `409 AUTH_REFRESH_RACE` / `AUTH_SESSION_MISMATCH`，登录会话还有数量上限），
而 `static let xytoken` 当时是**没有 `authProbeScript` 的两个站点之一**（另一个是 Perplexity，同样的问题还没动）：
`signInSheetDidOpen()` 在窗口刚打开（还停在登录页）就把 `hasSignedIn` 置 true，此后任意一次抓取
（闲置 5 分钟 / 看环 15 秒 / 开设置 / Refresh now）都会拿到 401 把它清回 false；登录成功后没有任何
路径置回 true（`windowWillClose` 的最终确认要求站点有 probe）。表象就是「登录了还是未登录、必须再点一次」。
修法沿用 deepseek/qianwen 的模式：`authProbeScript`（调 `/refresh`，用 `data.session.sid` 当
fingerprint）+ `pollsDuringSignIn: true`，并在 `AppDelegate` 接上 `onAuthenticated` →
`providerAuthenticationChanged` 以便登录后立刻出数。同一笔改动里把 bearer token 缓存到页面全局
（`window.__codenotchXyToken`，按 `access_expires_at` 过期），因为 access_token 有 15 分钟而闲置抓取是
5 分钟一次——少掉的轮换就是少掉的和页面自身 refresh 撞车的机会；缓存 token 撞 401 时会先换一次再判定掉线，
避免把「会话真没了」和「缓存 token 恰好过期」混为一谈。401/403 现在会带 `AUTH_*` 响应体写进
`Log.usage.error`（此前该分支在记录 body 之前就 throw，掉线在日志里没有痕迹）。

紧接着的一次真机掉线把上面的判断修了一半（**仍是非 rebase**）：日志里不是 `AUTH_UNAUTHORIZED`，而是
`AUTH_SESSION_REVOKED`——服务端明说这条会话被**撤销**，不是到期；同一账号在 Edge 里一周不掉，说明寿命/
空闲/会话上限都不是原因，被撤的只是"我们这个客户端"这条会话。与浏览器唯一的实质差别是刷新姿势：浏览器
页面首次 bootstrap 之后，每次 `/refresh` 都带 `X-Auth-Session: <session.sid>`，而我们的脚本体永远不带，
还每 15 分钟刷一次——站台的轮换契约（`AUTH_REFRESH_RACE`/`AUTH_SESSION_MISMATCH`）本来就是给"同一 cookie
上有多个客户端"准备的。所以 `Site.script` 补成照站台客户端的样子：记下 `data.session.sid` 并在后续刷新里
带回去，`409 AUTH_REFRESH_RACE` 隔 150ms 重试一次、`409 AUTH_SESSION_MISMATCH` 丢掉 sid 退回 bootstrap，
`401/403` 清掉 token 与 sid；整段包 `try/catch` 返回 `status: 0` + `script error: …`（崩溃/睡眠后
`fetch` 被拒以前只留一句"发生了JavaScript异常"，看不出是哪一层）；refresh 成功时把
`session.created_at / last_active_at / expires_at` 塞进 envelope，由 `WebSessionProvider` 记成
`session -> …` 一行。另外 `fetch script failed` / `response unreadable` 现在会把 `isLoaded` 置 false，
下一次先重载页面——真机日志里 08:22–10:02 连续 5 次失败正是"往同一个卡住的 WebView 里反复发"。
**判据记住：`needsAuth` 这行现在带站点自己的 `code`，先看它再猜原因。**

带 sid 的版本上线后仍然在 10-22 掉了一次（约 22.7 小时后），说明 sid 不是全部原因。于是补上最后一件可对接的
东西：响应的 `X-Request-Id`。脚本把每次响应头里的 id 带进 envelope，失败行是
`needsAuth: HTTP 401 request=XY… {body}`，成功刷新的 `session ->` 行末尾也带 `request=XY…`。站台自己的
请求日志能按这个 id 查到 IP/UA/触发了哪条撤销分支——**这是 App 侧唯一够不着的证据**，下次掉线先拿 id，
再谈假设。id 本身前 16 位是 UTC 时间戳（`XY` + `yyyyMMddHHmmss`），没有服务端日志时也能先定位到分钟。

再往后一次掉线（10-25，登录后约 48.8–53.5h）拿到了完整时间线，方向又变了一次，**并且这次动到了
upstream 的文件**：`pmset -g log` 显示 12:57:00 那次成功刷新和"Entering Sleep"同一秒，之后 4h50
只有每次 2 秒的 DarkWake、App 一个请求都没发，17:47:01 的 DarkWake 里第一次联系服务端就拿到
`401 AUTH_SESSION_REVOKED`（request id `XY20261025094703…`）。10-21 那次形状完全一样。但**"DarkWake 里
刷新后立刻睡"本身不是充分条件**：同一条会话在 04:30/06:09/07:18/11:55 都做过同样的事且活了下来，
所以别把它当成已证实的因果。据此在 `Sources/Model/UsageStore.swift` 加了一条**通用**规则（不是 xytoken
专属）：`displayIsAsleep`（默认 `CGDisplayIsAsleep(CGMainDisplayID()) != 0`，测试可注入）为真时
`tick()` 和 `didWake` 都不抓取，`lastAttempt` 不动——屏幕亮起来后的第一个 tick 直接补一次。理由有二：
屏幕灭着没人看；以及一个网页会话不该在系统挂起前几秒花掉一次 cookie 轮换。**rebase 注意**：
`UsageStore.swift` 是冲突热点，这条改动在 `tick()` 开头和 `wakeObserver` 闭包里，上游改这两处时两边都留。

**踩过的坑（务必记牢）**：第一版直接拿整个 `rule_key` 当窗口 id，而且照抄了测试 fixture——fixture
自述「rewrites ids」、把 `rule_key` 也改成了 `week:1|day:1,00:00`，于是**测试全绿、线上却失配**。线上每周窗口
的真实 id 是 `week:1|week:MON 00:00`，`weeklyID` 匹配不上 → `weeklyWindow` 为 nil → 周环与周读数都不画
（主环的 `day:1|day:00:00` 恰好是真值，所以只有每周那半失效）。现在窗口 id 取自 `rule_key` 里 `|` 之前的
稳定半段（`XyTokenUsage.windowID`，排程不进 id），fixture 也改回线上真实的 `rule_key`，并新增
`testWindowIDIsTheStableHalfOfTheRuleKey` 钉住「排程不进 id」。**教训：核对 provider 数据以线上真实响应为准，
fixture 只保证它自己内部一致。**

另外，声明 `headlineID` 后主环不再回退 `windows.first`——站台若连 `rule_key` 前半段也改了，主环留白、
周弧消失（与所有声明角色的 provider 一致，见 `QianwenUsage`）。kimi / opencode 未动；测试
`testSiteWindowRolesResolveToTheParsedWindows` 钉住 site 声明与 parser 产出一致。清单与判据见上面的
「外观配置同步规则」。

## 6. 浏览器会话 provider 的登录提示修复

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
1.13.1 复核仍是**上游没修**：upstream 这轮确实改了 `SettingsView.swift`（keychain 文案与 `Deny` 语义），
但改的是另外几段；`grep -rn needsSignIn Sources/` 命中的仍是 fork 的三处，upstream 侧只有
`needsSignInRenewal`。本地版本继续留着——它与 `Deny` 语义不冲突：`Deny` 让 `account()` 那条路走到
`accessDenied`，本节处理的是「浏览器会话 provider 本来就取到了用量」的那条路。
1.15.0 复核仍是**上游没修**：`grep -rn needsSignIn Sources/` 命中的仍是 fork 的三处，upstream 侧只有
`needsSignInRenewal`。upstream 这轮把 Settings 面板整体重做（`SettingsView.swift` +598 行），但 fork 的
两处读取（`isSetUp`、`AccountRow` 的 `!provider.needsSignIn` 分支）都干净落地，说明它改的是别处的
结构。本地版本继续留着。
1.16.0 复核仍是**上游没修**：`grep -rn needsSignIn Sources/` 命中的仍是 fork 的三处，upstream 侧只有
`needsSignInRenewal`。但本轮 `UsageStore.swift` **真冲突了**——upstream 给 `ProviderSummary` 加了
`customIconFilename:`（自定义端点的图标），正好落在 fork 那段「读一次 `account()` 并传 `needsSignIn:`」
的中间。处理：取 upstream 的新参数与 fork 的共享 `account` 变量、保留 `needsSignIn:` 那一行，参数顺序按
`ProviderSummary` 的声明（`glyph` → `customIconFilename` → `account` → …）。`ProviderAccount.swift` 与
`SettingsView.swift` 自动合并干净，两处读取（`isSetUp`、`AccountRow` 的 `!provider.needsSignIn` 分支）原样。
1.18.0 复核仍是**上游没修**：`grep -rn needsSignIn Sources/` 命中的仍全是 fork 的（`ProviderAccount.needsSignIn`
的声明、`UsageStore` 的 `needsSignIn(_:account:)` 与它的调用点、`SettingsView` 的两处读取），upstream 侧只有
`needsSignInRenewal`。但本轮 upstream 给 `SignInRoute` **加了第四个 case**——`case command(String, name:
install:)`（CLI 账号的登录按钮：在新终端里跑那个工具自己的登录命令），而 fork 的 switch 是穷尽的、没有 `default`，
**于是编译直接失败**（`switch must be exhaustive`）。注意这个文件是**自动合并干净**的、没有任何冲突标记，只有
`make build` 才会报出来——所以「冲突都解完」不等于「能编」。
处理：`.command` 并入 `.openApp, .guidance` 那一支，判据就是本节的原文——**它同样借用本地凭证**，`account()`
找不到就是未登录，所以总是要提示登录；`.modal`（浏览器会话）那支不收它。**这一条不是可有可无的**：kimi 本轮正好
从 `.guidance` 改成 `.command`（见第 8 节），漏掉它就会把 kimi 的登录提示一起弄丢。
**归类为什么是安全的**：走 `.command` 的 provider（`KiroProvider`、`GitHubCopilotProvider`、`OpenCodeProvider`、
`GrokLocalProvider`、`KimiProvider`、`CodexLocalProvider`、`ClaudeOAuthProvider`）**都实现了 `account()`**，所以登录好之后
`account()` 非空、不会一直催。（判据：`grep -rln '\.command(' Sources/Providers/` 再逐个看有没有 `func account()`。）
下次 upstream 若再加一个 `.command` provider 而**它没有 `account()`**，这条归类就得重新想——那种 provider 会永远
提示登录。
`UsageStore` 与 `ProviderAccount` 本轮都没进 upstream 的改动集，上面那处是本节唯一的改动；`SettingsView` 的两处
读取（`isSetUp`、`AccountRow` 的 `!provider.needsSignIn` 分支）自动合并干净、原样保留。
1.19.0 复核仍是**上游没修**：`grep -rn needsSignIn Sources/` 命中的仍全是 fork 的（`ProviderAccount.needsSignIn` 的
声明、`UsageStore.needsSignIn(_:account:)` 与调用点、`SettingsView` 的两处读取），upstream 侧只有 `needsSignInRenewal`。
upstream 本轮**没有再给 `SignInRoute` 加 case**（仍是 1.18.0 那四个：`.modal` / `.openApp` / `.guidance` / `.command`），
所以 fork 的穷尽 switch 原样编过——本轮没有这一形态的 fallout。**穷尽 switch 是每轮都要过的关**：
`UsageStore` 与 `ProviderAccount` 本轮都没进 upstream 的改动集，但下一轮很可能进，别因为连着没事就放宽这条判据。

1.22.0 + 1.23.0 复核仍是**上游没修**：`grep -rn 'needsSignIn\b' Sources/` 命中的仍是 fork 的三处
（`ProviderAccount.needsSignIn` 的声明、`UsageStore.needsSignIn(_:account:)` 与调用点、`SettingsView` 的两处读取），
upstream 侧只有 `needsSignInRenewal`。两轮都**没有**再给 `SignInRoute` 加 case（仍是 `.modal` / `.openApp` /
`.guidance` / `.command` 四个），所以 fork 的穷尽 switch 原样成立——**但这条判据这一轮没能靠编译器确认**
（沙箱里编不了），下次在沙箱外 `make build` 时留意 `switch must be exhaustive` 就是这一形态的复发。
`UsageStore.swift` 1.22.0/1.23.0 都进过 upstream 的改动集（1.22.0 的 `ProviderSummary` 一带、1.23.0 的
`ResetCopy` 格式化器缓存），但都自动合并干净；`ProviderAccount.swift` 两轮都没进。
**1.23.0 新增 provider 的归类核对**（每个都自己声明 `signInRoute`，照上面的判据逐个看）：
`GrokBotProvider` / `MuseLocalProvider` 是 `.guidance`、远程那两个（`ClaudeRemoteProvider` / `CodexRemoteProvider`，
经 SSH）也是 `.guidance`，四个**都实现了 `account()`**，与 `.openApp, .guidance, .command` 归 true 那支自洽；
`OMLXLocalProvider` 是 `.openApp` 但**没有 `account()`**，于是它会一直显示登录提示——**这与 upstream 自己的行为一致**
（upstream 在 `account == nil` 时同样摆出登录引导），fork 的归类没有让它更糟，所以不必改。哪天 upstream 给 OMLX 补上
`account()`，这里就自然恢复正常。

1.24.0 复核仍是**上游没修**：`grep -rn 'needsSignIn\b' Sources/` 命中的仍是 fork 的那五处
（`ProviderAccount.needsSignIn` 的声明、`UsageStore.needsSignIn(_:account:)` 与调用点、`SettingsView` 的两处读取），
upstream 侧只有 `needsSignInRenewal`。`SignInRoute` **仍然只有那四个 case**（本轮 `.command` 没加第五个），
所以穷尽 switch 原样编过——**而且这次是靠编译器确认的**：`make build` 与 `build-for-testing` 都跑了，
没有 `switch must be exhaustive`。`UsageStore.swift` 这轮**进了** upstream 的改动集（`refreshNow` 改成返回 `Task?`），
但撞上的是 fork 的 wake 观察者、不是 `needsSignIn` 那条路径，见「冲突热点」；`ProviderAccount.swift` 没进。
**1.24.0 新增 provider 的归类核对**：`HiggsfieldProvider` 是 `.command("hf auth login", name: "Higgsfield", install: …)`
且**实现了 `account()`**（`HiggsfieldCredentials.isPresent` 为真才非空），与「借用本地凭证的都归 true」自洽，
不用为它加分支。这也是第 1.18.0 段那条告警的又一次正面样本：**`.command` + 有 `account()` ＝ 安全**。

## 7. 玻璃样式测试在 macOS 26 以下跳过

**为什么存在**：upstream 新增的 `NotchRenderTests.testTheFoldedPillIsTransparentInTheGlassStyle`
假定 Liquid Glass 存在。macOS 14.3 上 `NotchSurfaceStyle` 会把 glass 样式解析成纯色，
该断言不可能成立——纯色下 pill 本来就是不透明的，旁边的兄弟测试钉的正是这个行为。

**涉及文件**：`Tests/NotchRenderTests.swift`、`Tests/UsageBandTests.swift`（两处都是
`XCTSkipUnless(NotchSurfaceStyle.glassAvailable, …)`）。

1.16.0 起还有**第二类**：`Tests/UsageBandTests.swift` 的 `PaletteAppearanceTests` 里三个比较
Liquid Glass 对比度的测试（`testOnlyDarkStandardLiquidGlassGetsReadableSecondaryInk`、
`testOnlyDarkSystemLiquidGlassGetsTheReadableDim`、`testReadableLiquidGlassDimStaysDarkAndTranslucent`）。
它们断言 `TooltipGlassContrast` 在 `.glass` / `.darkGlass` 下的取值，而 macOS 26 以下
`NotchSurfaceStyle.effective` 把这两个风格都解析成 `.solid` → `needsReadableDim` 只能是 false、
`dim(...)` 只能是 nil。upstream 这几个测试本来是 `skip`，本轮 `de5fbde` 改成直接断言（它的环境是
macOS 26），所以在旧系统上必然红。**这三个门禁不是 fork 的功能改动**，删掉的条件同下：upstream 自己
给它们加 `glassAvailable` 门禁（或改成 `#available` 自跳过）时，本地这三行就该删。

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
1.13.1 复核：upstream 这轮碰了 `Tests/NotchRenderTests.swift`，但改的是 `StaleAfterMarginTests` 的
`staleAfter` 余量（0.45 → 3，怕 CI 负载把断言压垮），没碰这个玻璃测试，本地那行继续留；实测跳过
仍是 5 个。
1.15.0 复核：upstream 这轮没碰 `NotchRenderTests.swift`，本地那行继续留；它碰的是
`Tests/NotchLayoutTests.swift`（26 行），fork 在那里 `#if swift(>=6.2)` 里的 glass 比较测试自动合并干净。
实测跳过仍是 5 个。
1.16.0 复核：upstream 这轮**碰了** `Tests/NotchRenderTests.swift`（+42/-18），但改的是 `testHidingClearsBothHolds`
那几个（`Hiding` 相关的两个 hold），fork 那行 `XCTSkipUnless` 自动合并干净、继续留。新出现的是上面第二类：
`Tests/UsageBandTests.swift` 本轮被 upstream 加了三个玻璃对比度测试，三个都加了门禁，实测跳过从 5 变成 8
（3 个 opt-in live check + `NotchRenderTests` 2 个 + `PaletteAppearanceTests` 3 个）。
1.18.0 复核：upstream 这轮**又碰了** `Tests/NotchRenderTests.swift`（+158）与 `Tests/UsageBandTests.swift`（+82），
但改动落在别处（`NotchRenderTests` 的 hunk 在 817 / 955 / 972 行，`UsageBandTests` 的在 33 行往后的新增
`testRamp*` 那几支），fork 的 4 行 `XCTSkipUnless`（`NotchRenderTests` 1 + `UsageBandTests` 3）一处都没被碰、自动合并
干净、继续留。上面那三个对比度测试
upstream **依旧没有门禁**（`git show upstream/main:Tests/UsageBandTests.swift` 里 grep 不到 `glassAvailable`），
所以本地那三行照旧需要。实测跳过从 8 变成 11，但**多出来的 3 个全是 opt-in live check**（本轮新增的 Amp、
Apify 与 `testLiveClaudeResetCard`），玻璃那 5 个一个没变——本轮没有新的适配要加。

1.22.0 + 1.23.0 复核：upstream 两轮都动过这两个测试文件，但**门禁一处都没被碰**，fork 的 4 行
`XCTSkipUnless`（`NotchRenderTests` 1 + `UsageBandTests` 3）自动合并干净、继续留；
`testTheFoldedPillIsTransparentInTheGlassStyle` 在 upstream 1.23.0 里**仍然没有门禁**（仍是 `func …()`、无 `throws`）。
**1.23.0 有一处新变化要记**：`UsageBandTests` 里现在出现了 `if NotchSurfaceStyle.glassAvailable { … }`——那是**另一个**
测试里内联包住 `.dock` 那一段断言用的，不是给我们这三个测试加门禁
（`git show upstream/main:Tests/UsageBandTests.swift | grep -c glassAvailable` 是 1，不是 3），所以**本地那三行照旧需要**。
跳过的数量这一轮**没法在沙箱里实测**——测试执行要在 LaunchServices 下启动宿主，沙箱里过不去
（`-10822`，见「rebase 流程与验证基线」）。
1.24.0 复核：upstream 这轮**一个玻璃门禁文件都没碰**（`git diff --name-only 9e7cd3d upstream/main | grep -E
'NotchRenderTests|UsageBandTests|NotchEdgeTests'` 为空），fork 的 4 行 `XCTSkipUnless` 原样；那三个
`PaletteAppearanceTests` 与 `testTheFoldedPillIsTransparentInTheGlassStyle` 在 upstream 里**依旧没有门禁**。
这一轮的跳过数终于**在沙箱外实测到了**：`make test` 是 2632 个测试 / 2599 通过 / **33 跳过** / 0 失败，
逐条对下来构成没变（9 opt-in + 16 玻璃/dock），多出的 8 个是 `FullScreenAutoFoldTests` 的「指针停在 notch 上」，
见「rebase 流程与验证基线」的基线段。玻璃门禁**一行都不用加**。

**1.23.0 起还有第三类，和玻璃无关：显示器几何**。`Tests/NotchRenderTests.swift` 里两个测试
（`EdgeCrossfadeTests.testItComesBackOnTheNewEdgeAtFullStrength` 与
`EverySizeSettingAppliesEverywhereTests.testTheSizeSettingSurvivesTheHardwareEdge`）在**本机实测直接红**
（2026-10-20 第一次在沙箱外跑 `make test`：**2482 个测试、2455 通过、25 跳过、2 失败**——失败的就这两个；
跳过数从 1.19.0 的 11 涨到 25，构成还没逐条核对，其中既有本轮新增的 opt-in live check，也应有「本机缺某个 CLI/
显示器」那类），
根因是 upstream 默认了「解析出来的屏幕 = 面板落到的屏幕」：

- 前者在断言时重新调 `NotchGeometry.preferredScreen(from: NSScreen.screens)`（内部走 `NSScreen.main`），
  而 `NSScreen.main` 在**没有窗口的测试宿主**里不稳定 → 期望 982（外接屏，位于内建屏上方）、实际 0（内建屏），
  也就是断言在比较两块不同的屏幕。改成**从面板自身的位置反推它在哪块屏幕上**
  （`NSScreen.screens.first { $0.frame.contains(面板中点) }`），再比较两者的 `minY`。
- 后者用 `guard NSScreen.screens.contains(where: { $0.hardwareNotch != nil })` 只保证**某块**屏有刘海，
  但 notch 采纳的是 `NSScreen.main` 那块（本机是外接屏）→ `cutout` 为 nil → `mergedScale` 为 nil。
  改成把显示偏好钉到有刘海那块——**直接赋值 `controller.displayPreference = .display(identifier)`**，
  不能用 `apply(displayPreference:)`（它会 `relocate()`）。

两处都**不是行为改动**，只是让前提成立，因此没有加 `XCTSkipUnless`——那会在这台机器上永久跳过，而这台机器
恰恰是唯一需要验证的机器。判据不变：upstream 若自己把这两个测试改成不依赖 `NSScreen.main`，本地这两处就该删。
1.24.0 复核：upstream 这轮**没碰** `Tests/NotchRenderTests.swift`，fork 那两处（第 772 行按面板中点反推屏幕、
第 1244 行直接赋值 `displayPreference = .display(identifier)`）原样在页；`make test` 在**接了外接屏的本机**上
0 失败，说明这两处仍然成立——**上游没修，本地继续留**。

**修这两条时踩到的坑，值得记**：`relocate()` 会创建 panel（`NotchWindowController` 第 391 行），而
`apply(edge:)` 只有在**还没有 panel** 时才同步设 `model.edge`；panel 一旦存在，它就走 0.16s 淡出、
在 **completion 里**才把 edge 改掉。测试不 run loop，edge 就永远不变 → `adopt()` 仍按旧 edge 算 →
`cutout` 为 nil → `mergedScale` 为 nil。第二轮失败正是这么来的（我给测试加的 `apply(displayPreference:)`
先 relocate 了一次，把这条同步路径变成了异步路径）。所以这类测试里设显示偏好必须**直接赋值**
`controller.displayPreference = …`，不要调 `apply(displayPreference:)`。

## 8. Kimi OAuth token 自主续期

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
3. 与 Claude 的取舍无关（它已经回到 upstream 的形态，见「已被 upstream 吸收的本地改动」）：Claude 是
   刷新一次管八小时，Kimi 的只有十五分钟，后者每 13 分钟起一个 node 进程不划算，而 `kimi login`
   还会顺带重写 `config.toml`。

1.11.0 同步复核：**上游没修**。信号那条 grep 干净——`oauth/token` / `refresh_token` 只出现在 fork 的
`KimiTokenRefresher.swift` 和 fork 改过的 `KimiCredentials.swift` 里；upstream 的 `KimiProvider` 仍然
只读凭证，`fetchSnapshot()` 里没有任何写回或 401 重取的动作。这一整笔提交继续留着。
1.12.0 复核：**上游仍未修**。`KimiProvider.swift` / `KimiCredentials.swift` 都没进 upstream 本轮的
改动集，信号 grep 仍只命中 fork 的那两个文件。
1.13.1 复核：**上游仍未修**。`KimiProvider.swift` / `KimiCredentials.swift` 都没进 upstream 本轮的改动集
（它只动了 `KimiActivityMonitor.swift`：`17287c5` 让工作目录匹配不再碰磁盘），信号 grep 仍只命中
fork 的那两个文件。
1.15.0 复核：**上游仍未修**。`KimiProvider.swift` / `KimiCredentials.swift` 都没进 upstream 本轮的改动集
（它只动了 `KimiActivityMonitor.swift`），信号 grep（`oauth/token` / `refresh_token`）仍只命中 fork 的
那两个文件。
1.16.0 复核：**上游仍未修**。upstream 本轮**一个 Kimi 文件都没碰**（`git diff --name-only ec1a7e3
upstream/main | grep -i kimi` 为空），信号 grep 仍只命中 fork 的 `KimiTokenRefresher.swift` 与
`KimiCredentials.swift`。这一整笔提交继续留着。
1.18.0 复核：**上游仍未修**。upstream 这轮**碰了三个 Kimi 文件**（`KimiProvider.swift`、`KimiUsage.swift`、
`Tests/KimiUsageTests.swift`），但都不是续期这件事：`KimiProvider` 只改了 `signInRoute`（`.guidance` → 新的
`.command("kimi", name: "Kimi", install: …)`，见第 6 节），`KimiUsage.row` 改成「`used` 缺失时用 `limit - remaining`
反推」（读数据的宽容度，与凭证无关）；`KimiProvider` 里仍只有 `status == 401 || 403 → throw needsAuth`，
没有任何写凭证或 401 后重取的动作。信号 grep（`oauth/token` / `refresh_token`）仍只命中 fork 的
`KimiTokenRefresher.swift` 与 `KimiCredentials.swift`；fork 的 `fetchSnapshot()` 里那句 `refresher.usableCredential()`（第 44 行）
原样在页，与 upstream 改的 `signInRoute` 不同区段，自动合并干净。
这一整笔提交继续留着。**注意新形态**：`KimiProvider` 现在是「upstream 改一处、fork 改另一处」的共享文件，
下轮 rebase 别再默认它整文件是 fork 的。
1.19.0 复核：**上游仍未修**，而且这轮**一个 Kimi 文件都没碰**（`git diff --name-only 07ba1db upstream/main | grep -i kimi`
为空）——`KimiProvider` 因此自动合并干净，`fetchSnapshot()` 里那句 `refresher.usableCredential()` 原样在页，
这一整笔继续留着。

1.22.0 复核：**上游仍未修**。`KimiProvider.swift` / `KimiCredentials.swift` 都进了 upstream 那 91 个提交的改动集，
但都不是续期这件事：`KimiProvider` 改的是文档注释（fork 那笔把它重写过，两边的措辞不同 → 该笔因此"变了形"，
见「rebase 流程与验证基线」的 1.22.0 段），`KimiCredentials` 一侧仍只有读、没有写。`fetchSnapshot()` 里那句
`refresher.usableCredential()`（现在在第 44 行）原样在页。
1.23.0 复核：**上游仍未修**，而且这轮**一个 Kimi 文件都没碰**（`git diff --name-only bcb2889 upstream/main | grep -i kimi`
为空）——`KimiProvider` 自动合并干净，那一整笔继续留着。
**信号 grep 的基线这一轮变了**，记下来免得下次误判：`grep -rn "oauth/token\|refresh_token" Sources/Providers/`
现在**除了 fork 的两个文件还会命中 upstream 自己的 `GrokLocalProvider.swift` 与 `GrokCredentials.swift`**——
1.23.0 让 Grok 第一次拿到「access token 过期就自己刷新」的能力。但它**只在内存里**用新 token
（`renewed = (minted.accessToken, minted.expiresAt, refreshToken)`，没有写回任何文件、也没动 `~/.grok` 下的凭证），
与 fork 的 Kimi 做法（照着 CLI 的私有协议**写回**、还要抢 CLI 的锁）不是一回事。所以信号 grep 要按文件看：
**上游若开始往 Kimi 的凭证文件里写、或在 401 后重取，才算它修了同一件事**；Grok 命中不算。

1.24.0 复核：**上游仍未修**，而且这轮**又一个 Kimi 文件都没碰**（`git diff --name-only 9e7cd3d upstream/main
| grep -i kimi` 为空）——`KimiProvider` 自动合并干净，`fetchSnapshot()` 里那句 `refresher.usableCredential()`
原样在页（第 44 行），这一整笔继续留着。
**信号 grep 的基线这轮又宽了一点**：`grep -rln "oauth/token\|refresh_token" Sources/Providers/` 现在命中
`KimiCredentials` / `KimiTokenRefresher`（fork 的那两个）、`GrokLocalProvider` / `GrokCredentials`（1.23.0 起），
**外加 `AntigravityCredentials`**——1.24.0 让它自己做 token 刷新（那个文件里就换了新的 `AntigravityCredentials` 返回，**只在内存里用**，与 Grok 同类；`grant_type=refresh_token` 与
`payload.refresh_token` 都在那个文件里）。判据不变：**上游往 Kimi 的凭证文件里写、或 401 后重取，才算修了同一件事**；
Grok 与 Antigravity 命中都不算。下次复核先按文件看，别再被命中清单的长度带偏。

## 冲突热点（真实踩到过的）

| 位置 | 现象 | 处理 |
| --- | --- | --- |
| 整个仓库 | upstream 重写了全部 commit（hash 全变），没有共同祖先 | 见「上游重写过历史」：用 `--onto`，别用 `git rebase upstream/main` |
| `ProviderGlyph.swift` / `GlyphOutline.swift` | git **自动合并成功**，但 enum 出现重复的 `case kimi` / `static let kimi` | 回退到 upstream 版本 |
| `README.md` | 同上：表格行重复 | 回退到 upstream 版本 |
| `AppDelegate.swift` 的 provider 组装 | 它被 upstream 反复重构，且**几乎每轮都往链里加 provider**：1.15.0 加 `qianwen`（与 fork 的 `xytoken` 落在同一个列表字面量）、1.16.0 加 `customProviders`、1.18.0 加 `AmpProvider()` / `ApifyProvider()` / `KiloProvider()`（正落在 fork 1.16.0 拆成 `+=` 的那条链中间）、1.22.0 加 `qoder`（同样是 `WebSessionProvider`）与 `commandCodeProfiles`、1.23.0 加 `remoteProviders` / `GrokBotProvider()` / `MuseLocalProvider()` / `OMLXLocalProvider(…)`、1.24.0 加 `HiggsfieldProvider()`（落在 `KiloProvider(),` 之后，仍是那句 `+=` 的数组字面量里；**它不是 `WebSessionProvider`**，不进 `webProviders` / `signInItems`） | 保留 upstream 的 provider 集合与顺序，fork 只保留「一句一个 `+=`」的形态：新 provider 按 upstream 的位置各起一句并显式 `as UsageProvider`；`webProviders` / `signInItems` 里把 XyToken 加回去（1.23.0 起是 `[deepSeek, qianwen, qoder, xytoken]`），见第 5 节 |
| `Sites.swift` | 两个相邻的 site 定义 | 见第 5 节 |
| `UsageStore.swift` 的 `ProviderSummary` 构造 | upstream 1.16.0 加了 `customIconFilename:`，正好落在 fork「读一次 `account()` + `needsSignIn:`」那一段中间 | 两边都留：upstream 的新参数 + fork 的共享 `account` 变量与 `needsSignIn:`，顺序按 `ProviderSummary` 声明，见第 6 节 |
| `UsageStore.swift` 的 `needsSignIn` switch | upstream 给 `SignInRoute` 加 case（1.18.0 的 `.command`），而 fork 的 switch 穷尽、没有 `default` → **自动合并干净、没有任何冲突标记，但 `make build` 报 `switch must be exhaustive`** | 新 case 按第 6 节的判据归类：借用本地凭证的（`.openApp` / `.guidance` / `.command`）返回 true，只有 `.modal` 看 `snapshotStatus == .needsAuth` |
| `UsageStore.swift` 的 wake 观察者（1.24.0 新增这一形态） | upstream 把 `refreshNow()` / `refreshNow(freshness:)` 的返回从 `Void` 改成 `Task<Void, Never>?`（`ca6d274`「Refresh all from the menu without closing it」要等那一轮跑完），而 fork 的 `guard !displayIsAsleep()` 两行正落在被改的那一行里 → **真冲突**（不是自动合并） | 两边都留：保留 fork 的两行 guard，返回值按新签名写 `_ = self.refreshNow(freshness: .live)`（新签名**没有** `@discardableResult`，漏了 `_ =` 只是警告不是错误，但同文件另一处 upstream 自己就写的 `_ =`，跟着写） |
| `TooltipCard.swift` / `UsageResetCard.swift` 的 tooltip 玻璃 | upstream 1.16.0 改了**同一行**的内容（`clampedTailOffset`、`TooltipGlassContrast.dim(...)`），而 fork 把这一行换成了 shim | 取 upstream 的新内容，只把 `glassEffect` 换成 `compatGlassEffect(surfaceStyle, …)`，见第 1 节 |
| `SettingsView.swift` 的侧栏底与 orb | upstream 1.15.0 把玻璃侧栏换成扁平 `SettingsPalette.sidebar`，并删掉 `sidebarToggle` / `collapsedSidebarToggle` / `SidebarIcon` | fork 那两处 `compatGlassEffect` 失去对象 → **取 upstream，不要加回**（见第 1 节） |
| `project.yml` / `Info.plist` 的本地化列表 | upstream 反复往 `CFBundleLocalizations` 追加（1.15.0 加 `zh-Hant`、1.18.0 加 `id` / `ko` / `uz` / `tr`），总有一两项紧邻 fork 改的 `LSMinimumSystemVersion` | 各留一份：本地化列表取 upstream，`LSMinimumSystemVersion` 保持 14.3 |
| `ClaudeTokenRefresher.swift` 的 `run` | upstream 把新的 `arguments` 常量与文档加在 fork 标了 `nonisolated` 的那个声明正上方 | 保留 upstream 的文档与常量，`run` 仍标 `nonisolated` |
| `Info.plist` | `LSMinimumSystemVersion` 15.0 vs 14.3 | 保留 14.3 |
| `NotchSurfaceStyle.swift` | upstream 新增的 `glass: Glass` 在旧 SDK 里连**类型**都不存在，`@available` 救不了 | 属性与比较它的测试整段进 `#if swift(>=6.2)`，见第 1 节 |
| `MacOS26Shims.swift` 的签名 | shim 收 `Glass` 则调用点在旧 SDK 上必编译失败 | shim 只收 `NotchSurfaceStyle`，调用点不写 `Glass`，见第 1 节 |
| `Makefile` | upstream 的 SwiftPM 逻辑与 fork 的签名逻辑在同一块 | 两边都留 |
| `Package.resolved` | upstream 新增的锁定文件会盖掉 fork 的 pin | 见第 3 节 |
| `MoveHandle.swift` | upstream 1.19.0 把整个 `struct MoveHandle` 换成 `enum MoveHandle`（只剩两面弧共用的几何）**加** `MoveGrip`（六颗点的整套绘制），fork 那笔 shim 改的 `restingArc` / `hoverDisc` 正好是被删掉的两个成员 | **整块取 upstream**：不要试图把 fork 的旧代码搬回来（`arcRadius` / `restingTrim` 在 `MoveGrip` 里已不存在）。新代码里的 `glassDots` 才是需要 shim 的地方，算「旧工具链 fallout」，见第 1 节 |
| `SettingsHandle.swift` 的玻璃分支 | 同一段里 upstream 新增 `.mask { GooArc(…) }`（弧线改成跟着 flare 走，不再是 `clipShape(ArcBand(…))`），而 fork 在那里删的是 `#available` 包装、换的是调用 | 取 upstream 的新结构（`.mask { GooArc }`），只把 `glassEffect` 换成 `compatGlassEffect`——两者不是一回事，别把 `GooArc` 换回 `ArcBand` |
| `project.yml` 的 `SU*` 段 | upstream 1.19.0 在 `SUEnableAutomaticChecks` 与 `SUAutomaticallyUpdate` 之间插了一段注释（正好落在 fork 那两行中间），并**顺手把 `SUAutomaticallyUpdate` 改成 `false`**（与 fork 同向） | `SUEnableAutomaticChecks` 取 fork 的 `false`、`SUFeedURL` 取空、注释取 upstream；`SUAutomaticallyUpdate` 现已两边一致、不必再动，见第 4 节 |
| `NotchRootView.swift` 的两处玻璃（1.23.0） | upstream 在同一段里既加了 `if #available(macOS 26.0, *)`，又把 `surfaceStyle` 改名成 `drawnSurfaceStyle`、把条件收紧成 `if glassy && !dock`，还多画了一层 `slabGlass` 的 slab | 删掉 `#available` 包装、把两处调用换成 `compatGlassEffect(model.drawnSurfaceStyle, …)`（slab 那处传 `slab: true`）；**取 upstream 的 `if glassy && !dock` 与 `headlessGlass` 的 if/else 结构**，别把它们压平 |
| `NotchSurfaceStyle.swift` 的 `#if` 边界（1.23.0） | upstream 新增 `slabGlass: Glass` 与 `.dock` 分支、并写了一段 `dock` 的文档，正好压在 fork 的 `#if swift(>=6.2)` 说明与门禁之间 | 文档两边都留；`#if` 继续包住 `glass` **和新的 `slabGlass`**（`#endif` 留在 `slabGlass` 之后），见第 1 节 |
| `Info.plist` 的 `LSMinimumSystemVersion` 邻域（1.22.0） | upstream 新增 `NSAppTransportSecurity`（`100.64.0.0/10` 的例外域），插在 fork 改的 `LSMinimumSystemVersion` 正下方 | 取 upstream 的新字典、`LSMinimumSystemVersion` 保持 14.3——和 1.15.0 / 1.18.0 的 `CFBundleLocalizations` 是同一个形态 |
| `Tests/NotchLayoutTests.swift` 的 `#if swift(>=6.2)`（1.23.0） | upstream 给同一个测试补了 `dock` 的说明并加了 `.dock` 断言 | 取 upstream 的说明与断言，门禁照旧（这个测试比较的是 `Glass` 值，旧 SDK 里那个**类型**都不存在） |
| `KimiProvider.swift` 的文档注释（1.22.0） | upstream 重写了头部文档，fork 那笔也改过同一段 | 取 upstream 的措辞（fork 那笔只是重排文档），`fetchSnapshot()` 里那句 `refresher.usableCredential()` 原样保留，见第 8 节 |
| **upstream 新增的文件**（1.19.0 的 `Sources/Features/UpdateCard.swift`） | **不产生任何冲突**：fork 从没碰过它，git 只把它加进来；但里面有 `glassEffect` 时编译直接红 | 不要在「冲突都解完了」时收工——解完冲突后重跑第 1 节那条 grep，再 `make build` |

**教训**：`git rebase` 打出「Auto-merging」**不等于**没问题，而且有**三种**表现：

1. **合并结果自相矛盾**：enum case、README 表格这类「追加一行」的改动被自动合并成重复定义。
   （1.18.0 没有出现这一种——upstream 新增的 kilo / amp / apify 都落在 fork 从没碰过的文件里。）
2. **合并结果编不过**：文件本身没有冲突，但上游新增的 enum case 撞上 fork 的穷尽 switch、上游新增
   的 API 撞上旧工具链、上游的断言撞上旧 Foundation 的格式化行为。1.18.0 触发了其中两条——
   `SignInRoute.command` → `needsSignIn` 的穷尽 switch，`ApifyUsage.money` 在 `en_US_POSIX` 下的分组
   （这轮没有新增 macOS 26 API，所以「新 API」那条没触发）。

3. **冲突清单里根本没有的新代码**：upstream 新增的文件不进任何冲突——1.19.0 的 `Sources/Features/UpdateCard.swift`
   被整份加进来，git 一句提示都没有，只有 `make build` 报 `value of type 'some View' has no member 'glassEffect'`。
   1.23.0 把这条推广了一层：**新符号也可能落在「冲突文件里的非冲突区段」**——`MoveHandle` 那处早已如此，
   这轮是 `NotchRootView.swift` 里 dock 的 slab（`model.drawnSurfaceStyle.slabGlass`，那个文件另有冲突，
   但不在这一处）。所以第 1 节那条 grep 要在**解完冲突之后**再跑一遍，不要只在冲突文件里找。

三种都**只有编译期和测试期才发现**，所以 rebase 之后必须 `make build` + `make test`，不能只确认
「冲突都解完了」。

## 旧工具链编译错误的常见形态

这类改动每轮 rebase 都会出现，统一提交为 `Fix old-toolchain fallout from the upstream sync`。
历史上出现过的形态：

- **新 API**：macOS 26 才有的修饰符 → 走 `Sources/Compatibility/MacOS26Shims.swift`（见第 1 节）
- **新属性，不只是新修饰符**（1.23.0 首次出现）：Dock 样式给 `NotchSurfaceStyle` 加了一个返回 `Glass` 的
  `slabGlass`，于是「类型不存在」那条从**修饰符**扩到了**属性**——属性本身进 `#if swift(>=6.2)`，调用点则
  给 shim 加参数（`slab: true`），**不要在调用点拼 `Glass`**（见第 1 节）。判据：`make build` 报
  `cannot find 'slabGlass' in scope` 或 `cannot find type 'Glass' in scope`。
- **Swift 5.10 的并发限制**：不能在嵌套的并发闭包（`Task {}`、`MainActor.run {}`）里读取
  捕获的 `weak self` 变量 → 在**外层**先绑定（见 `PhoneLinkServer`、`LMStudioMetrics`；1.15.0 的
  `GrokActivityMonitor.rescan` 是同一个形态，而且嵌套两层——`scanQueue.async` 里再套
  `DispatchQueue.main.async` + `MainActor.assumeIsolated`）
- **actor 隔离**：upstream 声明为 isolated 的方法，5.10 下需要 `nonisolated`（见 `ClaudeTokenRefresher.run`）
- **测试里的可变捕获**：`var` 被并发闭包捕获 → 换成 `final class Box`（见 `ClaudeOAuthProviderTests`；
  1.23.0 的 `Tests/RemoteHostsTests.swift` 又是 7 处 `var loads/renewals/commands`，同样改成 `final class Box` +
  `loads.value += 1`）。**整文件新增的测试也会踩**，不是只有改过的文件。
- **类型推断差异**：字面量需要显式类型，例如 `[TimeInterval(18000), …]`（见 `OpenCodeUsageTests`）。
  5.10 不会把整数算术折叠成 `Double`，所以 `[5 * 3600, 7 * 86400]` 匹配不上 `[TimeInterval?]`，
  要写成 `[TimeInterval(5 * 3600), TimeInterval(7 * 86400)]`（1.11.0 的 `Tests/MiniMaxUsageTests.swift`）。
- **一整个表达式的类型检查超时**：`error: the compiler is unable to type-check this expression in
  reasonable time`。1.16.0 的 `AppDelegate` 就是这样——upstream 把 provider 组装写成一个跨十几种
  类型的 `+` 链（`[ClaudeOAuthProvider] + [CursorLocalProvider] + … + [WebSessionProvider] +
  `[UsageProvider]`），Swift 6 解得出、5.10 解不动。**拆成一句一个 `+=`**，并给每个 `map` 的元素显式
  写 `as UsageProvider`（不写的话 `map` 的结果是具体类型，`+=` 的 `Element == UsageProvider` 匹配不上，
  字面量可以靠上下文推断、`map` 不行）。给链首项标注类型、把长字面量单独提出来，都试过——不够，
  必须拆成独立语句。判据：`make build` 报这一条，且报的是 `let xxx: [SomeProtocol] = …` 这种长表达式。
- **类型不存在，而不是 API 不存在**：`@available` 门禁不了「返回类型不在这个 SDK 里」的声明——
  `NotchSurfaceStyle.glass` 返回 `Glass`，只能整段 `#if swift(>=6.2)`（见第 1 节）。同理，测试里
  比较这个值的断言要一起进 `#if`，否则**测试目标**编译失败——`make build` 仍是绿的，只有
  `make test` 会报 `enum case 'glass' cannot be used as an instance member`。
- **穷尽 switch 撞上上游新增的 enum case**：fork 的 `switch` 有意不写 `default`（写了就会把下一个新 case 一起
  静默吞掉），于是 upstream 给同一个 enum 加 case 时，**文件自动合并干净、没有任何冲突标记**，只有 `make build` 报
  `error: switch must be exhaustive`。1.18.0 的 `SignInRoute.command` 撞上 `UsageStore.needsSignIn` 就是这一形态。
  修法：按所在节的判据给新 case 归类，**不要**改成 `default`、也不要加 `@unknown default`。
- **只有新 SDK 才成立的格式化 / 区域行为**：upstream 的 CI 跑在 **`macos-26`**（`.github/workflows/ci.yml` 的
  `runs-on`），它的断言是在新 Foundation 上写死并验证过的；同样的代码在旧系统上可能算出别的字符串，而这类
  失败**只在 `make test` 出现**、`make build` 是全绿的。1.18.0 的 `ApifyUsage.money` 就是这样：`en_US_POSIX` 的
  decimal 模式 `groupingSize` 是 0，只置 `groupingSeparator = ","` 根本不会插入分组（那个 locale 下
  `usesGroupingSeparator = true` 也读不回 true），于是 `$12,345.68` 变成 `$12345.68`。修法是补上缺的那一项而不是
  改断言——`formatter.groupingSize = 3`，这在「本来就按三位分组」的 locale 上是 no-op。**判断手法**：先看 upstream
  的 CI 跑在哪个 runner，再用一段独立的 `swift` 脚本在本机复现同一个 API 的行为（`swift /tmp/x.swift` 几秒钟就有
  答案），别凭猜。
- **新文件 / 非冲突区段里的新 API**：这一形态**不经过冲突**——1.19.0 的 `Sources/Features/UpdateCard.swift` 是 upstream
  新增的文件，rebase 时整份加进来、没有任何冲突标记，`make build` 才报 `value of type 'some View' has no member 'glassEffect'`；
  1.23.0 的 dock slab 更进一步：它落在**有冲突的文件的非冲突区段**里（`NotchRootView.swift`）。
  对策：解完冲突后**重跑一遍第 1 节的 grep**，并按第 1 节的形态改（删 `#available` 包装、换 `compat*` 调用）。
- **本轮（1.22.0 + 1.23.0）的三处形态都是编译器报出来的**：这一轮终于在沙箱里把 `build-for-testing` 跑通了
  （配方见「rebase 流程与验证基线」），所以清单不再靠推：`#if swift(>=6.2)` 那条靠第 1 节的 grep 找，另外两条
  （`OMLXMetrics` 的嵌套 `weak self`、`RemoteHostsTests` 的 `var` 捕获）是**编译器逐个报出来的**，且都在
  **整文件新增**的代码里。教训是：光靠 grep + 翻旧形态不够，**必须真的编一次**；`make test` 的测试执行可以留给
  沙箱外，但 `build-for-testing` 一定要在沙箱内自己跑（见该节的命令）。
- **1.24.0：一处都没有**。`make build` 与 `build-for-testing` 都是一次绿，清单里八种形态**一种都没触发**。
  原因不是运气，可复核：upstream 本轮既没动任何 `glassEffect` / `pointerStyle` 调用点（第 1 节），
  也没动任何玻璃门禁测试（第 7 节），新增的 11 个 Swift 文件里没有玻璃调用、没有嵌套并发闭包、没有
  被并发闭包捕获的 `var`，`SignInRoute` 也没多出新 case（第 6 节）。**别把这一轮的「空」当成下轮的预期**——
  这三条恰好是每轮最常变的地方。

## 已被 upstream 吸收的本地改动

**Kimi provider**：本地提交 `c0aeaf0` 已被 upstream 收编，并被 upstream 演进过——
从读 `config.toml` 的 API key 改成读 `~/.kimi-code/credentials/*.json` 的 OAuth token，
多了 plan 与 weekly 窗口。2026-09 的 rebase 里整个提交被丢弃。
代价：upstream 没有 fork 那条 `case "kimi"` 的设置提示文案，走默认提示。

**Claude provider 的 store filter**（`e263f7b` 的一部分，**2026-09 的 1.13.1 rebase 里删除**）：fork 曾把
`ClaudeOAuthProvider` 排除在 `UsageStore` 之外，理由只有一个——ad-hoc 构建每次重建都换 cdhash，
"Always Allow" 授权留不住，读 `Claude Code-credentials` 会每次启动弹密码。**这条理由已经不成立**：
上一个基点 `3251208` 里就有 `7f036ab`，它让后台读取先关掉交互（`SecKeychainSetUserInteractionAllowed(false)`
加 `kSecUseAuthenticationUIFail`），被拒绝后改走 `/usr/bin/security` 兜底——Apple 签名、在这些 item 的
partition list 上，不需要授权；交互式读取只剩人点 "Allow access…" 的那一次（`ClaudeCredentials.askAgain`，
只有设置页那个按钮会调它）。1.13.1 又把这条收严成 `Deny` 全源生效（`e4a4c77`）。

本机实测（macOS 14.3、现编译的 ad-hoc 二进制、真钥匙串）：直接读返回 **-25293**（`errSecAuthFailed`）
**0.03 秒、全程无弹窗**，`security` 兜底静默取回该 item（305 字节）。于是 filter 与两段注释一并删除
（提交 `2da04bb`），`AppDelegate` 的 provider 组装与 upstream 完全一致。
复现方法（不必改 app）：枚举 item 属性拿到 `kSecValuePersistentRef`（不需授权），再用上面那两个开关读
它的 data；失败就 `security find-generic-password -a $USER -s "Claude Code-credentials" -w`。
**只看 status 与字节数，不要打印 token。** 若哪天 upstream 把后台读取改回交互式、或去掉
`/usr/bin/security` 兜底，先这样复现，再决定要不要把 filter 加回来。

**侧栏与 orb 的玻璃替换**（**2026-09 的 1.15.0 rebase 里删除**）：这一条不是「上游修了同一件事」，而是
**上游把对象删掉了**——1.15.0 把设置页侧栏从玻璃卡换成扁平的 `SettingsPalette.sidebar` + hairline（那一轮
「dark, flat」的 Settings 重做），`collapsedSidebarToggle`（那个玻璃圆盘）连同 `sidebarToggle`、`SidebarIcon`
一起被删。fork 原先在这两处做的 `compatGlassEffect` 替换因此无处可施，随两笔提交的 rebase 一并丢弃。
代价：无。macOS 14.3 支持不受影响——侧栏现在是 upstream 自己的扁平配色，与玻璃无关；`SettingsView` 里
仍需 shim 的只剩 `glassBackground(in:)` 与 `AccountRow` 的 `compatPointerStyle`。
判据：

```sh
grep -n 'collapsedSidebarToggle\|sidebarToggle' upstream/main -- Sources/Settings/SettingsView.swift
```

上游侧不再有这两个名字时，本节描述的状态即成立。

**`SUAutomaticallyUpdate: false`（1.19.0 起被 upstream 吸收一半）**：fork 的 `37f56e9` 把这一项从 `true` 改成 `false`，
1.19.0 upstream 自己也这么改了（`project.yml` 与 `Sources/Info.plist` 两处，理由是它新的「新版本在 notch 里问」
流程），于是 fork 提交里这半截就任务完成了——`cherry` 看不出来（整笔仍含 `SUEnableAutomaticChecks: false` 与空
`SUFeedURL`，那两处仍要留，所以整笔仍是 `+`）。**代价：无**——这一项现在两边一致，rebase 时不再需要维护它，
下一轮 `project.yml` 的 `SU*` 段若能只冲突 `SUEnableAutomaticChecks` / `SUFeedURL` 两行，就说明这里记对了。
判据（比 `cherry` 直接）：`git diff upstream/main HEAD -- project.yml Sources/Info.plist` 里还剩几键，就只有那几键要留。
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
1.13.1 复核（61 个提交）：18 个 fork 提交仍全为 `+`。Claude filter 那条**不是** `cherry` 判出来的——patch
不匹配，是人工复核时发现「上游把同一件事修好了」，正是本节存在的用途。
历史重写不影响这个判断——`cherry` 比的是 patch 内容，不是 commit hash。
1.15.0 复核（45 个提交）：19 个 fork 提交（18 + 本轮那笔 `Fix old-toolchain fallout`）仍全为 `+`。新增的
那一条（侧栏 / orb 的玻璃替换）同样**不是** `cherry` 判出来的——上游没有修同一件事，是把对象删掉了，
见上面那一条。
1.16.0 复核（68 个提交）：21 个 fork 提交（19 + 1.15.0 那笔 fallout + 本轮那笔 fallout）仍全为 `+`，
无新增条目。本轮 upstream 碰了不少 fork 也改过的地方（`UsageStore` 的 `ProviderSummary` 构造、两个
tooltip 的玻璃行、provider 组装），但没有一件事是「把 fork 的改动做了」——三处都是**不同内容落在同一行**，
所以仍然要人工看，不能只看 `cherry`。
1.18.0 复核（**174 个提交，历轮最多**）：`git cherry -v upstream/main main` 的 25 个 fork 提交（23 个重放 + 本轮那笔
fallout 与本记录）仍全为 `+`，**没有新增被吸收的条目**。对比面这一轮是 37 个文件 / +2824 -172（`git diff --shortstat
upstream/main HEAD`）。upstream 本轮
碰了不少 fork 也改过的文件——`Sites.swift`（`qianwen` 的 `headlineID`）、`AppDelegate` 的 provider 组装、
`KimiProvider` 的 `signInRoute`、两个 tooltip 的玻璃行、`project.yml` 与 `Sources/Info.plist` 的本地化列表——但
**没有一件事是「把 fork 的改动做了」**：五处都是不同内容落在同一文件或同一行，所以仍然要人工看，不能只看 `cherry`。
本节里 §6（`needsSignIn`）与 §8（Kimi 续期）两条本轮都复核过：upstream 依然没修，继续保留，理由和信号见各自小节。
1.19.0 复核（**3 个提交、历轮最少**）：`git cherry -v upstream/main main` = **28 行**（26 个重放 + 本轮那笔
fallout + 本笔记账），仍全为 `+`，**没有新增被吸收的条目**。对比面是 **38 个文件 / +3087 -183**
（`git diff --shortstat upstream/main HEAD`，含本笔记账；在 `141ed27` 那个时点是 38 / +2985 -183，
在解完冲突的 `43cd257` 时点是 36 / +2964 -158——**记这一行时务必在最终 tip 上重跑**，别沿用冲突刚解完时的数）。
upstream 本轮碰了 fork 也改过的三个文件——`project.yml`（`SUEnableAutomaticChecks` 旁边的新注释）、
`MoveHandle.swift`（整套重写成 `enum` + `MoveGrip`）、`SettingsHandle.swift`（玻璃分支里新增 `.mask { GooArc }`）——
三处都是**不同内容落在同一行或同一段**，所以仍然要人工看，不能只看 `cherry`。§6（`needsSignIn`）与 §8（Kimi 续期）
两条本轮都复核过：upstream 依然没修，继续保留，理由和信号见各自小节。

1.22.0 + 1.23.0 复核：`git cherry -v upstream/main main` = **29 行，仍全为 `+`，没有新增被吸收的条目**
（28 个重放 + 本轮那笔 fallout）。对比面是 **38 个文件 / +3112 -202**（`git diff --shortstat upstream/main HEAD`，
含本笔记账）。两轮碰了不少 fork 也改过的文件——1.22.0 的 `Info.plist`（`NSAppTransportSecurity`）、
`AppDelegate`（`qoder` / `commandCodeProfiles`）、`KimiProvider`（文档）、`SettingsView`、`TooltipCard`、
`UsageStore`、`NotchRootView`；1.23.0 的 `NotchRootView`（换成 `drawnSurfaceStyle` + dock 那套）、`NotchSurfaceStyle`（`slabGlass`）、
`AppDelegate`（`remoteProviders` / Muse / OMLX / GrokBot）、`SettingsView`、`Tests/NotchLayoutTests`——
**没有一件事是「把 fork 的改动做了」**，全是不同内容落在同一行或同一段，所以仍然要人工看，不能只看 `cherry`。
§6（`needsSignIn`）与 §8（Kimi 续期）两条本轮都复核过：upstream 依然没修，继续保留，理由和信号见各自小节。
**顺带记一条容易误判的**：1.22.0 让 `SUAutomaticallyUpdate` 的两边一致早已写在上面（1.19.0 吸收半截），
本轮 `SU*` 段一次都没冲突，说明那条判断仍然对。

1.24.0 复核：`git cherry -v upstream/main main` = **35 行，仍全为 `+`，没有新增被吸收的条目**
（34 个重放 + 本轮这笔记录；**这一轮没有 `Fix old-toolchain fallout`**——编译期零 fallout，见
「rebase 流程与验证基线」）。对比面是 **43 个文件 / +4004 -240**（`git diff --shortstat upstream/main HEAD`，
含本笔记账；在解完冲突、还没记账时是 43 / +3892 -240）。
upstream 本轮碰了 fork 也改过的 9 个文件——`AppDelegate`（`HiggsfieldProvider`）、`UsageStore`（`refreshNow`
的返回类型）、`SettingsView`（菜单栏那一段）、`TooltipCard`、`Info.plist` 与 `project.yml`（只有 `es` 与版本号）、
三个 `Tests/*`——但**除了 `es` 那一行是「同一件事的两种写法」之外，没有任何一件是「把 fork 的改动做了」**，
所以 `cherry` 仍要配人工看。§6（`needsSignIn`）与 §8（Kimi 续期）两条本轮都复核过：upstream 依然没修，
理由和信号见各自小节；§5 那个旧 Kimi 提交（`c0aeaf0`，已被吸收）也不受影响。
**顺带记一条**：1.24.0 的 `git cherry` 里重放的那 34 个提交**没有一个**因为「上游做了同一件事」变成 `-`——
`SU*` 两边一致那半截（1.19.0 吸收）也仍然只是「不需要维护」，没到「可以删」。

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
7. 判断一处失败「是旧工具链的，还是 upstream 自己就坏的」，先看 `.github/workflows/*.yml` 的 `runs-on`：上游 CI 是
   **`macos-26`**，它的断言只在那个系统上被验证过。1.18.0 那处 `ApifyUsage.money` 的千分位就是这么定位的。
8. **核对 provider 解析以线上真实响应为准，不要以测试 fixture 为准**：fixture 的注释常写着它会 rewrite id，
   它只保证自己内部一致。§5 的 XyToken 窗口 id 就被 fixture 带偏过一次（测试全绿、线上周环不画）。
   真值的取法：应用把响应体打进 `log stream`（`xytoken usage -> …`，被截断就再加一句日志），
   或直接读解析结果——`~/Library/Preferences/com.vinz.codenotch.plist` 的 `lastGoodReadings`（base64 → JSON）。
9. **验证分两半：编译在沙箱内自己跑，测试留给沙箱外**。pi 的 bash 工具跑在一个默认只允许写工作区与
   `TMPDIR` 的 seatbelt 沙箱（`pi-sandbox` 扩展）里，但按「rebase 流程与验证基线」里那份配方补齐
   `sandbox.json` 之后，**`xcodegen` + `xcodebuild build-for-testing` 可以在沙箱内跑通**——这是本轮最大的收获，
   因为它能抓住所有编译期 fallout（1.23.0 的 3 处里有 2 处只有编译器能报）。
   **测试执行不行**：`xcodebuild test` 要 LaunchServices（`-10822`），需要 runtime 的 `allowAppleEvents`，
   而 pi-sandbox 没透传这个键。所以：
   - 沙箱内：`XBS_DISABLE_SANDBOXED_BUILDS=1 xcodebuild … build-for-testing`（期望 `** TEST BUILD SUCCEEDED **`）
   - 沙箱外：`make test` + `Scripts/install-app.sh`，跑完把数字写回「rebase 流程与验证基线」那一段
10. **一次没记账的 rebase 是可以事后补的**：1.22.0 那轮只留下 `backup/pre-rebase-1.22.0` 与 reflog 里的
   `rebase (finish): onto bcb28894…`。用 `git reflog main --date=iso` 找命令、用
   `git range-diff <旧基点>..backup/pre-rebase-<版本> <新基点>..<新 tip>` 找出哪几笔 fork 提交变了形，
   就能把这轮补写成和别轮同样的格式（1.22.0 那段就是这么来的）。

不复核的文档比没有文档更糟：它会让下一次 rebase 照着过期结论删掉还需要的东西。

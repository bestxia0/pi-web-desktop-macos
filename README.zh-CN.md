# Pi Web Desktop (macOS)

一个极小的原生 macOS 菜单栏启动器，用于 **pi-web** Web UI：不用终端，就能探测、复用、启动、打开并停止本机的 `pi-web` 实例。

[English](README.md) · **简体中文**

[![CI](https://github.com/bestxia0/pi-web-desktop-macos/actions/workflows/ci.yml/badge.svg)](https://github.com/bestxia0/pi-web-desktop-macos/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: macOS 13+](https://img.shields.io/badge/Platform-macOS%2013%2B-lightgrey.svg)](#环境要求)
[![Swift 5](https://img.shields.io/badge/Swift-5-orange.svg)](#环境要求)
[![Zero dependencies](https://img.shields.io/badge/dependencies-0-brightgreen.svg)](#环境要求)
[![Latest release](https://img.shields.io/github/v/release/bestxia0/pi-web-desktop-macos?display_name=tag)](https://github.com/bestxia0/pi-web-desktop-macos/releases)

![菜单栏图标](docs/images/menubar-icon.png)
*菜单栏里的 Pi Web：SF Symbol 加一个 `Pi` 标题，按启动器状态变色。*

## 定位（是什么 / 不是什么）

| 是什么 | 不是什么 |
| --- | --- |
| 一个原生 Swift + AppKit `NSStatusItem` 菜单栏应用（`LSUIElement`，没有 Dock 图标） | 不是浏览器或 Electron 外壳——它拥有自己的单个原生窗口和多个 `WKWebView` 标签页，不内嵌浏览器引擎 |
| 一个**纯启动器**：替你查找、启动、停止 `pi-web` CLI | 不是打包器——从不附带 Node、npm 或 `pi-web` 包 |
| 本机 `127.0.0.1` 上 `pi-web` 服务的前端窗口 | 不是 `pi-web` 的替代品；CLI 与 `node` 必须已经装好 |
| 一个**零依赖**、只用 `swiftc` 构建的应用 | 不依赖 SPM、CocoaPods 或任何第三方包 |

## 它替你解决的 4 个具体麻烦

- **不想为了开个界面去敲终端。** 敲一下**右侧 Option** 就能唤出/收起窗口，或者点菜单栏图标。
- **不想重复起第二个实例。** 每次启动都先读 `pi-web` 自己的运行记录，健康的既有实例直接**附加**，而不是再起一个。
- **端口被占时不想看它崩。** `pi-web` 自己没有端口回退（30141 被占就直接 “Next.js exited unexpectedly” 退出），本壳会先选好一个空闲端口。
- **停止时想搞清楚停的是谁。** 本壳启动的走信号升级；别处启动的（比如终端）会先弹确认，再委托上游 `pi-web stop --port N`。

## 场景 1 · 第一次装好它（约 5 分钟）

1. **装运行时。** 需要全局的 `pi-web` 和 `node`：

   ```sh
   brew install node
   npm install -g @agegr/pi-web
   pi-web --version        # 应该打印版本号，例如 0.12.2
   ```

2. **构建应用。** 只需要 Xcode Command Line Tools：

   ```sh
   git clone https://github.com/bestxia0/pi-web-desktop-macos.git
   cd pi-web-desktop-macos
   ./build.sh              # swiftc + 组装 build/PiWeb.app + 代码签名
   open build/PiWeb.app
   ```

   `./build.sh --run` 可以一步构建并启动。产物是 **arm64 + x86_64 通用二进制**，Apple 芯片和 Intel 都能跑。

3. **`make install`（可选，但推荐）。** 把应用装到 `/Applications`：

   ```sh
   make install            # = ./scripts/install.sh
   ```

   开机自启（`SMAppService.mainApp`）需要一个稳定的 bundle 位置，先装到 `/Applications` 才能启用。

4. **授权输入监控（想用右侧 Option 热键才需要）。** 首次敲右侧 Option 如果没反应，点菜单里的 `⚠︎ 需要「输入监控」权限——点击授权`，在系统设置 → 隐私与安全性 → 输入监控里勾上本应用。

5. **按需打开开机自启。** 菜单里的 `开机自启` 复选框始终反映系统真实状态。

验收：菜单栏出现 `Pi` 图标；展开菜单，第一行是 `Pi Web — <状态>`，最后一行是 `V<版本>-<构建日期>`，中间有可用的 `打开 Pi Web`。

## 场景 2 · 日常：打开、开新标签、关掉

- **打开/收起**：敲**右侧** Option，或点菜单栏图标 → `打开 Pi Web` / `显示 / 隐藏窗口`。窗口只创建一次：再打开只是聚焦，保留滚动位置、前进/后退状态和标签页。
- **新标签页**：标签栏右侧的 `+`、⌘T，或菜单的 `新建标签页`。新标签默认加载会话列表：当前标签有 `cwd` 时就限定到那个目录，否则不加限定；它从不在服务端创建会话。
- **给不同项目各留一个标签页**：每个标签页都是独立的 `WKWebView`，可以各自指向不同的会话（`?session=<id>`）或不同的工作目录。
- **给标签页上色**：右键标签页 → `颜色`（无颜色、红、橙、黄、绿、薄荷、蓝、靛蓝、紫、粉、灰），同一菜单里还有 `关闭标签页` 与 `关闭其他标签页`。
- **关掉**：⌘W 关闭**当前标签页**；关掉最后一个标签页时窗口只是隐藏。红色关闭按钮和右侧 Option 热键作用于整个窗口（隐藏，不销毁）。

![菜单展开](docs/images/menu.png)
*菜单展开的样子（此图采集自 v0.5.0：当前菜单在标签页与热键功能加入后还多出 `新建标签页`、`标签页`、`右侧 Option 唤起窗口` 等项）。*

## 场景 3 · 终端里已经跑着 pi-web

先探测，再决定：

1. 读 `<agentDir>/pi-web-run/*.json`（`agentDir` 是 `PI_CODING_AGENT_DIR`，默认 `~/.pi/agent`）。
2. 校验 `pid` 存活**并且**确实是我们的进程（`ps -ww -p <pid> -o args=`，启动器参数含 `pi-web`，next 参数含 `next`；启动器已退出但 next 还活着的记录记为*孤儿*）。
3. **只有到这一步**才探测 URL（任何 HTTP 状态码都算响应，包括 `pi-web` 密码保护下的 401）。

顺序不能颠倒：过期的记录可能指向一个仍然响应得飞快的 URL（那个端口被另一个实例占着），先查 URL 就会数出两个实例。

于是：终端里已经有健康的 `pi-web`，本壳会**附加**它、直接把窗口指过去，绝不会再起一个。探测是**只读**的——本壳从不删除你的运行记录（上游自己的 `listRunRecords` 会清理，本壳刻意不做）。

想自己看一眼它怎么判断：

```sh
build/PiWeb.app/Contents/MacOS/PiWeb --probe
pi-web status          # 上游自己的实例列表，可对照
```

## 场景 4 · 停止与退出

两条路径，取决于实例是谁起的：

| 路径 | 机制 | 升级阶梯 | 确认 |
| --- | --- | --- | --- |
| 自有（本壳启动） | 直接向子进程发信号 | `SIGINT`（10 秒）→ `SIGTERM`（5 秒）→ `SIGKILL` | 无 |
| 附加（别处启动） | 委托上游 `pi-web stop --port N` | 由上游处理 | 有，模态警告 |

- 先发 `SIGINT` 是因为 Next.js 会挂着 SSE 连接，它的 `instrumentation-node.ts` 在 SIGINT/SIGTERM 时会把这些流关掉，让 `pi-web` 干净退出。
- 附加实例的停止永远带 `--port N`（不带时上游在多实例情况下会报错），并且会先弹确认框，因为它可能来自你终端里正在用的会话。
- 同时有多个实例时，`停止 Pi Web` 变成 `停止 Pi Web（N 个实例）`，下面按实例列出 `<url>  pid <pid>（本壳）`。
- 任何一次停止之后都会重新探测，菜单始终反映现实。
- 退出时，`退出时同时停止后台 pi-web` 复选框（默认**开启**）决定是否连带停掉**附加**实例；本壳自己起的子进程总会停。

## 场景 5 · 出问题时按症状排查

| 现象 | 可能原因 | 一次修好 |
| --- | --- | --- |
| 菜单栏没有图标 | 图标被菜单栏溢出区 / 刘海挡住，或已有另一个实例持有单实例锁 | 检查溢出区与活动监视器里的 `PiWeb`；再启动一次应用会让运行中的实例把菜单弹出来。看 `~/Library/Logs/PiWeb/pi-web.log`。 |
| 从 Finder 启动后提示 "pi-web not found" | LaunchServices 只给应用 `/usr/bin:/bin:/usr/sbin:/sbin`，且登录 shell 探测失败或超时（`.zshrc` 太慢） | 全局装好 `pi-web`，用 `/bin/zsh -lic 'command -v pi-web'` 验证；然后设置 `PiWebExecutablePath` 或 `PI_WEB_DESKTOP_EXECUTABLE`。用 `--resolve` / `--probe` 诊断。 |
| 首选端口被占用 | `pi-web` 自己没有回退，会以 "Next.js exited unexpectedly" 退出 | 让本壳用 `30151+` 或临时端口（状态标题里会显示实际 URL）；用 `停止 Pi Web` 或 `--probe` 找到并停掉过期实例。 |
| 第二次启动看似没反应 | LaunchServices 会去重 bundle 启动，已在运行的实例收到激活通知并弹出自己的菜单 | 点菜单栏图标；若仍无反应，用日志与状态标题确认运行中的实例。 |
| 开机自启项指向仓库目录 | `.app` 不在 `/Applications`，`SMAppService.mainApp` 注册的是仓库路径 | 先 `make install`，再启用 `开机自启`；此前菜单会显示 `开机自启（App 需位于 /Applications）`。 |
| pi-web 界面在默认浏览器而不是应用窗口里打开 | 只影响无头 `--open-url` 回退：`/Applications` 下找不到四个规范的 Chrome 系应用 | 装 Google Chrome、Microsoft Edge、Brave 或 Arc 之一，或接受默认浏览器。GUI 始终使用原生窗口。 |
| 走完启动流程却停在“启动失败” | `pi-web` 进程提前退出（端口冲突、Node 缺失等） | 菜单会显示失败原因，日志尾部有子进程的 stdout/stderr；`--resolve` 打印解析到的 `pi-web`、来源与子进程 `PATH`。 |

### 输入监控授权失效（30 秒修复）

右侧 Option 热键受 macOS **输入监控**权限控制，而这个授权与代码签名绑定，可能悄悄失效。

**为什么会失效。** 默认构建是 ad-hoc 签名（`codesign --sign -`），**每次重新构建都会生成新的 cdhash**；移动 `.app` 同样是一次身份变化。TCC 里还存着旧构建的匹配条件，于是系统设置里的勾选可能仍然为**开**，热键却已经失效。日志里会出现 `Failed to match existing code requirement for subject com.piweb.desktop`。

**30 秒修复：**

```sh
/usr/bin/tccutil reset ListenEvent com.piweb.desktop
/usr/bin/tccutil reset Accessibility com.piweb.desktop   # 如果也曾授予辅助功能
```

重启应用，点菜单里的 `⚠︎ 需要「输入监控」权限——点击授权`，勾上本应用，再把热键打开。菜单项 `重置「输入监控」授权并重新请求` 会在应用内完成同样的重置与再次请求。

**一劳永逸：稳定的自签名证书。** 用**钥匙串访问**创建一次：

1. 钥匙串访问 → 证书助理 → 创建证书…
2. 名称：`PiWeb Local Signing`（必须完全一致）
3. 身份类型：自签名根证书
4. 证书类型：代码签名
5. 有效期：`3650` 天或更长 → 创建
6. 打开新证书 → 显示简介 → 信任 → 将「代码签名」设为「始终信任」

此后 `./build.sh` 会自动用它：先看 `$PI_WEB_SIGN_IDENTITY`，否则从 `security find-identity -v -p codesigning` 里精确匹配同名的 `PiWeb Local Signing`，并打印 `signed (identity: PiWeb Local Signing)` 与 `CDHash`。没有可用身份时回退 ad-hoc 并明确警告。**切换签名身份后**需要再执行一次 TCC 重置并重新授权。

> 如果 `codesign` 弹出钥匙串授权框，选一次“始终允许”即可；拒绝或取消会让本次构建回退到 ad-hoc 签名（`build.sh` 会自动回退并打印警告）。

## 场景 6 · 升级与卸载

- **从发布包升级**：在 [Releases](https://github.com/bestxia0/pi-web-desktop-macos/releases) 下载 `PiWeb-<版本>.zip`（arm64 + x86_64 通用），解压后覆盖 `/Applications/PiWeb.app`，然后重新启动应用。首次打开未公证的下载包需要一次 Gatekeeper 确认。
- **从源码升级**：`git pull` 之后 `make install`（或只 `./build.sh` 用仓库内的 `build/PiWeb.app`）。
- **卸载**：`make uninstall` 会删除 `/Applications/PiWeb.app` 并退出运行中的实例。
- **残留（想彻底清干净时手工删）**：偏好 `defaults delete com.piweb.desktop`、日志 `~/Library/Logs/PiWeb/`、单实例锁 `~/Library/Application Support/PiWeb/`。
- **自动检查更新**：尚未实现（见[路线图](#路线图)）。目前 `pi-web` CLI 自己可以 `pi-web update --check` 检查它自身的版本。

## 截图

![pi-web 控制台](docs/images/pi-web-console.png)
*在应用自有的某个原生 `WKWebView` 标签页里渲染的 `pi-web` 控制台界面。*

## 环境要求

- **macOS 13.0 或更高版本**（`LSMinimumSystemVersion` 为 `13.0`；`SMAppService` 需要 macOS 13）。
- **Xcode Command Line Tools**（提供 `swiftc`、`lipo`、`sips`、`iconutil`）——唯一需要的构建工具。
- 要真正启动服务：`PATH` 上有**全局安装的 `pi-web` CLI** 和 **`node`**。

无 SPM、无 CocoaPods、无第三方包。应用只用 `swiftc` 对接系统框架（Foundation、AppKit、WebKit、CoreGraphics、ApplicationServices、ServiceManagement、UniformTypeIdentifiers）。

## 参考手册

### 菜单参考

菜单项以简体中文显示，下表按从上到下的顺序列出。

| 菜单项 | 作用 | 状态 / 条件 |
| --- | --- | --- |
| `Pi Web — <detail>` | 菜单顶部的状态标题；显示当前阶段、活动 URL/版本或实例数量。 | 始终存在，禁用（仅显示）。 |
| `错误：<message>` | 展示最近一次失败（换行会压成一行）。 | 仅在存在错误时出现。 |
| 打开 Pi Web | 显示应用自己的单个原生窗口（必要时创建窗口），并恢复持久化的标签页。快捷键 `O`。 | 仅在已知活动实例 URL 时可用。 |
| 显示 / 隐藏窗口 | 切换单个原生窗口：前台可见时隐藏，否则显示并聚焦。 | 在已知活动实例 URL 或窗口已存在时可用。 |
| 新建标签页 | 手动新建原生标签页（标签栏右侧的 `+`，或真实主菜单中的 ⌘T）。未指定 URL 时加载会话列表：活动标签页有 `cwd` 时限定到该目录，否则不加限定；从不创建服务端会话。 | 始终可用。 |
| 关闭标签页 | 关闭当前标签页。若为最后一个则隐藏窗口（`orderOut`）。 | 至少有一个标签页时可用。 |
| 下一个标签页 | 选择下一个标签页（循环）。 | 多于一个标签页时可用。 |
| 上一个标签页 | 选择上一个标签页（循环）。 | 多于一个标签页时可用。 |
| 标签页 | 列出所有已打开标签页的子菜单（`<n> <标题>`）；选中即聚焦，当前项带勾选标记。 | 无标签页时禁用。 |
| 启动 Pi Web | 先探测；附加到既有实例，否则在空闲端口以 `--no-open` 启动一个并打开。快捷键 `S`。 | 仅在启动器已停止或失败时可用。 |
| 停止 Pi Web | 停止实例。自有 → `SIGINT → 10s → SIGTERM → 5s → SIGKILL`；附加 → 确认提示后执行上游 `pi-web stop --port N`。 | 恰好有一个活动实例时可用。有多个时变为 `停止 Pi Web（N 个实例）` 并带逐实例子菜单（自有项显示 `<url>  pid <pid>（本壳）`）。 |
| 刷新状态 | 重新执行探测并重建菜单。快捷键 `R`。 | 始终可用。 |
| 打开日志 | 打开 `~/Library/Logs/PiWeb/pi-web.log`。快捷键 `L`。 | 始终可用。 |
| 在 Finder 中显示日志 | 在 Finder 中显示日志文件。 | 始终可用。 |
| 开机自启 | 通过 `SMAppService.mainApp` 注册/注销登录项。 | 复选框反映真实状态；需要批准时标题为 `开机自启（需在系统设置中批准）`，bundle 未安装时为 `开机自启（App 需位于 /Applications）`；不支持时以 `开机自启不可用：<reason>` 显示并禁用。 |
| 退出时同时停止后台 pi-web | 切换退出时是否同时停止附加实例。持久化于 UserDefaults 键 `PiWebStopAttachedOnQuit`。 | 复选框，默认**开启**。始终可用。 |
| 右侧 Option 唤起窗口 | 复选框：启用/禁用右侧 Option 全局热键。持久化于 UserDefaults 键 `PiWebHotKeyEnabled`。 | 复选框，默认**开启**。切换会立即启动/停止 `HotKeyMonitor`。 |
| 退出 Pi Web | 停止自有子进程（开关开启时还包括所有附加实例），然后退出。快捷键 `Q`。 | 始终可用。 |
| ⚠︎ 需要「输入监控」权限——点击授权 | 请求输入监控（`CGRequestListenEventAccess`）并打开系统设置 > 隐私与安全性 > 输入监控。 | 仅在未授予输入监控时出现，位于版本行之前。 |
| 重置「输入监控」授权并重新请求 | 清除过期的 TCC 条目（`tccutil reset ListenEvent com.piweb.desktop`），然后再次请求授权并打开系统设置。适用于重新构建/移动后勾选仍在但热键已失效的情况。 | 紧随授权项之后，仅在未授予输入监控时出现。 |
| `V<semver>-<builddate>` | 启动器版本，例如 `V0.8.0-20261025`。 | 始终存在，禁用（仅显示），最后一行。 |

### 状态图标

状态图标由 `MenuController.updateIcon()` 绘制：一个 SF Symbol 加简短标题 `Pi`，按状态着色。

| 状态 | 符号 | 颜色 |
| --- | --- | --- |
| 运行中 | `play.circle.fill` | 绿色 |
| 启动 / 停止中（忙碌） | `arrow.triangle.2.circlepath` | 橙色 |
| 已停止 | `power.circle.fill` | 标签色 |
| 失败 | `exclamationmark.triangle.fill` | 红色 |

### 原生窗口、标签页与右侧 Option 热键

界面渲染在**一个**原生 `NSWindow`（`AppWindowController`）里，顶部是原生标签栏，每个标签页都是独立的 `WKWebView`，首次使用时创建、之后复用：

- 重复点击 `打开 Pi Web` 或按热键只聚焦窗口，绝不新建第二个窗口；首次显示时会从 `UserDefaults` 恢复标签页。
- **红色关闭按钮**和**右侧 Option 热键**隐藏整个窗口（`orderOut`），从不销毁，因此再次打开是瞬时的。
- 在未探测到活动实例 URL、但仍有打开的标签页时，热键也能唤出窗口。
- `⌘W` 关闭**当前标签页**；关闭最后一个标签页时隐藏窗口。
- host 不是 `127.0.0.1`/`localhost` 的链接会在系统浏览器中打开。
- 持久化：每个标签页的 URL + 颜色以及选中索引保存在 `UserDefaults`（`PiWebTabs` / `PiWebTabsSelected`）。下次启动会把存储 URL 的 scheme/host/port 重写到当前的 pi-web base（端口可能变化），保留 path、query 与 fragment。

热键使用仅监听的 `CGEvent` tap（`flagsChanged`），无法创建时回退到 `NSEvent` 全局/本地监视器。它只认右侧 Option（keyCode `61`），左 Option（`58`）完全忽略，且**从不吞掉事件**，所以右侧 Option 在其他应用里仍是普通修饰键。

### 主菜单快捷键

浏览器式快捷键位于真实的 `NSApp.mainMenu`（`MainMenu.swift`），因为状态栏菜单的快捷键只在该菜单展开时生效。

| 快捷键 | 作用 |
| --- | --- |
| ⌘T / ⌘W | 新建标签页 / 关闭当前标签页 |
| ⌘⇧] / ⌘⇧[ | 下一个 / 上一个标签页 |
| ⌘1…⌘9 | 选择第 N 个标签页 |
| ⌘[ / ⌘] | 后退 / 前进 |
| ⌘R | 重新加载 |
| ⌘Z / ⌘X / ⌘C / ⌘V / ⌘A | 标准编辑（作用于聚焦的网页输入框） |
| ⌘H / ⌥⌘H / ⌘Q | 隐藏 / 隐藏其他 / 退出 |

### 无头与验证标志

同一个二进制支持无头标志，无需显示即可验证探测、启动/停止与端口回退：

```sh
BIN=build/PiWeb.app/Contents/MacOS/PiWeb

$BIN --self-test                                # 断言：运行记录解析 + 过期记录逻辑 + PATH/node 解析
$BIN --probe                                    # 打印每条运行记录及其分类与附加/启动决策
$BIN --test-cycle --port 30199                  # 在 30199 启动，等待就绪，然后停止
$BIN --test-cycle --occupy --port 30199         # 占用 30199，然后在回退端口启动
$BIN --test-cycle --gui-path --port 30199       # 端到端模拟 LaunchServices（系统默认）PATH
$BIN --test-fallback --port 30199               # 显示 30199 被占用时规划器选择的端口
$BIN --open-url http://127.0.0.1:30141          # 打开应用模式窗口
$BIN --resolve [--gui-path]                     # 打印解析出的 pi-web + 来源 + 子进程 PATH + node
$BIN --stop-port 30199                          # 通过上游 `pi-web stop --port 30199` 停止一个实例
$BIN --test-quit --port 30199                   # 演练 stopForQuit（附加实例被停止）
$BIN --test-quit --port 30199 --keep-attached   # 同上，但开关关闭
$BIN --port 30199                               # 覆盖首选端口
$BIN --version                                  # 打印菜单底行显示的确切字符串
$BIN --log-path                                 # 打印日志文件路径
```

| 标志 | 作用 | 说明 |
| --- | --- | --- |
| `--self-test` | 运行内置断言（运行记录解析、过期/孤儿记录、PATH/node 解析、停止命令、停止菜单、标签页数学、版本组合）。 | 任一检查失败则以非零退出。仅用于验证。 |
| `--probe` | 打印每条运行记录及其第 2/3 步分类，以及附加/启动决策。 | 只读；从不删除记录。仅用于验证。 |
| `--test-cycle [--occupy] [--gui-path]` | 针对一次性实例执行完整的启动 → 就绪 → 停止循环。 | `--occupy` 预先占用首选端口以演练回退；`--gui-path` 强制使用系统默认 PATH。仅用于验证。 |
| `--test-fallback` | 占用首选端口并报告规划器会选择的回退端口。 | 仅用于验证。 |
| `--open-url <url>` | 通过 `BrowserOpener` 打开 URL（Chrome 系应用模式，否则默认浏览器），并打印所用命令。 | 仅无头回退；GUI 使用原生窗口。 |
| `--resolve [--gui-path]` | 打印解析出的 `pi-web`、其来源、子进程 PATH、`node`、运行目录与浏览器计划。 | `--gui-path` 绕过所有缓存并强制探测。 |
| `--stop-port <n>` | 通过上游 `pi-web stop --port n` 停止一个实例，并打印停止前后的探测结果。 | 仅用于验证。 |
| `--test-quit [--keep-attached]` | 演练 `stopForQuit`，范围限定为 `--port`。 | `--keep-attached` 模拟开关关闭。仅用于验证。 |
| `--port <n>` | 覆盖首选端口。 | 也可通过 `PI_WEB_DESKTOP_PORT` 设置；`--port` 优先。 |
| `--version` | 打印菜单底行显示的版本字符串。 | —— |
| `--log-path` | 打印日志文件路径。 | —— |

> `--stop-port`、`--test-cycle`、`--test-fallback` 与 `--test-quit` **仅用于验证**，不属于正常菜单流程。`--test-cycle` 绝不触碰 `30141` 实例：它只对自己启动的子进程发信号。

### 探测机制（复用 pi-web 契约）

运行记录位于 `<agentDir>/pi-web-run/<launcherPid>.json`，其中 `agentDir` 为 `PI_CODING_AGENT_DIR`（展开 `~` / `~/` / `file://`）或 `~/.pi/agent`。本壳复用 pi-web 的确切格式，并镜像 `bin/run-records.js`：

1. 读取所有 `*.json`。
2. 校验 `pid` 存活（`kill(pid,0)`；`EPERM` 也算存活）**并且**该进程确实属于我们（`ps -ww -p <pid> -o args=`；启动器参数包含 `pi-web`，next 参数包含 `next`）。启动器已消失但 `nextPid` 仍存活的记录称为*孤儿*记录。
3. **只有到这一步**才探测 URL（任何 HTTP 状态码都算响应，超时 2 秒）。

顺序很重要：过期记录可能指向一个仍然响应的 URL，因为该端口由另一个实例占用，所以必须先做进程检查。

本壳刻意让探测保持**只读**——不同于 pi-web 自己的 `listRunRecords`，它在探测期间从不删除过期记录。过期记录只是被忽略。

### 端口选择

`pi-web` 没有端口回退：端口被占用时它会以 "Next.js exited unexpectedly" 退出。因此本壳在启动前先选定端口：

1. 用 `bind()` 探测 `127.0.0.1:30141` —— 空闲则使用。
2. 否则从 `30151` 向上扫描（最多 500 次），取第一个空闲端口。
3. 否则通过绑定端口 `0` 向内核申请一个临时端口。

### 停止

| 路径 | 机制 | 升级阶梯 | 确认 |
| --- | --- | --- | --- |
| 自有 | 直接向启动的子进程发信号 | `SIGINT`（10s）→ `SIGTERM`（5s）→ `SIGKILL` | 无 |
| 附加 | `pi-web stop --port N` | 由上游处理 | 有，模态警告 |

### 日志

仅追加的日志位于 `~/Library/Logs/PiWeb/pi-web.log`。启动的 `pi-web` 的 stdout 与 stderr 都重定向到同一个文件，启动失败会在文件尾部留下原因；`menu build:` 行记录了每次菜单重建时的状态（实例数、热键模式、`tapDisabled`、标签页数、版本行位置）。菜单提供 `打开日志` 与 `在 Finder 中显示日志`，`make log` 可跟踪该文件。

### 版本

`V0.8.0-20261025` 作为菜单最后一行显示在 `退出 Pi Web` 下方，是禁用且仅用于显示的条目。它来自唯一一处：

| 来源 | 值 | 写入 Info.plist 为 |
| --- | --- | --- |
| `VERSION` 文件 | `0.8.0` | `CFBundleShortVersionString` |
| 构建时的 `date +%Y%m%d` | `20261025` | `CFBundleVersion` |
| 两者拼接 | `0.8.0-20261025` | `PiWebVersion` |

因此升级版本就是：编辑 `VERSION`，运行 `./build.sh`。Swift 中没有任何硬编码，日期也从不手工维护。`make check-docs` 会校验两语言 README 与本文件的版本示例是否都跟上了 `VERSION`。

`VersionInfo` 从 bundle 读回该键并加上前缀 `V`；在构建产物之外则回退为 `V0.0.0-dev`，而不是显示空白。`--version` 打印完全相同的字符串。

### 配置与偏好

存储在 bundle 域 `com.piweb.desktop` 中，可用 `defaults write com.piweb.desktop <key> <value>` 设置。

| 键 | 类型 | 默认值 | 作用 |
| --- | --- | --- | --- |
| `PiWebStopAttachedOnQuit` | Bool | `true` | `退出 Pi Web` 是否也停止附加实例。可在菜单中切换。 |
| `PiWebHotKeyEnabled` | Bool | `true` | 右侧 Option 全局热键是否启用。由 `右侧 Option 唤起窗口` 菜单项切换。 |
| `PiWebExecutablePath` | String | 未设置 | `pi-web` 可执行文件的显式路径；发现优先级最高。 |
| `PiWebLoginShellPATH` | String | 未设置 | 一次性登录 shell 探测捕获并缓存的 `PATH`。 |
| `PiWebLoginShellPiWeb` | String | 未设置 | 从登录 shell 捕获并缓存的 `pi-web` 路径。 |
| `PiWebTabs` | Data (JSON) | 未设置 | 持久化的已打开标签页：`{ "url": String, "color": Int }` 数组。恢复时会重写到当前 pi-web base。 |
| `PiWebTabsSelected` | Int | `0` | 选中标签页的索引，与 `PiWebTabs` 一同持久化。 |

由于 GUI 启动不会继承登录 shell，应用会用 `/bin/zsh -lic 'command -v pi-web; echo "$PATH"'`（超时 5 秒）向登录 shell 询问一次，把结果缓存到 UserDefaults，并回退扫描 `/opt/homebrew/bin`、`/usr/local/bin`、`~/.local/bin`、`~/.bun/bin`、`~/.npm-global/bin` 以及 `npm prefix -g`。显式路径始终优先。

| 变量 | 默认值 | 作用 |
| --- | --- | --- |
| `PI_WEB_DESKTOP_EXECUTABLE` | 未设置 | 显式 `pi-web` 可执行文件；优先于发现（仅次于 `PiWebExecutablePath`）。 |
| `PI_WEB_ARCHS` | `arm64 x86_64` | 仅构建时：`build.sh` 编译哪些架构，例如 `PI_WEB_ARCHS=arm64 ./build.sh` 只出一份本机切片，本地迭代更快。 |
| `PI_WEB_DESKTOP_PORT` | `30141` | 首选端口覆盖；`--port` 优先于它。 |
| `PI_WEB_SIGN_IDENTITY` | 未设置 | 仅构建时：`build.sh` 的代码签名身份（名称或 SHA-1）；回退到 `PiWeb Local Signing` 证书，再回退到 ad-hoc。 |
| `PI_CODING_AGENT_DIR` | `~/.pi/agent` | 存放 `pi-web-run/` 的 agent 目录；会展开 `~`、`~/` 与 `file://`。 |
| `HOME` | 用户主目录 | `~` 展开以及日志 / 支持目录的基路径。 |

GUI 启动时，应用先探测，再附加或启动，然后打开窗口；它从不启动第二个实例。双击已在运行的应用会发送 `com.piweb.desktop.activate` 分布式通知，弹出正在运行实例的菜单，因此该操作从不悄无声息。

### 应用图标

bundle 图标来自 `Resources/AppIcon.jpg`，由 `build.sh` 通过 `sips` + `iconutil` 转换为 `Contents/Resources/PiWeb.icns`（全部十个必需尺寸，`CFBundleIconFile` = `PiWeb`）。

源图仅为 282x267 且非正方形，因此先**居中裁剪**为正方形：不拉伸、不补色带。由于源图太小，512 与 1024 条目是放大得到的，看起来偏软。在同一路径放入至少 1024x1024 的正方形源图并重新构建即可解决；无需改动代码。

这只改变*应用*图标（Finder、启动台、显示简介）。**菜单栏状态图标不受影响**——它仍是 `MenuController.updateIcon()` 绘制的 SF Symbol 加 `Pi` 文本。

## 开发与发布

### 构建

```sh
./build.sh                    # 通用二进制：arm64 + x86_64，然后签名
./build.sh --run              # 构建并启动
PI_WEB_ARCHS=arm64 ./build.sh # 只出本机切片，本地迭代更快
make build                    # 等价于 ./build.sh
```

`build.sh` 对每个架构跑一次 `swiftc`（都指定 `-target <arch>-apple-macos13.0`），再用 `lipo -create` 合成通用二进制——仍然只有 Apple 自带工具，零依赖红线不破。`swiftc`/`lipo` 只要 Xcode Command Line Tools。

> 在 Apple 芯片上交叉编译 `x86_64` 时，链接器可能打印 `ignoring file '/Library/Developer/CommandLineTools/usr/lib/swift/macosx/libswiftCompatibilityPacks.a': fat file missing arch 'x86_64'`。这是 CLT 自带的向后兼容静态库缺 x86_64 切片导致的**无害告警**，通用二进制仍然生成；Intel 侧的真正执行由 CI 的 `macos-13` runner 覆盖。

### 验证

```sh
make verify                   # 构建 + 无头验证套件（scripts/verify.sh）
VERIFY_FULL=1 make verify     # 再跑真实 pi-web 的启动→就绪→停止循环
build/PiWeb.app/Contents/MacOS/PiWeb --self-test
```

`scripts/verify.sh` 只使用一次性端口 `30199`，绝不触碰 `30141` 上的实例，并在结束时清理它启动的一切；它还会断言产物是**通用二进制**，并运行文档一致性检查。

### 文档一致性

```sh
make check-docs
```

`scripts/check-docs.sh` 是零依赖的 bash 检查，专门盯住三类容易漏掉的漂移：版本示例（两个 README 与 `CHANGELOG.md`）必须等于 `VERSION`；两个 README 的截图、命令行标志、UserDefaults 键与环境变量集合必须一致；`docs/images` 里的文件必须被引用或登记。`make verify`、`make release` 与 CI 都会跑它。

### 发布链路

```sh
make release                  # = ./scripts/release.sh
./scripts/release.sh --dry-run # 绿了就停，不建 tag
```

`scripts/release.sh` 先拒绝脏工作区和已存在的 tag，再跑文档检查与完整验证套件，然后 `git tag -a v<VERSION>` 并推送分支与 tag。**发布本身由 GitHub Actions 从 tag 构建**（`.github/workflows/release.yml`）：`./build.sh` → 断言通用二进制 → 文档检查 → 打包 `PiWeb-<版本>.zip` → 创建 Release。本地不产出发布物，也不提交任何构建产物。

因此一次发布就是：

1. 改 `VERSION`（并在 `CHANGELOG.md` 顶部加一节，链接 `v<VERSION>`）。
2. 提交（`chore: release vX.Y.Z` 或用带 `(vX.Y.Z)` 的 `feat:`/`fix:` 主题）。
3. `make release`。

`.github/workflows/ci.yml` 在 `macos-13`（Intel）和 `macos-14`（Apple 芯片）上各跑一遍 `./build.sh` + `scripts/verify.sh --no-build`，并断言通用二进制——Intel runner 是唯一真正执行 `x86_64` 切片的地方。

### 项目结构

```text
pi-web-desktop-macos/
├── Sources/                    由 swiftc 编译的 Swift 源码（无 SPM）
│   ├── main.swift              入口 + 无头验证模式 + 单实例锁
│   ├── MenuController.swift    NSStatusItem 菜单、图标与菜单动作
│   ├── MainMenu.swift          真实 NSApp.mainMenu（App / 编辑 / 标签页 / 浏览 快捷键）
│   ├── AppWindow.swift         单个 NSWindow + 原生标签栏，每个标签页一个 WKWebView
│   ├── TabBar.swift            原生标签栏、调色板与标签项视图
│   ├── TabStore.swift          标签页 + 选中索引的 UserDefaults 持久化
│   ├── TabSupport.swift        纯函数：标签 URL 重写 / 关闭 / 相邻索引
│   ├── HotKeyMonitor.swift     右侧 Option 全局热键（CGEvent tap / NSEvent 监视器）
│   ├── StatusController.swift  探测 / 启动 / 停止编排与 UI 状态
│   ├── ProcessManager.swift    pi-web 解析、子进程启动、就绪等待、信号升级
│   ├── RunRecords.swift        运行记录解析、校验顺序与分类
│   ├── PortPlanner.swift       bind() 探测、回退扫描与临时端口
│   ├── EnvironmentResolver.swift 登录 shell 探测与子进程 PATH 组装
│   ├── BrowserOpener.swift     Chrome 系应用模式打开与默认浏览器回退
│   ├── PiWebCommands.swift     上游 `pi-web stop --port N` 调用
│   ├── LoginItem.swift         SMAppService.mainApp 开机自启
│   ├── Preferences.swift       基于 UserDefaults 的偏好
│   ├── StopMenu.swift          可测试的逐实例停止子菜单模型
│   ├── VersionInfo.swift       VERSION + 构建日期组合与显示
│   ├── Logger.swift            仅追加的文件日志
│   ├── AppConfig.swift         常量与 agent 目录解析
│   ├── HTTPProbe.swift         HTTP 存活探测
│   └── SelfTest.swift          `--self-test` 断言
├── Resources/AppIcon.jpg       应用图标源图（构建时居中裁剪）
├── docs/
│   ├── ARCHITECTURE.md         启动器的设计说明
│   └── images/                 README 使用的截图与清单（docs/images/README.md）
├── scripts/
│   ├── install.sh              构建、复制到 /Applications 并重新注册
│   ├── verify.sh               无头验证套件（make verify）
│   ├── check-docs.sh           文档一致性检查（make check-docs）
│   ├── release.sh              打 tag 并推送，触发发布（make release）
│   └── capture-screenshots.sh  重新生成 docs/images 截图
├── .github/                    CI / 发布工作流与 issue 模板
├── build.sh                    swiftc 构建（通用二进制）、.app 组装与代码签名
├── Makefile                    help / build / run / install / uninstall / verify / check-docs / release / clean / version / log
├── VERSION                     语义化版本的唯一来源
├── CHANGELOG.md                发布历史
├── AGENTS.md                   给 AI 协作者的仓库规则（纳入版本管理）
├── CONTRIBUTING.md             贡献指南
├── SECURITY.md                 安全策略
├── CODE_OF_CONDUCT.md          贡献者公约
└── LICENSE                     MIT
```

`build/` 是生成产物，不纳入版本控制。

## 已知限制

- **未测试：** 在开发环境中未开启 `开机自启`（`SMAppService.mainApp`），因为 bundle 位于仓库内时注册会创建一个指向该处的登录项。菜单反映 `SMAppService` 返回的真实状态。
- 浏览器探测只检查四个规范的 `/Applications` 路径（Chrome、Edge、Brave、Arc）；非标准安装位置会回退到默认浏览器。这仅影响无头的 `--open-url` 标志——GUI 使用原生窗口。
- 探测是只读的，且从不清理过期记录（有意为之）。注意*附加*停止路径会调用 `pi-web stop`，上游会在该命令中清理过期记录。
- 本壳仅在内存中跟踪归属；本壳崩溃后，它先前启动的实例在重启后会变成附加实例（仍可停止，此时通过 `pi-web stop`）。
- 日志是仅追加的，没有轮转；长期高频使用需要自己清理 `~/Library/Logs/PiWeb/pi-web.log`。
- 下载的构建是 ad-hoc 签名、未公证的，首次打开需要一次 Gatekeeper 确认。
- `--stop-port`、`--test-cycle`、`--test-fallback` 与 `--test-quit` 用于验证，不属于正常菜单流程。
- `docs/images/menu.png` 采集自 v0.5.0 的菜单，尚未包含 0.6.0/0.7.0 加入的标签页与热键条目。
- 第二次启动触发的屏幕菜单弹出在无头测试会话中未能截图（macOS 没有为该配件应用渲染程序化弹出菜单）；显示代码路径会执行，菜单内容由 `menu build:` 日志行与自检覆盖。

## 路线图

- [ ] 公证并签名的发布构建（Developer ID + `notarytool`）。
- [ ] 针对最新 GitHub release 的更新检查（`pi-web` 自己的 `pi-web update --check` 是另一件事）。
- [ ] 1024x1024 的正方形源图，去除偏软的 512/1024 放大条目。
- [ ] 重采 `docs/images/menu.png`，让它包含标签页与热键条目。
- [ ] Homebrew tap / cask。

## 贡献

欢迎贡献。请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)、[AGENTS.md](AGENTS.md) 与 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)，并按照 [SECURITY.md](SECURITY.md) 报告漏洞。提交 PR 前请运行 `make verify`（它包含 `make check-docs`）。

## 许可证

基于 [MIT License](LICENSE) 发布。Copyright (c) 2026 bestxia0。

## 致谢

本启动器是上游 **pi-web** 项目（`@agegr/pi-web`）的轻量前端，复用了它的运行记录格式、`pi-web stop --port N` 命令与端口行为。感谢 pi-web 的作者与 Pi 社区。

# 阅读 Lite 项目现状报告

> 生成日期：2026-11-09  
> 代码基线：v1.5 / build 30（`CFBundleShortVersionString = 1.5`，`CFBundleVersion = 30`）  
> 远端提交：`8fba63ffab3c8df854f22993f31a036ad33f1810`  
> 目标设备：iPhone 4S（iOS 9.3.6，armv7，越狱，AppSync Unified）  
> 适用读者：接手本项目的新会话 / 新开发者  
> 说明：本报告基于当前源码快照与已完成的构建、发布记录整理。源码中的行号会随修改变化，正文优先用“文件 + 类/函数名”定位。

---

## 0. 先看这里：五个最重要的结论

1. **项目主体已经可用**：本地 TXT/EPUB 阅读、书架、详情、排版面板、TTS、书签、WebDAV/legado 双向进度同步、阅读统计、应用内更新、GitHub Actions 构建都已实现，build 30 已发布。
2. **源码目前放在临时目录，且本地没有 `.git`**：源码在 `C:\Users\25744\AppData\Local\Temp\opencode\work`，这是最大的工程风险。临时目录一旦被清理，项目源码和未提交修改都会丢失。**建议第一件事是把源码复制到持久目录并初始化 git / 推送远端。**
3. **build 30 的“应用内直接安装 IPA”链路还没有被真实端到端验证**：build 29 的旧更新器仍然走 WebDAV/itms-services，无法自升级到 build 30，所以 build 30 必须先用 Filza/AppSync 手动安装一次。装好后，要等 build 31 发布才能验证新的“下载 → 本机安装 → 删除 → 重启”链路。
4. **更新发现依赖抓取 Gitee/GitHub Release 页面的 HTML**，这是当前最脆弱的外部依赖：页面结构变化、发布说明里没有 `Build NN`、资源名不是 `YueduLite.ipa`，都会导致漏更新或版本判断错误。建议改成“优先读取固定 JSON 清单，HTML 只做兜底”。
5. **打开一本书可能被同步阻塞**：首页/书架打开书时会先 `sync.pullBook`，阅读器 `loadChapters` 又拉一次；而 `pullBook` 实际会拉取整个 `bookProgress/`、阅读统计和旧格式进度，首次同步可能非常慢。离线或弱网时表现为“点开书半天没反应”。这是 build 31 最值得优先修的用户体验问题。

---

## 1. 项目定位与当前现状

### 1.1 一句话定位

“阅读 Lite”是一个**完全运行在 iPhone 4S 本机**的轻量阅读器：原生 Objective-C + JavaScriptCore，本地解析 TXT/EPUB，通过 WebDAV 与安卓版“阅读”（legado）共享书架进度，不依赖在线书源搜索，安装包为未签名 armv7 IPA。

### 1.2 运行环境与硬约束

| 项目 | 约束 |
|---|---|
| 设备 | iPhone 4S，3.5 英寸，320×480 pt，A5 双核，512 MB RAM |
| 系统 | iOS 9.3.6（最低声明 iOS 9.0） |
| 架构 | armv7（32 位）；IPA 内 Mach-O 为 `feedface`，cputype 12 |
| 安装方式 | 越狱 + AppSync Unified，Filza 或命令行安装未签名 IPA |
| 构建 | Theos + iPhoneOS9.3 SDK，GitHub Actions `macos-15` 交叉编译 |
| JS 引擎 | JavaScriptCore；不支持正则 lookbehind 等新语法 |
| 网络 | iOS 9 根证书库旧，项目选择信任任意 HTTPS 证书 |
| 包体 | 约 331 KB（build 30） |

### 1.3 当前版本与发布状态

| 项目 | 值 |
|---|---|
| 版本 / 构建 | v1.5 (build 30) |
| 提交 | `8fba63ffab3c8df854f22993f31a036ad33f1810` |
| GitHub Release | `438238758`，资产 `725829458` |
| Gitee Release | `1287848`，附件 `3637490` |
| Gitee 下载 | `https://gitee.com/jyz2574461147/yuedu-lite/releases/download/v1.5/YueduLite.ipa` |
| GitHub 页面 | `https://github.com/Daniel123999/yuedu-lite/releases/tag/v1.5` |
| IPA 大小 | 331,445 B |
| SHA256 | `468BF3939F83B7953356155B6DDBD8AA8CAA1F14C46B3812C217BCBEA5172E8E` |
| 本地 IPA | `C:\Users\25744\Documents\Default Project\YueduLite-v1.5-build30-armv7.ipa` |
| CI | GitHub Actions run #44 成功 |

### 1.4 源码位置与工程风险

| 路径 | 说明 |
|---|---|
| `C:\Users\25744\AppData\Local\Temp\opencode\work` | 当前源码根目录（**临时目录，无 `.git`**） |
| `...\work\ios` | iOS 工程、Objective-C、JS 引擎、Makefile、打包脚本 |
| `...\work\.github\workflows\build-ios.yml` | CI 构建流程 |
| `...\opencode\publish.ps1` / `gitee_publish.ps1` / `publish-notes.js` | 发布脚本 |
| `...\opencode\gh_token.txt` / `gitee_token.txt` | GitHub / Gitee 令牌（**不要删除、不要提交**） |
| `...\opencode\android` | 安卓 legado 参考实现（`TextFile.kt`、`ReadRecord.kt` 等） |

**风险：** 源码根目录只有 `ios/` 和 `.github/`，没有 `README`、`LICENSE`、`CHANGELOG`，也没有本地 git 历史。建议尽快：

```powershell
# 示例：复制到持久目录（不要复制 .theos 构建产物）
robocopy "C:\Users\25744\AppData\Local\Temp\opencode\work" "C:\Users\25744\Documents\yuedu-lite" /E /XD .theos .git
cd "C:\Users\25744\Documents\yuedu-lite"
git init
git add .
git commit -m "import build 30 source"
git remote add origin <远端地址>
git push -u origin main
```

---

## 2. 技术架构

### 2.1 技术栈

| 层 | 技术 |
|---|---|
| UI | Objective-C + UIKit（手写布局，无 Storyboard） |
| 业务引擎 | JavaScript（`engine.js`，约 134 KB）+ `engine-core.js`（HTML/文本解析，约 39 KB） |
| 桥接 | JavaScriptCore `JSContext` + `YLNative` 原生对象 |
| 网络 | `NSURLSession`，全部收敛在 `EngineBridge.m` 和 `YLAppUpdater.m` |
| 解析 | 原生 ZIP（`zipList` / `zipReadText` / `zipReadBase64`）、CoreText 字体注册 |
| 存储 | 本地 JSON 文件 + `NSUserDefaults` |
| 同步 | WebDAV（PROPFIND/GET/PUT/MKCOL），兼容 legado 目录结构 |
| 打包 | Theos + `ldid` + `zip`，输出未签名 IPA |
| CI | GitHub Actions，macOS runner，Theos + iPhoneOS9.3 SDK |

### 2.2 分层架构

```
┌─────────────────────────────────────────────────────────┐
│ UIKit 控制器层                                            │
│ Home / Bookshelf / BookDetail / Reader / Toc / Cloud /   │
│ Settings / 更新 UI                                        │
└───────────────────────┬─────────────────────────────────┘
                        │ API shared（串行队列）
                        ▼
┌─────────────────────────────────────────────────────────┐
│ API.m：把 /api/xxx 映射成引擎 action                      │
└───────────────────────┬─────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────┐
│ EngineBridge.m：JSContext + YLNative 原生能力             │
│ 文件 / 网络 / ZIP / Base64 / MD5 / 字体 / 延时 / 日志     │
└───────────────────────┬─────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────┐
│ engine-core.js：HTML 解析、实体解码、文本转换              │
│ engine.js：状态、书架、进度、同步、统计、导入、EPUB、书签  │
└───────────────────────┬─────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────┐
│ 本地文件：Documents/yuedu/*.json + books/fonts/covers     │
│ 远端：WebDAV/<dir=legado>/books + bookProgress + readStats│
└─────────────────────────────────────────────────────────┘
```

### 2.3 启动链路

1. `AppDelegate didFinishLaunchingWithOptions:`
2. `YLStore prepare`：确定根目录（默认 `Documents/yuedu`），创建 `books/fonts/inbox/covers`，做写入探测；失败自动回退默认目录。
3. `YLFontManager reload`：注册已导入的 TTF/OTF。
4. `YLTheme applyAppearance`：应用全局主题、夜间模式、强调色。
5. `YLAppUpdater cleanupStalePackages`：清理上次更新残留的 `yuedu-update-*.ipa`。
6. 创建 `UIWindow`，根控制器为 `YLNavigationController(HomeViewController)`。
7. 若 `yl.autoCheckUpdate` 为真（默认是），1.5 秒后静默检查更新。
8. 进入后台时 `applicationDidEnterBackground` 触发一次 `sync.push`。

### 2.4 原生桥能力（`YLNative`）

| 能力 | 说明 |
|---|---|
| `docsDir/storeRoot/booksDir/fontsDir/inboxDir/coversDir` | 目录查询 |
| `setStoreRoot` | 修改保存根目录并迁移 |
| `fonts/reloadFonts` | 字体列表与重新注册 |
| `readText/readTextFile/writeText` | 文本读写（`readTextFile` 做编码探测） |
| `readBase64/writeBase64` | 二进制读写 |
| `exists/remove/mkdir/listDir/fileSize/copy` | 文件系统 |
| `fetch/downloadTo` | HTTP（信任任意证书、可下载到文件） |
| `base64Encode/base64Decode/md5/decodeText` | 编码工具 |
| `zipList/zipReadText/zipReadBase64` | ZIP/EPUB 读取 |
| `now/defer/log` | 时间、延时回调、日志 |

**设计原则：** 只有 `EngineBridge.m` 和 `YLAppUpdater.m` 做 HTTP；`API.m` 用串行队列保证 JSContext 不被并发访问。

### 2.5 本地数据布局

```
Documents/yuedu/                 # 可通过设置修改根目录
├── config.json                  # 配置：WebDAV、自动上传、阅读时长、设备 ID、章节映射…
├── sources.json                 # 书源（当前 UI 不使用）
├── shelf.json                   # 书架
├── progress.json                # 阅读进度
├── bookmarks.json               # 书签（按书 key 分组）
├── local.json                   # 本地书元数据（路径、章节、封面、简介…）
├── books/                       # 本地 TXT / EPUB
├── fonts/                       # 导入字体
├── inbox/                       # 收件箱（字体/书籍导入）
├── covers/                      # 封面缓存
└── cache/                       # 章节/目录/下载临时缓存；启动时每周清一次
```

### 2.6 远端 legado 布局

```
<WebDAV URL>/<dir，默认 legado>/
├── books/                                   # 安卓 legado 的书籍文件（TXT/EPUB）
├── bookProgress/<书名>_<作者>.json           # 单本进度（核心兼容点）
├── readStats.json                           # iOS 自建：按设备分桶的阅读时长
├── progress.json                            # iOS 旧版全量进度备份
├── readRecord.json / readRecordDetail.json  # 安卓 legado 阅读记录（尽力读取）
└── backup/、readRecord/                     # 安卓可能出现的其他位置
```

进度文件名严格按 legado 规则：`"name_author".normalizeFileName()` 后对 `% / 空格 " # & ( ) + , : ; < = >` 等做百分号转义，例如 `书名_作者.json`。

### 2.7 API 路由表（`API.m`）

| 方法 | 路径 | action |
|---|---|---|
| GET | `/api/ping` | `ping` |
| GET | `/api/sources` | `sources.list` |
| GET | `/api/shelf` | `shelf.list` |
| POST | `/api/shelf` | `shelf.add` |
| POST | `/api/shelf/remove` | `shelf.remove` |
| GET | `/api/search` | `search`（当前无 UI） |
| GET | `/api/book` | `book.info`（当前基本只走本地） |
| GET | `/api/toc` | `toc` |
| GET | `/api/content` | `content` |
| GET | `/api/progress` | `progress.get` |
| POST | `/api/progress` | `progress.save` |
| GET | `/api/cloud/books` | `cloud.list` |
| POST | `/api/cloud/fetch` | `cloud.fetch` |
| POST | `/api/cloud/import` | `cloud.import` |
| GET | `/api/settings` | `settings.get` |
| POST | `/api/settings` | `settings.save` |
| GET | `/api/webdav/config` | `webdav.config`（返回真实密码，仅原生更新流程） |
| GET | `/api/store` | `store.get` |
| POST | `/api/store/root` | `store.setRoot` |
| POST | `/api/sync/test` | `sync.test` |
| POST | `/api/sync/pull` | `sync.pull` |
| POST | `/api/sync/push` | `sync.push` |
| POST | `/api/sync/pullBook` | `sync.pullBook` |
| POST | `/api/sync/pushBook` | `sync.pushBook` |
| POST | `/api/local/import` | `local.import`（无 UI 入口） |
| POST | `/api/local/importPath` | `local.importPath`（无 UI 入口） |
| POST | `/api/backup/importPath` | `backup.importPath`（无 UI 入口） |
| POST | `/api/inbox/scan` | `inbox.scan`（Settings 中有方法但未接线） |
| GET | `/api/export/legado` | `export.legado` |
| POST | `/api/cache/clear` | `cache.clear` |
| GET | `/api/cache/info` | `cache.info` |
| GET | `/api/stats` | `stats.get` |
| POST | `/api/stats/add` | `stats.add` |
| POST | `/api/bookmark/list` | `bookmark.list` |
| POST | `/api/bookmark/add` | `bookmark.add` |
| POST | `/api/bookmark/remove` | `bookmark.remove` |
| POST | `/api/bookmark/clear` | `bookmark.clear` |

> 注：`API.m` 的 GET/POST 分发是手写 if-else，新增接口要同时改两处（`API.m` 路由 + `engine.js dispatch`），否则返回“未知接口”。

### 2.8 引擎 action 分组

- 基础：`ping`
- 书架：`shelf.list/add/remove`
- 书源（遗留）：`sources.list/save`、`search`、`book.info`、`toc`、`content`
- 进度：`progress.get/save`
- 同步：`sync.pull/push/pullBook/pushBook/test`
- 存储：`store.get/setRoot`
- 字体：`font.list`
- 云端：`cloud.list/fetch/import`
- 设置：`settings.get/webdav.config/settings.save`
- 导入：`export.legado`、`local.import/importPath`、`backup.importPath`、`inbox.scan`
- 缓存：`cache.clear/info`
- 统计：`stats.get/add`
- 书签：`bookmark.list/add/remove/clear`

---

## 3. 已实现功能清单

状态说明：✅ 已实现且主流程可用；⚠️ 可用但存在明显隐患/限制；❌ 缺失或未接线。

| 模块 | 状态 | 说明 |
|---|---|---|
| 首页当前书卡片 | ✅ | 封面/完整书名占位图、进度、继续阅读 |
| 首页统计磁贴 | ⚠️ | 累计阅读时长、读过的书；依赖远端拉取，弱网可能延迟 |
| 首页快捷入口 | ✅ | 云端书库、我的书架、同步进度 |
| 启动自动续读 | ✅ | `autoResumePending` 默认 YES，进入首页自动打开最近一本书 |
| 书架列表/大图标 | ✅ | 设置中切换，旧 mode=2 自动归位大图标 |
| 全部/本地过滤 | ✅ | 顶栏分段控件 |
| 长按书籍详情 | ✅ | 封面、阅读记录、书籍简介、目录、开始阅读 |
| 云端书库 | ✅ | WebDAV 递归扫描 `books/`，支持 TXT/EPUB/ZIP 备份 |
| 云端封面 | ✅ | 同目录 `书名.jpg` / `cover.jpg` / `封面.jpg` |
| 本地 TXT 阅读 | ✅ | 编码探测 UTF-8/GB18030/Big5，章节规则分章 |
| 本地 EPUB 阅读 | ⚠️ | 解析 OPF spine，转纯文本；丢失图片/CSS/复杂排版 |
| 本地导入 UI | ❌ | `local.import`、`inbox.scan` 有引擎能力，但界面没有入口 |
| 翻页模式 | ✅ | `UIPageViewController`，左右翻页/上下滚动 |
| 翻页动画 | ✅ | 仿真卷页 / 平移滚动；仅翻页模式可切换 |
| 全屏阅读 | ✅ | 点击正文中间隐藏上下栏和状态栏；左右 28% 区域翻页 |
| 排版面板 Aa | ✅ | 翻页、动画、字号、行距、段距、字距、四边距、字体、背景、章节标题、页眉、页脚、粗体、斜体 |
| 字体导入 | ✅ | TTF/OTF，从收件箱或文件选择器导入；iOS 9 上文档选择器可能闪退，主推收件箱 |
| 主题/夜间模式 | ✅ | 白/米黄/浅绿/夜间；全局夜间模式和阅读背景 |
| 阅读方向 | ✅ | 自动/竖屏锁定/横屏锁定 |
| 目录 | ✅ | 当前章节高亮、滚动定位、点击跳转 |
| 书签 | ⚠️ | 添加、跳转、清空、当前页标记；只显示最近 8 条，无单条删除 |
| TTS | ⚠️ | 中文语音、按标点分句、朗读/暂停/继续、长按停止；章末停止，无自动下一章，语速固定 |
| 阅读进度保存 | ✅ | 翻页/滚动防抖保存，退出保存 |
| 自动上传 | ✅ | 3 秒防抖 + 30 秒冷却 + 失败指数退避（上限 600 秒） |
| 手动同步 | ✅ | 设置/书架/首页均有入口 |
| legado 进度同步 | ✅ | `bookProgress/<name>_<author>.json`，远端更靠前则采纳 |
| 章节号重映射 | ⚠️ | 用 `durChapterTitle` 映射到本机章节；标题对不上时可能夹到最后一章 |
| 旧格式兼容 | ✅ | `progress.json`、`bookProgress.json`、`readRecord.json` 尽力读取 |
| 阅读统计 | ⚠️ | 本机累计 + 多设备分桶 + 安卓 readRecord；双写 NSUserDefaults，口径有重复风险 |
| 设置 | ✅ | 6 段：WebDAV、外观、同步、字体与存储、工具、应用 |
| WebDAV 折叠 | ✅ | 默认折叠，展开后编辑 URL/用户名/密码/目录 |
| 缓存管理 | ✅ | 查看大小、清空；启动时每周自动清一次 |
| 文件管理 | ✅ | 尝试用 Filza/iFile scheme 打开存储目录 |
| 应用内检查更新 | ⚠️ | Gitee→Gitee→GitHub 三级；HTML 抓取；下载进度条；本机安装 |
| 自动检查更新 | ✅ | 默认开启，启动 1.5 秒后静默检查 |
| 更新安装 | ⚠️ | `ipainstaller` → `MobileInstallation` → `LSApplicationWorkspace`；未端到端验证 |
| 安装后重启 | ⚠️ | `/bin/sh` 后台 `uiopen`/`open`，0.6 秒后 `exit(0)`；失败需手动点图标 |
| 构建 | ✅ | Theos armv7 + iPhoneOS9.3 SDK + GitHub Actions |
| 发布 | ✅ | Gitee + GitHub 双发布，Release 说明含 Build 号 |
| 书源搜索 | ❌ | 用户明确不要搜索 UI；引擎仍有遗留代码 |

---

## 4. 关键机制详解

### 4.1 legado 双向同步

#### 4.1.1 拉取（pull）

- 入口：
  - 首页打开书：先 `POST /api/sync/pullBook`，再进入阅读器。
  - 书架打开书：先 `pullBook`，再进入阅读器。
  - 阅读器 `loadChapters`：**又调用一次 `pullBook`**（除非从详情页带了 chapters）。
- `sync.pullBook` 实际执行的是完整的 `pullProgress`：
  1. `pullBookProgressFiles`：列出 `bookProgress/`（最多 400 个 JSON），按 `修改时间|大小` 缓存跳过未变文件；对不认识的进度文件最多尝试 80 个；每个下载超时 20 秒。
  2. `pullReadStats`：下载 `readStats.json`（15 秒超时），并 `pullLegadoReadTime` 读取 `readRecord.json` / `backup/readRecord.json` / `readRecord/readRecord.json` / `readRecordDetail.json`（每个 12 秒），目录和根目录各试一轮。
  3. `pullLegacyProgress`：下载旧 `progress.json`（20 秒）。
  4. 只有在完全没有安卓进度文件、也没有旧格式进度时，才回退 `pullReadRecord`。
- 采纳规则 `progressAhead`：先比章节序号，序号相同再比章内位置；远端更靠前才覆盖本机。
- 远端书不在书架时，挂到 `legado-<hash>` 的 pending 进度；书加入书架后按书名 + 作者合并。
- 云端进度里的章节号按安卓分章计算；本机用 `durChapterTitle` 找到同名章节再换算，避免整章偏差。
- 每次学到“章节标题 → 安卓章节号”都会写入 `state.config.chapterIndexMaps[key]`；单本超过 600 条会整体清空重来。

#### 4.1.2 推送（push）

- `sync.pushBook`：立即推送当前书，`checkRemote: true`，先 GET 远端进度；远端领先则采纳，不覆盖。
- 自动推送：`saveProgressEntry` 标记 `pendingPush[key]`，3 秒后执行；30 秒冷却；失败后 60 秒起指数退避，上限 600 秒。
- 全量推送 `sync.push`：遍历所有进度，每本都可能先 GET 一次；最后上传 `progress.json` 和 `readStats.json`。
- 上传字段：`name`、`author`、`durChapterIndex`、`durChapterPos`、`durChapterTime`、`durChapterTitle`。

#### 4.1.3 进度文件命名

```js
base = name + "_" + author
base = base.replace(/[\\/:*?"<>|]/g, "_")
base = base.replace(/%/g, "%25") ... // 空格 %20、# %23、& %26 等
file = "bookProgress/" + base + ".json"
```

### 4.2 阅读统计

- 本机时长：`config.readSeconds`（秒），由 `stats.add` 累加。
- 多设备：`readStats.json` 的 `devices` 对象，每台设备只写自己的桶；拉取时排除本机 `deviceId`，其余相加。
- 安卓：`pullLegadoReadTime` 从 `readRecord*.json` 求和；`readTime` 毫秒在 `>= 10000` 时按毫秒转秒；单设备超过 20 年视为脏数据丢弃。
- 旧数据迁移：`migrateReadStats` v2，清掉旧的 `legado-android` 桶并强制重算。
- 首页显示：`stats.get` 返回 `totalSeconds = localSeconds + remoteSeconds`；`booksRead` 按进度记录中的书名分组，有作者时按作者去重，无作者算 1 本。
- 双写：阅读器退出时同时 `POST /api/stats/add` 和写 `NSUserDefaults["yl.stats.readSeconds"]`；首页只在引擎总时长为 0 时使用 NSUserDefaults 兜底。

### 4.3 导入、编码与大小限制

- 支持 `.txt` / `.epub`；云端额外支持 `.zip`（仅 legado 备份：`bookshelf.json` + `readRecord.json`）。
- 大小上限 `MAX_BOOK_BYTES = 12 MB`；超过直接拒绝，提示“iPhone 4S 建议不超过 12 MB”。
- TXT 编码：BOM（UTF-8/UTF-16LE/BE）→ HTML meta `charset` → UTF-8 → GB18030 → Big5。
- EPUB：`META-INF/container.xml` → OPF → manifest/spine → 每个 spine 项转纯文本；读取 `dc:title`、`dc:creator`、`dc:description`；封面从 OPF/guide 或同目录图片提取。
- TXT 简介：跳过短行和章节标题行，取前 4 段、最多约 300 字。
- 章节缓存：内存中最多保留 2 本正文；磁盘 `cache/` 每周启动清一次。
- 云端扫描：深度 3，最多 400 本书、60 个目录；先扫 `books/`，为空再扫根目录。

### 4.4 应用内更新与安装

#### 4.4.1 检查更新（`YLAppUpdater`）

- 源顺序：
  1. `https://gitee.com/jyz2574461147/yuedu-lite`
  2. `https://gitee.com/Daniel123999/yuedu-lite`
  3. `https://github.com/Daniel123999/yuedu-lite`
- 每个源请求 `/releases/latest`，单次 20 秒；从最终 URL 或 HTML 提取 tag。
- 从 HTML 提取第一个 `Build <n>`；从 HTML 找 `.ipa` 资源链接；找不到就用 `…/releases/download/<tag>/YueduLite.ipa` 兜底。
- 版本比较：远端版本 > 本地 `CFBundleShortVersionString`，或版本相同但远端 build > 本地 `CFBundleVersion`。
- 自动检查默认开启（`yl.autoCheckUpdate` 未设置时返回 YES）。

#### 4.4.2 下载与安装

1. 下载到 `NSTemporaryDirectory()/yuedu-update-<tag>.ipa`。
2. 用 `NSURLSessionDownloadTask` + `YLTransferProgress` 每 0.25 秒轮询字节数更新进度条。
3. 安装（后台线程，最多阻塞约 120 秒）：
   - 优先 `/usr/bin/ipainstaller <path>`（也查 `/usr/local/bin`、`/var/jb/usr/bin`）。
   - 失败则 `dlopen` `MobileInstallation.framework`，调用 `MobileInstallationInstall`。
   - 再失败则 `LSApplicationWorkspace installApplication:withOptions:`（通过 IMP 调用）。
4. 成功后删除 IPA；失败则保留并提示路径，要求确认 AppSync Unified。
5. 重启：`/bin/sh -c "sleep 2; uiopen yuedulite:// || open <bundleId> || uiopen ..."`，0.6 秒后 `exit(0)`。

### 4.5 签名与权限

- `make_ipa.sh` 在打包前用 `ldid -S entitlements.plist` 重新签名二进制。
- `entitlements.plist`：
  - `platform-application`
  - `com.apple.private.security.no-container`
  - `com.apple.private.security.no-sandbox`
  - `com.apple.private.mobileinstall.allowedSPI`（Install/Upgrade/Uninstall/Lookup/Browse）
  - `get-task-allow`
- 目的：允许 `posix_spawn` 调用 `ipainstaller`，并允许调用 `MobileInstallation`。
- 依赖：设备已越狱、已安装 AppSync Unified；否则安装会失败。

### 4.6 排版与主题

- `YLTheme` 单例，所有设置保存在 `NSUserDefaults`。
- 字号 13–30；行距 2–16；段距 0–20；字距 0–6；四边距 0–48。
- 字体：系统 / 宋体 / 黑体 / 楷体 + 导入字体（CoreText 注册）。
- 粗体/斜体：`fontOfSize:bold:italic:` 生成 traits；自定义字体不支持斜体时用合成斜体矩阵兜底；分页和滚动使用同一字体。
- Aa 面板按 320×480 竖屏设计：固定 11 行 × 32 pt，双列步进器，面板可滚动，`panelContentHeight = 11 * 32 + 6`。
- 全屏：上下栏是覆盖层，淡入淡出，不触发重排；状态栏随 `barsHidden` 隐藏。
- 翻页：`UIPageViewController` 的水平翻页；仿真卷页用 `PageCurl`，否则 `Scroll`。iOS 9 的 `UITextView` 在 `UIPageViewController` 里末尾约两行会被裁掉，代码中有补偿处理。

### 4.7 性能设计

- 12 MB 文件上限，避免 4S 解码时被 jetsam。
- 正文内存缓存最多 2 本。
- 进度文件按 `修改时间|大小` 缓存，未变不下载。
- 云端扫描有深度/数量上限。
- 自动上传有防抖、冷却、指数退避。
- 阅读时工具条覆盖层淡入淡出，避免重排/重分页。
- 图片封面按目标尺寸重绘并缓存（首页/书架）。

---

## 5. 当前存在的问题

### 5.1 问题总表

| ID | 优先级 | 问题 | 影响 |
|---|---|---|---|
| P0-1 | P0 | 源码在临时目录且无本地 git | 可能整体丢失，无法回滚 |
| P0-2 | P0 | 更新安装链未端到端验证，build 29 无法自升级 | 用户可能卡在旧版；安装失败无回滚 |
| P0-3 | P0 | 更新发现依赖 HTML 抓取 | 页面改版/说明缺 Build 就漏更新 |
| P1-1 | P1 | 打开书阻塞且重复拉取全量进度 | 弱网/离线点开书长时间无响应 |
| P1-2 | P1 | 本地导入 UI 缺失 | 只能从云端导入，Filza 放书无法入库 |
| P1-3 | P1 | 统计双写、后台时长丢失、远端合并口径 | 时长/读书数可能不准 |
| P1-4 | P1 | 书签只显示 8 条、不能单条删除 | 多书签无法管理 |
| P1-5 | P1 | TTS 章末停止、语速固定、无后台控制 | 连续听书体验差 |
| P1-6 | P1 | 12 MB 上限 + 整章排版内存峰值 | 大书/长章节可能卡顿或被杀 |
| P1-7 | P1 | 信任任意 TLS + 明文 WebDAV 密码 + ATS 全开 | 安全风险 |
| P1-8 | P1 | 无自动化测试，异常大量被吞 | 回归风险高，排错困难 |
| P1-9 | P1 | GitHub 国内不可达，Gitee 镜像需手动同步 | 更新源可能失效 |
| P2-1 | P2 | 书源/搜索遗留代码 | 维护成本、误改风险 |
| P2-2 | P2 | 全量上传每本先 GET | 书多时同步慢 |
| P2-3 | P2 | 章节映射 600 条上限整体清空 | 极端情况下映射丢失 |
| P2-4 | P2 | 每周清空 cache | 可能删掉刚下载的临时文件（概率低） |
| P2-5 | P2 | 320×480/横屏适配有限 | 横屏或大字体下面板可能拥挤 |
| P2-6 | P2 | 发布脚本硬编码 build/SHA/Release ID | 每次发版要手改，易错 |
| P2-7 | P2 | 验证脚本解析 plist/armv7 较粗糙 | 可能误报 |
| P2-8 | P2 | 无 README/LICENSE/CHANGELOG | 接手成本高 |
| P2-9 | P2 | 封面占位图/图标资源不完整 | 某些尺寸可能用默认图标 |

### 5.2 P0 详解

#### P0-1 源码在临时目录且无 git

- 现状：`C:\Users\25744\AppData\Local\Temp\opencode\work` 只有 `ios/` 和 `.github/`，没有 `.git`。
- 影响：系统清理临时目录、OpenCode 清理工作区、误删都会导致源码丢失；无法查看历史 diff，无法回滚。
- 建议：立即复制到持久目录，初始化 git，至少推送到一个远端（Gitee 优先）。把 `gh_token.txt` / `gitee_token.txt` 加入 `.gitignore`，不要提交。

#### P0-2 更新安装链未端到端验证

- 现状：build 30 的新安装链代码已完成，但用户仍在 build 29；build 29 的更新器是旧的 WebDAV/itms-services 方案，无法安装 build 30。
- 风险：
  - build 30 必须手动安装一次；如果 entitlements 或 AppSync 不匹配，可能启动失败。
  - `ipainstaller` 可能不存在或行为不同；`MobileInstallationInstall` 返回值/权限在 iOS 9.3.6 上未验证；`LSApplicationWorkspace` 可能被沙盒拒绝。
  - 安装覆盖当前运行中的 App 可能被系统终止；`exit(0)` 可能来不及执行；`uiopen`/`open` 可能不存在。
  - 安装成功后没有校验新版本号；失败没有回滚。
- 建议：
  1. 先手动安装 build 30，确认能启动，执行 `ldid -e YueduLite` 检查 entitlements。
  2. 发布 build 31，用 build 30 的应用内更新做一次真机端到端测试。
  3. 安装前把当前 IPA 备份到 `/var/mobile/Documents`，失败可回滚。
  4. 安装成功后读取 `CFBundleVersion` 校验；失败时保留 IPA 并给出明确日志。
  5. 考虑加入“仅下载 IPA，交给 Filza 安装”的保守模式作为兜底。

#### P0-3 更新发现依赖 HTML 抓取

- 现状：`YLAppUpdater` 用 `NSString rangeOfString` / 正则从 Release 页面找 tag、`Build N`、`.ipa` 链接。
- 风险：
  - Gitee/GitHub 页面结构改版 → 解析失败。
  - 页面里第一个 `Build N` 可能来自旧 Release 或更新日志，导致版本判断错误。
  - Release 说明必须写 `Build NN`，否则同版本号的新构建不会被发现。
  - 资源名必须是 `YueduLite.ipa`，否则兜底 URL 404。
  - 每次检查最多 3×20 秒，弱网体验差。
- 建议：增加固定 JSON 清单（见 6.1），HTML 只做兜底；清单包含 `version/build/tag/ipa/sha256/notes/minOS`，并可做 SHA256 校验。

### 5.3 P1 详解

#### P1-1 打开书阻塞且重复拉取全量进度

- 证据：
  - `HomeViewController openBook:` → `POST /api/sync/pullBook` → 进入 Reader。
  - `BookshelfViewController openBookAtChapter:` → `POST /api/sync/pullBook` → 进入 Reader。
  - `ReaderViewController loadChapters` → 再次 `POST /api/sync/pullBook` → `/api/toc`。
  - `sync.pullBook` 调 `pullProgress`，会拉 `bookProgress/`、`readStats.json`、`readRecord*.json`、`progress.json`。
- 影响：首次同步或弱网时，点开书可能几十秒无响应；离线时每个请求都要等超时。
- 建议：
  - 新增 `sync.pullBookProgress(key)`：只按当前书的 `name_author` 构造远端路径，最多 GET 一个文件；同时只拉当前书的 `readStats`（或完全不拉）。
  - UI 先显示本地章节和上次位置，后台再拉；远端更靠前时提示“已同步到云端位置”，不要阻塞首屏。
  - 去掉 Reader 的重复 pull：由打开方负责一次，Reader 只读本地；或加 `skipPull` 参数。
  - 给整个 `pullBook` 加总超时（如 3 秒），超时就先打开。

#### P1-2 本地导入 UI 缺失

- 证据：`SettingsViewController` 有 `scanInbox` 方法，但没有任何 `didSelectRow` 调用；`API.m` 有 `/api/inbox/scan`、`/api/local/import`、`/api/local/importPath`，但 ObjC 没有入口。
- 影响：用户把 TXT/EPUB 放进 `Documents/yuedu/inbox` 或用 Filza 放到 `books/`，应用不会自动识别；目前只能通过“云端书库”下载。
- 建议：
  - 书架顶栏加“+”菜单：`从收件箱导入` / `扫描书籍目录` / `从 Filza 选择`。
  - 启动时可选自动扫描 inbox（只扫 `.txt/.epub`，跳过 `yuedu` 目录）。
  - 导入时显示进度、成功数量和失败原因。
  - 扫描 `books/` 中未被 `local.json` 记录的书籍，补录入库。

#### P1-3 统计口径

- 问题点：
  - 阅读器同时写引擎 `config.readSeconds` 和 `NSUserDefaults["yl.stats.readSeconds"]`；首页只在引擎总时长为 0 时读后者，两个存储可能长期不一致。
  - 阅读时长只在 `viewWillDisappear` 累加；App 进入后台、锁屏、被系统杀死时不会触发，TTS/后台阅读时间会丢失。
  - `stats.get` 会触发 `pullReadStats`，首次可能拉 `readStats.json` + 多轮 `readRecord*.json`，弱网时首页统计磁贴长时间显示 `--`。
  - `remoteReadSeconds` 把 `legado-android` 桶和其他设备桶相加；如果安卓 `readRecord` 的总时长与 `readStats` 中某设备桶重叠，可能重复计算。
  - `booksRead` 遍历的是 `progressMap`，包含 `legado-` pending 记录；可能显示“读过的书”多于书架数量。
- 建议：
  - 统一为引擎单一数据源；NSUserDefaults 只做迁移或本地缓存，不作为第二本账。
  - 在 `applicationDidEnterBackground` / `willResignActive` 记录一次会话时长，并处理 `applicationWillTerminate`。
  - 首页先显示上次缓存值，再异步刷新；`stats.get` 不阻塞首屏。
  - 明确“读过的书”口径：只统计书架内且进度 > 0 的书，或明确包含云端 pending 书。
  - 给统计同步加开关，避免用户不关心时产生网络请求。

#### P1-4 书签管理

- 现状：`showBookmarkSheet` 只列最近 8 条；没有单条删除；只能清空本书。
- 建议：新增书签列表页（按章节排序、左滑删除、点击跳转）；保留当前页 ±30 字标记；导出/导入书签可选。

#### P1-5 TTS

- 现状：`AVSpeechSynthesizer`，中文 voice，`rate = 0.47`、`pitch = 1.0` 固定；按中文标点分句；章末 `didFinishSpeechUtterance` 后停止，不自动下一章；无后台控制/锁屏播放信息。
- 建议：
  - 增加语速/音调设置，持久化到 `YLTheme` 或独立 TTS 设置。
  - 章末自动加载下一章并继续，跨章保持播放状态。
  - 配置 `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter`，支持锁屏暂停/继续。
  - 记住每本书的朗读位置，重新进入可继续。
  - 长按停止的交互可加提示，或改成面板按钮。

#### P1-6 内存与 12 MB 限制

- 现状：`MAX_BOOK_BYTES = 12 MB`；TXT 解码后在 JS/ObjC 中保留整本字符串；分页时为整章构建 `NSAttributedString` 和 `pageRanges`；`textCache` 最多 2 本。
- 风险：接近 12 MB 的 TXT、超长章节、EPUB 解压都可能造成内存峰值，4S 容易被 jetsam。
- 建议：
  - 分章懒加载：只保留当前章 + 前后各一章；分页按需计算。
  - 对单章长度设上限，超长章节分块排版。
  - 大文件导入前给出更明确的警告；提供“精简模式”（关闭页眉页脚/动画）。
  - 用 Instruments / `memory warning` 日志在真机验证 8–12 MB 样本。

#### P1-7 安全

- 现状：
  - `EngineBridge` 和 `YLAppUpdater` 都实现了 `URLSession:didReceiveChallenge:`，对任意 `ServerTrust` 直接使用凭据。
  - `Info.plist` 的 `NSAppTransportSecurity.NSAllowsArbitraryLoads = true`。
  - WebDAV 密码明文存在 `config.json`；`/api/webdav/config` 会返回真实密码给原生更新流程。
- 影响：中间人可截获 WebDAV 凭据和更新 IPA；恶意 IPA 可被安装。
- 建议：
  - 至少限制信任范围到 Gitee/GitHub/用户配置的 WebDAV 主机；其他域名走系统默认校验。
  - WebDAV 密码迁移到 Keychain，config.json 只存引用。
  - 更新 IPA 增加 SHA256 校验（清单里提供）。
  - 提供“严格 TLS”开关，默认关闭以兼容旧设备，但让用户知情。

#### P1-8 无自动化测试

- 现状：有 `checkdelims.js` 括号检查、`test-engine.js` 之类的临时脚本，但 CI 只构建，不跑测试；大量 `catch (e) { /* 忽略 */ }`。
- 建议：
  - 用 Node 跑 `engine.js`，mock `YLNative` 的文件/网络，覆盖：
    - 进度文件名编码
    - `progressAhead` / `remapRemoteChapter`
    - 统计合并去重
    - TXT 分章 / EPUB 解析
    - 书签增删
  - CI 增加 `node checkdelims.js` + `node test-engine.js`。
  - 关键路径加日志级别，不要全部静默。

#### P1-9 更新源可达性

- 现状：Gitee 镜像优先，GitHub 兜底；Gitee 镜像仓库需要手动同步 Release 和 IPA。
- 风险：Gitee 页面/下载被限流、镜像未同步、GitHub 国内不可达。
- 建议：固定 JSON 清单 + 多镜像（Gitee raw、Gitee Pages、GitHub raw、jsDelivr 等）；清单和 IPA 都提供 SHA256；失败时给出“手动下载地址”。

### 5.4 P2 详解（摘要）

- **书源/搜索遗留代码**：`engine.js` 仍保留 `Source`、`searchBooks`、`requireSource`、`book.info/toc/content` 远程分支和 `sources.json`，但 UI 没有入口。建议删除或明确标记“实验性”，避免误改。
- **全量上传慢**：`pushProgress` 对每个 key 都可能先 GET 远端；书多时是 N 次网络往返。建议批量 PROPFIND 或只推当前书。
- **章节映射上限**：`chapterIndexMaps[key]` 超过 600 条直接清空，长书可能丢失映射；建议按最近使用 LRU 淘汰，而不是整体清空。
- **缓存清理**：每周启动清空 `cache/`，如果此时有云端下载临时文件，可能被删；建议只清超过 N 天的文件。
- **横屏/大字体**：Aa 面板固定 11 行，横屏高度 320 pt 时依赖滚动；可考虑横屏双栏或精简面板。
- **发布脚本硬编码**：`publish-notes.js` 里 build=30、SHA、Release ID 都是常量；每次发版要改。建议参数化或从 IPA/环境变量读取。
- **验证脚本**：`verify.ps1` 用 `[xml]` 解析 plist，只取 `dict.key`/`dict.string`，遇到 array/dict 会不准；armv7 检查依赖 magic/cputype，建议用 `file` / `otool` / `ldid -e` 交叉验证。
- **文档缺失**：没有 README、LICENSE、CHANGELOG；新会话只能靠本报告和源码。
- **图标资源**：`Info.plist` 引用 `Icon60x60`、`Icon40x40`、`Icon29x29`、`Icon76x76`，实际文件是 `@2x/@3x`；4S 是 @2x，通常没问题，但建议补齐 1x/其他尺寸并验证桌面图标。

---

## 6. 下一步优化建议与开发方向

### 6.1 建议的 build 31 范围（稳定性优先）

目标：**让现有用户安全地从 build 30 升到 build 31，并验证更新链路。**

1. **修复打开书阻塞**
   - 新增 `sync.pullBookProgress(key)`，只拉当前书进度。
   - Reader 首屏先本地渲染，后台同步；远端领先时提示并跳转。
   - 去掉 Home/Bookshelf + Reader 的重复 pull。
   - 验收：飞行模式点开书 < 1 秒进入；弱网 3 秒内进入。
2. **接线本地导入**
   - 书架“+”→ 从收件箱导入 / 扫描书籍目录。
   - 验收：Filza 放一本 TXT 到 inbox，点导入后出现在书架并可读。
3. **统计修正**
   - 单一数据源；后台/锁屏时长；首页先显示缓存值；统计拉取不阻塞。
   - 验收：离线首页立即显示上次统计；两台设备来回读不重复累计。
4. **更新清单**
   - 新增 `update.json`（Gitee Release 资产或 raw 文件），字段：`version`、`build`、`tag`、`ipa`、`sha256`、`notes`、`minOS`。
   - 更新器先读清单，失败再 HTML 兜底。
   - 验收：改 HTML 不影响检查；清单缺 Build 时仍能按 version 判断。
5. **更新安装校验**
   - 安装后读取 `CFBundleVersion` 校验；失败保留 IPA 并提示手动 Filza 安装。
   - 验收：build 30 → build 31 真机成功；故意破坏权限时能给出可操作提示。
6. **发布脚本参数化**
   - `publish-notes.js` 从 `Info.plist` / 参数读取 build、SHA、Release ID。
   - 验收：改版本号后一条命令完成双平台发布说明更新。

### 6.2 短期（1–2 周）

- 书签列表页 + 单条删除。
- TTS 语速/音调 + 章末自动下一章 + 锁屏控制。
- 云端书库搜索/排序/批量下载；封面缓存。
- 章节内容搜索（书内搜索）。
- 阅读进度百分比、剩余时长估算。
- 统计页：按天/周/月、阅读热力图（可选）。
- 错误提示统一：同步失败、网络失败、导入失败给出可操作建议。
- 崩溃日志：捕获 `NSSetUncaughtExceptionHandler`，写入本地文件，设置页可导出。

### 6.3 中期（1–2 个月）

- **EPUB 增强**：嵌套目录、图片、简单 CSS、脚注；或明确标注“纯文本模式”。
- **本地书库管理**：批量导入、重命名、删除、分组/标签、最近阅读。
- **同步增强**：冲突提示（保留本地/云端）、每本同步状态、仅 Wi-Fi、后台同步。
- **性能**：大文件分块/懒加载；用 SQLite 替代大 JSON（书架/进度/书签）以降低全量读写成本。
- **安全**：Keychain 存密码、更新包 SHA256、TLS 主机白名单。
- **UI**：横屏双栏、iPad 适配、动态字体（iOS 9 有限）、无障碍。

### 6.4 长期（架构/工程化）

- **单一数据层**：把 `shelf/progress/bookmarks/local` 从 JSON 迁移到 SQLite，提供迁移脚本；保留 JSON 导入/导出。
- **热更新引擎**：因为越狱分发，可考虑把 `engine.js` 做成可替换资源；但必须加签名/哈希校验，防止被替换。
- **多平台**：如果继续维护安卓参考实现，建立共享的协议文档（进度 JSON schema、文件名规则、统计 schema）。
- **发布流水线**：CI 构建 → 自动生成 `update.json` → 上传 Gitee/GitHub → 自动校验 SHA/armv7/entitlements → 生成发布说明。
- **文档**：README（功能/截图/安装）、CHANGELOG、CONTRIBUTING、LICENSE、故障排查。

### 6.5 不建议做 / 需要谨慎

- **不要恢复书源搜索 UI**：用户明确不要；现有遗留代码只会增加风险。
- **不要默认关闭 TLS 校验的“严格模式”**：旧设备兼容需要放宽，但应让用户知情并提供开关。
- **不要在 4S 上追求复杂动画/毛玻璃**：性能优先。
- **不要依赖 GitHub 作为唯一更新源**：国内不可达。
- **不要在没有回滚方案时自动覆盖安装**：至少保留上一版 IPA 或提供手动安装路径。

---

## 7. 开发、构建、发布 SOP

### 7.1 修改前

1. 确认源码已备份到持久目录（见 1.4）。
2. 不要用 PowerShell 5.1 的 `Set-Content` / 默认编码修改 `engine.js`、`EngineBridge.m`、`YLStore.m`、`SettingsViewController.m` 等含中文的文件；使用 `edit` 工具或 UTF-8 无 BOM 写入。
3. 不要删除 `gh_token.txt` / `gitee_token.txt`；不要提交到 git。
4. 改 `engine.js` 后先跑括号检查：

```powershell
node "C:\Users\25744\AppData\Local\Temp\opencode\checkdelims.js" `
  "C:\Users\25744\AppData\Local\Temp\opencode\work\ios\Resources\engine.js" `
  "C:\Users\25744\AppData\Local\Temp\opencode\work\ios\Resources\engine-core.js"
```

### 7.2 版本号

- 修改 `ios/Resources/Info.plist`：
  - `CFBundleShortVersionString`：如 `1.6`
  - `CFBundleVersion`：递增，如 `31`
- 修改 `engine.js` 的 `ping` / `YL.version`（当前 `1.5`），保持与 UI 显示一致（可选但建议）。
- Release 说明必须包含 `Build 31`（更新器靠它比较）。

### 7.3 构建

本地（需要 macOS/Theos）：

```bash
cd ios
make clean || true
make TARGET=iphone:clang:9.3:9.0 ARCHS=armv7
chmod +x make_ipa.sh
./make_ipa.sh
```

CI：推送到 `main`/`master` 或手动触发 `.github/workflows/build-ios.yml`。构建约 4 分钟。

### 7.4 验证

```powershell
# 1. 哈希 / 大小
Get-FileHash .\YueduLite.ipa -Algorithm SHA256
(Get-Item .\YueduLite.ipa).Length

# 2. 解包检查
#    Payload/YueduLite.app/YueduLite 存在
#    Info.plist 版本/build 正确
#    URL scheme yuedulite 存在
#    Mach-O magic=feedface, cputype=12 (armv7)
#    ldid -e 包含 platform-application / allowedSPI / no-container / get-task-allow
```

建议同时用 `file` / `otool -L` / `nm -u` 交叉验证，不要只依赖 `verify.ps1` 的粗略 plist 解析。

### 7.5 发布

**Gitee（优先）：**

- Release：`https://gitee.com/jyz2574461147/yuedu-lite/releases/tag/v1.5`
- 上传附件时 `access_token` 必须放在 query 参数；放在 form 里会 401 `code 40001`。
- Release PATCH 可以把 token 放 JSON body。
- 更新 Release 说明用 Node（UTF-8 安全），不要用 PowerShell 5.1。

**GitHub：**

- Release：`https://github.com/Daniel123999/yuedu-lite/releases/tag/v1.5`
- 用 `gh` 或 REST API 上传资产。
- 发布说明同样包含 `Build NN` 和 SHA256。

**发布后检查：**

- Gitee `/releases/latest` 是否 302 到新 tag。
- 下载 URL 是否 302 → CDN 200。
- Release 页面标题/正文第一个 `Build N` 是否是新 build。
- 应用内“检查更新”是否能发现新版本（build 30 上测试）。

### 7.6 编码与密钥红线

- `engine.js`、`EngineBridge.m`、`YLStore.m`、`SettingsViewController.m` 等中文文件：只用 UTF-8（无 BOM）。
- 发布说明/JSON 用 Node 写，不用 PowerShell 5.1 `Set-Content`。
- `gh_token.txt` / `gitee_token.txt` 只在本机使用，不写入源码、不提交、不贴到聊天。
- Release 说明里的 SHA256 必须与实际 IPA 一致。

### 7.7 回滚

1. 保留上一版 IPA（至少 build 30）在 `Documents` 或电脑上。
2. 更新失败时，Filza 手动安装上一版；书架/进度/设置都在 `Documents/yuedu`，覆盖安装不会丢。
3. 如果新版本启动崩溃，先用 Filza 回滚，再收集 `/var/mobile/Containers/Data/Application/<uuid>/Documents/yuedu/config.json` 和崩溃日志。
4. 如果 entitlements 导致启动失败，回滚到 build 29，调整 `entitlements.plist` 后重新构建。

---

## 8. 新会话快速上手

### 8.1 可直接粘贴给新会话的提示词

```text
项目：阅读 Lite（iOS 9.3.6 / iPhone 4S / armv7 / 越狱 / 未签名 IPA）
源码：C:\Users\25744\AppData\Local\Temp\opencode\work（临时目录，先备份）
当前版本：v1.5 build 30，commit 8fba63ffab3c8df854f22993f31a036ad33f1810
发布：Gitee release 1287848（附件 3637490）；GitHub release 438238758（资产 725829458）
IPA：C:\Users\25744\Documents\Default Project\YueduLite-v1.5-build30-armv7.ipa
SHA256：468BF3939F83B7953356155B6DDBD8AA8CAA1F14C46B3812C217BCBEA5172E8E

请先阅读 C:\Users\25744\Documents\Default Project\PROJECT_REPORT.md。
技术栈：ObjC UIKit + JavaScriptCore（engine.js/engine-core.js），Theos + GitHub Actions。
约束：armv7、iOS 9.3.6、320×480、12MB 书限、JSC 不支持 lookbehind。
当前优先事项：
1) 把源码备份到持久目录并初始化 git；
2) build 31 修复打开书阻塞/重复 pullBook；
3) 接线本地导入（inbox.scan 已有但 UI 未接）；
4) 统计单一数据源；
5) 更新改为 JSON 清单优先，HTML 兜底；
6) 发布 build 31 验证 build 30 的应用内更新链路。
不要：恢复书源搜索 UI；用 PowerShell 5.1 改中文源码；删除 token 文件。
```

### 8.2 前 30 分钟检查清单

- [ ] 确认源码路径存在；若在临时目录，先复制到 `C:\Users\25744\Documents\yuedu-lite`。
- [ ] 确认 `Info.plist` 版本/build。
- [ ] 确认 `engine.js` 能通过 `checkdelims.js`。
- [ ] 确认 build 30 真机能启动；`ldid -e` 查看 entitlements。
- [ ] 确认 Gitee Release 页面第一个 `Build N` 是 30。
- [ ] 确认 `publish-notes.js` 里的 build/SHA/Release ID 是否要更新。
- [ ] 确认 token 文件存在且未提交。
- [ ] 选一个最小改动（建议 P1-1 或 P1-2）开始。

### 8.3 待确认问题（下次会话问用户）

1. build 30 是否已经手动安装并成功启动？桌面图标/URL scheme 正常吗？
2. 是否愿意把源码迁出临时目录并推送到 Gitee/GitHub？
3. 下一版优先级：稳定性（打开书/统计/导入）还是功能（TTS/书签/EPUB）？
4. 是否需要保留书源/搜索代码作为未来功能，还是直接删除？
5. WebDAV 主要用坚果云还是自建？是否需要多账号？
6. 是否接受“仅下载 IPA，手动 Filza 安装”的保守更新模式作为兜底？

---

## 9. 附录

### A. 引擎 action 全量列表

`ping`、`shelf.list`、`shelf.add`、`shelf.remove`、`sources.list`、`sources.save`、`search`、`book.info`、`toc`、`content`、`progress.get`、`progress.save`、`sync.pull`、`sync.push`、`sync.pullBook`、`sync.pushBook`、`store.get`、`store.setRoot`、`font.list`、`sync.test`、`cloud.list`、`cloud.fetch`、`cloud.import`、`settings.get`、`webdav.config`、`settings.save`、`export.legado`、`local.import`、`local.importPath`、`backup.importPath`、`inbox.scan`、`cache.clear`、`cache.info`、`stats.get`、`stats.add`、`bookmark.list`、`bookmark.add`、`bookmark.remove`、`bookmark.clear`。

### B. 关键 NSUserDefaults 键

| 键 | 含义 |
|---|---|
| `yl.store.root` | 本地存储根目录 |
| `yl.theme.fontSize` | 字号 |
| `yl.theme.fontFamily` | 字体 |
| `yl.theme.lineSpacing` | 行距 |
| `yl.theme.paragraphSpacing` | 段距 |
| `yl.theme.letterSpacing` | 字距 |
| `yl.theme.insetLeft/Right/Top/Bottom` | 四边距 |
| `yl.theme.showChapterTitle` | 正文顶部章节标题 |
| `yl.theme.boldText` | 正文粗体 |
| `yl.theme.italicText` | 正文斜体 |
| `yl.theme.showHeader` | 页眉 |
| `yl.theme.showFooter` | 页脚 |
| `yl.theme.readerTheme` | 阅读背景（白/米黄/浅绿/夜间） |
| `yl.theme.pagedMode` | 翻页/滚动 |
| `yl.theme.pageCurl` | 仿真/平移 |
| `yl.theme.nightMode` | 全局夜间模式 |
| `yl.reader.orientation` | 阅读方向 |
| `yl.autoCheckUpdate` | 自动检查更新（默认 YES） |
| `yl.stats.readSeconds` | 阅读时长兜底（NSUserDefaults） |
| `kYLBookShelfModeKey` | 书架列表/大图标 |
| `kYLBookShelfFilterKey` | 全部/本地过滤 |

> `kYLBookShelfModeKey` / `kYLBookShelfFilterKey` 的实际字符串在 `BookshelfViewController.m` 中定义，修改时以源码为准。

### C. 状态文件字段（摘要）

- `config.json`：`autoPush`、`fontSize`、`webdav{url,username,password,dir,timeout}`、`deviceId`、`readSeconds`、`readStatsDevices`、`readStatsPullAt`、`readStatsVersion`、`chapterIndexMaps`、`progressCache`、`lastCachePrune`、`storeRoot`。
- `shelf.json`：`{ books: { key: {name, author, sourceUrl, bookUrl, coverPath, intro, lastChapter, addedAt, ...} } }`。
- `progress.json`：`{ books: { key: {name, author, chapterIndex, chapterTitle, pos, updatedAt, ratio, pending?} } }`。
- `bookmarks.json`：`{ key: [{index, pos, title, snippet, time}] }`。
- `local.json`：`{ key: {key, name, author, ext, path, coverPath, intro, chapters[], chaptersVersion, size} }`。

### D. 远端进度 JSON 示例

```json
{
  "name": "书名",
  "author": "作者",
  "durChapterIndex": 123,
  "durChapterPos": 456,
  "durChapterTime": 1730000000000,
  "durChapterTitle": "第 123 章 标题"
}
```

### E. 构建 / 发布相关路径

| 用途 | 路径 |
|---|---|
| CI | `C:\Users\25744\AppData\Local\Temp\opencode\work\.github\workflows\build-ios.yml` |
| Makefile | `...\work\ios\Makefile` |
| 打包 | `...\work\ios\make_ipa.sh` |
| 权限 | `...\work\ios\entitlements.plist` |
| 版本 | `...\work\ios\Resources\Info.plist` |
| GitHub 发布 | `...\opencode\publish.ps1` |
| Gitee 发布 | `...\opencode\gitee_publish.ps1` |
| 发布说明（UTF-8 安全） | `...\opencode\publish-notes.js` |
| 构建监视 | `...\opencode\watch2.ps1` |
| IPA 验证 | `...\opencode\verify.ps1` |
| 括号检查 | `...\opencode\checkdelims.js` |
| 引擎测试（临时） | `...\opencode\test-engine.js` |

### F. 已知死代码 / 遗留分支

- `engine.js` 的 `Source`、`requireSource`、`searchBooks`、`sources.list/save`、`book.info/toc/content` 远程分支。
- `sources.json` 及设置页的 `sources` 计数。
- `SettingsViewController scanInbox` 方法未接线。
- `API.m` 的 `/api/local/import`、`/api/local/importPath`、`/api/backup/importPath`、`/api/inbox/scan` 没有 UI 入口。
- `engine.js` 的 `export.legado` 有 action，但 UI 未使用（可能用于未来导出）。
- `TocViewController` 只加载目录，不做书内搜索。

### G. 术语

- **legado / 阅读**：安卓开源阅读 App，本项目同步协议的兼容目标。
- **bookProgress**：legado 的单本进度目录，文件名 `书名_作者.json`。
- **durChapterIndex/Pos/Time**：legado 进度字段（章节序号、章内位置、更新时间）。
- **pending 进度**：云端有、书架没有的书，临时挂在 `legado-<hash>` 下，等书加入后合并。
- **jetsam**：iOS 内存压力下杀进程的机制，4S 上尤其敏感。
- **AppSync Unified**：越狱插件，允许安装未签名 IPA。

---

## 10. 结论

项目已经跨过“能跑”的阶段：核心阅读、legado 同步、统计、更新、CI 发布都具备，build 30 是可用的基线。当前最大的风险不是功能不足，而是**工程可持续性**（源码在临时目录、无 git）和**更新链路的真实验证**（build 30 → build 31 尚未跑通）。建议下一版以“稳定性 + 可恢复性”为主，不要急着加新功能；先把打开书阻塞、本地导入、统计口径、更新清单这四件事做扎实，再考虑 TTS/书签/EPUB 增强。

---

*报告结束。若需要，我可以继续把源码复制到持久目录、初始化 git，或直接开始 build 31 的第一项修复。*

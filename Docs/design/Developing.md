# 开发参考（项目结构）

写 Moneyknows 产品代码时 **先读本文、[Architecture.md](Architecture.md)，以及对应功能篇**（Session / Market / Charting / Trading / …）。  
需求是产品输入；本文规定 **文件落点** 和 **必须复用的横切能力**。

源码根目录：`Moneyknows/`（与展示名 / target 名一致）。Xcode 工程生产 Bundle ID：`com.byteknows.moneyknows`。

`../money-app` **不是** 目录模板。不要按 RN 的 `services/` `store/` `hooks/` 一一建 Swift 文件。

环境对应 RN 的 `.env.*`：编译配置选主机，App 只读 `AppEnvironment`。

| RN | iOS |
| --- | --- |
| `.env.development` | `Config/Debug.xcconfig` + scheme **Moneyknows**（Debug） |
| `.env.staging` | `Config/Staging.xcconfig` + scheme **Moneyknows Staging** |
| `.env.production` | `Config/Release.xcconfig` + scheme **Moneyknows Release** |
| 本机改局域网 IP | `Config/Debug.local.xcconfig`（gitignore；从 `Debug.local.xcconfig.example` 复制） |

改完 xcconfig 后 `xcodegen generate` 再编。不要在 Swift 里写死第二套 URL。

---

## 1. 目录

```text
Moneyknows/
  App/                     组合根：启动、环境、注入、版本门禁
  Platform/                跨功能基础设施，不含交易/行情规则
    Logging/               os.Logger，按领域 category
    Errors/                错误类型、给用户看的句子
    Localization/          String Catalog（en / zh-Hans）、L10n
    HTTP/                  JSON 客户端：超时、取消、解码、公共头
    Socket/                Socket.IO 连接、重连、鉴权钩子（无业务事件语义）
    Cache/                 内存 / 磁盘缓存原语
    Storage/               Keychain、小文件落盘的统一入口
  Session/                 应用账号会话（令牌），不是券商凭证
  Mapping/                 自家后端路径 + DTO；不写界面、不写下单
  Brokerage/               券商账户抽象 + 当前账户
    Alpaca/                第一期唯一实现：REST + 交易 Socket
  Market/                  扫描、摘要、K 线仓库、实时订阅、秒线缓冲
  Trading/                 下单规则、数量、开盘保护、自动止盈止损
  Insights/                市场情绪、经济日历、新闻
  Notifications/           FCM 注册、历史、深链
  Preferences/             用户偏好 ↔ 后端
  Charting/                K 线表面：模型 + Lightweight Charts 适配
    Indicators/            VWAP / RSI / ADX / ATR（纯函数，可测）
    Lightweight/           唯一 import LightweightCharts
  Support/                 交易时段、美东时间、数量取整等无网络工具
  UI/
    Theme/                 颜色、字体、间距
    Components/            可复用控件（不发起业务请求）
    Screens/               按导航分组的屏幕
```

测试与源码镜像：`MoneyknowsTests/Support/`、`Market/`、`Trading/`、`Charting/Indicators/`。图表库适配可以少测，指标和开盘保护必须测。

| 目录 | 放什么 | 不放什么 |
| --- | --- | --- |
| `App/` | `MoneyknowsApp`、`AppEnvironment`、`AppModel`（注入）、版本门禁编排 | API 路径、下单、算 VWAP |
| `Platform/Logging` | `AppLog` categories | `print`、业务判断 |
| `Platform/Errors` | `AppError`、`UserFacingError` | 某屏私有的「出错了」字符串逻辑 |
| `Platform/Localization` | `L10n`、xcstrings | View 里写死的中英文 |
| `Platform/HTTP` | 通用 `HTTPClient`（可多实例、不同 baseURL） | `/v1/users/...` 具体路径 |
| `Platform/Socket` | 连接生命周期 | `trade` / `second-trade` 如何进 Store（那是 Market / Trading） |
| `Platform/Cache` | 带 TTL 的内存表、磁盘 JSON 箱 | 「K 线业务」字段名写死在 Platform |
| `Platform/Storage` | Keychain 包装、App 支持目录 | 把 token 当 UserDefaults 字符串 |
| `Session/` | 读写 App access/refresh、过期、登出清理编排入口 | Alpaca Key、扫描器 |
| `Mapping/` | money-api / gateway 的 `*API.swift` | `URLSession`、401 退出、SwiftUI |
| `Brokerage/` | `BrokerageAccount`、`BrokerageServing`、当前账户 Store | App 登录、扫描器 HTTP |
| `Brokerage/Alpaca` | Alpaca 主机、签名、订单 DTO | 开盘保护规则（在 Trading） |
| `Market/` | 棒仓库、订阅、扫描列表 Store | 图表库、Alpaca 下单 |
| `Trading/` | 下单用例、自动 TP/SL、持仓/订单/组合 Store | Alpaca URL、图表 |
| `Insights/` | 情绪 / 日历 / 新闻 Store | 自己再包一层 HTTP |
| `Notifications/` | token 注册、历史 Store、深链解析 | 扫描器 UI |
| `Preferences/` | 偏好 Store、与 PATCH 同步 | 主题色值（在 Theme） |
| `Charting/` | `ChartSurface` 输入输出、库适配 | 拉棒、算完再藏进 WKWebView 配置里的业务 |
| `Support/` | `MarketClock`、`OrderSizing` | 变成杂物抽屉（新工具先问该不该进领域） |
| `UI/Components` | 股票行、空态、徽标、确认框、分段 | `HTTPClient`、Store 内部类型泄漏 |
| `UI/Screens` | 一屏一个主文件，状态来自 Store | 复制扫描器页 |

新增目录必须同时改本文第 1 节。不要为「好看」建空的 `Services/`、`Helpers/`、`Managers/`。

---

## 2. 横切能力（必须复用）

加功能先在这里找。找不到再新增，并落在 `Platform/`（或 `Support/`），不要写进某一个屏幕。

### 2.1 日志 — `Platform/Logging/AppLog.swift`

| category | 用途 |
| --- | --- |
| `app` | 启动、版本门禁 |
| `http` | 自家后端 REST：方法、路径、状态码 |
| `socket` | 网关连接、重连 |
| `session` | 登录、刷新、登出（无令牌） |
| `brokerage` | 券商 REST/WS：主机类型、状态码、订单 id |
| `market` | 拉棒、订阅变更 |
| `trading` | 下单结果、自动 TP/SL（symbol、方向，不要密钥） |
| `chart` | 适配失败、数据形状不对 |
| `push` | 注册 token 成败（不要打出完整 token） |

- **不准记：** 密码、邀请码、App / Alpaca 密钥、`Authorization`、请求体里的 secret。
- 不要用 `print`。用户已经在界面上看到的句子不必再抄进日志。

### 2.2 错误 — `Platform/Errors/`

| 用这个 | 做什么 |
| --- | --- |
| `AppError` | 抛给上层（网络、解码、业务码、券商拒单） |
| `error.isCancellation` | 下拉刷新取消；**不要**弹红字 |
| `error.isUnauthorized` | App 令牌 401 且刷新失败；已登录流退出。登录页 401 只提示密码错误 |
| `UserFacingError.message(from:)` | 屏幕文案；走 `L10n`；取消和「该退出」返回 `nil` |

开盘保护、数量非法是 Trading 的领域错误，同样经 `UserFacingError` 映射，不要在按钮 action 里写死中文。

### 2.3 本地化 — `Platform/Localization/`

- `Localizable.xcstrings`：`en` + `zh-Hans`。
- 入口：`L10n.Auth.*`、`L10n.Market.*`、`L10n.Trading.*` … 按领域分子命名空间。
- 语言：偏好 `locale` 为 `en` / `zh` 时固定；`nil` 跟随系统。
- **不要**在 View 里写死句子。服务器 `message` 原样展示，我们的状态码用自己的句子。
- 日志、路径、symbol 保持英文，不进目录。

### 2.4 HTTP — `Platform/HTTP/HTTPClient.swift`

所有 JSON REST（自家后端 **和** 券商适配器）都走这一个类型，用 **不同实例**：

| 实例 | baseURL | 鉴权 |
| --- | --- | --- |
| App 主站 | `AppEnvironment.apiURL` | Bearer App token + `X-App-Version` + `X-Platform: ios` |
| 网关 REST | `AppEnvironment.socketHost`（订阅增删） | 同上 |
| 券商 | 由 `Brokerage/Alpaca` 按 paper/live 注入 | Alpaca Key/Secret（适配器里加头，不进 UI） |

- 超时默认 30s，可取消。
- **不要**在 `UI/`、`Market/`、`Trading/` 里 `URLSession.shared`。
- 路径只写在 `Mapping/*API` 或 `Brokerage/Alpaca/*API`。

未登录：`HTTPClient` + `Mapping/AuthAPI`。  
已登录自家后端：`AuthorizedSession` 取 token、401 刷新、失败退出。  
券商：`BrokerageServing` 内部自带凭证，**不**走 `AuthorizedSession`。

### 2.5 Socket — `Platform/Socket/`

只负责：连上 `AppEnvironment.socketHost` 的 namespace、带 token、重连、把 **原始事件名 + JSON** 交给订阅者。

- `/alpaca-stream`、`/ibkr-stream` 的事件含义在 `Market/` / `Insights/` / `Trading/` 里翻译进 Store。
- 不要在 Platform 里 `import` 领域 Store（避免环）。用回调或异步流上抛。

### 2.6 本地缓存 — `Platform/Cache/` + 领域仓库

两级原语，业务自己决定用哪一级：

| 原语 | 用途 |
| --- | --- |
| `MemoryCache` | 进程内、可设 TTL 与条数上限。分钟棒、秒线环缓、摘要 |
| `DiskCache` | Codable JSON，有预算（例如 20MB）。新闻、最近摘要、可选的「上一交易日分钟」 |

约定：

- Key 由领域拼（如 `bars:US:AAPL:2026-09-04:1Min:regular`），Platform 不理解业务。
- 凭证、令牌 **不准** 进 Cache，只进 `Platform/Storage` Keychain。
- 偏好：`Preferences` Store + 磁盘一份，登录后与服务器对齐；不是 Cache。
- 图表不缓存；它每次向 Market 要当前切片。
- 第一期不做 Core Data / SwiftData。不够用再开设计，不要先上重型数据库。

### 2.7 安全存储 — `Platform/Storage/`

| 数据 | 放哪 |
| --- | --- |
| App access / refresh / 过期 | Keychain，由 `Session/` 读写 |
| 券商账户密钥（按账户 id） | Keychain，由 `Brokerage/` 读写，**分账户 key** |
| 语言、主题、非机密偏好备份 | 磁盘或 UserDefaults，经 `Preferences/` |
| FCM token 开关 | 同 Preferences / Notifications，不是 Keychain |

登出：`Session` 触发清理清单——App 令牌、券商当前账户是否清（与 RN 对齐：登出清 Alpaca 凭证）、通知缓存、内存棒。具体清单实现时写在 `Session/LogoutCleanup`，各领域注册自己的一段，避免 Session 依赖所有模块。

---

## 3. 自家后端 vs 券商直连

```text
Mapping/AuthAPI          POST /v1/users/email/signin
Mapping/BarsAPI          GET  /alpaca/market/intraday-bars
Mapping/ScreenerAPI      GET  /intraday-stocks/...
Mapping/SubscribeAPI     GET/POST 网关 /alpaca/market/subscribe
Mapping/AIAPI            GET  /v1/ai/...
Mapping/PushAPI          FCM、通知历史
Mapping/PreferencesAPI   GET/PATCH /v1/users/preferences
```

`Mapping` **不调用** `/v1/subscription/*`（付费已不做）、不调用 `/auth/google/mobile`。

```text
Brokerage/Alpaca/AccountAPI     GET /v2/account
Brokerage/Alpaca/PositionsAPI   GET/DELETE /v2/positions
Brokerage/Alpaca/OrdersAPI      /v2/orders
Brokerage/Alpaca/TradeSocket    wss://…/stream  只听 trade_updates
```

`Trading` 只依赖：

```swift
protocol BrokerageServing {
    var account: BrokerageAccount { get }           // id、券商品牌、环境
    func portfolio() async throws -> Portfolio
    func positions() async throws -> [Position]
    func place(_ order: NewOrder) async throws -> Order
    func cancel(orderId:) async throws
    func replace(orderId:amendment:) async throws -> Order
    func closePosition(symbol:percentage:) async throws
    func fills(symbol: String, day: Date) async throws -> [Fill]  // 复盘：该美东日已成交
    var orderUpdates: AsyncStream<Order> { get }
}
```

第一期 `AlpacaBrokerage` 实现它。UI 和 Trading **看不到** Alpaca 类型名（文案「Alpaca」可以出现在设置页说明里）。

当前账户：`Brokerage/CurrentBrokerageStore`。第一期恒为唯一 Alpaca。以后加 Schwab 是新目录 + 新实现，不是复制 `Trading/`。

---

## 4. 图表与工具

- 领域算出 `[Bar]`、叠加线（VWAP）、`[PriceLine]`、`[ChartMarker]`，交给 `Charting/ChartSurface`。买卖点由 Trading 的成交转成 marker，图表不查单。
- `Charting/Lightweight/` 是唯一碰 `LightweightCharts` 的地方。
- `Charting/Indicators/`：`vwap(bars:)`、`rsi`、`adx`、`atr`，纯函数，单元测试。
- 仪表盘数字卡用 Swift Charts，放 `UI/Components/Stats/`，不要进 `Charting/`。
- `Support/MarketClock`：美东、盘前/盘中/盘后、假期、开盘保护是否生效。Trading 和 Market 都用它，不要各写一份 `dateHelper`。

---

## 5. UI

```text
UI/Screens/
  Root/            版本门禁、未登录栈、已登录 Tab
  Auth/            登录、注册、找回
  Home/            仪表盘
  Market/          扫描器目录、各扫描结果、详情、历史分钟
  TradeTab/        实时订阅列表
  Portfolio/       持仓、持仓详情、组合、订单
  Insights/        情绪、日历、新闻
  Notifications/
  Settings/        凭证、偏好、资料、其它（无付费页）

UI/Components/
  Feedback/        空态、加载、可重试错误
  Symbol/          股票行、搜索框
  Badges/          涨跌、今日盈亏、RSI/ADX/ATR
  Trading/         确认框、数量倍数、模拟/实盘条
  ChartChrome/     周期分段、蜡烛/线、VWAP 开关（不持有库）
```

屏幕通过注入的 Store 工作。组件只收结构体和闭包。  
新扫描器：新的 `Mapping` 方法 + `Market` 一个 fetch + **同一套** 结果列表屏。禁止复制 `YahooScreenersScreen` 改三个字。

---

## 6. 加功能时对号

| 你要做的事 | 进这里 | 复用 | 不要做 |
| --- | --- | --- | --- |
| 新屏幕 | `UI/Screens/…` | Components、L10n、UserFacingError | View 里 URLSession |
| 新文案 | `L10n` + xcstrings | 已有 key | 写死中文 |
| 已登录自家接口 | `Mapping/*API` | `HTTPClient`、`AuthorizedSession` | 新的 Alamofire 式封装 |
| 扫描器 | `Mapping` + `Market` + 共用列表屏 | 股票行 | 新的表格页 |
| K 线周期 | `Market` 聚合 + `Support` | 已有 1/3/5 | 新图表组件 |
| VWAP / 指标 | `Charting/Indicators` | 纯函数 | 写进 WebView |
| 下单 / 自动 TP/SL | `Trading` + `BrokerageServing` | `MarketClock`、`OrderSizing` | 屏幕里拼 Alpaca JSON |
| 新券商 | `Brokerage/<Name>/` 实现协议 | 同一 Trading Store | 复制持仓页 |
| 推送 | `Notifications/` | Mapping PushAPI | 在 AppDelegate 写业务跳转细节（可薄转发） |
| 缓存一种列表 | 领域 Store + `MemoryCache`/`DiskCache` | 原语 | 各页 `UserDefaults` 私货 |
| 日志 | `AppLog.<category>` | 已有 category | print |

---

## 7. 明确不要做

- 不要第二个 JSON 客户端、第二套 401 退出、第二套 Keychain 包装。
- 不要在 `UI/` 拼 `Bearer` 或 Alpaca Key。
- 不要让 `Market/` `import` LightweightCharts。
- 不要让 `Mapping/` 依赖 `Brokerage/`，也不要反过来。
- 不要预埋付费、Google、空的「添加券商」。
- 不要把 `Support/` 做成 `Misc/`。日期格式化若只给某一个领域用，放到该领域。
- 不要为对齐 RN 再建 `hooks/` 目录。

---

## 8. 改了结构就改本文

新增目录、新的复用入口、或不得不破例时，**同一变更里更新本文**。

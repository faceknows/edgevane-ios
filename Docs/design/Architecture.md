# 架构

**状态：** 结构已通过；功能细节见同目录其它篇  
**约束：** [09-工程与扩展原则.md](../requirements/09-工程与扩展原则.md)、[10-多券商账户.md](../requirements/10-多券商账户.md)

## 1. 一句话

Moneyknows iOS 是一个 **已登录的交易辅助客户端**：自家后端提供扫描、K 线、通知、AI 解读；**当前券商账户**（第一期只有 Alpaca）负责下单、持仓、组合。

界面不认识 URL，也不认识 Lightweight Charts 或 Alpaca 路径。

## 2. 分层与依赖

只允许实线向下。禁止 UI 调 Mapping/券商路径，禁止 Charting 调网络，禁止 Mapping 当「万能 Service」。

```text
                    ┌─────────────┐
                    │     UI      │  屏幕 + 可复用组件
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │  Market  │ │ Trading  │ │ Session  │
        │ Insights │ │  Prefs   │ │   Push   │
        └────┬─────┘ └────┬─────┘ └────┬─────┘
             │            │            │
             │            ▼            │
             │     ┌────────────┐      │
             │     │ Brokerage  │      │   当前券商账户（可换实现）
             │     └─────┬──────┘      │
             ▼           │             ▼
        ┌──────────┐     │      ┌───────────┐
        │ Mapping  │     │      │  Session  │
        │(自家后端)│     │      │  Keychain │
        └────┬─────┘     │      └─────┬─────┘
             │           ▼            │
             │    ┌────────────┐      │
             │    │ Alpaca 等  │      │
             │    │ 直连适配   │      │
             │    └─────┬──────┘      │
             └──────────┼─────────────┘
                        ▼
                 ┌────────────┐
                 │  Platform  │  日志 / HTTP / Socket / 缓存 / L10n / 错误
                 └────────────┘

        Charting（只吃棒/线/价线/标记）← Market 算好再喂；不进网络
        Support（交易时段、数量）← 无网络，可供 Trading / Market 测
```

| 层 | 目录 | 可以依赖 | 不可以 |
| --- | --- | --- | --- |
| UI | `UI/` | 领域 Store、Charting 的 **视图入口**、Platform 的 L10n/错误 | `URLSession`、路径字符串、Alpaca REST |
| 领域 | `Market/` `Trading/` `Insights/` `Notifications/` `Preferences/` | Mapping、Brokerage 抽象、Charting 模型、Support、Platform | SwiftUI 页面、具体图表库 |
| 券商 | `Brokerage/` | Platform HTTP（独立会话，**不带** App JWT） | Mapping、UI |
| 自家后端 | `Mapping/` | Platform HTTP / Socket（带 App JWT） | Brokerage、UI、Charting |
| 图表 | `Charting/` | Support（时间）、Platform 日志 | 任何网络、Trading |
| 平台 | `Platform/` | 系统框架 | 产品规则、API 路径 |

**硬规定：**

- 自家后端（扫描、分钟线、订阅网关、登录）走 `Mapping` + App 令牌。
- 券商交易（账户、持仓、订单、交易 Socket）走 `Brokerage`，凭证是券商的，不是 App JWT。
- 第一期 `Brokerage` 只有 Alpaca 一个实现；对外接口是「当前券商账户」，不是 `AlpacaKey`。
- IBKR 筛选取自 **自家后端**（`Mapping`），不是券商交易账户。

## 3. 领域怎么切

按用户任务切，不按 RN 的 service 文件名切。

| 领域 | 用户任务 | 主要数据 |
| --- | --- | --- |
| Session | 登录、令牌、登出 | 应用账号 |
| Market | 搜股票、扫描器、K 线、实时订阅、秒线 | 棒、快照、订阅列表 |
| Trading | 下单、撤单、自动止盈止损（改单底层 `replace` 保留，第一期无 UI） | 当前券商账户上的单与仓 |
| Insights | 情绪、日历、新闻 | 服务端 AI + 新闻流 |
| Notifications | 推送历史与跳转 | FCM + 历史 API |
| Preferences | 偏好、主题、语言 | 与 `/v1/users/preferences` 同步 |
| Brokerage | 当前用哪一个券商账户 | 第一期：一个 Alpaca |

仪表盘是 UI 组合，不是第五个后端。它读 Trading（盈亏/持仓/订单摘要）+ Market（搜索）。

## 4. 状态放哪

- **每个领域一个或少数 Store**（或等价的可观察对象），在 `App/` 注入。
- 列表刷新、分页、错误，放 Store，不放 View 的一堆 `@State`。
- 分钟棒、秒线缓冲、摘要：`Market` 缓存；图表只拿当前要画的切片。
- 不要全局「God Store」。也不要为每个屏幕复制一套网络状态。

## 5. 两个网络世界

```text
App 令牌 ──► money-api REST
         ──► money-gateway Socket + 订阅 REST

券商凭证 ──► Alpaca trading REST / trading WebSocket
         ──► （少数）Alpaca market data REST
```

两套 Client，两套 Base URL，两套鉴权。禁止用 App JWT 打 Alpaca，禁止用 Alpaca Key 打 money-api。

环境（Debug / Staging / Release）只改 `Config/*.xcconfig`，由 `App/AppEnvironment` 读 Info.plist。生产主机见需求 06。生产 Bundle ID 见需求 00 第 6 节。

## 6. 第一期刻意不做的结构

不预建空的 `Schwab/`、`IBKRTrading/`、`IAP/`、`GoogleSignIn/`。  
`Brokerage` 的协议与「当前账户」入口必须在；第二个实现等有需求再加目录。

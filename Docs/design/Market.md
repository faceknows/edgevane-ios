# 行情与详情

**状态：** 待验收  
**需求：** [02](../requirements/02-功能清单.md)、[03](../requirements/03-用户流程与页面.md)、[05](../requirements/05-图表.md)  
**落点：** `Market/`、`UI/Screens/Market/`、`UI/Screens/TradeTab/`、`UI/Screens/Home/`  
**图表合同：** [Charting.md](Charting.md)

## 1. Store

| Store | 职责 |
| --- | --- |
| `SymbolSummaryStore` | `GET /stocks/summaries`，按 symbol 缓存 |
| `BarStore` | 分钟（分会话）与日线仓库；key 含 market/symbol/date/session/timeframe |
| `SecondBarStore` | 已订阅 symbol 的秒线环缓（约 10 分钟） |
| `QuoteStore` | 已订阅最新成交价和盘口 bid/ask：`trade` + **`quote` 为主**，`latest-snapshot`（`bp` / `ap`）兜底 |
| `SubscriptionStore` | 网关 `{ me, all }`；添加/退订 |
| `ScreenerStore` | 当前扫描器结果（一种列表，换 fetch） |

详情页不自己持有网络客户端，只选 symbol、周期、开关，向这些 Store 要 `ChartModel` 零件。

## 2. 扫描器

目录屏列出第一期 8 项（需求 01）。  
结果屏 **一个** `ScreenerResultsView`：标题、筛选（仅价格斜率等有参数的扫描器注入）、`SymbolRow` 列表、点进详情。

价格斜率参数：日期、结束时间、窗口分钟、方向、最低价/量。其它扫描器按 RN 现有 query，缺省即可。

从通知带来的 `symbols`：目录顶上 chips，点进详情。

## 3. 实时订阅（交易 Tab）

- 列表 = `SubscriptionStore.me` + 摘要/最新价。
- 添加：输入代码 → subscribe。失败展示网关原因（含可能的服务端上限）。**客户端不按 Pro 限额拦截。**
- 退订：清该 symbol 秒线缓冲与盘口。
- 点行 → 详情。
- 未配券商账户：列表仍可用。
- 行情 Socket 未连接或断开：列表顶或空态旁显示「行情未连接」，不要假装没数据。

## 4. 股票详情

路由参数只要 `symbol`。

**始终：** 标题价（有订阅用 Quote 的 last；未订阅用摘要/快照）、**账户今日盈亏徽标**（Trading 组合盈亏，文案不要写成该标的盈亏）、RSI/ADX/ATR 等数字徽标（按当前 1/3/5 分钟棒现场算）、分钟图、盘前盘后、偏好控制的日线 / **纳指矮图**、加入订阅按钮。交易相关时间按美东。

**仅 `me` 含此 symbol：** 秒图、滑条、交易条、**退订**、盘口 bid/ask 与数量（`quote` 为主，快照兜底；都没有才用成交价，Q 条显示 —）。未订阅没有交易条；标题价用摘要/快照 last。

VWAP 开关默认开（实现时若与 RN 默认不一致，跟 RN）。  
3M/5M 不另存仓库，用 1 分钟聚合。

搜索：仪表盘搜索框，合法代码直接进详情（可先 summaries 校验，失败提示无此代码）。

## 5. 历史分钟 / 复盘

独立屏（仪表盘「历史分钟」入口）：选美东日期 + 已有 symbol（或本页再搜）。

- `BarsAPI` 拉该日 1 分钟（不写入「今天」的 `BarStore` 桶）。
- 本地算 VWAP；可切蜡烛/线、1/3/5 分钟。
- 若有当前券商账户：向 Trading 要该日该 symbol 的成交，编成 `ChartMarker` 叠在图上（见 [Charting.md](Charting.md) 4.1）。**模拟只标模拟、实盘只标实盘。**
- 下方可列当天成交（时间、方向、价、量），点一行等同 `pickedMarker`。
- 无账户或无成交：只看图，不报错。

这就是复盘的第一入口，不另做一套图表。

## 6. Socket 接入

登录后 `App` 打开 Platform Socket。

- `trade` / `quote` / `second-trade`：仅当 symbol ∈ `me` 才写入 Quote / SecondBar。
- 已订阅标的同时用 `latest-snapshot` 给 QuoteStore 兜底（`bp` / `ap` / `bs` / `as`；Socket `quote` 未到时盘口条也能显示数量）。
- 订阅变更后：新 symbol 开始收；退订立即停写并丢缓冲与盘口。
- 连接状态对 UI 可见。

## 7. 验收现象

- 八个扫描器都能进列表并打开详情。
- 未订阅无秒图、无交易条；订阅后出现，并能退订。
- 切 1/3/5 分钟与蜡烛/线、VWAP 符合图表设计。无 VXX。
- 历史分钟 / 复盘不改变详情里「今天」的棒；有成交时图上能看到买卖点。
- 交易 Tab 能加/删订阅且不出现升级页；断线时能看出未连接。

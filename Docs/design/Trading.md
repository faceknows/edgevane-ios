# 交易、持仓与券商账户

**状态：** 待验收  
**需求：** [04](../requirements/04-交易与风控.md)、[10](../requirements/10-多券商账户.md)  
**落点：** `Trading/`、`Brokerage/`、`Support/`、`UI/Screens/Portfolio/`、详情交易条

## 1. 当前券商账户

`CurrentBrokerageStore`：

- 第一期：0 或 1 个账户（Alpaca paper 或 live）。
- 凭证按 `account.id` 进 Keychain，禁止全局 `alpacaKey`。
- 对外只暴露 `BrokerageServing`（见 Developing）。
- 无账户：行情可用；交易条/持仓/组合/订单显示「去设置填写凭证」。
- 切换模拟/实盘：关掉旧连接、清空 Trading 内存、换实现或换主机、重拉。界面常驻「模拟/实盘」。

不预埋添加 Schwab 按钮。

Alpaca 直连路径只在 `Brokerage/Alpaca`：

| 动作 | Alpaca |
| --- | --- |
| 组合 | `GET /v2/account` |
| 持仓 | `GET /v2/positions` |
| 平仓 | `DELETE /v2/positions/:symbol` |
| 下单/查/改/撤 | `/v2/orders` |
| 某日成交（复盘） | `GET /v2/account/activities?activity_types=FILL`。`after`/`until` 为该美东日 00:00–次日 00:00（活动 `transaction_time`，能拿到几个月前提交、当天成交的 GTC）。不要用 `date=`（UTC 日历），也不要用 closed orders 的时间过滤/`before_order_id`（按 `submitted_at` 排序，不能以「碰到缓存 ID」停页）。用上一页最后一条 activity `id` 作 `page_token`。无 symbol 查询参数；按账户+美东日缓存整天 FILL，再本地过滤 symbol。同日同 `order_id` 的 FILL 合成一条（数量相加、价为 VWAP、`filledAt` 取最晚 `transaction_time`）。Fill 身份为 `order_id` + 美东成交日，跨日部分成交各记一天。**一单一标**仍只在同一天内合成。历史日 LRU（按日，不是按 symbol）；**当天每次重拉**。页面停留时订单更新后短防抖再拉当天 FILL，历史日不重拉；初次加载期间当天本地成交有变，结束后同样再拉。字段不完整的 FILL 抛 decoding。分页上限 20 页 × 每页最多 100 条 = 全账户当天 2,000 笔，超出或游标循环抛可本地化的 `orderHistoryIncomplete`，图照常、远程成交标记为空。本地订单只补 Activities 已成功、且提交日与成交日相同的那一日；失败日或跨日累计单不得用 `filled_qty` 补量，只提示不完整。 |
| 订单推送 | `wss://paper-api…/stream` 或 live，`trade_updates` |

`trading_blocked`：禁止下单并说明。

## 2. Trading Store

| Store | 职责 |
| --- | --- |
| `PortfolioStore` | 净值、现金、购买力、今日盈亏% |
| `PositionStore` | 开仓列表 / 按 symbol |
| `OrderStore` | 订单列表；取消；改单 |
| `OrderPlacement` | 用例：校验 + 调用 `BrokerageServing` |
| `AutoExit` | 自动止盈止损 |
| `DayFills` | 指定 symbol + 美东日的已成交，给复盘编 `ChartMarker`。只读当前环境（paper ≠ live） |

刷新：有账户且 App 在前台。`MarketClock` 判定开盘则 **3 秒**，否则 **15 秒**（开盘明显更勤，不必 1 秒）。  
另接收 **统一订单流**（见下）。

今日盈亏 ≤ **-1.5%**：仪表盘卡片警示色。

## 3. 统一订单流（去重）

两条来源都进 `OrderStore.apply(update)`：

1. 网关 `trade_updates`
2. Alpaca 直连 `trade_updates`

以 `order.id`（及 `updated_at`/`status`）去重。同一状态不重复 toast。  
`AutoExit` **只订阅 `OrderStore` 的「入场成交」**，不分别挂在两条 Socket 上。这样只连上网关也能同时做自动止盈和止损。

## 4. 下单用例

`Support/OrderSizing`：`max(floor(valuePerTrade / price), 1)`，再乘 1/3…3。  
`Support/MarketClock`：盘前 04:00–09:30 ET、常规、盘后 16:00–20:00、假期、开盘后 N 分钟保护（默认 30）。

`OrderPlacement.submit` 顺序：

1. 有当前账户且未 `trading_blocked`
2. 不在保护窗（否则 `L10n`：还要等几分钟）。手动下单、平仓、**自动止盈止损**都走这一条
3. 数量 ≥ 1，价格合法
4. 角色 `MAX_ORDER_VALUE`（若有）
5. 调用 `BrokerageServing`

| 动作 | 领域单 | 参考价 |
| --- | --- | --- |
| 限价买/卖 | limit，TIF day，可选 extendedHours（**盘前/盘后时段默认勾选**） | **买=bid，卖=ask**，缺则最新成交 |
| OTO | 仅偏好打开；入场 limit + 止盈，价差 ≥ 0.01 | 同上 |
| 止盈 | 对仓位反向 limit | 中间价或成交 |
| 止损 | stop；数量：可用/全部/自定义 | 同上 |
| 市价全平 | `closePosition` 100%，可撤挂单 | — |
| 限价平 | 反向 limit | — |
| 滑条 | 仅已订阅；limit 在用户价；松手确认；拖动锁区间 10s | 滑条价 |

`showMarketTrade` **只控制「市价全平」是否出现**。限价买/卖始终有；不要因此加市价开仓。OTO 按钮跟 `showOTOAction`，默认关。

交易弹窗必须常驻显示代码、方向、盘口（最新成交、bid/ask 与数量）和**模拟或实盘**。数量提供 1/3、1/2、1、2、3 倍快捷选择，并与价格一样支持直接输入和减/加微调；点「确认」通过校验后立即执行，不再弹出二次确认框。

改单：未完成限价/止损单可改价格和/或数量，确认框同样写明模拟/实盘后 `replace`。

## 5. 自动止盈 / 止损

偏好 0 = 关；0.1–1 表示百分之该值。默认关。

入场成交（排除 `client_order_id` 前缀 `auto-tp-` / `auto-sl-`）：

1. 刷新该 symbol 仓位（可重试）
2. 价 = 成本 × (1 ± percent/100)，距成本至少 0.01
3. 撤该 symbol 已有自动单
4. 挂新单（走同一套 `OrderPlacement`，保护窗内不挂）；失败 toast 带 symbol 与种类；最多再试 2 次

黑名单：Trading 本机集合（按 symbol，可分自动止盈 / 自动止损）。在黑名单则跳过。第一期只做内存+磁盘，不需要新后端。

**黑名单 UI：** 详情交易区可把当前标的加入/移出；偏好里可查看并移除。第一期不需要后端名单接口。

## 6. 屏幕

| 屏 | 行为 |
| --- | --- |
| 持仓列表 | 刷新；行 → 详情 |
| 持仓详情 | 数量、成本、盈亏；**只平仓，不加仓**。平仓受开盘保护；市价全平跟 `showMarketTrade`；限价平始终可走。加仓走该标的详情交易条（须已订阅） |
| 组合 | 净值、购买力、现金、今日/总盈亏 |
| 订单 | 全部 / 成交 / 新建；按 symbol；取消；改单 |
| 详情交易条 | 仅已订阅；无账户则引导凭证。盘口条：最新成交 + Q bid/ask 与数量。有仓：Type / Qty（空头为负）/ Filled（成本）与相对 live 中间价%。按钮：限价平、止盈、止损、按买价买、按卖价卖；OTO 与市价全平仍跟偏好。有 new/accepted 订单时可进该标的订单列表。 |

## 7. 验收现象

- 无凭证能看行情，不能下单，有入口去设置。
- 保护窗内下单被拦并说明。
- 限价单出现在订单列表；取消后状态更新（即使只有一条推送通道）。
- 开自动止盈/止损后，入场成交会挂上对应离场单（不依赖必须同时连上 Alpaca Socket）。
- 模拟/实盘切换后列表换成新环境，标题能看出环境。
- 没有付费、没有第二券商入口。
- 复盘买卖点与当前模拟/实盘一致；一笔成交一个点。

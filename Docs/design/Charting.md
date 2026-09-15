# 图表功能设计

**状态：** 已验收
**需求：** [05-图表.md](../requirements/05-图表.md)  
**落点：** `Charting/`、`Charting/Indicators/`、`UI/Components/ChartChrome/`、`UI/Components/Stats/`

## 1. 责任

`Charting` 只负责 **把已经算好的数据画出来**，并回传手势。

| 它做 | 它不做 |
| --- | --- |
| 画蜡烛 / 折线、叠加线、价格线、**买卖点标记** | 拉 REST / Socket、拉成交 |
| 左右平移、双指缩放、十字光标 | 算 VWAP / RSI（在 `Indicators`，由 Market 调用） |
| 日线触达最早一根时发「需要更早数据」 | 知道用户有没有订阅；不知道「复盘」是什么业务 |
| 统一一套 `ChartSurface` | 仪表盘数字卡、**订阅页多标的迷你折线**（那是 `UI/Components/Stats`） |

详情、盘前、盘后、历史分钟、秒图、日线、**复盘** **共用** `ChartSurface`。差别只在喂进去的 `ChartModel`（含 `markers`）和 `followLatest`。

交易 Tab 与持仓列表同时展示多只代码时，**不要**每行嵌两套 `ChartSurface`。扫描器结果同样不嵌 `ChartSurface`。迷你图走 `SparklineView`（折线与蜡烛都走 Canvas，这样时间轴、价格轴、高低/现价能和序列对齐；无成交量、无面积填充、无十字光标、不缩放；单点用点而不是空白折线，X 轴范围不能退化成 0...0）。迷你图只吃 `SparklinePlot`：`.line(values:times:overlay:timeKind:)` 或 `.candles(bars:vwap:timeKind:)`，不要平行塞 style / values / bars。`times` 必须与 `values` 条数对齐，对不齐就不画时间轴。叠加须与主序列条数对齐，对不齐就不画叠加。`timeKind` 由调用方标明分钟或秒，不要按时间跨度猜格式。交易 Tab 分钟用 1 分钟收盘折线（不聚合）叠蓝色 VWAP，秒图用 1 秒收盘、不聚合成 5 秒；两图都不显示周期标题。**扫描器分钟图只画 1 分钟蜡烛 + 蓝色 VWAP**（VWAP 用 1 分钟棒算出后对齐到各根蜡烛；不要再画收盘折线）。迷你图要画：底部时间轴（美东；分钟 `HH:mm`，秒图 `HH:mm:ss`；X 刻度按图宽与标签宽计算，两图并排时宁少勿叠）、右侧价格轴（可见最高到最低均分 4 档）、图内最高/最低只标数字（左半 `--价`、右半 `价--`，不要画高低价线）、当前价虚线从最后一根收到右侧价格轴（折线最后点已在图区右缘时，虚线走右轴槽；不是横贯整图，也不是昨收/今开）。扫描器蜡烛另在左上标 `VWAP:价`。高低现价不是 `ChartModel.priceLines`。迷你图空数据由 `SparklinePane` 可配置：扫描器成功拉到空分钟棒时展示空态文案，不要留整块可点空白；交易 Tab 不传文案，空数据留空、不准假平线。秒图只取相对现在约 10 分钟内、且不晚于现在的棒；未来棒不进环缓。无新行情时按下一次出窗调度，插入新棒要唤醒调度器，不每秒刷新整表；无棒时长时间休眠，过期循环重叠时插入仍能打断当前休眠。分钟拉取失败要有失败提示和重试，不能只打日志；有上次折线时也要提示，不能把旧图当成最新。卡片进详情是按钮；重试是独立按钮，不触发进详情。离开本页要取消未完成的分钟拉取（含重试）。

复盘不是第二种图表：选一天 + 当天 K 线 + 当天成交 → 仍是一个 `ChartModel`。图表只画标记，不查订单。

## 2. 输入模型

实现可用同名结构体；这是合同，不绑定 Lightweight Charts 类型。

```text
Bar
  time          该棒开始时刻（Date，UTC 存，展示用美东）
  open high low close
  volume

OverlayLine
  id            如 "vwap"
  points        [(time, value)]
  colorToken    主题色名，不是写死 hex
  width

PriceLine
  id            如 "prevClose"、"open"
  price
  title         已本地化或由 UI 传入 L10n key 的结果
  dashed        Bool

ChartStyle      candle | line

ChartMarkerKind buy | sell | other

ChartMarker
  id            稳定 id（如成交/订单 id）
  time          成交时刻（组装方会钳到所在棒的开始时刻，图表不猜）
  price         成交价（没有则用该时刻所在棒的 close，由组装方决定，图表不猜）
  kind          买蓝色 ∨、卖蓝色 ∧，画在成交价与对应时间
  title         可选，如 "100@12.34"；只给列表/点选用，图上不画字
  position      aboveBar | belowBar | auto（适配器按价位画 ∧/∨，不再用圆点或棒上/棒下）

ChartModel
  bars          [Bar]  时间升序
  style         ChartStyle
  overlays      [OverlayLine]
  priceLines    [PriceLine]
  markers       [ChartMarker]   可空；蜡烛和折线都要画
  followLatest  Bool    秒图 true；分钟主图 / 复盘 false
  showVolume    Bool    由组装方按场景传入；图表只画，不猜。true 时成交量在底部独立条带，不与 K 线共用价格轴
  usesCalendarDays Bool 日线 true（横轴按日历日）；分钟 / 秒 false
```

空 `bars`：组件显示空态（由外层也可以先挡），**不准**画一条假平线。  
`markers` 为空就是「没有买卖点」，不是另一种组件。适配器从第一天就必须实现 markers，禁止复盘时再开一条绘图分支。

## 3. 输出事件

```text
ChartEvent
  picked(Bar)           十字光标选中某根
  pickedMarker(id)      点到买卖点（复盘用来对照订单）
  reachedOldest         用户滑到已有数据最早端（日线用来再拉 100 天）
  visibleTimeRange      当前可见时间起止（仅详情分钟主图用来同步纳指；盘前/盘后/日线/秒图不发）
```

左右平移和双指缩放由库内部消化，不必每帧回传给页面业务。详情分钟主图与纳指对照共用同一段**墙钟时间**起止：切 1/3/5 时保持该窗口，不要按逻辑索引对齐（1 分钟 300 根和 5 分钟 60 根不是同一时段）。分钟主图是源，平移/缩放/双击铺满后纳指跟到同一起止；纳指作为从属图关闭平移、缩放和双击复位，时间窗只跟主图。纳指自己的数据更短时仍用这段时间，不要反过来把主图裁短。盘前、盘后、日线、秒图不同步。双击图区复位：已加载的全部棒铺满当前图区（与第一次出图相同）；分钟主图双击后把新窗口同步给纳指。单指上下滑**不**给图表（详情叠了多张图，要滚整页）；左右滑仍平移 K 线（纳指对照除外）。标记必须跟着缩放平移，不能用 SwiftUI 盖一层对不齐的点。

## 4. 谁组装 ChartModel

`Market`（或详情 Store）组装，**不在 View 里算 VWAP**。

| 图 | bars 来源 | overlays | priceLines | followLatest | showVolume |
| --- | --- | --- | --- | --- | --- |
| 盘中分钟 1/3/5 | 1 分钟仓库，3/5 现场聚合 | VWAP（开关开；按当前 1/3/5 周期的棒算） | 昨收、今开（有快照才有） | false | 股票 true；正在看 COMP / NASDAQ 则 false |
| 盘前 / 盘后 | 对应会话棒，展示按 5 分钟聚合 | 无（第一期） | 可选 | false | true |
| 日线 | 日线仓库 | 无 | 无 | false | 股票 true；COMP / NASDAQ false |
| 秒 1/5/10/30（详情缺省 1 秒折线） | 秒线环缓聚合 | 无 | 无 | true | true |
| 纳指对照 | **第二套** `ChartSurface`（矮图），只画 COMP。不要 VXX，也不要把纳指叠进主图价格轴。**1/3/5 与蜡烛/线跟盘中分钟同一套 `ChartChrome`**；**可见时间起止与盘中分钟相同**，切周期保持该窗口。没有自己的周期开关，也不画 VWAP | — | — | false | false |
| 历史分钟 / 复盘 | 指定日期拉取，不进「今天」仓库 | VWAP | 可选昨收 | false；**markers = 当天该标的成交** | 与盘中分钟相同 |
| 订阅监视迷你图 | 当日 regular 1 分钟收盘折线（不聚合）+ 秒线环缓 1 秒收盘 | 分钟叠蓝色 VWAP（1 分钟棒算出后对齐到各收盘点）；秒图无 | 无（现价虚线由 `SparklineView` 画，不是 priceLines） | — | false（不走 `ChartSurface`） |
| 扫描器结果迷你图 | 当日 regular 1 分钟蜡烛；未订阅无秒图；成功空数组走空态文案，不要留整块可点空白 | VWAP（蓝色；1 分钟算完再对齐到各根蜡烛） | 无（现价虚线由 `SparklineView` 画，不是 priceLines） | — | false（不走 `ChartSurface`） |

### 聚合

- 3 / 5 分钟、5 / 10 / 30 秒：在 `Market` 用同一套 `aggregate(bars:minutes:)` / `aggregate(seconds:)`。OHLC 取首开、最高、最低、末收，量相加。
- VWAP：`Charting/Indicators/VWAP.swift`，典型价 `(h+l+c)/3`，按量累加。详情 / 复盘按 **当前周期** 的棒算（1M 用 1 分钟棒，3M/5M 用聚合后的棒），不要把 1 分钟 VWAP 叠到 3/5 分钟图上。扫描器蜡烛与交易 Tab 分钟折线都只有 1 分钟，仍用 1 分钟棒算再对齐。
- RSI / ADX / +DI / -DI / ATR：对 **当前 1/3/5 分钟聚合棒** 算，周期 10（与 RN 详情一致）。ATR 是最近最多 10 根的平均真实波幅；AtcPct = ATR / 最新收盘 × 100。详情徽标只展示最新值，不要画副图。

### 价格线 id（第一期）

| id | 条件 |
| --- | --- |
| `prevClose` | `StockLiteSummary.snapshot` 有昨收 |
| `sessionOpen` | 有今开 |

有数据才加。成本价、止盈价以后只是多一条 `PriceLine`。

## 4.1 复盘（同一套表面）

用户选 **某一自然日（美东）** + **一个 symbol**：

1. `Market` 拉该日盘中（及需要的盘前盘后）1 分钟棒，聚合成当前周期，**再对该周期的棒**算 VWAP。
2. `Trading` / `BrokerageServing` 拉 **当前券商账户** 在该日、该 symbol 的 **已成交订单**（不是所有新建单）。第一期 Alpaca：FILL 活动的 `transaction_time` 落在该日 00:00–24:00 ET。**一单一标**，同一天内不拆部分成交；同一 GTC 跨美东日的部分成交各记一天。拉不全时图照常、已成功的那天保留，并提示。Activities 当日数量优先。本地订单只补 **Activities 已成功且无跨日歧义** 的日期（提交日与成交日为同一美东日）；失败日或跨日累计单不得用 `filled_qty` 补量，只提示不完整。详情停留期间订单更新后短防抖重拉**当天** FILL；初次加载期间若当天本地成交有变，加载结束后同样安排一次刷新。
3. 每个已成交订单变成一条 `ChartMarker`：`buy` / `sell`、时间、成交价；数量可写进 `title` 给列表用，图上只画点。只标在 `filled_at` 所在时段（盘前 / 盘中 / 盘后）且落入该棒区间的图上，不要钳到首尾棒。20:00–04:00 的成交，或该时段没有覆盖该分钟棒时，留在列表并标「仅列表」，不上分钟图。盘前跨两个美东日时，一天失败不要丢掉另一天已拉到的成交，并提示。
4. 交给同一个 `ChartSurface`。切蜡烛/线时标记留着。

没有券商账户或该日无成交：图照常，`markers` 为空，不报错。  
**一笔成交一条标记**，即使落在同一分钟也不要合成。  
复盘 `followLatest = false`，不要被实时秒线拽走。  
复盘价格线：没有该日 snapshot 就不画昨收/今开，不要套用今日 summary。
**模拟盘复盘只标模拟成交，实盘只标实盘成交**，不要混环境。

详情里「今天」也可以叠 **今日已成交**（同一 `markers`）。盘前 `regularDate` 与 `extendedDate` 不是同一天时，按两个日期拉成交再分到对应图。这是同一条组装函数：`markers(fills:)`，不是复盘专用。

第一期入口：把现有 **历史分钟页** 做成复盘页（选日期 + 图 + 可选成交列表）。不新做第二套 K 线。完整「按订单筛选、多标的一日回放」以后加，仍只加组装，不加新图表类型。

## 5. 库适配

`Charting/Lightweight/LightweightChartView`：

- 唯一 `import LightweightCharts` 的地方。
- SwiftUI 用 `UIViewRepresentable` 包官方 iOS 封装。
- `PriceLine` → `createPriceLine`；`OverlayLine` → `LineSeries`；`ChartMarker` → 成交价上的蓝色 ∨（买）与 ∧（卖），图上不画数量文字。
- `showVolume`：histogram 用独立 overlay 价格轴（`volumeSeries.priceScale()`），固定在图底部；K 线价格轴留出下边距。不要设全局 `overlayPriceScales`，也不要把成交量画在蜡烛同一价格轴上。
- `ChartSurface.height` 是图区总高度。成交量条带是其中一块，可用 `volumeHeight` 指定；不传则按总高的默认比例切。
- 蜡烛 / 折线切换拆/建 series，买卖点仍画在同一套 `ChartSurface` 上（按成交价，不跟主 series 形状走），不要两套 View。
- 主题：背景、涨跌色跟 `UI/Theme`，经 `ChartModel` 或环境传入。
- 手势：单指上下滑交给外层页面滚动（详情叠了多张图）；左右平移、双指缩放仍由图表消化。双击图区调用与第一次出图相同的铺满（时间轴 `fitContent`，价格轴恢复自动缩放）；缩放或平移后都能这样复位。详情纳指对照关闭这些时间轴交互，只跟分钟主图的可见时间。
- 可见范围：最高价、最低价标在对应棒的实际价位旁（蜡烛用影线，折线用收盘；左半 `--价`、右半 `价--`，不要画高低价线，也不要用棒上/棒下纯数字）。当前价是可见最后一根收盘：先画虚线只从该点连到右侧价格轴（最后点已在图区右缘时走右轴槽），再画现价数字盖在虚线上，不要穿过数字，也不要用库的横贯 last-visible 价格线和轴上现价盒。不是昨收/今开。缩放平移后跟着变。这是适配器按视口算的，不进 `ChartModel.priceLines`。

换库：只替换 `Lightweight/`，`ChartModel` / `ChartEvent` 不动。

## 6. 详情页怎么摆

上到下（已订阅）：

1. 导航栏：代码 + 涨跌幅 + 成交量缩写（正文不再重复代码）；右上角 **账户今日盈亏**（组合盈亏，不是该标的；纯数字，不要底、不要边框；≤ -1.5% 用警示字色）
2. 成交价条 + **Q 盘口**（买/卖价与数量；`quote` 为主，快照兜底，没有盘口才显示 —）
3. 盘前 / 盘后（有数据才出现）
4. 日线（偏好默认关）chrome + surface
5. **纳指对照矮图**（偏好默认开，无 VXX）surface，**没有自己的 chrome**
6. `ChartChrome`：1M/3M/5M、蜡烛/线、VWAP（只作用分钟主图）+ 盘中 `ChartSurface`（可叠今日成交 `markers`）。切周期/形态时纳指矮图一起变，**可见时间起止跟分钟主图相同且切 1/3/5 保持不变**（换周期后用当前 1/3/5 的棒时长重算柱宽，不要从首两根去猜、也不要沿用上一周期的逻辑索引把柱压扁），VWAP 不画在纳指上
7. RSI/ADX/+DI/-DI/ATR/AtcPct 数字徽标（随当前分钟周期重算，不是副图、不用 summaries 上的指标）
8. 秒图 chrome + surface（有秒线才出现）
9. 价格滑条（仅有秒图时；区间来自秒图高低，不要用最新价兜底出滑条）
10. 交易条（有仓则 Type / Qty / Filled 与相对中间价%；Liquidate @ Limit / Take Profit / Stop / Buy @ Bid / Sell @ Ask）；可退订

未订阅：无 2 的盘口、无 8–10 的秒图/滑条/交易条；正文顶部仍显示摘要最新价；底部「加入实时订阅」。

## 7. 刷新

| 数据 | 策略 |
| --- | --- |
| 分钟棒 | 进入详情 / 扫描器 / 交易 Tab 都走同一 `BarStore`；记下成功拉取的美东分钟（空结果也算），同一分钟同一代码不重复请求。已有棒则带 `startTime` 增量合并；首根晚于开盘不整段重拉。开盘中每分钟对齐后再拉该会话。用户点重试（含纳指矮图重试）才强制刷新；同一代码进行中的重试不重复入队 |
| 日线 | 缺今日则拉；`reachedOldest` 再向前约 100 个交易日 |
| 秒线 | 仅已订阅，Socket `second-trade` 写入环缓（约 10 分钟） |
| 最新价 / 盘口 | 已订阅：`trade` + **`quote`**，快照兜底；未订阅：摘要/快照 last |

休市仍展示已拉到的棒。

## 8. 验收

对有数据的标的走需求 05 第 8 节。另加：

- 历史分钟 / 复盘开关 VWAP 不污染详情「今天」的棒。
- `ChartSurface` 在蜡烛和折线下都能画 `markers`（可用夹具数据验收，不必等复盘页做完）。
- 复盘日有成交时，买为蓝色 ∨、卖为蓝色 ∧，落在成交价与时间上；点标记能对上那一笔。模拟/实盘不混。
- 无 VXX。纳指是独立矮图。
- 第一次出图铺满已加载棒；缩放或平移后双击同样铺满。切 1/3/5 时分钟主图与纳指对照保持同一可见时间起止，不要整段跳窗。操作纳指图不会改时间窗。
- 详情图最高/最低在实际价位旁用 `--价` / `价--`；当前价先画虚线再画数字盖住虚线，不横贯整图、不穿过数字。
- 扫描器 / 交易 Tab 迷你图有美东时间轴、右侧价格轴、最高/最低数字、当前价虚线（只从最后一根收到右轴）；仍不嵌 `ChartSurface`。

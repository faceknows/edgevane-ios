# 自家后端映射

**这不是产品说明。** 路径只写在 `Moneyknows/Mapping/`。请求走 `Platform/HTTP` + `AuthorizedSession`（未登录 Auth 除外）。券商 REST **不在本文**，见 [Trading.md](Trading.md) / `Brokerage/Alpaca`。

不调用：`/v1/subscription/*`、`/auth/google/mobile`、`/auth/link`。

响应可能是裸数组或 `{ data }`：在 Mapping 里解开，领域只看见干净模型。

## 1. 文件

| 文件 | 覆盖 |
| --- | --- |
| `AuthAPI` | 注册、登录、验证码、重置、删号、`/me`、role-config |
| `VersionAPI` | `GET /app/version` |
| `PreferencesAPI` | `GET/PATCH /v1/users/preferences` |
| `BarsAPI` | 分钟 / 盘前 / 盘后 / 日线 / 快照 / 指数分钟 |
| `ScreenerAPI` | 第一期 8 个扫描器 + `stocks/summaries` |
| `SubscribeAPI` | 网关主机上的订阅 REST |
| `AIAPI` | 情绪、经济日历（个股 AI 第一期不接） |
| `PushAPI` | FCM、通知历史 |
| `AdminAPI` | 邀请等；第一期不接（邀请码运营线下发） |

## 2. 账号与版本

| 用户动作 | 接口 |
| --- | --- |
| 注册 | `POST /v1/users/email/signup` `{ email, password, nickname?, invitationCode }`。**不发、不传验证码** |
| 发验证码 | `POST /v1/users/email/verification-code` `{ email, type: reset-password }`（只用于忘记密码；后端仍有 `signup` 类型，iOS 不调用） |
| 登录 | `POST /v1/users/email/signin` `{ email, password }` |
| 重置密码 | `POST /v1/users/email/reset-password` `{ email, verificationCode, newPassword }`。确认密码只在客户端校验，不另传字段 |
| 刷新令牌 | `POST /auth/refresh` `{ refreshToken }` |
| 资料 | `GET /v1/users/me` |
| 改昵称 | `PUT /v1/users/me`（第一期资料页可不开放编辑） |
| 删号 | `DELETE /v1/users/me` |
| 角色配置 | `GET /v1/users/role-config` |
| 版本 | `GET /app/version`（可未登录）。426 / `APP_VERSION_NOT_SUPPORTED` 视为强制更新 |

登录响应：`accessToken`、`expiresAt`、`refreshToken?`、`user`。忽略 `subscription` 做任何产品逻辑。

公共头：`Authorization`、`X-App-Version`、`X-Platform: ios`。

## 3. 偏好

| 动作 | 接口 |
| --- | --- |
| 拉取 | `GET /v1/users/preferences` |
| 部分更新 | `PATCH /v1/users/preferences` |

字段与需求 07 默认值对齐。`getAllSubscriptions` 第一期忽略。

## 4. K 线与摘要

| 动作 | 接口 |
| --- | --- |
| 盘中分钟 | `GET /alpaca/market/intraday-bars` `symbol, date, startTime?, timeFrame?` |
| 盘前 | `GET /alpaca/market/intraday/pre/bars` |
| 盘后 | `GET /alpaca/market/intraday/after/bars` |
| 日线 | `GET /alpaca/market/daily-bars` `symbol, startDate?, timeFrame?, market`（第一期固定 `us`） |
| 快照 | `GET /alpaca/market/latest-snapshot` `symbols`。盘口字段 `bp` / `ap`（或等价 quotes map）。**已订阅作 `quote` 兜底** |
| 纳指分钟 | `GET ibkr/market/intraday-bars` 符号 `COMP`（产品侧 NASDAQ）。**不拉 VXX** |
| 摘要 | `GET /stocks/summaries` `market, symbols` |

棒：`d, o, h, l, c, v`，可选 `n, vw`。`d` 的日期/时刻解析集中在 Mapping，领域得到 `Date`。`bars` 可以是数组、按 symbol 分组的 map，或夹着空位；Mapping 丢掉空位，不要当成整段失败。

## 5. 扫描器（第一期只接这些）

| 页面 | 接口 |
| --- | --- |
| 热门筛选器 | `GET /intraday-stocks/yahoo/screener` |
| 动量 | `GET /intraday-stocks/top-momentum` |
| ATR | `GET /intraday-stocks/top-atr-stocks` |
| 价格斜率 | `GET /intraday-stocks/price-slope` |
| 阶梯 | `GET /intraday-stocks/top-stair-setups` |
| RSI ADX | `GET /intraday-stocks/indicators-rsi-adx` |
| 成交量 | `GET /intraday-stocks/top-volumes-increased` |
| 二级筛选 | `GET /intraday-stocks/ibkr/screener` 或 `/ibkr/screeners/run`（实现时与 RN 现用那条对齐，只接一条） |

列表项落到统一 `SymbolSummary`（代码、快照、趋势、指标…）。  
不接：top-scored-trendings、top-vwap-distance、trend-day、find-v-shape、top-state-matches、micro-analysis。

## 6. 实时订阅（网关主机）

Base：`AppEnvironment.socketHost`。

| 动作 | 接口 |
| --- | --- |
| 我的 / 全部列表 | `GET /alpaca/market/subscriptions` → `{ all, me }` |
| 订阅 | `POST /alpaca/market/subscribe` `{ symbols }` |
| 退订 | `POST /alpaca/market/unsubscribe` `{ symbols }` |

Socket：`{host}/alpaca-stream`、`{host}/ibkr-stream`，auth/query 带 App token。

| 事件 | 交给 |
| --- | --- |
| `trade` | Market 最新成交价（仅 `me` 内 symbol） |
| `quote` | Market 盘口 bid/ask（`bp` / `ap`，仅 `me` 内 symbol）。**必须消费**；REST 快照兜底 |
| `second-trade` | Market 秒线 |
| `news` | Insights 新闻 |
| `trade_updates` | Trading 订单流（与 Alpaca 直连去重） |
| `ping` | Platform 应答 |
| `bar` / `micro_analysis_*` | 第一期忽略 |

IBKR 流：新闻可与 Alpaca 新闻合并去重；报价/成交第一期不进 Store。

## 7. AI 与推送

| 动作 | 接口 |
| --- | --- |
| 市场情绪 | `GET /v1/ai/intraday-market-sentiment?language=en\|zh` |
| 经济日历 | `GET /v1/ai/economic-calendar?language=en\|zh` |
| 注册 FCM | `POST /v1/users/fcm-token` `{ token, platform: ios, deviceId? }` |
| 注销 | `DELETE /v1/users/fcm-token` `{ token }` |
| 通知历史 | `GET /v1/notifications/history` `limit, offset, lastTime, type` |

`language` 来自偏好。个股 AI 第一期不接。

## 8. 改接口

现有路径对不上时 **停**，回需求提案，不要在 Mapping 里发明新 URL。

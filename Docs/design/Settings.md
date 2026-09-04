# 设置与偏好

**状态：** 待验收  
**需求：** [07](../requirements/07-账号订阅通知与设置.md)  
**落点：** `Preferences/`、`UI/Screens/Settings/`、凭证写入 `Brokerage/`

## 1. 设置首页

入口：凭证、偏好、资料、其它、推送开关、深色模式、语言、登出。  
**没有** 套餐/购买/恢复/订阅问题。  
**没有** Admin：邀请（码由运营线下发）、本地存储、获取全部订阅。

## 2. 凭证

表单：Key、Secret、模拟/实盘。保存 → `CurrentBrokerageStore.replace` → Trading 重拉。  
校验失败：说明并保持旧账户仍可用直到新保存成功（避免写坏后两头空；若实现简单也可先清再写，但必须有明确失败态）。

## 3. 偏好

`PreferencesStore`：启动用本地，登录后 GET 覆盖，改一项即 PATCH。

| 字段 | 默认 | UI |
| --- | --- | --- |
| valuePerTrade | 100 | 数字 |
| allowTradeInMinutesAfterOpen | 30 | 数字 |
| showOTOAction | false | 开关 |
| showMarketTrade | false | 开关；文案是「显示市价全平」，不是「市价交易」 |
| autoTakeProfitPercent | 0 | 0 或 0.1–1 |
| autoStopLossPercent | 0 | 同上 |
| showDailyBarInDetail | false | 开关 |
| showIndexBarInDetail | true | 开关；「详情显示纳指对照矮图」（无 VXX） |
| 自动止盈/止损黑名单 | 本机 | 列表可移除；详情也可改当前标的 |
| notificationVolumeThreshold | 0 | 0,2–8 |
| locale | null | 跟随系统 / 英 / 中 |

忽略 `getAllSubscriptions`。

语言变更：立刻换 `L10n`，Insights 按新语言重拉。

## 4. 资料 / 其它

- 资料：昵称、邮箱、角色、**已启用功能**（role-config）。不展示套餐、到期、自动续费。第一期不强制可编辑昵称。
- 其它：删除账户（确认）→ `DELETE /v1/users/me` → 登出。

## 5. 外观

深色模式：跟随系统或用户覆盖，写在 Theme + 本机，不必进后端（RN 若只在本地，对齐本地）。

## 6. 验收

- 设置里找不到付费与 Google。
- 改每笔金额后，详情下单默认股数跟着变。
- 删号后无法用旧密码登录（以后端为准）。

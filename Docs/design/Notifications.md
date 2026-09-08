# 推送与通知中心

**状态：** 已验收  
**落点：** `Notifications/`、`UI/Screens/Notifications/`、`App` 深链

## 1. 开关与注册

- 设置里总开关。关：不注册或注销 token，列表仍可看历史（只读）。
- 登录且开关开：要系统权限 → `PushAPI` 注册 `platform: ios`。
- 登出：注销 token。
- Token 刷新：再注册。

## 2. 历史屏

`NotificationStore`：`GET /v1/notifications/history` 分页。

筛选：类型走 `GET /v1/notifications/history` 的 `type` 参数（趋势上/下、日内高/低、突破、弱势回调）；symbol 与成交量在客户端。
空态分「完全没有」和「筛选后没有」。

`notificationVolumeThreshold`（0 = 不过滤，否则 2–8）：**历史列表与前台 toast 用同一套过滤**。实现时与 RN 对齐过滤发生在服务端还是客户端。

## 3. 深链

- 解析通知 `data`（与 RN `openNotificationTarget` 对齐，**按此顺序**）：

| 条件 | 去哪 |
| --- | --- |
| 趋势/高低点且 `screen=Markets` | 扫描器目录 + symbol chips（即使只有一个 symbol） |
| 单 symbol | 股票详情 |
| 其它 | 通知中心 |

未登录：记住一次目标，登录后再跳。  
版本门禁未过：不跳。

## 4. 验收

- 关推送后不再向系统要权打扰（已拒权按系统行为）。
- 从一条单代码通知能进详情。
- 没有「升级解锁通知」之类文案。

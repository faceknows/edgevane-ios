# money-ios 可执行方案

本文规定 **怎么做**，不代替需求正文，也不代替设计正文。

**当前门：阶段 B，功能性设计待验收。** 结构已通过。功能篇通过前不建 Xcode 工程。

## 1. 目标

把现有 React Native App（Moneyknows / `money-app`）用原生 iOS 重构一遍，做成可长期演进的美股盘中交易辅助客户端。

- 产品行为以已验收的 `Docs/requirements/` 为准。
- 后端默认复用现有 `money-api` 与 `money-gateway`。
- 需要增删或优化接口时，先写进需求「后端提案」，确认后再进设计。

## 2. 工作方式

三个大阶段，顺序固定：

```text
A. 需求（写清产品是什么、不是什么、与 RN 的对等关系）
        ↓ 验收
B. 设计（模块边界、图表、网络、第一个可运行客户端怎么落地）
        ↓ 验收
C. 实现（一次只做一个可交付切片）
        ↓ 每步单独验收
```

规则：

1. **先文档，后代码。** 产品行为以 `Docs/requirements/` 为准；结构以 `Docs/design/` 为准。
2. **渐进。** 每一步交付可在真机或模拟器上操作的结果，而不是半截屏幕。
3. **清晰。** 每一步写明范围、不做、验收。验收用现象，不用“代码写完了”。
4. **不把 RN 现状当天花板。** `money-app` 证明过哪些能力存在；隐藏入口、Admin 专属、半残功能要在需求里单独标出，由产品决定带不带进 iOS。
5. **不在实现步偷偷发明后端。** 现有 HTTP / Socket 是近期约束。要改协议，回到需求提案。

近期约束（可在后续需求里改）：

- 第一个客户端只做 iOS。Android 仍走现有 RN，不在本期范围。
- 主图用 Lightweight Charts；仪表盘类统计图用 Swift Charts。
- 不追求毫秒级图表。

## 3. 阶段清单

| 编号 | 工作 | 阶段 | 状态 |
| --- | --- | --- | --- |
| R | 需求写清并验收 | A | **已收口**（无付费/Google/VXX；邀请码线下发；第一期就要 bid/ask） |
| D | 设计写清并验收 | B | **进行中**：功能篇待验收，见 `Docs/design/README.md` |
| C0+ | 按设计切片实现 | C | 未开始 |

实现切片编号在设计验收后补进本文。不要在需求未定时预写 C0、C1 编码顺序。

## 4. 设计文档索引

| 文件 | 内容 |
| --- | --- |
| [design/README.md](design/README.md) | 设计索引 |
| [design/Architecture.md](design/Architecture.md) | 分层（结构已通过） |
| [design/Developing.md](design/Developing.md) | 目录与横切能力 |
| [design/Navigation.md](design/Navigation.md) | 导航 |
| [design/Session.md](design/Session.md) | 启动与账号 |
| [design/Market.md](design/Market.md) | 行情与详情 |
| [design/Charting.md](design/Charting.md) | 图表合同 |
| [design/Trading.md](design/Trading.md) | 交易与券商 |
| [design/Insights.md](design/Insights.md) | 资讯 |
| [design/Notifications.md](design/Notifications.md) | 推送 |
| [design/Settings.md](design/Settings.md) | 设置 |
| [design/Mapping.md](design/Mapping.md) | 自家后端映射 |

## 5. 需求文档索引

按这个顺序 review：

| 文件 | 内容 |
| --- | --- |
| [requirements/00-概述.md](requirements/00-概述.md) | 产品是什么、谁在用、重构目标 |
| [requirements/01-范围与分期.md](requirements/01-范围与分期.md) | 本期做 / 不做 / 待你拍板 |
| [requirements/02-功能清单.md](requirements/02-功能清单.md) | 与 RN 对照的功能表 |
| [requirements/03-用户流程与页面.md](requirements/03-用户流程与页面.md) | 启动、导航、每页能做什么 |
| [requirements/04-交易与风控.md](requirements/04-交易与风控.md) | 下单、持仓、自动止盈止损 |
| [requirements/05-图表.md](requirements/05-图表.md) | 蜡烛图、线图、VWAP、价格线、缩放 |
| [requirements/06-后端接口与复用.md](requirements/06-后端接口与复用.md) | 现有接口 + 提案（提案默认不采纳） |
| [requirements/07-账号订阅通知与设置.md](requirements/07-账号订阅通知与设置.md) | 登录、订阅、推送、偏好 |
| [requirements/08-待确认事项.md](requirements/08-待确认事项.md) | 已拍板 + 仍可讨论的默认项 |
| [requirements/09-工程与扩展原则.md](requirements/09-工程与扩展原则.md) | 可扩展、图表与组件复用 |
| [requirements/10-多券商账户.md](requirements/10-多券商账户.md) | 多券商预留（不实现） |

## 6. 验收怎么做

- **阶段 A：** 已收口。
- **阶段 B：** 先验收结构（Architecture + Developing）。通过后再补图表模型与 API 对照，全部通过才能建工程。
- **阶段 C：** 每步有可操作现象（例如：未登录看到登录页；登录后看到仪表盘今日盈亏）。

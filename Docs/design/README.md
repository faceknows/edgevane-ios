# 设计（阶段 B）

结构已通过。本目录是实现的对照。未验收功能性设计前不建工程。

## 结构（已通过）

| 文件 | 内容 |
| --- | --- |
| [Architecture.md](Architecture.md) | 分层、依赖 |
| [Developing.md](Developing.md) | 目录、横切能力 |

## 功能（待验收）

按这个顺序看：

| 文件 | 内容 |
| --- | --- |
| [Navigation.md](Navigation.md) | 导航树、仪表盘、跳转 |
| [Session.md](Session.md) | 启动、版本、邮箱登录 |
| [Market.md](Market.md) | 扫描器、订阅、详情 |
| [Charting.md](Charting.md) | ChartModel、VWAP、库适配 |
| [Trading.md](Trading.md) | 券商账户、下单、自动止盈止损 |
| [Insights.md](Insights.md) | 情绪、日历、新闻 |
| [Notifications.md](Notifications.md) | 推送、深链 |
| [Settings.md](Settings.md) | 凭证、偏好、删号 |
| [Mapping.md](Mapping.md) | 自家后端路径 ↔ Mapping 文件 |

券商 Alpaca 路径写在 Trading / Developing，不进 Mapping。

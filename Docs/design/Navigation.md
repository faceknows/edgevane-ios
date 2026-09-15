# 导航

**状态：** 已验收
**需求：** [03](../requirements/03-用户流程与页面.md)

## 1. 树

```text
Root
  VersionGate
  AuthStack          Login / Signup（邀请码线下发）/ ForgotPassword（成功回登录）
  MainTabs
    HomeStack        Dashboard, Notifications, Screeners, ScreenerResults,
                     Sentiment, Calendar, News, NewsDetail, HistoricalMinutes（复盘）,
                     Positions, Portfolio, Orders
    TradeTab         Subscriptions
    SettingsStack    Settings, Credentials, Preferences, Profile, Other
  RootOverlay        SymbolDetail（从任意 Tab push）
                     Preferences 也可 sheet
```

路由用类型安全枚举，禁止字符串乱跳。

## 2. 仪表盘组成

不是独立领域。读：

- `PortfolioStore` → 今日盈亏卡（仪表盘仅此卡显示模拟/实盘徽标；下单弹窗另显）
- `PositionStore` → 持仓摘要
- `OrderStore` → 订单摘要
- 搜索 → `SymbolDetail(symbol)`
- 快捷入口 → 上表各屏

仪表盘无迷你 K 线。盈亏数字不必上 Swift Charts（纯文本+颜色即可）；若要用图，走 `UI/Components/Stats`。交易 Tab 的订阅监视迷你折线也走 Stats，见 [Market.md](Market.md) 第 3 节。

## 3. 跳转表

与需求 03 第 7 节一致。实现集中在 `UI/Screens/Root/AppRouter`，深链与列表点击都走它。

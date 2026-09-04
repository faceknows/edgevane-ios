# 启动与账号

**状态：** 待验收  
**需求：** [03](../requirements/03-用户流程与页面.md)、[07](../requirements/07-账号订阅通知与设置.md)  
**落点：** `App/`、`Session/`、`UI/Screens/Root/`、`UI/Screens/Auth/`

## 1. 启动顺序

```text
冷启动
  → VersionAPI（可未登录）
       检查中 / 失败可重试 / 过低 → 商店链接，不能进登录
       通过
  → SessionStore 有未过期令牌（或可 refresh）？
       否 → Auth 栈（登录）
       是 → 已登录根（Tab）
            并行：Preferences 拉取、role-config、FCM 注册、
                  订阅列表、若有券商账户则拉组合/持仓/订单、
                  连接网关 Socket
```

没有引导页、没有付费墙、没有 Google 按钮。

推送冷启动：版本 + 会话通过后再按 [Notifications.md](Notifications.md) 深链跳转。未登录先登录，登录后消费一次待跳转。

## 2. 会话

`SessionStore` 是应用账号的唯一入口。

| 存什么 | 哪里 |
| --- | --- |
| access / refresh / expiresAt | Keychain |
| 当前 user 摘要（id、email、nickname、role） | 内存 + 磁盘非机密副本 |

- 过期前 5 分钟主动 refresh。
- 已登录请求 401 → refresh → 再失败则 `signOut`。
- 登录页 401 **只**提示密码/账号错误，不走全局退出。

`LogoutCleanup`：Session 发出登出，各领域清自己的（Market 棒与订阅内存、Trading 仓单、**Insights 新闻缓存**、Notifications 历史、**Brokerage 当前账户凭证与 RN 对齐：一并清除**）。

## 3. 屏幕

| 屏 | 行为 |
| --- | --- |
| 版本门禁 | 三种状态；强制更新打开 App Store（现网应用） |
| 登录 | 邮箱 + 密码；去注册、找回。无第三方登录 |
| 注册 | 邮箱、密码 + **确认密码**（至少 8 位）、**邀请码**（运营线下发，App 内不发码）、昵称可选。**不要**邮箱验证码。成功 `applySignIn` 进 Tab |
| 找回 | 验证码（可重发）+ 新密码 + **确认新密码**；两次不一致当场拦住；成功 **回登录页**，不自动登录 |

错误：邀请码无效、邮箱占用、密码过短，用接口/`L10n` 可行动句子。找回才提示验证码过期。

## 4. 已登录根

底栏：首页 / 交易 / 设置。  
股票详情、偏好用根导航 push/sheet，不挂死在某一个 Tab。

Admin 入口第一期不出现（含详情上的 AI View、价格通知）。

## 5. 验收现象

- 过低版本进不了登录。
- 无邀请码不能注册；注册页没有邮箱验证码；App 内没有「邀请用户」。
- 登录页没有第三方登录、没有升级。
- 找回密码成功后停在登录页，必须再输入一次新密码。
- 杀进程再开，令牌有效则仍在 Tab。
- 登出回到登录，交易、券商数据与新闻缓存不可见。

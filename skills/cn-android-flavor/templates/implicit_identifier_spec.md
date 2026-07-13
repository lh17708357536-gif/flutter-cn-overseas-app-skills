# <APP_DISPLAY_NAME> 隐式标识技术说明文档（Android）

> 用途：国内 Android 应用市场（华为 / 小米 / OPPO / vivo / 应用宝）/ 工信部备案 等合规审核场景提交。
> 当前对应版本：<x.y.z+n>（YYYY-MM-DD）。
> 应用包名：`<APP_PACKAGE>`（cn flavor，国内市场专用）。

## 一、方案总览

为支持登录会话保持、N 台设备并发限制、系统通知投递、注销账号后清除设备绑定，本 app 在 Android 端仅使用：
- **Android 系统原生 Build 字段**（系统级公开字段，非个人信息，重装即重置）
- **极光 JPush 推送注册号**（推送服务自有 Token，与个人身份解耦）

**未使用以下任何敏感设备标识**：
- ❌ IMEI / MEID / IMSI（手机串号）
- ❌ `Settings.Secure.ANDROID_ID`
- ❌ MAC 地址 / WiFi BSSID
- ❌ 华为 OAID（App 层不直接读取）
- ❌ 第三方设备指纹 SDK（无 TalkingData / 友盟 / 数美等）
- ❌ 任何广告归因 / 跨 App 跟踪标识

## 二、标识清单

| 标识 | 字段名 | 来源 | 用途 | 重置方式 |
|---|---|---|---|---|
| Build ID | `Build.id` | Android 系统（**非** ANDROID_ID） | 区分本 app 不同设备的登录会话；多设备并发限制 | 用户卸载本 app 后由系统自动重置 |
| 设备品牌 | `Build.BRAND` | Android 系统 | "已登录设备"列表展示 | — |
| 设备机型 | `Build.MODEL` | Android 系统 | "已登录设备"列表展示 | — |
| 推送注册号 | `JPush registrationId` | 极光推送 SDK | 国内推送投递（订单 / 工单 / 聊天 / 通话 / 投诉等系统通知） | 关闭通知 / 调用 `JPushInterface.stopPush()` |

## 三、标识用途对照

| 业务用途 | 调用的标识 | 备注 |
|---|---|---|
| 登录会话保持（JWT 颁发） | `Build.id` | 与登录账号绑定；注销账号时同步删除 |
| 多设备并发限制 | `Build.id` | 超过限制时自动剔除最早登录设备 |
| 系统通知投递 | `JPush registrationId` | 用户可在系统设置关闭通知 |
| 已登录设备列表 | `Build.BRAND`、`Build.MODEL` | 仅用户可见，不上传任何第三方 |
| 反作弊 / 风控 | ❌ 未使用 | 本 app 不做风控级设备指纹 |
| 广告归因 / 跨 App 跟踪 | ❌ 未使用 | 不读取任何广告标识 |

## 四、第三方 SDK 隐式标识声明

### 极光推送 JPush（国内 Android 包唯一集成的推送 SDK）
- SDK 包名：`cn.jiguang.sdk:jpush:<version>`
- **SDK 内部会采集**：OAID（移动安全联盟匿名标识）、Android ID、网络信息、系统版本、应用列表
- **本 app 在代码层不直接调用上述标识**，仅读取极光返回的 `registrationId` 与后端绑定
- 极光 SDK 隐私合规说明：`https://docs.jiguang.cn/jpush/updates/jpush_sdk_privacy_statement`

### 其他未集成的 SDK
- 本 app 国内版本（cn flavor）通过 Gradle Product Flavor 显式排除：境外推送服务、境外广告 SDK、境外应用商店服务库、第三方设备指纹 SDK

## 五、Android 权限清单与隐式标识对照

| 权限 | 用途 | 是否涉及隐式标识 |
|---|---|---|
| `INTERNET` | 网络通信 | 否 |
| `ACCESS_NETWORK_STATE` | 检测网络是否可用 | 否（仅读连接类型） |
| `ACCESS_WIFI_STATE` | 检测是否处于 WiFi | 否（**不读** MAC / BSSID） |
| `CAMERA` | 业务拍照 / 扫码 | 否 |
| `RECORD_AUDIO` | 业务语音输入 | 否 |
| `POST_NOTIFICATIONS` | 通知展示（Android 13+ 必需） | 否 |
| `READ_EXTERNAL_STORAGE`（maxSdkVersion=32） | 旧版选图 | 否 |

**未声明**：`READ_PHONE_STATE` / `ACCESS_*_LOCATION` / `READ_CONTACTS` / `READ_CALL_LOG` / `GET_ACCOUNTS` / `QUERY_ALL_PACKAGES`

## 六、用户撤回路径

| 操作 | 影响 |
|---|---|
| 退出登录 | JWT 失效；deviceInfo 解除绑定 |
| 卸载 app | `Build.id` 重读后值不变（系统级），但与账号绑定关系被服务端"卸载即解绑"机制清理；推送 Token 失效 |
| 系统通知设置关闭 | JPush 仍接收数据，不在通知栏展示 |
| 应用内"账户安全 → 退出此设备" | 服务端立即吊销 JWT 并删除该设备的绑定 |
| 注销账号 | 删除所有设备绑定记录、推送 Token、deviceInfo |

## 七、合规对照清单

| 法规 / 规范 | 对应条款 | 本 app 状态 |
|---|---|---|
| 《App 个人信息保护规定》 | 不得强制采集 IMEI / IMSI / MAC | ✅ 未采集 |
| 工信部 164 号文 | 隐式采集设备标识需明示用途与撤回路径 | ✅ 仅采集 `Build.id`、`Build.BRAND`、`Build.MODEL`，App 启动后用户登录前不上传 |
| 《个人信息保护法》第 13 条 | 处理个人信息须有合法基础 | ✅ 用户登录后基于"履行合同所必需"采集 |

## 八、截图清单（提交审核时附在文档中）

请在真机上拍摄：
1. 首次启动隐私政策弹窗
2. 登录页"用户协议 + 隐私政策"超链接
3. "我的"→ 账户安全 → 已登录设备列表
4. 系统设置 → 应用 → <APP_DISPLAY_NAME> → 权限（仅相机 / 麦克风 / 通知 等业务必需）
5. "我的"→ 通知开关
6. "我的"→ 账户安全 → 退出此设备
7. "我的"→ 账户安全 → 注销账号

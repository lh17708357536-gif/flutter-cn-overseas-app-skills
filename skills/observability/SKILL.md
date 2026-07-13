---
name: observability
description: 多区域 Flutter + NestJS 可观测性 — ★ flavor 感知的崩溃采集（cn 用 Sentry 自托管、overseas/iOS 可 Crashlytics，因 cn 禁 Firebase）、release 与 buildNumber 绑定、结构化后端日志（nestjs-pino + requestId/tenantId/userId + PII 脱敏）、前端 breadcrumb、健康检查与 uptime 监控、告警阈值、trace/correlation id 透传。
---

# 可观测性 Skill（多区域 Flutter + NestJS）

> 把"生产出了什么事"变得可见。分三层：**崩溃/错误采集**（前端）、**结构化日志 + 追踪**（后端）、**健康/告警**（运维）。所有 `<PLACEHOLDER>` 替换为项目实际值。
>
> ★ **多区域最大约束**：cn flavor 禁 Firebase（对应 `cn-android-flavor` §1），所以 **Crashlytics 不能进 cn 包**。崩溃采集必须按 flavor 分流。

## 1. ★ Flavor 感知的崩溃采集（核心决策）

| flavor | 崩溃采集方案 | 理由 |
|---|---|---|
| **cn_android** | **Sentry**（可自托管国内） | 禁 Firebase → 不能用 Crashlytics；Sentry Dart SDK 无 Google 依赖 |
| **overseas_android** | Sentry 或 Firebase Crashlytics | 二选一；用 Sentry 可与 cn 统一后台 |
| **iOS** | Sentry 或 Crashlytics | 同上 |

**推荐：三 flavor 统一用 Sentry**（一个后台看全部，cn 可指向自托管实例；避免维护两套崩溃后台）。Crashlytics 仅在你已重度依赖 Firebase 生态时用于 overseas/iOS。

`pubspec.yaml`：
```yaml
dependencies:
  sentry_flutter: ^8.x.x
  # 若 overseas/iOS 另用 Crashlytics（可选，且必须条件 import 隔离，勿进 cn）：
  # firebase_crashlytics: ^4.x.x
```

**★ flavor 分流初始化**（对应 `flutter-coding-conventions` §18 工厂模式）：
```dart
// lib/core/config/crash_reporter_factory.dart
Future<void> initCrashReporter(Widget app) async {
  final flavor = FlavorConfig.current;
  final dsn = _dsnForFlavor(flavor);            // 不同 flavor 不同 DSN/项目
  await SentryFlutter.init(
    (o) {
      o.dsn = dsn;
      o.environment = flavor.name;              // cn_android / overseas_android / ios
      o.release = '<APP_PACKAGE>@$appVersion+$buildNumber';  // ★ 与 pubspec 版本号绑定
      o.tracesSampleRate = 0.2;                 // 性能追踪采样，按量调
      o.beforeSend = _redactPII;                // ★ 脱敏（第 5 节）
    },
    appRunner: () => runApp(app),
  );
}
```
> ★ **cn 的 DSN 指向自托管 Sentry**（`sentry.<PROD_DOMAIN>`），数据不出境、国内上报快；overseas/iOS 可用 Sentry SaaS。

**手动上报业务错误 + breadcrumb**：
```dart
try {
  await api.callAI(...);
} catch (e, st) {
  Sentry.addBreadcrumb(Breadcrumb(message: 'toolId=A1 action=generate', category: 'credits'));
  await Sentry.captureException(e, stackTrace: st);
  rethrow;   // ★ 仍然 rethrow，不吞错（对应日志铁律）
}
```

## 2. release 与 buildNumber 绑定（不绑等于没上报）

崩溃如果不带 release 版本号，无法定位是哪个包。**铁律**：
- `o.release = '<pkg>@<versionName>+<buildNumber>'`，值从 `package_info_plus` 读，与 `pubspec.yaml`（`_shared/rules.md` §3 唯一真相源）一致
- 每次发版在 CI 里 **上传 debug symbols / dSYM**，否则堆栈是混淆后的乱码：
  ```yaml
  # release-mobile.yml 追加（Sentry）
  - run: |
      flutter build apk --flavor cn --release --split-debug-info=build/symbols --obfuscate ...
  - run: sentry-cli debug-files upload --include-sources build/symbols
    env: { SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }} }
  ```
- iOS dSYM：archive 后 `sentry-cli upload-dif ios/build/...`（或 Crashlytics 走 `upload-symbols`）

## 3. 后端结构化日志（nestjs-pino）

NestJS 默认 Logger 是纯文本,生产要**结构化 JSON + 关联字段**才能检索。用 `nestjs-pino`：
```typescript
// app.module.ts
LoggerModule.forRoot({
  pinoHttp: {
    level: process.env.LOG_LEVEL || 'info',
    genReqId: (req) => req.headers['x-request-id'] || randomUUID(),   // ★ 每请求 requestId
    redact: {                                                          // ★ PII 脱敏（第 5 节）
      paths: ['req.headers.authorization', 'req.headers["x-device-token"]',
              '*.password', '*.token', '*.idCard', '*.phone'],
      censor: '***',
    },
    transport: process.env.NODE_ENV === 'production'
      ? undefined                            // 生产输出 JSON，交给 pm2/日志采集
      : { target: 'pino-pretty' },           // 开发彩色
  },
});
```

**★ 每条业务日志带 tenantId / userId**（多租户排障刚需）：
```typescript
this.logger.log({ tenantId, userId, toolId, action, msg: 'consume ok' });
// 检索："给我 tenant-A 最近 1h 所有 A1 扣费失败" → 一条 grep/查询就出
```
沿用 `nestjs-backend-conventions` §19 的 `[methodName] key=value` 习惯,但值放进结构化字段而非拼字符串。

## 4. Trace / correlation id 端到端透传

一次用户操作跨 前端 → 后端 → 队列 → 第三方,靠同一个 id 串起来：
```
Flutter Dio 拦截器：req.headers['x-request-id'] = uuid()   （或复用 Sentry trace id）
   → NestJS genReqId 复用该 header
   → 入队时写进 job.data.requestId
   → processor 日志带同一 requestId
   → 上报 Sentry 时 setTag('request_id', id)
```
Dio 拦截器：
```dart
dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
  o.headers['x-request-id'] = const Uuid().v4();
  h.next(o);
}));
```

## 5. PII 脱敏铁律（合规刚需，尤其海外 GDPR）

**绝不上报/落日志**的字段：完整手机号、身份证、密码、token、完整邮箱、精确定位、支付凭证。
- 后端：pino `redact.paths`（第 3 节）
- 前端：Sentry `beforeSend` 剔除：
```dart
SentryEvent? _redactPII(SentryEvent e, Hint h) {
  e.request?.headers?.remove('Authorization');
  e.request?.headers?.remove('x-device-token');
  // 面包屑里若含手机号/token 一并抹掉
  return e;
}
```
- ★ token 若必须记录用于排障,只留前后各 4 位（对应 `nestjs-backend-conventions` §19）
- ★ 海外用户数据上报走**海外 Sentry 项目**,别把 GDPR 数据塞进国内自托管(对应 `overseas-android-google-play` §11 数据驻留)

## 6. 健康检查与 uptime 监控

**后端健康端点**（比单纯 `/health` 多探依赖）：
```typescript
@Get('api/v1/health')
async health() {
  const [db, redis] = await Promise.allSettled([
    this.prisma.$queryRaw`SELECT 1`,
    this.redis.ping(),
  ]);
  const ok = db.status === 'fulfilled' && redis.status === 'fulfilled';
  return {
    status: ok ? 'ok' : 'degraded',
    db: db.status, redis: redis.status,
    version: process.env.APP_VERSION, ts: new Date().toISOString(),
  };
}
```
- **liveness**（进程活着）：`/api/v1/health` 200
- **readiness**（依赖就绪）：上面的 db/redis 探测；degraded 时告警但不一定重启

**外部 uptime 监控**（三选一，都探 HTTPS 域名 + 关键 API）：
| 工具 | 适合 |
|---|---|
| **UptimeRobot / BetterStack** | SaaS,5 分钟粒度,免费层够用 |
| **自托管 Uptime Kuma** | 国内数据不出境,可探内网 |
| **pm2 + pm2-logrotate** | 进程级(重启计数、内存),配 `pm2 monit` |

`pm2` 侧：
```bash
pm2 install pm2-logrotate            # 日志切割,防撑爆磁盘
pm2 set pm2-logrotate:max_size 50M
pm2 restart <APP> --max-memory-restart 1G   # OOM 自动重启
```

## 7. 告警阈值

沿用项目已有的 MailService（如 A7 Gemini 故障告警：连续 ≥5 次/小时失败 → 邮件）,推广为统一告警规则：
| 信号 | 阈值 | 动作 |
|---|---|---|
| 上游 AI 调用失败 | 连续 ≥5 次 / 小时 | 邮件 + Sentry issue |
| 健康检查 degraded | 连续 3 次探测失败 | uptime 工具告警(邮件/webhook) |
| 崩溃率 | 单版本 crash-free < 99% | Sentry alert rule |
| 5xx 比例 | > 1% (5 分钟窗口) | 日志系统告警 |
| pm2 重启 | 10 分钟内 ≥3 次 | 说明 crash loop,人工介入 |
| 磁盘 | uploads 分区 > 85% | 提醒迁 OSS |

★ **告警要能收敛**：同一 issue 别每分钟发一封(Sentry 自带去重;自建告警加冷却窗口),否则告警疲劳等于没告警。

## 8. 前端性能与用户行为(可选,按需)

- Sentry Performance：`tracesSampleRate` 采样页面加载/网络耗时,定位慢接口
- 自定义埋点：关键漏斗(注册→设置→首个工具使用)用轻量事件表或 Sentry breadcrumb,别引重型第三方分析 SDK(尤其 cn 侧避免 Google Analytics/Firebase Analytics)
- ★ cn flavor 埋点 SDK 同样受"禁 Google"约束,选国内合规方案或自建

## 9. 落地顺序(新项目从 0)

1. 后端 `nestjs-pino` + `/api/v1/health`(依赖探测)——最先,排障立刻受益
2. Sentry Flutter,三 flavor 分流 DSN + release 绑定 + beforeSend 脱敏
3. CI 上传 symbols/dSYM(否则堆栈没用)
4. 外部 uptime 监控探生产域名
5. 告警规则(先配"上游 AI 失败"+"健康 degraded"两条最高价值的)
6. 有余力再上 Performance/埋点

## 10. 自检模板

```
可观测性改动：
崩溃采集：（flavor 是否分流 / release 是否绑 buildNumber / symbols 是否上传）
日志：（是否结构化 / 是否带 tenantId+userId+requestId / 是否脱敏 PII）
健康检查：（是否探依赖 db+redis）
告警：（新增哪条阈值 / 是否会告警风暴）
合规：（海外 PII 是否落海外项目 / cn 是否误引 Firebase/Google）
```

## 参考

- 配套 skill：`cn-android-flavor`（禁 Firebase → 崩溃采集分流的根因）、`overseas-android-google-play`（GDPR 数据驻留）、`nestjs-backend-conventions` §19（日志铁律）、`ci-cd-github-actions`（symbols 上传 job）、`backend-production-deploy`（健康检查已在 SOP §7）
- Sentry Flutter：https://docs.sentry.io/platforms/flutter/
- nestjs-pino：https://github.com/iamolegga/nestjs-pino
- Uptime Kuma：https://github.com/louislam/uptime-kuma

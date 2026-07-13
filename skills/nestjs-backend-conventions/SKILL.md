---
name: nestjs-backend-conventions
description: NestJS + Prisma 后端开发规范 — Module/Controller/Service 分层、DTO + class-validator、Prisma schema 多租户字段（hotelId/storeId/tenantId 等）强约束、JWT @CurrentUser/@UseGuards 鉴权、Wave 0-3 契约优先流程、Redis/BullMQ/UploadService/内容审核接入、AI 扣费 consume/refundWithRetry 双保险、HTTP 错误 code 规范。
---

# NestJS 后端开发规范 Skill

> 适用于 Flutter + NestJS + Prisma + MySQL 全栈项目的后端层。所有 `<PLACEHOLDER>` 替换为项目实际值。

> **占位符约定**：本 skill 用 `<TENANT_ID>` 表示业务租户字段名（id 列），`<tenant>` 表示其 Prisma model 小写（如 `<tenant>` model 实际可能是 `hotel` / `store` / `org`），`<Tenant>` 表示 Pascal case 类型。新项目按业务命名替换 — 例如酒店 SaaS 用 `hotelId` / `hotel` / `Hotel`，门店 SaaS 用 `storeId` / `store` / `Store`，通用多租户用 `tenantId` / `tenant` / `Tenant`。

## 1. 分层架构

```
server/
├── prisma/
│   ├── schema.prisma           # 数据库 schema（唯一真相源）
│   └── migrations/             # 生产用 migration（开发用 db push 即可）
├── src/
│   ├── modules/                # 业务模块（每个模块一个文件夹）
│   │   └── <feature>/
│   │       ├── <feature>.module.ts
│   │       ├── <feature>.controller.ts
│   │       ├── <feature>.service.ts
│   │       ├── dto/
│   │       │   └── <feature>.dto.ts
│   │       └── interfaces/
│   ├── common/                 # 跨模块基础设施
│   │   ├── prisma/             # PrismaModule（全局）
│   │   ├── redis/              # RedisModule（全局，ioredis）
│   │   ├── queue/              # BullMQ QueueModule（全局）
│   │   ├── decorators/         # @CurrentUser、@RequirePermission
│   │   ├── guards/             # JwtAuthGuard、PermissionGuard
│   │   ├── interceptors/       # 日志 / 限流
│   │   ├── filters/            # HTTP 异常过滤器
│   │   ├── services/           # UploadService、CryptoService 等
│   │   ├── constants/          # 全局常量（语言列表、tier 限额、credit 默认值）
│   │   └── utils/              # 工具函数（normalizeBusinessLanguageCode 等）
│   ├── h5/                     # 对客 H5 渲染（Handlebars 模板）
│   ├── websocket/              # WebSocket Gateway
│   └── main.ts                 # bootstrap
└── .env                        # 环境配置（不进 git）
```

## 2. 命名规范

- 文件：`kebab-case.ts`（如 `complaint-analytics.service.ts`）
- 类：`PascalCase`（如 `ComplaintAnalyticsService`）
- DTO 类：`<Action><Resource>Dto`（如 `CreateComplaintDto`）
- 注释：中文（如团队偏好）
- Service 方法：动词开头，camelCase（`generateAnalyticsReport` / `consumeReserved`）

## 3. Module / Controller / Service 模板

```typescript
// <feature>.module.ts
@Module({
  imports: [/* PrismaModule、RedisModule 全局，无需重复 import */],
  controllers: [<Feature>Controller],
  providers: [<Feature>Service],
  exports: [<Feature>Service],   // 仅当其他模块需要才 export
})
export class <Feature>Module {}
```

```typescript
// <feature>.controller.ts
@Controller('api/v1/<feature>')
@UseGuards(AuthGuard('jwt'))
@Throttle({ short: { limit: 30, ttl: 60_000 } })
export class <Feature>Controller {
  constructor(
    private readonly featureService: <Feature>Service,
    private readonly creditsService: CreditsService,
  ) {}

  @Post('do-something')
  async doSomething(
    @Body() dto: DoSomethingDto,
    @CurrentUser('id') userId: string,
    @CurrentUser('<TENANT_ID>') <TENANT_ID>: string,   // ★ 必须从 jwt 取，禁止从 body / query 接收
  ) {
    return this.featureService.doSomething(userId, <TENANT_ID>, dto);
  }
}
```

```typescript
// <feature>.service.ts
@Injectable()
export class <Feature>Service {
  private readonly logger = new Logger(<Feature>Service.name);

  constructor(private prisma: PrismaService) {}

  async doSomething(userId: string, <TENANT_ID>: string, dto: DoSomethingDto) {
    this.logger.log(`[doSomething] userId=${userId} <TENANT_ID>=${<TENANT_ID>}`);
    const record = await this.prisma.<entity>.create({
      data: {
        <TENANT_ID>,           // ★ 业务表 where/data 必须显式带 <TENANT_ID>
        userId,
        ...dto,
      },
    });
    this.logger.log(`[doSomething] ok id=${record.id}`);
    return record;
  }
}
```

## 4. DTO + class-validator

```typescript
// <feature>.dto.ts
import { IsString, IsOptional, IsArray, IsIn, MaxLength } from 'class-validator';

export class DoSomethingDto {
  @IsString()
  @MaxLength(200)
  title: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @IsOptional()
  @IsIn(['type_a', 'type_b', 'type_c'])
  category?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  tags?: string[];
}
```

**强约束**：
- 所有用户输入字段必须有 class-validator 装饰器（防注入、防长度炸库）
- `@IsIn` 用项目级常量（如 `WORKING_LANGUAGE_OPTIONS`），禁止内联字符串数组
- `<DESCRIPTION>` 长字段加 `@MaxLength()`
- 嵌套对象用 `@ValidateNested() + @Type(() => SubDto)`

`main.ts` 启用全局 ValidationPipe：
```typescript
app.useGlobalPipes(new ValidationPipe({
  whitelist: true,        // 自动剥离 DTO 未声明的字段
  forbidNonWhitelisted: true,
  transform: true,
}));
```

## 5. JWT 鉴权 + @CurrentUser

```typescript
// jwt.strategy.ts validate()
async validate(payload: JwtPayload) {
  // payload = { sub: userId, tier, <TENANT_ID>, teamRole }
  return {
    id: payload.sub,
    tier: payload.tier,
    <TENANT_ID>: payload.<TENANT_ID>,
    teamRole: payload.teamRole,
  };
}
```

```typescript
// common/decorators/current-user.decorator.ts
export const CurrentUser = createParamDecorator(
  (key: string | undefined, ctx: ExecutionContext) => {
    const user = ctx.switchToHttp().getRequest().user;
    return key ? user[key] : user;
  },
);
```

**铁律**：
- ★ 所有租户域 Controller 必须 `@UseGuards(AuthGuard('jwt'))` + `@CurrentUser('<TENANT_ID>')`
- ★ **禁止从 body / query / `@Param('<TENANT_ID>')` 接收 <TENANT_ID>**（用户可篡改 → 越权）
- ★ DTO 中的 `<TENANT_ID>` 字段仅作 sanity 校验，不再权威

## 6. Prisma Schema 多租户铁律

```prisma
model SomeBusinessTable {
  id          String   @id @default(uuid())
  <TENANT_ID>     String   @map("<tenant_id>")          // ★ 显式 <TENANT_ID> 字段
  userId      String   @map("user_id")
  ...
  <tenant>    <Tenant> @relation(fields: [<TENANT_ID>], references: [id], onDelete: Cascade)
  user        User     @relation(fields: [userId], references: [id])

  createdAt   DateTime @default(now()) @map("created_at")
  updatedAt   DateTime @updatedAt @map("updated_at")

  @@index([<TENANT_ID>])              // ★ 必须建索引
  @@index([<TENANT_ID>, createdAt])   // 常用查询路径再加复合索引
  @@map("some_business_table")
}
```

**铁律**：
- ★ **新增业务表必须**：`<TENANT_ID>` 字段 + 外键 `onDelete: Cascade` + `@@index([<TENANT_ID>])`
- ★ 子表即使可通过父表间接关联，也要**显式写 <TENANT_ID>**（避免 N+1 查询、便于直接过滤）
- ★ **跨租户共享实体白名单**（如评论 / 通用工具收藏）必须文档化（`docs/specs/<project>_cross_tenant_whitelist.md`）
- ★ 字段命名：DB 用 `snake_case`（`@map`），TS 用 `camelCase`
- ★ 时间字段统一 `createdAt` / `updatedAt`

## 7. Service 查询：where 必带 <TENANT_ID>

```typescript
// ❌ 错：忘记 <TENANT_ID>，A 租户可读 B 租户数据
async findById(id: string) {
  return this.prisma.someTable.findUnique({ where: { id } });
}

// ✅ 对：where 必带 <TENANT_ID>
async findById(id: string, <TENANT_ID>: string) {
  return this.prisma.someTable.findFirst({ where: { id, <TENANT_ID> } });
}

// ✅ 对：deleteMany 必须带 <TENANT_ID> 过滤
async deleteByOwner(ownerId: string, <TENANT_ID>s: string[]) {
  return this.prisma.someTable.deleteMany({
    where: { <TENANT_ID>: { in: <TENANT_ID>s }, ownerId },
  });
}
```

## 8. Wave 0-3 契约优先开发流程

| 阶段 | 目标 | 门禁 |
|---|---|---|
| **Wave0** | API 契约对齐（URL+Method+Request/Response JSON） | 用户确认契约 |
| **Wave1** | 后端 API 独立可用 + curl 验证 | curl 通过 |
| **Wave1.5** | 前端 UI 骨架（mock 数据），可与 Wave1 并行 | UI 渲染正确 |
| **Wave2** | 前后端联调，逐层验证 Layer1→4 | 完整流程走通 |
| **Wave3** | 文档补全（代码冻结后集中写） | 5 章节齐全 |

**强约束**：
- ★ 写代码前必须先输出 API 契约让用户确认
- ★ curl 验证不通过 = 不准开始前端接入
- ★ 联调每层验证通过后告知用户，不要等第 4 层才汇报

**契约示例**（写在 `docs/api_contracts/<feature>.md`）：
```yaml
# POST /api/v1/<feature>/do-something

Request:
  Headers:
    Authorization: Bearer <JWT>
  Body:
    title: string (required, ≤200)
    description?: string (≤2000)
    category?: enum(type_a|type_b|type_c)

Response 200:
  id: string (uuid)
  title: string
  createdAt: ISO 8601
  ...

Response 4xx:
  400 ValidationError
  401 Unauthorized (JWT 失效)
  403 Forbidden (权限不足)
  429 RateLimit
```

## 9. 错误码与 HTTP 状态规范

```typescript
// 4xx 业务错误（用户/前端可重试或修正）
throw new BadRequestException('VALIDATION_ERROR');
throw new UnauthorizedException('JWT_EXPIRED');
throw new ForbiddenException({ code: 'MEMBER_REMOVED', message: '已被移除该团队' });
throw new ForbiddenException({ code: 'MEMBER_FROZEN', message: '账号已冻结' });
throw new ForbiddenException({ code: 'TEAM_OWNER_DISABLED', message: 'Owner 已禁用' });
throw new NotFoundException({ code: 'NOT_FOUND', message: '记录不存在' });
throw new HttpException({ code: 'CREDITS_INSUFFICIENT', isTeamMember, ownerEmail }, 402);

// 5xx 系统错误（服务端 bug，前端只能 retry）
throw new InternalServerErrorException('UPSTREAM_AI_TIMEOUT');
```

**强约束**：
- 业务错误（用户能解决）用 4xx + 明确 `code` + 中英文 message
- 系统错误（服务端 bug）用 5xx
- 团队成员扣费失败必须返回 `{isTeamMember, ownerEmail, ownerName}`，前端展示"请联系 xxx 充值"

## 10. AI 扣费 consume / refundWithRetry 双保险

详见 `~/.claude/skills/_shared/rules.md` §1（Dart + TS 双模板 + 边界条件 + 三方同步铁律）。NestJS 端落地点：
- `<feature>.service.ts` 中 `consume → try → callAI → catch → refundWithRetry → throw e`
- `consume`/`refundWithRetry` 的 `<TENANT_ID>` 必须来自 `@CurrentUser('<TENANT_ID>')` 的 jwt active 租户（同步场景）；异步任务退款用 task payload 持久化的 `<TENANT_ID>`
- 新增扣费 action 必须同步 `server/src/common/constants/tool-credit-pricing.ts` 的 `DEFAULT_TOOL_CREDIT_PRICING`

## 11. 持久化 <TENANT_ID> 反查（防 reserve→consume race）

详见 `~/.claude/skills/_shared/rules.md` §2（典型场景表 + 前端反例正例 + 完整 NestJS 反查模板）。本 skill 不重述模板。**铁律**：长生命周期资源（reserve→consume / 异步任务 / 长会话）必须用持久化的 `<TENANT_ID>`，**不读 jwt active**。

## 12. Redis 全局模块

```typescript
// common/redis/redis.module.ts
@Global()
@Module({
  providers: [{
    provide: 'REDIS_CLIENT',
    useFactory: () => {
      if (!process.env.REDIS_HOST) {
        // 开发环境无 Redis 时降级到内存（Map）
        return createInMemoryFallback();
      }
      return new Redis({
        host: process.env.REDIS_HOST,
        port: Number(process.env.REDIS_PORT || 6379),
        password: process.env.REDIS_PASSWORD,
        db: Number(process.env.REDIS_DB || 0),
        keyPrefix: '<APP_PREFIX>:',  // 例：myapp:
      });
    },
  }],
  exports: ['REDIS_CLIENT'],
})
export class RedisModule {}
```

**Key 规范**：所有 key 用 `<APP_PREFIX>:<module>:<key>` 三段式（如 `myapp:session:abc123`）

**用途**：
- Session 存储 / 分布式限流
- Socket.io Adapter（多实例 ws 同步）
- 热数据缓存（5-30 分钟 TTL）

## 13. BullMQ 异步任务队列

```typescript
// common/queue/queue.module.ts — 全局
@Global()
@Module({
  imports: [
    BullModule.forRoot({ connection: { ...redis, db: Number(process.env.REDIS_QUEUE_DB || 1) } }),
    BullModule.registerQueue(
      { name: 'ai-tasks' },
      { name: 'image-processing' },
      { name: 'notification' },
    ),
  ],
  exports: [BullModule],
})
export class QueueModule {}
```

**约定**：
- `ai-tasks` 队列：所有 LLM / 图像 / 视觉 AI 调用，并发软限流（按 tier 决定 priority）
- `image-processing` 队列：本地图像处理（resize / format conversion）
- `notification` 队列：邮件 / SMS / 推送投递
- Redis DB 1（与缓存 DB 0 隔离）
- 重试策略：最多 3 次 + 指数退避

```typescript
@Processor('ai-tasks')
export class AiTaskProcessor {
  @Process()
  async handle(job: Job<AiTaskPayload>) {
    try {
      const result = await this.callAI(job.data);
      return result;
    } catch (e) {
      // ★ 失败退款用 payload.<TENANT_ID> 不读 jwt
      await this.creditsService.refundWithRetry(
        job.data.userId, job.data.cost, `${job.data.action}_refund`, '失败',
        3, job.data.<TENANT_ID>,
      );
      throw e;
    }
  }
}
```

## 14. UploadService 文件上传抽象

```typescript
// common/services/upload.service.ts
@Injectable()
export class UploadService {
  async uploadFile(file: Express.Multer.File, opts: { module: string; <TENANT_ID>: string }) {
    if (process.env.UPLOAD_STORAGE === 'oss') {
      return this.uploadToOSS(file, opts);
    }
    return this.uploadToLocal(file, opts);  // 默认 local
  }

  getFileUrl(filePath: string): string {
    if (process.env.UPLOAD_STORAGE === 'oss') {
      return `${process.env.OSS_CDN_DOMAIN}/${filePath}`;
    }
    return `/uploads/${filePath}`;
  }
}
```

**铁律**：
- ★ 新增文件上传必须通过 `UploadService`，禁止 `writeFileSync` 直接写盘
- ★ 禁止在 Service 中拼接上传路径，统一由 UploadService 生成
- ★ 切换 OSS 只需改 `.env`：`UPLOAD_STORAGE=oss` + 填 OSS 配置（zero code change）

`.env`：
```
UPLOAD_STORAGE=local                              # 或 oss
OSS_REGION=oss-cn-hangzhou
OSS_BUCKET=<BUCKET>
OSS_ACCESS_KEY_ID=<KEY_ID>
OSS_ACCESS_KEY_SECRET=<KEY_SECRET>
OSS_CDN_DOMAIN=https://cdn.<PROD_DOMAIN>
```

## 15. 内容审核（中国 + 海外）

```typescript
// common/services/content-moderation.service.ts
@Injectable()
export class ContentModerationService {
  async moderateText(text: string, locale?: string): Promise<'block' | 'review' | 'pass'> {
    if (locale?.startsWith('zh') || !locale) {
      return this.aliyunGreen.moderateText(text);  // 中国
    }
    return this.perspectiveApi.moderate(text);     // 海外
  }

  async moderateImage(url: string, locale?: string) {
    if (!url.startsWith('http')) {
      this.logger.warn('图片审核需要公网 URL，本地 path 跳过');
      return 'pass';
    }
    if (locale?.startsWith('zh') || !locale) {
      return this.aliyunGreen.moderateImage(url);
    }
    return this.awsRekognition.moderate(url);
  }
}
```

**铁律**：
- ★ 所有 UGC 入口（论坛 / 聊天 / 投诉 / 头像 / 用户上传图）必须接入审核
- ★ 三分档：`block` → 403 拒绝；`review` → status=pending 挂起人工；`pass` → approved
- ★ SDK 失败默认 `review`（挂起人工，绝不自动放行）
- ★ 图片审核要求公网 URL（local 模式需配 `BASE_URL` 或切 OSS）

## 16. WebSocket Gateway 多租户隔离

```typescript
@WebSocketGateway({ namespace: '/ws/<feature>' })
export class FeatureGateway implements OnGatewayConnection {
  @WebSocketServer() server: Server;

  async handleConnection(socket: Socket) {
    const jwt = socket.handshake.auth.token;
    const payload = await this.verifyJwt(jwt);
    socket.data.userId = payload.sub;
    socket.data.<TENANT_ID> = payload.<TENANT_ID>;
    socket.join(`hotel_${payload.<TENANT_ID>}`);   // ★ 加入租户房间
  }

  // 推送某租户全员
  notifyHotel(<TENANT_ID>: string, payload: any) {
    // ★ payload 必须带 <TENANT_ID>，前端二道防线 _isForeignHotelEvent 用
    this.server.to(`tenant_${<TENANT_ID>}`).emit('event', { ...payload, <TENANT_ID> });
  }
}
```

**铁律**：
- ★ `emit` 必须 `to('tenant_${<TENANT_ID>}')` 限定房间
- ★ payload 必须带 `<TENANT_ID>` 字段（前端 race 期残留事件过滤用）
- ★ 跨租户切换时 socket 必须重连用新 jwt（防止旧连接还在旧租户房间）

## 17. AI Proxy raw 语言码 vs 归一码

```typescript
// common/utils/business-language.util.ts
export const BUSINESS_LANGUAGE_ZH = 'zh';
export const BUSINESS_LANGUAGE_EN = 'en';

export function normalizeBusinessLanguageCode(code?: string | null) {
  const n = code?.trim().replace(/_/g, '-').toLowerCase();
  if (!n) return BUSINESS_LANGUAGE_ZH;
  if (n.startsWith('en')) return BUSINESS_LANGUAGE_EN;
  if (n.startsWith('zh')) return BUSINESS_LANGUAGE_ZH;
  return BUSINESS_LANGUAGE_ZH;
}

// ai-proxy.service.ts: getLanguageNameForPrompt
private getLanguageNameForPrompt(code: string): string {
  const map: Record<string, string> = {
    zh: '中文', 'zh-HK': '繁體中文', en: 'English',
    ja: '日本語', ko: '한국어', /* ... */
  };
  return map[code] || code;
}
```

**铁律**：
- ★ LLM Prompt 注入语言指令时**用 raw `<tenant>.workingLanguage`**（zh / zh-HK / en），**不能**先经 `normalizeBusinessLanguageCode` 二元归一
- ★ 业务二元分支（如"中文 vs 英文"切换 UI 文案路径）才用归一后的二元 code
- ★ 调用 AI 后端的 service / controller 必须先查 `<tenant>.findUnique({ select: { workingLanguage: true } })` 透传

## 18. Prisma migrate vs db push

| 命令 | 用途 |
|---|---|
| `npx prisma db push` | 开发环境快速同步 schema → DB（不生成 migration 文件） |
| `npx prisma db push --accept-data-loss` | 含破坏性改动（删字段 / 改类型）；CI/CD 慎用 |
| `npx prisma migrate dev --name <desc>` | 开发环境生成 migration 文件 + 同步 DB |
| `npx prisma migrate deploy` | 生产环境应用已生成的 migration（不创建新 migration） |
| `npx prisma generate` | 生成 Prisma Client TypeScript 类型 |

**项目阶段建议**：
- 早期开发：`db push` 快速迭代
- 进入生产期：切到 `migrate dev` + `migrate deploy`，所有 migration 进 git

## 19. 日志规范

```typescript
private readonly logger = new Logger(<ServiceName>.name);

async someMethod(args) {
  this.logger.log(`[someMethod] 入口 args=${JSON.stringify(args)}`);
  try {
    const result = await this.work();
    this.logger.log(`[someMethod] 出口 ok size=${result.length}`);
    return result;
  } catch (e) {
    this.logger.error(`[someMethod] 失败: ${e.message}`, e.stack);
    throw e;
  }
}
```

**强约束**：
- ★ 异步操作必须有日志，禁止 try/catch 吞掉错误
- ★ 关键方法：入口 + 出口 + 错误三类日志
- ★ 日志格式：`[methodName] message key=value`（便于 grep）
- 不打印敏感信息（密码 / token / 完整身份证号）；token 打印只显示前后各 4 位

## 20. 自检模板

```
修改文件：
主要实现：
涉及高风险区域：（JWT/WebSocket/异步时序/API字段映射/Prisma迁移/积分/品牌VI/环境变量/文件上传/多租户隔离）
验证命令：（curl POST /api/v1/...）
文档同步：（已更新 docs/backend_spec.md / docs/api_contracts/...）
潜在风险：
```

## 21. 项目启动 checklist

新建后端时：
- [ ] `npm init` + 安装 NestJS CLI / Prisma / class-validator / passport-jwt / ioredis / bullmq / aliyun-green
- [ ] `prisma init` 创建 `schema.prisma` + `.env`
- [ ] 第一张表用模板（含 `<TENANT_ID> @map("<tenant_id>")` + `@@index([<TENANT_ID>])`）
- [ ] 全局 `ValidationPipe` + `JwtAuthGuard` + 异常 filter
- [ ] `@CurrentUser` decorator + jwt strategy
- [ ] PrismaModule + RedisModule + QueueModule + UploadService 全局注册
- [ ] `main.ts` bootstrap：`app.setGlobalPrefix('api/v1')` + CORS + Helmet
- [ ] `scripts/deploy-backend.sh`（参考 `backend-production-deploy` skill）
- [ ] 第一个 health check API：`GET /api/v1/health` → `{ status: 'ok', ts }`
- [ ] curl 通过 → 进入 Wave1.5（前端骨架）

## 参考

- 配套 skill：
  - `backend-production-deploy`（部署 SOP）
  - `flutter-coding-conventions`（前端配套）
  - `frontend-backend-alignment`（API 契约 / 字段对齐 / 文档同步）
  - `flutter-multi-region-dev`（项目启动总入口）
- NestJS 文档：https://docs.nestjs.com/
- Prisma：https://www.prisma.io/docs

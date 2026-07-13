---
name: flutter-testing
description: Flutter + NestJS 多区域项目测试规范 — Flutter 单元测试（Notifier/Provider + ProviderContainer override）、widget 测试、golden 测试、★ flavor 条件编译测试（cn 不含 Firebase / overseas 不含 JPush 的静态与运行时验证）、多租户隔离测试、AI 扣费 refund 测试、NestJS service 单测（mock Prisma）、e2e（supertest + 测试库）、mocktail/jest mock 约定、覆盖率门禁。
---

# Flutter + NestJS 测试规范 Skill

> 适用于多区域 Flutter + NestJS 项目的测试基线。所有 `<PLACEHOLDER>` 替换为项目实际值。
>
> **本 skill 与 CI 强绑定**：测试写完必须进 CI 门禁才有意义，CI 矩阵见 `~/.claude/skills/ci-cd-github-actions/SKILL.md`。多区域项目**最易漏测的就是 flavor 条件编译**（第 6 节），必看。

## 1. 测试金字塔与原则

```
        ╱╲   e2e（少）—— 后端 supertest 打真实 HTTP + 测试库；关键业务链路
       ╱──╲
      ╱widget╲  widget（中）—— 页面渲染 / 交互 / 空态 / 加载态
     ╱────────╲
    ╱   unit    ╲ unit（多）—— Notifier 业务逻辑 / util / Service 纯逻辑
   ╱────────────╲
```

**该测 / 不该测**：
- ✅ **必测**：业务规则（积分扣费/退款、多租户 where 过滤、切租户重置、语言归一）、flavor 工厂选择、错误分支（余额不足、越权、race 守卫）、数据映射（Freezed ↔ JSON）
- ✅ **建议测**：关键 widget 的空态 CTA、加载骨架、向导 exit guard、i18n key 不缺失
- ❌ **不必测**：纯 UI 布局像素（golden 覆盖即可）、第三方 SDK 内部、Freezed/json_serializable 生成代码、getter/setter
- ★ **禁止**：为了覆盖率写无断言的假测试；测试里连真实生产后端 / 真实第三方 AI（用 mock）

## 2. Flutter 依赖与目录

`pubspec.yaml` `dev_dependencies`：
```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  mocktail: ^1.0.0          # mock（不需要 codegen，优于 mockito）
  golden_toolkit: ^0.15.0   # golden（可选）
  network_image_mock: ^2.1.1 # widget 测试里拦截 CachedNetworkImage
```

目录（与 `lib/` 镜像）：
```
test/
├── unit/
│   ├── providers/        # Notifier / Provider 业务逻辑
│   ├── services/         # API service（mock Dio）
│   ├── utils/            # normalizeBusinessLanguageCode / date / locale
│   └── config/           # ★ flavor 工厂选择（第 6 节）
├── widget/               # 页面 / 组件渲染与交互
├── golden/               # golden 基准图
└── helpers/
    ├── pump_app.dart     # 统一 pumpWidget（注入 ProviderScope + l10n + theme）
    └── mocks.dart        # 共享 mock 类
```

## 3. Notifier / Provider 单元测试（ProviderContainer + override）

**核心模式**：用 `ProviderContainer` + `overrideWith` 注入 mock 依赖，直接驱动 Notifier，不启 UI。

```dart
// test/unit/providers/credits_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

class MockCreditsApi extends Mock implements CreditsApiService {}

void main() {
  late MockCreditsApi api;

  setUp(() => api = MockCreditsApi());

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [creditsApiProvider.overrideWithValue(api)],
      );

  test('扣费成功后余额减少', () async {
    when(() => api.consume(any(), any(), any()))
        .thenAnswer((_) async => ConsumeResult(balance: 80));
    final c = makeContainer();
    addTearDown(c.dispose);

    await c.read(creditsProvider.notifier).consume('A1', 'generate', 20);

    expect(c.read(creditsProvider).balance, 80);
  });

  test('★ AI 调用失败必须触发退款（refundWithRetry）', () async {
    when(() => api.consume(any(), any(), any()))
        .thenAnswer((_) async => ConsumeResult(balance: 80));
    when(() => api.callAI(any())).thenThrow(Exception('upstream 500'));
    when(() => api.refundWithRetry(any(), any(), maxRetry: any(named: 'maxRetry')))
        .thenAnswer((_) async {});
    final c = makeContainer();
    addTearDown(c.dispose);

    await expectLater(
      c.read(someToolProvider.notifier).generate(),
      throwsA(isA<Exception>()),
    );
    // ★ 断言退款一定被调用一次（对应 _shared/rules.md §1 双保险）
    verify(() => api.refundWithRetry(20, any(), maxRetry: 3)).called(1);
  });
}
```

**★ 切租户重置测试**（对应 `_shared/rules.md` §4）：
```dart
test('切租户后按租户缓存的 Provider 被 invalidate', () async {
  final c = makeContainer();
  addTearDown(c.dispose);
  // 预热租户 A 的数据
  await c.read(tenantScopedListProvider.future);
  // 切到租户 B
  await c.read(tenantProvider.notifier).switchTenant('tenant-B');
  // 断言旧数据已失效（重新拉取，且带的是新租户 id）
  verify(() => api.fetchList('tenant-B')).called(1);
});
```

## 4. Widget 测试

统一 `pumpApp` helper（注入 ProviderScope override + AppLocalizations + Theme）：
```dart
// test/helpers/pump_app.dart
extension PumpApp on WidgetTester {
  Future<void> pumpApp(Widget child, {List<Override> overrides = const []}) {
    return mockNetworkImagesFor(() => pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: child,
        ),
      ),
    ));
  }
}
```

```dart
testWidgets('空态显示 CTA 按钮（对应 UI 原语强约束）', (tester) async {
  await tester.pumpApp(const SomeListScreen(),
      overrides: [listProvider.overrideWith((_) async => [])]);
  await tester.pumpAndSettle();
  expect(find.byType(ContraEmptyState), findsOneWidget);
  expect(find.text('去创建'), findsOneWidget);   // action 必传
});
```

## 5. Golden 测试（VI / 多语言渲染回归）

多区域项目字体/VI/繁简切换最容易视觉回归。golden 锁关键页面：
```dart
testWidgets('海报卡 golden - modern preset', (tester) async {
  await tester.pumpApp(const PosterCard(preset: 'modern'));
  await expectLater(find.byType(PosterCard),
      matchesGoldenFile('golden/poster_modern.png'));
});
```
更新基准：`flutter test --update-goldens`。**CI 里 golden 要固定字体渲染环境**（见 ci-cd skill，用 `flutter test --tags golden` + 固定 flutter 版本），否则平台字体差异导致假失败。

## 6. ★ Flavor 条件编译测试（多区域最易漏的坑）

**问题**：cn 包混入 Firebase 会被华为审核拒；overseas 混入 JPush 海外收不到推送。`flutter test` 默认不带 flavor，**测不到工厂分支**。三道防线：

### 6.1 工厂选择单测（运行时逻辑）
```dart
// test/unit/config/factory_test.dart
void main() {
  test('cn flavor → JPush，且不构造 FCM', () {
    FlavorConfig.overrideForTest(Flavor.cnAndroid);
    expect(createPushService(), isA<JPushService>());
  });
  test('overseas flavor → FCM', () {
    FlavorConfig.overrideForTest(Flavor.overseasAndroid);
    expect(createPushService(), isA<FcmPushService>());
  });
  test('ios flavor → APNs', () {
    FlavorConfig.overrideForTest(Flavor.ios);
    expect(createPushService(), isA<ApnsPushService>());
  });
}
```
> 前提：`FlavorConfig` 提供 `@visibleForTesting overrideForTest(Flavor)`；工厂内 `switch` 全枚举无 default（漏一个 flavor 编译期就报错）。

### 6.2 顶层禁止 import 平台包（静态扫描，进 CI）
`test/` 无法覆盖"哪个 flavor 打进了哪个 native lib"，用静态 grep 兜底：
```bash
# scripts/check_no_toplevel_platform_import.sh
# 禁止在工厂之外顶层 import jpush / firebase（会让所有 flavor 都打包该 native lib）
BAD=$(grep -rnE "^import 'package:(jpush_flutter|firebase_messaging|firebase_core)/" lib/ \
  | grep -vE "lib/core/config/.*_factory\.dart|lib/data/services/push/") || true
[[ -z "$BAD" ]] && echo "✅ 无顶层平台 import" || { echo "❌ 顶层 import 平台包:"; echo "$BAD"; exit 1; }
```

### 6.3 产物解包验证（构建后，进 CI release job）
真正确认 native lib 是否混入，只能解包（对应 `cn-android-flavor` §11 / `overseas-android-google-play` §9）：
```bash
# scripts/check_cn_no_google.sh
unzip -l build/app/outputs/flutter-apk/app-cn-release.apk \
  | grep -iE 'firebase|google-services|play-services|libgms' \
  && { echo "❌ cn 包混入 Google SDK"; exit 1; } || echo "✅ cn 包干净"

# scripts/check_overseas_no_jpush.sh
unzip -l build/app/outputs/bundle/overseasRelease/app-overseas-release.aab \
  | grep -iE 'jpush|libjcore|wechat|alipay' \
  && { echo "❌ overseas 包混入国内 SDK"; exit 1; } || echo "✅ overseas 包干净"
```
**三道防线缺一不可**：6.1 测逻辑、6.2 防手滑 import、6.3 是最终事实来源。

## 7. NestJS 后端单元测试（mock Prisma）

**核心模式**：`Test.createTestingModule` + `useValue` 注入 mock PrismaService，测 Service 纯业务逻辑。

```typescript
// <feature>.service.spec.ts
const prismaMock = {
  someTable: { findFirst: jest.fn(), create: jest.fn(), deleteMany: jest.fn() },
};
const creditsMock = { consume: jest.fn(), refundWithRetry: jest.fn() };

beforeEach(async () => {
  const module = await Test.createTestingModule({
    providers: [
      FeatureService,
      { provide: PrismaService, useValue: prismaMock },
      { provide: CreditsService, useValue: creditsMock },
    ],
  }).compile();
  service = module.get(FeatureService);
  jest.clearAllMocks();
});

it('★ 查询必带 tenantId（防越权）', async () => {
  prismaMock.someTable.findFirst.mockResolvedValue({ id: '1' });
  await service.findById('1', 'tenant-A');
  expect(prismaMock.someTable.findFirst).toHaveBeenCalledWith({
    where: { id: '1', tenantId: 'tenant-A' },   // where 必带 tenantId
  });
});

it('★ AI 失败触发 refundWithRetry（对应 _shared/rules.md §1）', async () => {
  creditsMock.consume.mockResolvedValue(undefined);
  jest.spyOn(service as any, 'callAI').mockRejectedValue(new Error('500'));
  await expect(service.generate('u1', 'tenant-A', {} as any)).rejects.toThrow();
  expect(creditsMock.refundWithRetry).toHaveBeenCalledWith(
    'u1', expect.any(Number), expect.stringContaining('_refund'),
    expect.any(String), 3, 'tenant-A',   // ★ tenantId 与扣费一致
  );
});
```

## 8. 多租户隔离测试（e2e，最高价值）

跨租户越权是多租户 SaaS 头号安全 bug，**必须有 e2e 断言 A 租户读不到 B 租户数据**：
```typescript
// test/tenant-isolation.e2e-spec.ts
it('租户 A 的 token 无法读取租户 B 的记录', async () => {
  const recB = await seedRecordForTenant('tenant-B');
  const res = await request(app.getHttpServer())
    .get(`/api/v1/feature/${recB.id}`)
    .set('Authorization', `Bearer ${tokenTenantA}`);   // A 的 jwt
  expect([403, 404]).toContain(res.status);            // 绝不能 200 泄漏
});

it('body 里伪造 tenantId 也不能越权（tenantId 只认 jwt）', async () => {
  const res = await request(app.getHttpServer())
    .post('/api/v1/feature/do')
    .set('Authorization', `Bearer ${tokenTenantA}`)
    .send({ tenantId: 'tenant-B', title: 'x' });        // 篡改 body
  // 记录必须落在 A（jwt active），不受 body 影响
  const created = await prisma.someTable.findFirst({ where: { title: 'x' } });
  expect(created.tenantId).toBe('tenant-A');
});
```

## 9. NestJS e2e（supertest + 测试库）

```typescript
beforeAll(async () => {
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
  app = moduleRef.createNestApplication();
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  await app.init();
});
afterAll(async () => await app.close());

it('/api/v1/health (GET) → 200', () =>
  request(app.getHttpServer()).get('/api/v1/health').expect(200));

it('DTO 校验：缺 title → 400', () =>
  request(app.getHttpServer()).post('/api/v1/feature/do')
    .set('Authorization', `Bearer ${token}`).send({}).expect(400));
```

**测试库策略**（三选一）：
| 方案 | 用法 | 适合 |
|---|---|---|
| 独立 dev/test MySQL schema | `.env.test` 指向 `<app>_test` 库，e2e 前 `prisma migrate reset --force` | 本地 + CI service container |
| Testcontainers | 每次 spin up 一次性 MySQL 容器 | CI 隔离最干净 |
| SQLite 内存 | schema 兼容时最快，但 MySQL 专属特性测不到 | 纯逻辑快测 |

★ **e2e 禁止连生产库 / dev 共享库**（对应部署红线）；CI 用 service container（见 ci-cd skill）。

## 10. Mock 约定

| 层 | 工具 | 约定 |
|---|---|---|
| Flutter | `mocktail` | 不需 codegen；`registerFallbackValue` 处理自定义类型入参；`when().thenAnswer` 异步 |
| NestJS | `jest.fn()` + `useValue` | Prisma/Credits/Upload/AI-Proxy 都注入 mock；`jest.clearAllMocks()` 每例重置 |
| HTTP（Flutter） | mock `Dio` 或 `http_mock_adapter` | 断言 URL + header（Authorization / x-device-token）+ body |
| AI 上游 | 一律 mock | ★ 禁止单测/e2e 打真实 Qwen/Gemini（烧钱 + flaky） |

## 11. 覆盖率门禁

```bash
# Flutter
flutter test --coverage           # 生成 coverage/lcov.info
# 过滤生成代码
lcov --remove coverage/lcov.info '*.freezed.dart' '*.g.dart' -o coverage/lcov.info

# NestJS
npm run test:cov                  # jest --coverage
```

**建议阈值**（写进 CI，不达标 fail）：
- 后端 Service 业务逻辑 ≥ 70%；多租户/积分相关文件 ≥ 85%
- 前端 Notifier/util ≥ 60%；UI 不强求
- ★ 覆盖率是下限不是目标；关键分支（越权、退款、race）必须有专门断言,不能只靠行覆盖蒙混

`package.json` jest 阈值：
```json
{ "jest": { "coverageThreshold": { "global": { "branches": 60, "functions": 70, "lines": 70 } } } }
```

## 12. 本地运行命令

```bash
# Flutter
flutter test                          # 全部
flutter test test/unit/               # 目录
flutter test --tags golden            # 只跑 golden
flutter test --update-goldens         # 更新 golden 基准

# NestJS
npm run test                          # 单测
npm run test:watch                    # watch
npm run test:e2e                      # e2e（需测试库）
npm run test:cov                      # 覆盖率
```

## 13. CI 集成

测试进 CI 门禁才有意义。矩阵、缓存、service container、golden 环境固定见 `~/.claude/skills/ci-cd-github-actions/SKILL.md`：
- PR 必跑：`flutter analyze` + `flutter test` + `npm run test` + 静态 grep（6.2 顶层 import / 中国 CDN 残留）
- release 必跑：三 flavor 构建 + 解包验证（6.3）

## 14. 自检模板

```
新增/修改测试：
覆盖的关键分支：（越权 / 退款 / 切租户 / flavor 工厂 / DTO 校验）
mock 了哪些依赖：（Prisma / Credits / AI-Proxy / Dio）
是否连了真实上游：（必须 = 否）
本地运行结果：（flutter test / npm run test 全绿）
CI 门禁：（已加入 / 不涉及）
```

## 参考

- 配套 skill：`ci-cd-github-actions`（把测试挂进门禁）、`flutter-coding-conventions`（被测代码规范）、`nestjs-backend-conventions`（Service/DTO 结构）、`observability`（生产侧兜住测试没覆盖的）
- 跨 skill 铁律：`~/.claude/skills/_shared/rules.md` §1 扣费退款 / §2 持久化反查 / §4 切租户
- Flutter 测试：https://docs.flutter.dev/testing
- NestJS 测试：https://docs.nestjs.com/fundamentals/testing
- mocktail：https://pub.dev/packages/mocktail

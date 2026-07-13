---
name: frontend-backend-alignment
description: 前后端对齐规范 — Freezed model ↔ Prisma schema 字段一致性、API 契约改动 → 文档同步、版本号双平台 bump、Changelog 三件套联动、cards 5 章节、AI 扣费三方同步（后端 pricing + 前端 i18n + ARB）、多租户 Provider 重置清单同步、团队 Owner 联系方式回传链路。
---

# 前后端对齐规范 Skill

> 解决"代码 / 文档 / 版本 / API 字段四处对齐"难题。前端 Flutter + 后端 NestJS + 文档 Markdown 三者必须一致，本 skill 列举强约束 + 自检清单。

## 1. API 字段对齐：Freezed Model ↔ Prisma Schema

**强约束**：前端 `lib/data/models/<resource>_model.dart` 的 Freezed 字段 + 后端 `server/prisma/schema.prisma` 的 model 字段，**一对一对齐**。

| 后端 Prisma | 前端 Freezed | 说明 |
|---|---|---|
| `id String @id @default(uuid())` | `required String id` | 主键 |
| `hotelId String @map("hotel_id")` | `required String hotelId` | DB snake_case，TS/Dart camelCase |
| `title String` | `required String title` | |
| `description String?` | `String? description` | nullable 一致 |
| `tags String[]` (Postgres) / `String @db.Text`(MySQL JSON) | `@Default(<>) List<String> tags` | 数组字段两端类型对齐 |
| `createdAt DateTime` | `required DateTime createdAt` | ISO 8601 字符串 ↔ DateTime |
| `metadata Json?` | `Map<String, dynamic>? metadata` | JSON 字段 |

**自检脚本**：`scripts/check_api_alignment.sh`（建议每次 schema 改动后跑）：
```bash
#!/usr/bin/env bash
# 1. 列 Prisma model 字段
echo "=== Prisma <Model> 字段 ==="
sed -n '/^model <Model> /,/^}/p' server/prisma/schema.prisma

# 2. 列 Freezed model 字段
echo "=== Freezed <Resource>Model 字段 ==="
grep -E "required|@Default|String\?|int\?|bool\?" lib/data/models/<resource>_model.dart
```

肉眼比对 → 字段名 / nullable / 类型 三者必须一致。

## 2. API 契约改动 → 文档同步铁律

每个 API 改动 → **同时**更新三个地方：

```
1. 后端代码：
   server/src/modules/<feature>/dto/<feature>.dto.ts          # DTO 类
   server/src/modules/<feature>/<feature>.controller.ts       # @Post / @Get 端点
   server/src/modules/<feature>/<feature>.service.ts          # 业务逻辑

2. 前端代码：
   lib/data/services/<feature>_api_service.dart               # API 调用
   lib/data/models/<feature>_model.dart                       # Freezed 数据类

3. 文档（强约束）：
   docs/api_contracts/<feature>.md                             # API 契约（请求/响应 JSON 示例）
   docs/backend_spec.md                                        # 后端架构总览（如新增端点段落）
   docs/cards/<tool>.md                                        # 前端工具卡片（5 章节）
```

**强约束**：
- ★ **改了代码 → 打开文档 → 检查是否一致 → 不一致立即更新**
- ★ **文档过时比没文档更危险**
- ★ **当前状态 / 实现 / 口径必须与源码一致**，禁止历史结论冒充现状
- ★ 旧审计 / 旧验收文档失效后立即删除或标注"历史归档、不可作为当前依据"

## 3. 工具卡片 5 章节（前端模块文档）

`docs/cards/<tool>.md` **强制**结构：

```markdown
# <工具名>（<TOOL_ID>）

> 最后审计日期 + 当前架构口径

## 1. 功能概述
- 一句话核心价值
- 用户角色 / 适用场景

## 2. UI 组件清单
- 主入口页面：`lib/presentation/screens/tools/<tool>/...`
- 关键组件树（<5 层）
- 共享 Widget 引用

## 3. 数据流
- 用户操作 → Provider → API Service → 后端端点 → Service → DB
- 涉及的 Riverpod Provider
- API 契约文件指向：`docs/api_contracts/<tool>.md`

## 4. 文件清单
| 文件 | 用途 |
| 前端：lib/data/services/...     | API 调用 |
| 前端：lib/domain/providers/...  | 状态管理 |
| 前端：lib/presentation/...      | UI |
| 后端：server/src/modules/...    | 业务模块 |
| 数据库表：<table_name>           | Prisma schema |

## 5. 修改记录
| 日期 | 内容 |
| YYYY-MM-DD | 初始版本：实现 ABC |
| YYYY-MM-DD | 优化 XYZ |
（仅保留关键里程碑，≤10 条）
```

**强约束**：新增工具模块必须建对应 `docs/cards/<tool>.md` + 更新 `docs/cards/README.md` 索引。

## 4. 版本号双平台对齐（pubspec ↔ iOS ↔ Android）

详见 `~/.claude/skills/_shared/rules.md` §3。本 skill 不重述 Info.plist / build.gradle.kts 模板。

## 5. Changelog 三件套联动（用户可感知改动 → 必触发）

详见 `~/.claude/skills/_shared/rules.md` §3（触发判定清单 + 三件套文件 + 编译前硬性检查）。

## 6. AI 扣费点三方同步（后端 + 前端 + i18n）

详见 `~/.claude/skills/_shared/rules.md` §1（三方同步铁律 + `scripts/check_credit_action_keys.sh` 自检模板）。本 skill 不重述模板。

## 7. AI Prompt → workingLanguage 端到端透传

**链路**：

```
Flutter (设置页) → hotel.workingLanguage = 'zh-HK'
   → POST /api/v1/hotel PATCH workingLanguage
   → 后端 hotel.dto @IsIn(['zh','zh-HK','en']) 校验
   → DB: hotels.working_language = 'zh-HK'

LLM 请求时：
   Controller @CurrentUser('hotelId') hotelId
   → service: hotel = await prisma.hotel.findUnique({ select: { workingLanguage: true } })
   → aiProxy.generateXxx(..., hotel.workingLanguage)    ← raw code 透传
   → ai-proxy.service: getLanguageNameForPrompt(rawCode) → '繁體中文'
   → prompt 注入 "请用 繁體中文 输出"
```

**强约束**：
- ★ 整个链路用 **raw `workingLanguage`** （`zh-HK` 不归一为 `zh`）
- ★ DTO `@IsIn` 必须用项目级常量（`WORKING_LANGUAGE_OPTIONS`），与 Flutter `AppConstants.workingLanguageOptions` 一致
- ★ 业务二元分支（"中文 vs 英文" UI 路径）才用归一后的 `normalizeBusinessLanguageCode(code)`

## 8. 多租户 Provider 重置清单同步

详见 `~/.claude/skills/_shared/rules.md` §4。**铁律**：新增"按租户缓存"的 Riverpod Provider 必须**同时**：
1. 加入 `TenantNotifier.switchTenant()` 的 invalidate 清单
2. 同步 `docs/specs/tenant_switch_spec.md §3.3 "按租户缓存的 Provider 清单"`
3. Code Review 时对照 `tenant_switch_spec.md §5 Checklist` 逐项核对，漏项打回

## 9. 团队成员积分扣费失败 → Owner 联系方式回传链路

```
后端 server/src/modules/credits/credits.service.ts:
   if (member && credits < cost) {
     throw new HttpException({
       code: 'CREDITS_INSUFFICIENT',
       isTeamMember: true,
       ownerEmail: ownerUser.email,       ★ 必传
       ownerName: ownerUser.nickname,     ★ 必传
       message: '积分不足'
     }, 402);
   }

前端 lib/core/utils/extract_dio_message.dart:
   String extractDioMessage(DioException e) {
     final data = e.response?.data;
     if (data is Map && data['isTeamMember'] == true) {
       final email = data['ownerEmail'];
       final name = data['ownerName'];
       return '${data['message']}，请联系 $name ($email) 充值';   ★ 自动追加
     }
     return data?['message'] ?? '请求失败';
   }
```

**强约束**：
- ★ 团队成员扣费失败必须返回 `{isTeamMember, ownerEmail, ownerName}`
- ★ 前端 `extractDioMessage` 必须解析这三字段并友好展示
- ★ 测试场景：用 member 账号扣费、Owner 余额为 0 → 看是否弹"请联系 xxx 充值"

## 10. 登录超 4 台设备 → 踢老设备回传

```
后端 server/src/modules/auth/auth.service.ts login():
   const devices = await prisma.device.count({ where: { userId } });
   let kickedOldDevice = false;
   if (devices >= MAX_DEVICES) {
     await prisma.device.deleteMany({
       where: { userId },
       orderBy: { lastActiveAt: 'asc' },
       take: devices - MAX_DEVICES + 1,
     });
     kickedOldDevice = true;
   }
   return { token, kickedOldDevice };          ★ 必传

前端 lib/domain/providers/auth_provider.dart _onLoginSuccess():
   if (response.kickedOldDevice == true) {
     ContraToast.warning(context, l.authOldDeviceKicked);
   }
```

**强约束**：
- ★ 后端 login 响应必须返回 `kickedOldDevice: boolean`
- ★ 前端 `_onLoginSuccess` 读取并显示 Toast

## 11. 切租户时序与 race 防护

详见 `~/.claude/skills/_shared/rules.md` §4。前端 4 步时序 + 后端配合（`@CurrentUser('hotelId')`/Service `where` 必带 hotelId/WS `to('hotel_${hotelId}')`/FCM `notifyUser(userId, hotelId, payload)` 三参签名）。

**race 防护**：
- 前端编辑型页面用 `_editingTenantId` 快照（参见 `_shared/rules.md` §4）
- 后端持久化 hotelId 反查（参见 `_shared/rules.md` §2）

## 12. 推送点击自动切租户

```
后端 fcm.service.ts pushToRegistrationIds():
   data: {
     ...payload,
     hotelId,                ★ 必注入 extras.hotelId
   }

前端 jpush_service.dart _navigateFromNotification():
   final hotelId = extras['hotelId'];
   if (hotelId != null && hotelId != currentTenantId) {
     await ref.read(tenantProvider.notifier).switchTenant(hotelId);  ★ 先切租户
   }
   ctx.push(deeplink);                                                ★ 再路由
```

**强约束**：FCM `onMessageOpenedApp` 同样规范。

## 13. uploads 双向补齐链路

后端 `UploadService` 把文件落到 `server/uploads/<module>/<hotelId>/<filename>`。本地 dev 与生产服务器分别本地磁盘存储，任意一方生成的图片另一方没有就 404。

**强约束**：
- ★ 部署后端时必须执行 uploads 双向补齐（`backend-production-deploy` skill 第 4 节）
- ★ 长期解法：`UPLOAD_STORAGE=oss` 切对象存储，绕开同步问题

## 14. i18n ARB 三档对齐

**强约束**：
- 改中文 UI 文案 → 必须同步更新 `app_zh.arb` + `app_en.arb`（多语言项目还要更新 `app_zh_HK.arb` 等）
- 新增 ARB key 后跑 `flutter gen-l10n`
- 自检：所有 .arb 文件 key 集合一致（用 `jq` / Python 脚本对比）

```bash
#!/usr/bin/env bash
# scripts/check_arb_alignment.sh
python3 - <<'PY'
import json, glob
keys_per_file = {}
for f in glob.glob('lib/l10n/app_*.arb'):
    with open(f) as fp:
        data = json.load(fp)
    keys = {k for k in data if not k.startswith('@')}
    keys_per_file[f] = keys
all_keys = set.union(*keys_per_file.values())
for f, keys in keys_per_file.items():
    missing = all_keys - keys
    if missing:
        print(f"❌ {f} 缺失 key: {sorted(missing)[:5]}...")
    else:
        print(f"✅ {f}")
PY
```

## 15. 跨业务协同（D1/D4/I1/F1 等）

某些工具间有协同关系（投诉数据 → 问卷生题、入住指南 → 入境游客入口）。**强约束**：
- 新增跨业务入口 → 更新 `docs/cross_business_relations.md`
- 入口最终展示条件 = 来源卡片自身开关 && 目标卡片已发布 / 已开通 && 目标卡片允许在当前场景展示
- 修改 `chat_provider.dart` / 类似跨业务 Provider 影响的工具数 ≥ 3 个 → Code Review 必须覆盖所有依赖方

## 16. 自检脚本汇总

建议放 `scripts/` 下，每次部署或合并 PR 前跑：

```bash
scripts/check_api_alignment.sh       # Prisma model ↔ Freezed model 字段对齐
scripts/check_credit_action_keys.sh  # 扣费 action 三方同步
scripts/check_arb_alignment.sh       # ARB key 多语言一致
scripts/check_cn_no_google.sh        # cn flavor 解包验无 Firebase
scripts/check_overseas_no_jpush.sh   # overseas 解包验无 JPush
```

## 17. 一致性强约束总览

| 项目 | 三方对齐位置 | 不对齐后果 |
|---|---|---|
| API 字段 | Prisma + Freezed + `docs/api_contracts/<tool>.md` | 前端解析失败 / 字段类型不匹配 |
| 工具卡片 5 章节 | `docs/cards/<tool>.md` + 实际代码 | 文档误导新成员，bug 排查慢 |
| 版本号 | pubspec ↔ Info.plist ↔ build.gradle.kts | iOS / Android 显示不同版本 |
| Changelog 三件套 | CHANGELOG + ios/<v>.md + android/<v>.md + 实际代码改动 | 商店审核拒 / 用户疑惑 |
| AI 扣费 action | tool-credit-pricing.ts + credit_log_label.dart + ARB | 积分明细落英文 / 切语言不变 |
| 工作语言三档 | DTO @IsIn + AppConstants + ARB | 用户写入非法值，业务层 fallback 兜底 |
| 多租户 Provider 重置清单 | switchTenant() invalidate 清单 + tenant_switch_spec.md §3.3 | 切租户残留旧数据 / 越权 |
| 团队成员扣费失败 | 后端 isTeamMember/ownerEmail + 前端 extractDioMessage | 用户拿不到 Owner 联系方式 |
| 4 设备踢出 | 后端 kickedOldDevice + 前端 _onLoginSuccess | 用户不知被踢，回去登录卡 |
| 推送点击 | 后端 extras.hotelId + 前端 switchTenant | 切错租户写错数据 |

## 18. Code Review checklist（每次合并 PR）

- [ ] API 字段：DTO ↔ Prisma ↔ Freezed 三方对齐
- [ ] 文档：API 改动同步到 `docs/api_contracts/<tool>.md` + `docs/backend_spec.md` + `docs/cards/<tool>.md`
- [ ] 版本号：如有用户可感知改动，pubspec buildNumber +1 + 三件套 changelog 写好
- [ ] 扣费：新增 action 三方同步（pricing.ts + credit_log_label.dart + ARB）
- [ ] 多租户：新增 Provider 加入 switchTenant() 重置清单 + 同步 tenant_switch_spec.md
- [ ] WebSocket：新增 emit 必须 `to('hotel_${hotelId}')` + payload 带 hotelId
- [ ] 安全：所有租户域 Controller 用 `@CurrentUser('hotelId')` 不接 body / query 的 hotelId
- [ ] AI 扣费点：`consume` 后必须 `try/catch + refundWithRetry`
- [ ] 持久化 hotelId 反查：reserve / 异步任务 / 长 session 退款用持久化字段不读 jwt
- [ ] i18n：新增 UI 文案三档 ARB 同步 + `flutter gen-l10n`

## 参考

- 配套 skill：
  - `flutter-coding-conventions`（前端规范）
  - `nestjs-backend-conventions`（后端规范）
  - `backend-production-deploy`（部署 SOP）
  - `ios-app-store` / `cn-android-flavor` / `overseas-android-google-play`（三发布渠道）
  - `flutter-multi-region-dev`（项目启动总入口）

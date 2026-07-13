# 共享规则（被多个 skill 引用）

> 本文件**不是 skill**（无 frontmatter，不会被 SkillSearch 自动加载），仅作为多个 skill 共同引用的"规则单一真相源"。被引用方式：skill 在对应章节写「详见 `~/.claude/skills/_shared/rules.md` §N」+ 一句本 skill 特有的补充。

## §1. AI 扣费 try/catch refundWithRetry 双保险

**铁律**：所有 AI Proxy 端点 `consume → try → catch → refundWithRetry`，禁止积分丢失。

**前端（Dart / Flutter）模板**：
```dart
await api.consumeCredits(toolId, action, cost);   // 先扣
try {
  return await api.callAI(...);
} catch (e) {
  await api.refundCreditsWithRetry(amount, reason: '${action}_refund', maxRetry: 3);
  rethrow;
}
```

**后端（NestJS）模板**：
```typescript
const cost = await this.creditsService.getActionCost(TOOL_ID, action, DEFAULT_COST);
await this.creditsService.consume(userId, <TENANT_ID>, TOOL_ID, action, cost, '描述');
try {
  return await this.aiProxyService.callXxx(prompt);
} catch (e) {
  await this.creditsService.refundWithRetry(
    userId, cost, `${action}_refund`, '失败退款', 3, <TENANT_ID>,
  );
  throw e;
}
```

**边界条件**：
- ★ `consume` 阶段失败（积分不足、网络错误）**不进** try block — 此时根本没扣到积分，无需退款。
- ★ 退款的 `<TENANT_ID>` 必须与原扣费时一致（异步任务退款用 task payload 持久化的 `<TENANT_ID>`，不读 jwt active）。
- ★ `consume` / `refundWithRetry` 的 `<TENANT_ID>` 参数必须来自 `@CurrentUser('<TENANT_ID>')` 的 jwt active 租户（同步场景）。

**新增扣费 action 必须三方同步**（即三处都改，否则积分明细落到英文 fallback、切语言不变）：
1. 后端 `server/src/common/constants/tool-credit-pricing.ts` 注册 `DEFAULT_TOOL_CREDIT_PRICING[TOOL_ID].actions[action] = { credits, ... }`
2. 前端 `lib/core/utils/credit_log_label.dart` 加 `case '<action>': return l.creditAction<Action>;`
3. i18n `lib/l10n/app_zh.arb` + `app_en.arb`（+ 其他语言）加 `creditAction<Action>` key

**自检脚本**（建议 `scripts/check_credit_action_keys.sh`）：
```bash
#!/usr/bin/env bash
grep -oE "'[a-z_]+'\s*:\s*\{\s*credits" server/src/common/constants/tool-credit-pricing.ts \
  | grep -oE "'[a-z_]+'" | sort -u > /tmp/backend_actions.txt
grep -oE "case '[a-z_]+'" lib/core/utils/credit_log_label.dart \
  | grep -oE "'[a-z_]+'" | sort -u > /tmp/frontend_actions.txt
diff /tmp/backend_actions.txt /tmp/frontend_actions.txt && echo "✅ 一致" || echo "❌ MISSING"
```

---

## §2. 持久化 ID 反查（防 reserve→consume race）

**铁律**：长生命周期资源（reserve→consume / 异步任务 / 长会话 / 推送点击）必须用**持久化的 `<TENANT_ID>`**，**不读 jwt active**。

**典型场景**：
| 场景 | 用什么反查 |
|---|---|
| 积分预留 → 消费 | `reserveCredits` 返回 `reserveLogId`，后续 `consumeReserved` / `releaseReserve` 通过 `reserveLogId` 反查 `CreditsLog.<TENANT_ID>` |
| 异步任务（AI 修图 / 海报）入队 | task payload 里把 `<TENANT_ID>` 写进去；processor 失败退款用 `payload.<TENANT_ID>` |
| 长会话（电话 / 视频通话） | `session.<TENANT_ID>` 是结算 ID；session start 写入，end 时用它退款 |
| 推送点击 deeplink | 后端注入 `extras.<TENANT_ID>`；前端 `await switchTenant(extras.<TENANT_ID>)` 后再路由 |

**前端反例 / 正例（Dart）**：
```dart
// ❌ 用 jwt 当前 tenant 退款 — 跨租户切换 race 时会扣错
await refundCredits(currentJwtTenantId, amount);

// ✅ 用任务 payload 持久化的 <TENANT_ID>
await refundCredits(task.payload.tenantId, amount);
```

**后端模板（NestJS）**：
```typescript
// 预留时返回 reserveLogId
const { reserveLogId, <TENANT_ID> } = await this.creditsService.reserveCredits(...);
await this.prisma.wizardSession.create({ data: { reserveLogId, ... } });

// 消费时从 reserveLogId 反查 <TENANT_ID>
async consumeReserved(reserveLogId: string) {
  const log = await this.prisma.creditsLog.findUnique({ where: { id: reserveLogId } });
  return this.creditsService.consume(log.userId, log.<TENANT_ID>, ...);
}

// 异步任务入队：<TENANT_ID> 写进 payload
const job = await this.queue.add('process', { <TENANT_ID>, payload: ... }, ...);

// processor 失败退款：用 payload.<TENANT_ID> 不用 jwt
async process(job: Job) {
  try { ... } catch (e) {
    await this.creditsService.refundWithRetry(
      job.data.userId, job.data.cost, ..., job.data.<TENANT_ID>,
    );
  }
}
```

---

## §3. buildNumber + Changelog 三件套（双平台共用）

**铁律**：`pubspec.yaml: x.y.z+n` 是 iOS / Android 双平台版本号唯一真相源（versionName.buildNumber）。

| 改动类型 | 操作 |
|---|---|
| Bug 修复 / 文案微调 | patch +1（1.0.1 → 1.0.2） |
| 新功能 / 体验优化 | minor +1（1.0.x → 1.1.0） |
| 破坏性改版 | major +1（1.x.x → 2.0.0） |
| 任意提交商店的构建（TestFlight / 各应用市场内测/正式） | **buildNumber +1，禁止与历史构建号冲突** |

**触发判定**（任一即必须 bump + 写 changelog）：
- UI 元素改动（按钮、文案、布局、配色、动画、交互流程）
- 新增 / 移除 / 重命名工具或入口
- 新增 / 调整积分扣费规则、定价、会员权益
- 新增 / 修改对客 H5 页面
- 用户能感知到的性能 / 稳定性提升
- 修复用户报告过的 bug
- 推送 / 通知行为变化
- i18n 文案改动

**禁止**：
- ❌ 手动改 Info.plist 的版本号（必须从 pubspec 派生：`$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`）
- ❌ Android / iOS 用不同版本号
- ❌ buildNumber 重用（iOS App Store / Google Play 直接 reject）
- ❌ 商店投放文案出现内部模块编号 / 第三方 AI 品牌名（Gemini / Qwen / Claude / GPT）

**四件套文件**：
```
docs/changelog/
├── CHANGELOG.md              # 总索引（按版本倒序）
├── ios/<x.y.z+n>.md          # iOS 商店文案 ≤4000 字符 + 中英双语
└── android/<x.y.z+n>.md      # Android 商店文案 ≤500 字符 + 中英双语
```

**`docs/changelog/ios/<v>.md` 模板**：
```markdown
# x.y.z+n · iOS（App Store / TestFlight）

> 字数限制：≤ 4000 字符（App Store What's New）。
> 禁止内部编号；禁止第三方 AI 品牌名（统一产品名）；动词开头，每条 1 句话。

## 中文（zh-Hans / zh-Hant 投放）
- 新增：[功能名] [一句话价值]
- 优化：[XX] [改进点]
- 修复：[XX] [问题]

## English (en + global locales)
- New: [feature] [value]
- Improved: [thing] [improvement]
- Fixed: [thing] [issue]
```

**Android 商店文案** ≤ 500 字符（各市场字数取最严）。

**编译前硬性检查**（如本次含"用户端可感知"改动）：
- [ ] `pubspec.yaml` buildNumber 已 +1
- [ ] `docs/changelog/CHANGELOG.md` 新增对应版本条目
- [ ] `docs/changelog/ios/<x.y.z+n>.md` 已写好（含 zh / en）
- [ ] `docs/changelog/android/<x.y.z+n>.md` 已写好（含 zh / en）

不含可感知改动（纯部署后端 / 改文档 / 重构）→ 无需改 buildNumber。

---

## §4. 多租户 Provider 重置时序（switchTenant）

**核心规则**：
- 用 `tenantProvider`（或类比 `hotelProvider`）作为顶层租户上下文
- 所有按租户缓存的 Provider，切换租户时**必须** invalidate
- JWT 中含 `<TENANT_ID>`，切租户时**重签** token

**`switchTenant` 时序**（4 步，禁止打乱）：

```dart
class TenantNotifier extends StateNotifier<TenantState> {
  Future<void> switchTenant(String tenantId) async {
    final prevState = state;
    try {
      // 1. 先 refresh token（拿到 active=tenantId 的新 JWT）
      await ref.read(authProvider.notifier).refreshTokenAndProfile(tenantId);
      // 2. 再 update HTTP / WS 上下文（拦截器 / WS 重连用新 token）
      await ref.read(httpClientProvider.notifier).updateTenantContext(tenantId);
      // 3. 然后 setState 当前租户
      state = state.copyWith(currentTenant: getTenantById(tenantId));
      // 4. 最后 ref.invalidate 所有按租户缓存的 Provider 清单
      for (final provider in _tenantScopedProviders) {
        ref.invalidate(provider);
      }
    } catch (e) {
      // 错误回滚：保持原 state 不变；上层 UI 通过 Toast 提示用户重试
      state = prevState;
      rethrow;
    }
  }
}
```

**禁止顺序错误**：把 `setState` 放在 `refreshToken` 之前 → 监听 currentTenant 的 widget 立刻 rebuild → HTTP 拦截器还在用旧 JWT → 写入旧租户数据。

**新增按租户缓存的 Provider 必须三方同步**：
1. 给 Notifier 加 `reset()` 方法（StateNotifier）或支持 `ref.invalidate()`（AsyncNotifier / FutureProvider）
2. 加入 `TenantNotifier.switchTenant()` 的 invalidate 清单
3. 同步 `docs/specs/tenant_switch_spec.md §3.3 "按租户缓存的 Provider 清单"`（如项目有此规范文档）

**ConsumerStatefulWidget 切租户监听**：凡 `initState` 中 `ref.read(tenantProvider)` 缓存到本地 state（编辑表单 / 向导 / Tab 索引 / loaded 标记）的页面**必须**在 `build` 顶部加：

```dart
ref.listen<String?>(
  tenantProvider.select((s) => s.currentTenant?.id),
  (prev, next) {
    if (prev == null || prev == next) return;
    if (mounted) setState(() {
      // 清空本地 state，重跑 autoFill / loadConfig
    });
  },
);
```

**编辑型页面保存前 race 守卫**：
```dart
class _MyEditScreenState extends ConsumerState<MyEditScreen> {
  String? _editingTenantId;

  @override
  void initState() {
    super.initState();
    _editingTenantId = ref.read(tenantProvider).currentTenant?.id;
  }

  Future<void> _onSave() async {
    final currentId = ref.read(tenantProvider).currentTenant?.id;
    if (_editingTenantId != currentId) {
      ContraToast.error(context, l.commonTenantSwitchedRetry);
      return;
    }
    // 实际保存逻辑
  }
}
```

**后端配合**：
- ★ 所有租户域 Controller 用 `@CurrentUser('<TENANT_ID>')` 取 jwt active 租户
- ★ Service `where` 必带 `<TENANT_ID>`，WS `emit` 必须 `to('tenant_${<TENANT_ID>}')` + payload 带 `<TENANT_ID>`
- ★ 跨租户切换时 socket 必须重连用新 jwt

---

## §5. ICP 备案应用名 / 双 label

工信部 ICP 备案要求"安装后用户看到的应用名"必须与备案完全一致；但完整备案名（含中英文功能描述）在主屏图标下会被截断。

**iOS**：
- `CFBundleDisplayName` 必须等于 ICP 备案 App 名称（**逐字符**核对）
- 主屏图标长备案名可能被截断 — 不能改短，否则备案不一致；主屏被截断是合规之下的可接受体验

**Android（双 label 解法）**：`android/app/src/main/AndroidManifest.xml`
```xml
<application
    android:label="<完整 ICP 备案 App 名称>"   <!-- aapt dump badging 取这个，工信部审核命中 -->
    android:name="${applicationName}"
    ...>
    <activity
        android:name=".MainActivity"
        android:label="<App 短名>"   <!-- 主屏 launcher 取 activity 的 label，优先于 application label -->
        ...>
        <intent-filter>
            <action android:name="android.intent.action.MAIN"/>
            <category android:name="android.intent.category.LAUNCHER"/>
        </intent-filter>
    </activity>
</application>
```

**aapt 校验**（构建后必跑）：
```bash
AAPT=$HOME/Library/Android/sdk/build-tools/35.0.0/aapt
$AAPT dump badging build/app/outputs/flutter-apk/app-cn-release.apk \
  | grep -E "package|application:|launchable-activity"
```

**期望**：
- `application: label='<完整 ICP 备案 App 名称>'` ← 工信部备案查询命中此字段
- `launchable-activity: label='<App 短名>'` ← 主屏图标显示此字段

**iOS App Store 中国区** 还需在 App Store Connect → App Information → "China Mainland" 区域填 ICP 备案号；版号变化时需在工信部更新备案。

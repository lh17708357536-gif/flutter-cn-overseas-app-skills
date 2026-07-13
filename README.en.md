# Flutter Multi-Region App Skills (China + Overseas)

**[简体中文](README.md) | English**

> A set of **agent-loadable engineering skills** for building & shipping a Flutter + NestJS app to **both the China and overseas markets** (iOS + Android), across three build flavors — distilled from real production experience.

This is **not a ready-to-use framework**. It's a **reference skeleton + a checklist of hard rules**. Every snippet uses `<PLACEHOLDER>` values you replace with your own. Its value: when an AI coding assistant helps you build a multi-region app, it *remembers* the traps — store rejections, cross-tenant data leaks, tenant-switch races, lost credits, or a China build that bundles Firebase and gets rejected by Huawei.

The China ↔ overseas intersection is barely documented anywhere. English resources ignore China (JPush, ICP filing, "no Firebase in China builds"); Chinese resources ignore going global (Play Billing, GDPR, Apple 4.8). This encodes both sides.

---

## What this covers (the honest version)

This is **one production-proven, opinionated stack** — not a pick-any-vendor catalog. Coverage boundaries, stated plainly:

### ✅ Covered
- **Three flavors**: iOS (APNs + App Store IAP) / cn_android (JPush + WeChat/Alipay + Aliyun) / overseas_android (FCM + Play Billing) + the mutually-exclusive hard rules (no Firebase in cn, no JPush in overseas)
- **Frontend**: Flutter + Riverpod + go_router + Freezed + i18n + UI primitives + multi-tenant provider reset
- **Backend**: NestJS + Prisma + MySQL multi-tenant rules + JWT + Redis + BullMQ + UploadService + content moderation
- **Auth / login**: Apple / Google / WeChat / QQ third-party login + server-side verification + account linking + App Store 4.8 compliance
- **Payments**: WeChat Pay / Alipay (fluwx/tobias) / Apple IAP (JWS verify) / Google Play Billing
- **Push**: JPush (China) / FCM (overseas) / APNs (iOS)
- **Storage**: Aliyun OSS / Tencent COS / AWS S3 (single UploadService abstraction, switch by env, zero code change)
- **Maps & location**: Amap (China) / Google Maps / Mapbox routed by country + GCJ-02 coordinates + location-permission compliance
- **Compliance**: ICP dual label / implicit-identifier disclosure doc / iOS Privacy Manifest / GDPR·CCPA
- **Testing**: unit / widget / golden / ★flavor conditional-compilation tests / tenant isolation / credit refunds
- **CI/CD**: GitHub Actions three-flavor build matrix + iOS signing (fastlane match) + artifact guards + deploy pipeline
- **Observability**: flavor-aware crash reporting (Sentry) + structured logs + health/alerts + PII redaction
- **Deploy**: rsync + PM2 + Nginx production SOP (ask-before-write / dry-run / two-way uploads sync)
- **Runnable starter**: `examples/starter/` — three-flavor Flutter skeleton + NestJS `/health` backend (verified: `flutter analyze` clean, backend `/health` returns 200)

### ❌ Not yet covered (roadmap — PRs welcome)
- Huawei native HMS Push (currently via JPush vendor channel)
- Overseas subscriptions: Stripe / RevenueCat
- Flutter Web / Desktop targets
- WeChat native share (fluwx supports it; not yet written up)

---

## Skill index (15)

Start from **`flutter-multi-region-dev`** — the router. It decides which sub-skills an agent should load based on your target markets.

| Skill | Purpose |
|---|---|
| **`flutter-multi-region-dev`** | 🚪 **Entry router**: market-scope decision + sub-skill index + bootstrap |
| `flutter-coding-conventions` | Flutter frontend conventions (Riverpod / Freezed / i18n / UI primitives / flavor factories) |
| `nestjs-backend-conventions` | NestJS backend (layering / DTO / Prisma multi-tenant / JWT / Redis / BullMQ / moderation) |
| `frontend-backend-alignment` | Field / doc / version / credit / tenant-reset consistency between front & back |
| `backend-production-deploy` | Production deploy SOP (rsync / two-way uploads sync / PM2 / health checks) |
| `cn-android-flavor` | China Android (JPush / WeChat-Alipay / ICP filing / implicit identifier / ProGuard / aapt) |
| `ios-app-store` | iOS App Store (TestFlight / Privacy Manifest / IAP JWS / APNs / train-closed) |
| `overseas-android-google-play` | Overseas Android (Firebase / Play Billing / GDPR / ProGuard) |
| `social-login` | Third-party login (Apple / Google / WeChat / QQ + server verify + linking + 4.8) |
| `maps-location` | Maps & location (Amap / Google Maps / Mapbox routed by country + GCJ-02 + permissions) |
| `object-storage` | Object storage (Aliyun OSS / Tencent COS / AWS S3 abstraction + STS + signed URLs) |
| `flutter-testing` | Testing (Notifier/widget/golden + ★flavor conditional-compilation + tenant isolation) |
| `ci-cd-github-actions` | CI/CD (PR gates + ★three-flavor matrix + iOS signing + artifact guards + deploy) |
| `observability` | Observability (crash reporting + structured logs + health/alerts + PII redaction) |
| `_shared/rules.md` | Single source of truth for cross-cutting rules (credit refunds / persisted-id lookups / versioning / tenant switching / ICP filing) |

---

## Quick start (pick your assistant)

See [`docs/INSTALL.md`](docs/INSTALL.md). Summary:

### Claude Code
```bash
cp -R skills/* ~/.claude/skills/
```
Claude Code reads each `SKILL.md`'s `description` frontmatter and auto-loads the relevant one. Then just describe your task ("start a Flutter app for both China and overseas").

### Codex / any AGENTS.md-aware agent
The repo root has [`AGENTS.md`](AGENTS.md). Point the agent at this repo (or clone it into your project) and it gets the routing table + path mapping.

### Cursor / Windsurf / generic
Add `skills/` to your project and tell the agent, in your rules file, to read `skills/flutter-multi-region-dev/SKILL.md` first. Any file-reading agent can open `skills/<name>/SKILL.md` — plain Markdown, no proprietary format.

> **Path mapping note**: references like `~/.claude/skills/X` in skill bodies map to `skills/X` in this repo. Claude Code users `cp` into `~/.claude/skills/`; other agents just read the mapping (explained in `AGENTS.md`).

---

## Runnable example (examples/starter)

```bash
# Backend (NestJS, port 3007)
cd examples/starter/server && npm install && npm run build && npm run start
curl http://127.0.0.1:3007/api/v1/health          # {"status":"ok",...}

# Frontend (pick one flavor)
cd examples/starter/app && flutter pub get
flutter run --flavor cn       --dart-define=BUILD_FLAVOR=cn_android
flutter run --flavor overseas --dart-define=BUILD_FLAVOR=overseas_android
flutter run                   --dart-define=BUILD_FLAVOR=ios
```
Push is stubbed, so **no credentials are needed to compile and run** — it demonstrates the architecture (flavor split + factory pattern + no-Google-in-cn), not live SDK wiring.

---

## Design principles

1. **Honesty first** — mark "not covered" rather than pretend to be exhaustive.
2. **Rules centralized** — cross-skill rules live in `_shared/rules.md` as the single source of truth; sub-skills only add their own specifics.
3. **Placeholderized** — no real IPs / domains / keys / filing numbers / package names (sanitized, safe to publish).
4. **Agent-agnostic** — plain Markdown + frontmatter; any file-reading agent can use it.

---

## Contact

- Questions / ideas / collaboration: **lh17708357536@gmail.com**
- Or open an [issue](../../issues) / send a PR.

## License

[MIT](LICENSE) © 2026 haoliu

PRs welcome. When adding a skill, follow the existing format (frontmatter `name`+`description`, `<PLACEHOLDER>` values, reference `_shared/rules.md` for shared rules, a "References" section at the end).

---
name: ci-cd-github-actions
description: 多区域 Flutter + NestJS 的 GitHub Actions CI/CD — PR 质量门禁（analyze/test/静态 grep）、★ 三 flavor（iOS / cn_android / overseas_android）矩阵构建、iOS 签名（fastlane match 或 App Store Connect API key）、Android keystore 经 GitHub Secrets 注入、cn 无 Google / overseas 无 JPush 的产物解包守卫、buildNumber 自动化、后端 rsync+pm2 部署 workflow（手动/tag 触发）。
---

# GitHub Actions CI/CD Skill（多区域 Flutter + NestJS）

> 把 `flutter-testing` 的测试与三 flavor 发布纪律固化成流水线。所有 `<PLACEHOLDER>` 替换为项目实际值；所有密钥走 **GitHub Secrets**，禁止进仓库。

## 0. 流水线总览

| workflow | 触发 | 作用 |
|---|---|---|
| `ci.yml` | PR / push 到非发布分支 | 质量门禁：analyze + test（前后端）+ 静态守卫 grep |
| `release-mobile.yml` | 打 tag `v*` / 手动 dispatch | ★ 三 flavor 矩阵构建 + 产物解包守卫 + 上传制品 |
| `deploy-backend.yml` | 手动 dispatch（含确认输入）/ tag | rsync + pm2 部署后端（对应 `backend-production-deploy` skill） |

**铁律**：
- ★ 所有凭证（keystore、`.p8`、`match` 密码、SSH key、Firebase json）走 `secrets`，**绝不 commit**
- ★ 生产部署 workflow 必须**手动确认**（`workflow_dispatch` + `environment: production` 需 reviewer 批准），对齐"未经同意禁止写生产"红线
- ★ flutter / node 版本**锁定**（`flutter-version:` 写死，不用 `latest`），否则 golden 假失败 + 构建漂移

## 1. CI 质量门禁（`ci.yml`）

完整模板见 [`templates/ci.yml`](templates/ci.yml)。三个并行 job：

**job: flutter-quality**
```yaml
- uses: subosito/flutter-action@v2
  with: { flutter-version: '<FLUTTER_VERSION>', channel: stable, cache: true }
- run: flutter pub get
- run: dart run build_runner build --delete-conflicting-outputs   # 生成 freezed/g.dart
- run: flutter gen-l10n
- run: dart format --set-exit-if-changed lib/ test/               # 格式
- run: flutter analyze --fatal-infos
- run: flutter test --coverage --exclude-tags golden
- run: flutter test --tags golden                                 # golden 单独（环境敏感）
```

**job: backend-quality**（带 MySQL service container 跑 e2e）
```yaml
services:
  mysql:
    image: mysql:8
    env: { MYSQL_ROOT_PASSWORD: test, MYSQL_DATABASE: <APP>_test }
    ports: ['3306:3306']
    options: >-
      --health-cmd="mysqladmin ping" --health-interval=5s --health-retries=10
steps:
  - uses: actions/setup-node@v4
    with: { node-version: '<NODE_VERSION>', cache: npm, cache-dependency-path: server/package-lock.json }
  - run: npm ci
    working-directory: server
  - run: npx prisma migrate reset --force        # 用测试库
    working-directory: server
    env: { DATABASE_URL: 'mysql://root:test@127.0.0.1:3306/<APP>_test' }
  - run: npm run test
    working-directory: server
  - run: npm run test:e2e
    working-directory: server
    env: { DATABASE_URL: 'mysql://root:test@127.0.0.1:3306/<APP>_test' }
```

**job: static-guards**（多区域专属静态守卫 — 最便宜的一道防线）
```yaml
- run: bash scripts/check_no_toplevel_platform_import.sh   # flutter-testing §6.2
- run: bash scripts/check_arb_alignment.sh                 # ARB key 多语言一致
- run: bash scripts/check_credit_action_keys.sh            # 扣费 action 三方同步
- run: |
    # 中国 CDN 残留检查（cn 相关代码不得直连 googleapis）
    ! grep -rnE "fonts\.googleapis\.com|generativelanguage\.googleapis\.com" lib/ server/src/ \
      || { echo "❌ 发现 Google CDN 直连残留"; exit 1; }
```

## 2. ★ 三 flavor 矩阵构建（`release-mobile.yml`）

完整模板见 [`templates/release-mobile.yml`](templates/release-mobile.yml)。核心是 matrix：

```yaml
jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - flavor: cn_android
            runs-on: ubuntu-latest
            cmd: flutter build apk --flavor cn --release --dart-define=BUILD_FLAVOR=cn_android
            guard: scripts/check_cn_no_google.sh
          - flavor: overseas_android
            runs-on: ubuntu-latest
            cmd: flutter build appbundle --flavor overseas --release --dart-define=BUILD_FLAVOR=overseas_android
            guard: scripts/check_overseas_no_jpush.sh
          - flavor: ios
            runs-on: macos-14
            cmd: ''          # iOS 走 fastlane，见第 4 节
            guard: ''
    runs-on: ${{ matrix.runs-on }}
```

**每个 Android flavor job 尾部必须跑产物解包守卫**（对应 `flutter-testing` §6.3）：
```yaml
- run: |
    flutter build ... --dart-define=API_BASE_URL=${{ secrets.PROD_API_URL }}
- name: 产物守卫（cn 无 Google / overseas 无 JPush）
  if: matrix.guard != ''
  run: bash ${{ matrix.guard }}
- uses: actions/upload-artifact@v4
  with: { name: ${{ matrix.flavor }}, path: build/app/outputs/** }
```

> ❗ **矩阵的意义**：一次 push 同时验证三条互斥分支都能编且产物干净。cn job 若混入 Firebase、overseas job 若混入 JPush，`guard` 直接 fail，比上架被拒早三天发现。

## 3. Android 签名（keystore 经 Secrets 注入）

keystore **不进仓库**，base64 存 Secret，CI 里还原：
```yaml
- name: 还原 keystore
  run: |
    echo "${{ secrets.ANDROID_KEYSTORE_BASE64 }}" | base64 -d > android/app/keystore/release.jks
    cat > android/key.properties <<EOF
    storeFile=keystore/release.jks
    storePassword=${{ secrets.ANDROID_STORE_PASSWORD }}
    keyAlias=${{ secrets.ANDROID_KEY_ALIAS }}
    keyPassword=${{ secrets.ANDROID_KEY_PASSWORD }}
    jpushAppKey=${{ secrets.JPUSH_APP_KEY }}
    jpushChannel=default
    EOF
```
本地生成 base64：`base64 -i android/app/keystore/release.jks | pbcopy` → 贴进 GitHub Secret `ANDROID_KEYSTORE_BASE64`。

overseas flavor 还需 `google-services.json`（同样 base64 Secret → 还原到 `android/app/src/overseas/`）。

**所需 Secrets 清单**：`ANDROID_KEYSTORE_BASE64` / `ANDROID_STORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD` / `JPUSH_APP_KEY` / `GOOGLE_SERVICES_JSON_BASE64` / `PROD_API_URL`。

## 4. iOS 签名（两条路，二选一）

### 方案 A：fastlane match（推荐，多人/多机一致）
`match` 把证书 + profile 加密存一个私有 git 仓库，CI 拉取解密。`ios/fastlane/Fastfile`：
```ruby
platform :ios do
  lane :beta do
    setup_ci                                   # CI 里建临时 keychain
    match(type: "appstore", readonly: true)    # 拉取已存的证书/profile
    build_app(
      scheme: "Runner",
      export_method: "app-store",
      configuration: "Release",
    )
    upload_to_testflight(skip_waiting_for_build_processing: true)
  end
end
```
CI job：
```yaml
- run: |
    flutter build ios --release --no-codesign \
      --dart-define=BUILD_FLAVOR=ios --dart-define=API_BASE_URL=${{ secrets.PROD_API_URL }}
- run: bundle exec fastlane beta
  working-directory: ios
  env:
    MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
    MATCH_GIT_BASIC_AUTHORIZATION: ${{ secrets.MATCH_GIT_TOKEN }}
    APP_STORE_CONNECT_API_KEY_KEY: ${{ secrets.ASC_API_KEY_P8 }}
    APP_STORE_CONNECT_API_KEY_KEY_ID: ${{ secrets.ASC_KEY_ID }}
    APP_STORE_CONNECT_API_KEY_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
```
首次本地初始化：`fastlane match appstore`（生成并推到 match 私有仓库）。

### 方案 B：App Store Connect API Key 直传（无 match，签名靠手动 profile）
用 `.p8` API Key + 手动 export。适合单人；`build_ios_testflight.sh` 逻辑（见 `ios-app-store` skill）+ `xcrun altool --apiKey/--apiIssuer` 上传。**train-closed 409** 的 patch+1 纪律同样适用（`ios-app-store` §1）。

> ⚠️ **macOS runner 分钟数贵**（10x Linux）。iOS job 只在 tag / 手动 dispatch 触发，不要挂在每个 PR 上。

## 5. buildNumber 自动化

版本号唯一真相源是 `pubspec.yaml`（`_shared/rules.md` §3）。CI 里两种做法：
- **手动权威**（推荐）：开发者按纪律在 `pubspec.yaml` bump `x.y.z+n`，CI 直接读；`release-mobile.yml` 校验"该 buildNumber 未用过"（查 tag / TestFlight）。
- **CI 自增**：用 `github.run_number` 覆盖 buildNumber（`--build-number=${{ github.run_number }}`）。简单但会脱离 pubspec 真相源，**需同步回写**，否则 changelog 对不上。默认用手动权威。

Changelog 三件套门禁（含用户可感知改动的 release 必查）：
```yaml
- name: 校验 changelog 三件套
  run: |
    V=$(grep '^version:' pubspec.yaml | sed 's/version: //')
    test -f docs/changelog/ios/$V.md && test -f docs/changelog/android/$V.md \
      || { echo "❌ 缺 docs/changelog/{ios,android}/$V.md"; exit 1; }
    grep -q "$V" docs/changelog/CHANGELOG.md || { echo "❌ CHANGELOG.md 未登记 $V"; exit 1; }
```

## 6. 后端部署 workflow（`deploy-backend.yml`）

把 `backend-production-deploy` skill 的 SOP 流水线化,**但保留人工确认**：
```yaml
on:
  workflow_dispatch:
    inputs:
      confirm:
        description: '输入 DEPLOY 确认部署生产'
        required: true
jobs:
  deploy:
    if: github.event.inputs.confirm == 'DEPLOY'
    environment: production          # ★ 在仓库设置里给此 environment 配 required reviewers
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: 写 SSH key
        run: |
          mkdir -p ~/.ssh && echo "${{ secrets.PROD_SSH_KEY }}" > ~/.ssh/id && chmod 600 ~/.ssh/id
          ssh-keyscan -H ${{ secrets.PROD_HOST }} >> ~/.ssh/known_hosts
      - name: rsync（排除 .env / uploads / node_modules）
        run: |
          rsync -avz -e "ssh -i ~/.ssh/id" \
            --exclude ".env" --exclude ".env.*" --exclude "node_modules/" \
            --exclude "dist/" --exclude "uploads/" --exclude "keys/" \
            server/ ${{ secrets.PROD_USER }}@${{ secrets.PROD_HOST }}:${{ secrets.PROD_PATH }}/
      - name: 远程 build + restart
        run: |
          ssh -i ~/.ssh/id ${{ secrets.PROD_USER }}@${{ secrets.PROD_HOST }} bash -s <<'EOF'
          cd ${{ secrets.PROD_PATH }}
          npm ci --omit=dev || npm install
          npx prisma generate
          npm run build
          pm2 restart <PM2_APP_NAME> --update-env
          EOF
      - name: 健康检查
        run: curl -fsSI https://<PROD_DOMAIN>/api/v1/health || exit 1
```

**铁律**：
- ★ `.env` 永不同步（对应部署红线）；生产 secret 只在服务器
- ★ `prisma db push --accept-data-loss` **不放进自动 workflow**（破坏性）；schema 改动走人工 SOP 或 `migrate deploy`（预生成 migration）
- ★ uploads 双向补齐不进 CI（跨机器磁盘），仍走人工或迁 OSS
- `environment: production` + required reviewers = GitHub 会在 job 前卡一个"审批"，等价于 ask & wait

## 7. 缓存与提速

```yaml
# Flutter：subosito/flutter-action 的 cache:true 已缓存 SDK；再缓存 pub
- uses: actions/cache@v4
  with: { path: ~/.pub-cache, key: pub-${{ hashFiles('pubspec.lock') }} }
# Node：setup-node 的 cache: npm 已处理
# Gradle：
- uses: actions/cache@v4
  with: { path: ~/.gradle/caches, key: gradle-${{ hashFiles('android/**/*.gradle*') }} }
```
- PR 门禁（`ci.yml`）只跑 Linux job，**不碰 macOS**
- `concurrency` 取消同分支旧 run：
```yaml
concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }
```

## 8. 中国网络在 CI 里的坑

GitHub runner 在海外,**pub / npm / gradle 拉国内镜像反而慢或失败**。CI 里用官方源:
- ❌ 不要在 CI 设 `PUB_HOSTED_URL=pub.flutter-io.cn`（国内镜像,runner 在海外）
- ✅ CI 用默认 `pub.dev` / `registry.npmjs.org`
- 国内镜像只在**本地/国内构建机**用（对应 `cn-android-flavor` 构建命令）

## 9. 其他 CI 平台（如不用 GitHub Actions）

| 平台 | 适合 | 备注 |
|---|---|---|
| **Codemagic** | Flutter 专用,iOS 签名开箱即用 | 免费额度含 macOS,签名管理最省心 |
| **GitLab CI** | 自托管 runner（国内机器） | 国内网络下比 GitHub 稳；yaml 语义类似 |
| **Gitee Go** | 纯国内 | 生态弱,适合仅国内发布 |
本 skill 模板以 GitHub Actions 为准,其他平台迁移时保留"三 flavor 矩阵 + 产物守卫 + 人工确认部署"三要素即可。

## 10. Secrets 总清单（首次配仓库时逐项建）

```
# 通用
PROD_API_URL
# Android
ANDROID_KEYSTORE_BASE64  ANDROID_STORE_PASSWORD  ANDROID_KEY_ALIAS  ANDROID_KEY_PASSWORD
JPUSH_APP_KEY  GOOGLE_SERVICES_JSON_BASE64
# iOS
MATCH_PASSWORD  MATCH_GIT_TOKEN  ASC_API_KEY_P8  ASC_KEY_ID  ASC_ISSUER_ID
# 后端部署
PROD_SSH_KEY  PROD_HOST  PROD_USER  PROD_PATH
```
★ 配完后本地 `git grep` 一遍确认这些值没有任何一个硬编码在仓库里。

## 参考

- 配套 skill：`flutter-testing`（被 CI 执行的测试与守卫脚本）、`backend-production-deploy`（部署 SOP 手动版）、`ios-app-store`（签名/上传/train-closed）、`cn-android-flavor` / `overseas-android-google-play`（产物守卫的判据）
- 跨 skill 铁律：`~/.claude/skills/_shared/rules.md` §3（buildNumber + Changelog）
- flutter-action：https://github.com/subosito/flutter-action
- fastlane match：https://docs.fastlane.tools/actions/match/
- GitHub Environments（审批）：https://docs.github.com/actions/deployment/targeting-different-environments

---
name: backend-production-deploy
description: NestJS + Prisma 后端生产部署 SOP — ask-before-write、dry-run rsync、uploads 双向补齐、Prisma db push、PM2 restart、健康检查。适用于「本地代码 + 远程 SSH 服务器 + PM2 + Nginx」架构。
---

# 后端生产部署 SOP

> 本 skill 蒸馏自实际生产经验，覆盖 NestJS + Prisma + PM2 + Nginx 的标准部署链路。所有 `<PLACEHOLDER>` 在新项目落地前需替换为真实值（建议放到 `scripts/deploy-backend.sh` 顶部变量段）。

## 强约束（不可违反）

1. **未经用户明确同意，禁止任何对生产的写操作** — `rsync 上传 / pm2 restart / prisma db push / npm install / .env 修改 / nginx reload / 写生产 uploads` 都属于"写操作"。本地代码完善随时可做，部署前必须 **ask & wait**。
2. **生产 `.env` 永远不被覆盖** — 只允许"追加缺失键"，禁止 rsync 同步 `.env*`。
3. **dry-run 先于正式 rsync** — 任何代码同步前先跑 `rsync -n --itemize-changes` 看实际要传的文件清单，向用户确认无意外。
4. **uploads 必须双向补齐** — 本地与生产共享数据库但分别本地磁盘存上传文件，任意一方生成图片对方就 404；必须 `--ignore-existing` 双向 rsync。
5. **buildNumber 重用风险** — 触发部署的客户端版本如果牵涉 iOS/Android，参考 `ios-app-store` skill 的版本号纪律。

## 6 步标准 SOP

```
1. git status --short            # 摸底：本次涉及哪些文件
2. rsync -n（dry-run）            # 看实际要传什么；用户审核
3. rsync 正式上传                 # 排除 .env / node_modules / uploads / dist / logs / ...
4. uploads 双向补齐               # remote→local，再 local→remote，都 --ignore-existing
5. 远程：npm install / db push / build / pm2 restart --update-env
6. 健康检查：curl 内网 + 外网 + pm2 logs 末 60 行无 error
```

每步对应模板见下文。

---

## 1. 配置变量（写在 `scripts/deploy-backend.sh` 顶部）

```bash
SSH_KEY="${SSH_KEY:-<SSH_KEY_PATH>}"          # 例：/tmp/prod_server_key
REMOTE_HOST="<REMOTE_USER>@<PROD_HOST>"        # 例：root@1.2.3.4
REMOTE_PATH="<REMOTE_PROJECT_PATH>"            # 例：/www/wwwroot/server
LOCAL_PATH="<LOCAL_PROJECT_PATH>/server"        # 例：/Users/me/code/myapp/server
PM2_APP_NAME="<PM2_APP_NAME>"                  # 例：myapp-api
PROD_DOMAIN="<PROD_DOMAIN>"                    # 例：myapp.com
```

校验：
```bash
if [[ ! -f "$SSH_KEY" ]]; then
  echo "❌ SSH 密钥不存在: $SSH_KEY"; exit 1
fi
chmod 600 "$SSH_KEY" 2>/dev/null || true
```

---

## 2. dry-run 模板（read-only，让用户先审）

```bash
rsync -avzn --itemize-changes -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  --exclude ".env" \
  --exclude ".env.*" \
  --exclude "*.backup-*" \
  --exclude ".DS_Store" \
  --exclude "node_modules/" \
  --exclude "dist/" \
  --exclude "coverage/" \
  --exclude "logs/" \
  --exclude "uploads/" \
  --exclude "keys/" \
  --exclude "scripts/rembg-env/" \
  --exclude "prisma/dev.db" \
  --exclude "prisma/test.db" \
  --exclude "prisma/prisma/" \
  --exclude "src/h5/public/downloads/*.apk" \
  --exclude "src/h5/public/downloads/*.aab" \
  "$LOCAL_PATH/" \
  "$REMOTE_HOST:$REMOTE_PATH/"
```

**dry-run 输出读法**：
- `<f.st....` 行表示文件内容会被替换；
- `.d..t....` 行只是目录元信息更新（不变内容），可忽略；
- `<f+++++++` 行是新建文件。

向用户报告：本次会同步几个 `.ts` / `.hbs` / `.prisma` 文件，等用户确认。

---

## 3. 正式 rsync 上传

把 dry-run 命令的 `-avzn` 改成 `-avz`（去 n）即可：

```bash
rsync -avz -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  --exclude ".env" --exclude ".env.*" --exclude "*.backup-*" --exclude ".DS_Store" \
  --exclude "node_modules/" --exclude "dist/" --exclude "coverage/" --exclude "logs/" \
  --exclude "uploads/" --exclude "keys/" --exclude "scripts/rembg-env/" \
  --exclude "prisma/dev.db" --exclude "prisma/test.db" --exclude "prisma/prisma/" \
  --exclude "src/h5/public/downloads/*.apk" --exclude "src/h5/public/downloads/*.aab" \
  "$LOCAL_PATH/" \
  "$REMOTE_HOST:$REMOTE_PATH/"
```

---

## 4. uploads 双向补齐（防 404）

本地 dev 与生产服务器共享数据库但分别本地磁盘存 uploads；任一方生成图片，另一方没有就 404。**双向 `--ignore-existing` rsync** 保护两端已有文件不被覆盖：

```bash
# 远程 → 本地（先拉本地缺的）
rsync -avz --ignore-existing -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$REMOTE_HOST:$REMOTE_PATH/uploads/" \
  "$LOCAL_PATH/uploads/" || true

# 本地 → 远程（再推远程缺的）
rsync -avz --ignore-existing -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$LOCAL_PATH/uploads/" \
  "$REMOTE_HOST:$REMOTE_PATH/uploads/" || true
```

**高风险子目录清单**（用户上传 + AI 生成，丢失即 404）：
- 用户头像 / 酒店 Logo / 装修图
- AI 生图（修图、海报、地图、邀请函等）
- 聊天 / 工单 / 投诉附件
- 工具指南图片（如 `uploads/tool-guide/`）

**长期解法**：切到 OSS / S3（`UPLOAD_STORAGE=oss`），双向 rsync 是过渡方案。

---

## 5. `.env` 处理铁律

**禁止**用 rsync 同步 `.env*`。生产 `.env` 永远比本地多某些配置（生产数据库密码、APNs key、第三方 secret）。如果需要在生产追加新的 key，用**幂等 ssh 脚本检测后追加**：

```bash
ssh -i "$SSH_KEY" "$REMOTE_HOST" bash -s <<'REMOTE_SCRIPT'
set -e
cd /path/to/server
cp .env ".env.backup-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
if ! grep -q '^APPLE_ISSUER_ID=' .env 2>/dev/null; then
  cat >> .env <<'APPLE_ENV'

# Apple App Store Server API
APPLE_ISSUER_ID=<APPLE_ISSUER_ID>
APPLE_KEY_ID=<APPLE_KEY_ID>
APPLE_PRIVATE_KEY_PATH=<REMOTE_PROJECT_PATH>/keys/AuthKey_<KEY_ID>.p8
APPLE_BUNDLE_ID=<APP_PACKAGE>
APPLE_WEBHOOK_ENVIRONMENT=Sandbox
APPLE_ENV
  echo "[remote] Apple 配置已追加到 .env"
else
  echo "[remote] APPLE_ISSUER_ID 已在 .env，跳过"
fi
REMOTE_SCRIPT
```

---

## 6. 服务器端 build + restart

按需执行（看 dry-run 涉及哪些文件）：

| 改动类型 | 必须执行 |
|---|---|
| `package.json` / `package-lock.json` 改动 | `PYTHON=/usr/bin/python3.11 npm install --no-audit --no-fund`（或 fallback `python3`） |
| `prisma/schema.prisma` 改动 | `npx prisma db push --accept-data-loss`（开发）或 `npx prisma migrate deploy`（生产） |
| Prisma client 改动 | `npx prisma generate` |
| **任何后端改动** | `npm run build && pm2 restart $PM2_APP_NAME --update-env` |

完整远程脚本：

```bash
ssh -i "$SSH_KEY" "$REMOTE_HOST" bash -s <<REMOTE_SCRIPT
set -e
cd $REMOTE_PATH
npm install --no-audit --no-fund || true
npx prisma db push --accept-data-loss || true
npx prisma generate
npm run build
pm2 restart $PM2_APP_NAME --update-env
sleep 8
pm2 logs $PM2_APP_NAME --lines 60 --nostream
REMOTE_SCRIPT
```

`--update-env` 必须有，让 pm2 重新读取 `.env`。

---

## 7. 健康检查清单

部署完毕必须跑：

```bash
echo "=== 内网 ==="
ssh -i "$SSH_KEY" "$REMOTE_HOST" \
  "curl -sI http://127.0.0.1:3000/admin/login | head -3"

echo "=== 外网（IP 直连） ==="
curl -sI http://<PROD_HOST>:3000/admin/login | head -3

echo "=== 域名 / HTTPS ==="
curl -sI https://$PROD_DOMAIN/admin/login | head -3
```

期望：三处都 `HTTP/x 200` 或 `301`（301 是 HTTPS 跳转，正常）。

**pm2 logs 必看项**：
- `Nest application successfully started`
- 各 module 初始化 OK：`Redis 已连接`、`APNs provider 初始化成功`、`AppleJwsService 初始化成功`、（如适用）`JPush 初始化`
- 无 stack trace 报错

如果有 SIGINT 在新 pid 之前，是 pm2 替换旧进程的正常信号，不算 error。

---

## 8. 失败回滚

| 故障 | 应对 |
|---|---|
| `npm run build` 失败 | 不要 pm2 restart；老服务继续运行；本地修复后重新 dry-run + rsync |
| `pm2 restart` 后健康检查 4xx/5xx | 立即 `pm2 logs $PM2_APP_NAME --lines 100 --nostream` 看错误；找到根因；如紧急，`pm2 restart $PM2_APP_NAME --update-env` 不会自动回滚（pm2 不存历史构建），需要本地 git revert + 重 rsync |
| `prisma db push` 失败 | 检查是否需要 `--accept-data-loss`；生产建议改用 `prisma migrate deploy`（基于事先 `migrate dev` 生成的 migration）|
| 部署后 H5 静态资源 404 | uploads 双向补齐遗漏，重跑第 4 步 |
| 部署后 `.env` 缺关键值 | 不要从本地 rsync 覆盖；ssh 进生产 `nano .env` 手动追加，再 `pm2 restart $PM2_APP_NAME --update-env` |

---

## 9. `scripts/deploy-backend.sh` 模板

完整可执行模板见 [`templates/deploy-backend.sh.template`](templates/deploy-backend.sh.template)。新项目落地步骤：
1. `cp ~/.claude/skills/backend-production-deploy/templates/deploy-backend.sh.template scripts/deploy-backend.sh`
2. 替换顶部 `<SSH_KEY_PATH>` / `<REMOTE_HOST>` / `<REMOTE_PROJECT_PATH>` / `<LOCAL_PROJECT_PATH>` / `<PM2_APP_NAME>` / `<PROD_DOMAIN>` 6 个占位符
3. `chmod +x scripts/deploy-backend.sh`

---

## 10. 静态资源（APK / IPA / 下载文件）单独处理

不通过 rsync 主流程同步：在 rsync 时 `--exclude "src/h5/public/downloads/*.apk"`，单独用 `scp` + 备份 + 原子 `mv` 替换：

```bash
# 备份现有
TS=$(date +%Y%m%d-%H%M%S)
ssh -i "$SSH_KEY" "$REMOTE_HOST" \
  "cp $REMOTE_PATH/src/h5/public/downloads/app.apk \
      $REMOTE_PATH/src/h5/public/downloads/app.apk.backup-$TS"

# 上传新版到 .uploading（避免下载用户拿到半截文件）
scp -i "$SSH_KEY" -o ServerAliveInterval=30 \
  ./build/app/outputs/flutter-apk/app-cn-release.apk \
  "$REMOTE_HOST:$REMOTE_PATH/src/h5/public/downloads/app.apk.uploading"

# sha1 校验完整性
LOCAL_SHA=$(shasum -a 1 ./build/app/outputs/flutter-apk/app-cn-release.apk | awk '{print $1}')
REMOTE_SHA=$(ssh -i "$SSH_KEY" "$REMOTE_HOST" \
  "sha1sum $REMOTE_PATH/src/h5/public/downloads/app.apk.uploading | awk '{print \$1}'")
[[ "$LOCAL_SHA" == "$REMOTE_SHA" ]] || { echo "❌ sha1 不一致"; exit 1; }

# 原子替换（同分区 mv 不会被中途读到半成品）
ssh -i "$SSH_KEY" "$REMOTE_HOST" \
  "mv $REMOTE_PATH/src/h5/public/downloads/app.apk.uploading \
      $REMOTE_PATH/src/h5/public/downloads/app.apk"

# 验证 HTTPS 下载
curl -sI https://$PROD_DOMAIN/static/downloads/app.apk | head -8
```

---

## 部署最佳实践要点

1. **先编译再部署** — 本地 `npm run build` 通过后再 push；远程 build 失败时老 pm2 进程不受影响（`pm2 restart` 命令尚未触发）。
2. **dry-run 用户确认** — 不要默认对 master 分支 untracked 文件直接部署，可能含本地未 commit 的实验代码。
3. **观察首批日志** — pm2 restart 后 `--lines 60 --nostream` 看完整启动序列；下游 module 任何 init 失败立即回滚。
4. **不主动 `git pull`** — 直接从本地 working tree rsync 上传，避免在生产 git pull 中插入合并冲突或 hook 触发。
5. **静态资源单独走** — APK / IPA / 大文件不进主 rsync，避免半截上传影响用户下载。
6. **保留备份** — 替换静态资源前 `cp xxx.apk xxx.apk.backup-YYYYMMDD-HHMMSS`，最近 5-10 份保留作回滚用。

---

## 参考

- 本 skill 的命令模板已在生产环境验证（rsync 双向 / pm2 restart / sha1 校验 / 原子 mv）
- 配套 skill：`flutter-coding-conventions`（前端 buildNumber 纪律）、`ios-app-store`（IPA 生成）、`cn-android-flavor` / `overseas-android-google-play`（APK 生成）

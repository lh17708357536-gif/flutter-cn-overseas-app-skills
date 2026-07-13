# starter-server

最小可运行的 NestJS 后端 starter，零外部依赖（无数据库 / Redis），开箱即跑。

## 依赖安装与运行

```bash
npm install          # 安装依赖（需联网）
npm run build        # tsc 编译到 dist/
npm run start        # node dist/main.js 启动
# 或开发模式（ts-node 直接跑源码）
npm run dev
```

## 验证

```bash
curl -s http://127.0.0.1:3007/api/v1/health
# => {"status":"ok","version":"0.1.0","ts":"2026-..."}
```

## 端口

默认监听 **3007**（可用环境变量 `PORT` 覆盖）。
若 3007 被占用，可 `PORT=3017 npm run start` 换端口启动。

## 说明

- 所有路由统一挂在 `/api/v1` 前缀下。
- 健康检查为最小实现；生产环境请按根仓库 `skills/observability` 增加
  db / redis 等下游依赖探测（`Promise.allSettled` 并行）。
- 后端分层 / DTO / 鉴权等规范参见根仓库 `skills/nestjs-backend-conventions`。

import { Controller, Get } from '@nestjs/common';

/**
 * 健康检查控制器。
 *
 * 注意：生产版本应参考根仓库 skills/observability，
 * 增加对 db / redis 等下游依赖的真实探测（建议用
 * Promise.allSettled 并行探测，任一失败降级为 degraded/down
 * 并返回对应 HTTP 状态码，便于负载均衡与告警）。
 * 本 starter 为最小可跑版，零外部依赖，故此处仅返回静态状态。
 */
@Controller('health')
export class HealthController {
  // GET /api/v1/health
  @Get()
  check(): { status: string; version: string; ts: string } {
    return {
      status: 'ok',
      version: process.env.APP_VERSION || '0.1.0',
      ts: new Date().toISOString(),
    };
  }
}

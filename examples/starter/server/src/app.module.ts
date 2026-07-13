import { Module } from '@nestjs/common';
import { HealthModule } from './health/health.module';

// 根模块：仅聚合 HealthModule，保持最小可跑
@Module({
  imports: [HealthModule],
})
export class AppModule {}

import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

// 应用启动入口：创建 Nest 应用、统一 API 前缀、监听端口
async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);

  // 统一前缀：所有路由挂到 /api/v1 下
  app.setGlobalPrefix('api/v1');

  // 默认 3007，避免与本机其它服务冲突；可用 PORT 覆盖
  const port = Number(process.env.PORT) || 3007;
  await app.listen(port);

  // eslint-disable-next-line no-console
  console.log(`[starter-server] listening on http://127.0.0.1:${port}/api/v1`);
}

void bootstrap();

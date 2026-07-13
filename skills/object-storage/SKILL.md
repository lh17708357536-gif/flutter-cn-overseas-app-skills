---
name: object-storage
description: 对象存储多供应商抽象 — UploadService 统一接口后挂阿里云 OSS / 腾讯云 COS / AWS S3，按 UPLOAD_STORAGE env 切换零代码改动，本地 local 起步；直传 vs 后端中转、STS 临时凭证、私有 bucket 签名 URL、CDN 域名、跨区域（国内 OSS/COS + 海外 S3）路由、local↔生产 uploads 双向补齐过渡方案。
---

# 对象存储多供应商 Skill（OSS / COS / S3）

> 让"存哪家"变成一行 env。所有 `<PLACEHOLDER>` 替换为项目实际值。核心是 `UploadService` 抽象——业务代码只调 `uploadFile()` / `getFileUrl()`，不关心底层是本地磁盘还是哪家云。

## 1. 供应商选型矩阵

| 供应商 | 适合 | 备注 |
|---|---|---|
| **local**（本地磁盘） | 开发起步 / 单机小量 | 过渡方案，多机会 404（§7）|
| **阿里云 OSS** | 国内主力 | 与阿里云生态（Green 审核）配套 |
| **腾讯云 COS** | 国内备选 / 已用腾讯云 | API 近似 S3 |
| **AWS S3** | 海外 | Google Play/海外用户就近 |
| **兼容 S3 的**（MinIO/R2/COS-S3） | 自托管/多云 | 都可走 S3 SDK |

**跨区域策略**：国内数据 → OSS/COS（国内节点快、合规）；海外数据 → S3（就近）。可按数据 country 路由（类比 `maps-location`）,或简单起见全站一家 + CDN。

## 2. ★ UploadService 抽象（唯一入口）

```typescript
// common/services/upload.service.ts
export interface UploadResult { filePath: string; url: string; size: number; }

@Injectable()
export class UploadService {
  private readonly driver = process.env.UPLOAD_STORAGE || 'local';   // local | oss | cos | s3

  async uploadFile(file: Express.Multer.File, opts: { module: string; tenantId: string }): Promise<UploadResult> {
    const key = this.buildKey(file, opts);          // ★ 路径统一由此生成，禁止业务层拼
    switch (this.driver) {
      case 'oss': return this.putOSS(key, file);
      case 'cos': return this.putCOS(key, file);
      case 's3':  return this.putS3(key, file);
      default:    return this.putLocal(key, file);
    }
  }

  getFileUrl(filePath: string): string {
    if (process.env.CDN_DOMAIN) return `${process.env.CDN_DOMAIN}/${filePath}`;   // 有 CDN 优先
    switch (this.driver) {
      case 'oss': return `https://${process.env.OSS_BUCKET}.${process.env.OSS_REGION}.aliyuncs.com/${filePath}`;
      case 'cos': return `https://${process.env.COS_BUCKET}.cos.${process.env.COS_REGION}.myqcloud.com/${filePath}`;
      case 's3':  return `https://${process.env.S3_BUCKET}.s3.${process.env.S3_REGION}.amazonaws.com/${filePath}`;
      default:    return `/uploads/${filePath}`;
    }
  }

  private buildKey(file, opts) {
    // module/tenantId/yyyymm/uuid.ext —— 统一路径规则
    return `${opts.module}/${opts.tenantId}/${yyyymm()}/${uuid()}${extname(file.originalname)}`;
  }
}
```
**铁律**（对应 `nestjs-backend-conventions` §14）：
- ★ 新增上传**必须**走 `UploadService`，禁止 `writeFileSync` 直接写盘
- ★ 禁止在业务 Service 拼上传路径,统一 `buildKey`
- ★ 切换供应商**只改 env**,业务代码零改动

## 3. 各供应商 put 实现

```typescript
// 阿里云 OSS —— ali-oss
import OSS from 'ali-oss';
private ossClient = new OSS({
  region: process.env.OSS_REGION, bucket: process.env.OSS_BUCKET,
  accessKeyId: process.env.OSS_AK, accessKeySecret: process.env.OSS_SK,
});
async putOSS(key, file) {
  const r = await this.ossClient.put(key, file.buffer);
  return { filePath: key, url: this.getFileUrl(key), size: file.size };
}

// 腾讯云 COS —— cos-nodejs-sdk-v5
import COS from 'cos-nodejs-sdk-v5';
private cos = new COS({ SecretId: process.env.COS_SECRET_ID, SecretKey: process.env.COS_SECRET_KEY });
async putCOS(key, file) {
  await this.cos.putObject({
    Bucket: process.env.COS_BUCKET, Region: process.env.COS_REGION, Key: key, Body: file.buffer,
  });
  return { filePath: key, url: this.getFileUrl(key), size: file.size };
}

// AWS S3 —— @aws-sdk/client-s3（兼容 R2/MinIO：改 endpoint）
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
private s3 = new S3Client({
  region: process.env.S3_REGION,
  endpoint: process.env.S3_ENDPOINT,   // R2/MinIO 填自定义；AWS 留空
  credentials: { accessKeyId: process.env.S3_AK, secretAccessKey: process.env.S3_SK },
});
async putS3(key, file) {
  await this.s3.send(new PutObjectCommand({
    Bucket: process.env.S3_BUCKET, Key: key, Body: file.buffer, ContentType: file.mimetype,
  }));
  return { filePath: key, url: this.getFileUrl(key), size: file.size };
}
```

## 4. .env 配置（切一家只填一段）

```bash
UPLOAD_STORAGE=local            # local | oss | cos | s3
CDN_DOMAIN=                     # 有 CDN 填 https://cdn.<domain>，getFileUrl 优先用

# 阿里云 OSS
OSS_REGION=oss-cn-hangzhou
OSS_BUCKET=<BUCKET>
OSS_AK=<AK>
OSS_SK=<SK>

# 腾讯云 COS
COS_REGION=ap-guangzhou
COS_BUCKET=<BUCKET-APPID>
COS_SECRET_ID=<ID>
COS_SECRET_KEY=<KEY>

# AWS S3 / 兼容
S3_REGION=ap-northeast-1
S3_BUCKET=<BUCKET>
S3_ENDPOINT=                    # R2/MinIO 填；AWS 留空
S3_AK=<AK>
S3_SK=<SK>
```

## 5. 私有 bucket 签名 URL（敏感文件）

公开读的图（Logo/海报）用公共 URL 即可；**用户证件/账单等敏感文件放私有 bucket + 临时签名 URL**：
```typescript
async signedUrl(key: string, expiresSec = 300): Promise<string> {
  switch (this.driver) {
    case 'oss': return this.ossClient.signatureUrl(key, { expires: expiresSec });
    case 'cos': return this.cos.getObjectUrl({ Bucket, Region, Key: key, Sign: true, Expires: expiresSec });
    case 's3':  return getSignedUrl(this.s3, new GetObjectCommand({ Bucket, Key: key }), { expiresIn: expiresSec });
  }
}
```
- ★ 敏感文件 bucket 设为私有,只发短时签名 URL,别放 CDN 公共路径

## 6. 直传 vs 后端中转 + STS 临时凭证

| 方式 | 场景 | 安全 |
|---|---|---|
| **后端中转**（file 传后端再 put） | 需服务端处理/审核（如内容审核）| key 只在后端 ✅ |
| **前端直传 + STS** | 大文件/高并发,减后端压力 | ★ 用 **STS 临时凭证**,绝不下发主 AK/SK |

前端直传时后端只发临时凭证：
```
POST /api/v1/upload/sts → { credentials, bucket, region, keyPrefix, expire }
```
- ★ STS 权限用 policy 限死到 `keyPrefix`(该用户/租户目录),防越权覆盖他人文件
- ★ **图片走内容审核的场景**(对应 `nestjs-backend-conventions` §15)必须后端中转或直传后回调审核,不能纯直传绕过

## 7. local↔生产 uploads 双向补齐（local 模式过渡）

`UPLOAD_STORAGE=local` 时本地 dev 与生产**各自磁盘**,任一方生成图另一方 404。过渡方案是双向 rsync（对应 `backend-production-deploy` §4）：
```bash
rsync -avz --ignore-existing <生产>:uploads/ <本地>/uploads/   # 拉
rsync -avz --ignore-existing <本地>/uploads/ <生产>:uploads/   # 推
```
- ★ 这是**过渡**,不是长久解;切 OSS/COS/S3 后此问题消失
- 高风险目录(丢失即 404):头像/Logo/AI 生图/聊天附件/工具指南图

## 8. 迁移到云（从 local 切走的一次性动作）

1. 建 bucket + 配 CDN 回源
2. 一次性把存量 `uploads/` 刷上云:
   ```bash
   ossutil cp -r uploads/ oss://<BUCKET>/ --update      # OSS
   coscli sync uploads/ cos://<BUCKET>/                 # COS
   aws s3 sync uploads/ s3://<BUCKET>/                  # S3
   ```
3. 改 `.env` `UPLOAD_STORAGE=oss|cos|s3` + `CDN_DOMAIN`
4. `getFileUrl` 自动切;**历史存的是相对 filePath 而非全 URL** → 老数据无需改库(这就是为什么第 2 节 DB 只存 `filePath` 不存完整 URL)
- ★ **DB 只存 filePath(相对 key),不存带域名的完整 URL** → 换云/换 CDN 零改库,这是关键设计

## 9. 测试要点（挂进 flutter-testing）

- `UPLOAD_STORAGE` 切 local/oss/cos/s3 时 `getFileUrl` 产出对应域名
- `buildKey` 路径规则稳定(module/tenant/月/uuid)
- 私有文件走 signedUrl 且带过期
- DB 存的是相对 filePath 不含域名

## 10. 自检模板

```
存储改动：
是否走 UploadService：（禁止 writeFileSync / 禁止业务层拼路径）
DB 存 filePath 还是完整 URL：（必须相对 filePath）
敏感文件：（是否私有 bucket + 签名 URL）
直传：（是否用 STS 且限 keyPrefix / 审核场景是否绕过）
切换成本：（换供应商是否只改 env）
```

## 参考

- 配套 skill：`nestjs-backend-conventions` §14（UploadService 铁律）、`backend-production-deploy` §4（local uploads 双向补齐）、`maps-location`（同样的按 country 路由思路）、`overseas-android-google-play`（海外数据驻留 → S3 就近）
- ali-oss：https://github.com/ali-sdk/ali-oss
- 腾讯云 COS Node SDK：https://cloud.tencent.com/document/product/436/8629
- AWS S3 SDK v3：https://docs.aws.amazon.com/sdk-for-javascript/v3/developer-guide/

---
name: maps-location
description: 多区域地图与定位 — ★ 按国家/地区路由地图源（中国大陆 → 高德直连；港澳台/海外 → Google Maps 经海外节点中转 或 Mapbox 直连），flavor 感知（cn 禁 Google → 只用高德；overseas 用 Google/Mapbox），后端 _resolveMapSource 决策 + Google API 在华走新加坡中转、静态图/地理编码/地点检索代理，前端条件加载地图 SDK，定位权限按需申请合规。
---

# 多区域地图与定位 Skill

> 覆盖"中国大陆用高德、其他地区用 Google/Mapbox"的双源路由。所有 `<PLACEHOLDER>` 替换为项目实际值。
>
> **核心决策依据是数据的归属地（如 `hotel.country` / 业务实体的 country），不是用户 IP、不是手机系统区域**——同一个 App 里，展示北京的店用高德，展示东京的店用 Google，由数据决定。

## 1. ★ 地图源路由矩阵

| 数据归属地 | 地图源 | 网络路径 |
|---|---|---|
| 中国大陆（`country='CN'`） | **高德 Amap** | 直连（国内节点快、合规） |
| 港澳台（HK/MO/TW） | **Google Maps** 或 Mapbox | Google 走海外中转；Mapbox 直连 |
| 海外（JP/US/EU/...） | **Google Maps** 或 Mapbox | 同上 |

**flavor 叠加约束**：
- **cn_android**：禁 Google（对应 `cn-android-flavor` §1）→ **只能用高德**；若 cn 包需要显示海外地图，用高德的海外底图或静态图代理，**不引入 Google Maps SDK**
- **overseas_android / iOS**：用 Google Maps 或 Mapbox；中国大陆数据仍建议走高德静态图（Google 在华不可靠）
- ★ 路由决策放后端 `_resolveMapSource(entityId)`，前端只拿"用哪个源 + 已代理好的 URL"，不自己判断

## 2. 后端源决策 + Google 在华中转

```typescript
// map.service.ts
type MapSource = 'amap' | 'google' | 'mapbox';

resolveMapSource(country: string): MapSource {
  if (country === 'CN') return 'amap';
  // 港澳台 + 海外：按项目策略选 google 或 mapbox
  return process.env.OVERSEAS_MAP_PROVIDER === 'mapbox' ? 'mapbox' : 'google';
}
```

**Google Maps API 在中国大陆被墙 → 后端经海外节点中转**（对应项目 nginx `gemini_proxy.conf` 同款思路）：
```
.env:
GOOGLE_MAPS_KEY=<SERVER_SIDE_KEY>                 # ★ 服务端 key，限 IP，不下发前端
GMAPS_PROXY_BASE=https://<OVERSEAS_PROXY>/gmaps   # 海外 Nginx 反代 maps.googleapis.com
AMAP_WEB_KEY=<AMAP_WEB_SERVICE_KEY>               # 高德 Web 服务 key（服务端）
AMAP_JS_KEY=<AMAP_JS_KEY>                         # 高德 JS API key（前端/H5 用，配安全密钥）
MAPBOX_TOKEN=<MAPBOX_TOKEN>
OVERSEAS_MAP_PROVIDER=google                       # 或 mapbox
```
海外 Nginx 需代理三类端点（对应你项目已有的 `/gmaps/static` `/gmaps/geocode/` `/gplaces/`）：
```nginx
location /gmaps/static/   { proxy_pass https://maps.googleapis.com/maps/api/staticmap; }
location /gmaps/geocode/  { proxy_pass https://maps.googleapis.com/maps/api/geocode/; }
location /gplaces/        { proxy_pass https://maps.googleapis.com/maps/api/place/; }
```

## 3. 静态地图（对客 H5 / 卡片最常用）

后端统一出静态图 URL，前端只贴 `<img>`，天然规避 SDK 与被墙问题：
```typescript
staticMapUrl(source: MapSource, lat: number, lng: number, zoom = 15): string {
  switch (source) {
    case 'amap':                                          // 高德静态图
      return `https://restapi.amap.com/v3/staticmap?location=${lng},${lat}`
        + `&zoom=${zoom}&size=750*400&markers=mid,,A:${lng},${lat}&key=${process.env.AMAP_WEB_KEY}`;
    case 'google':                                        // 经海外中转
      return `${process.env.GMAPS_PROXY_BASE}/static/?center=${lat},${lng}`
        + `&zoom=${zoom}&size=750x400&markers=color:red%7C${lat},${lng}&key=${process.env.GOOGLE_MAPS_KEY}`;
    case 'mapbox':
      return `https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/`
        + `pin-s+f00(${lng},${lat})/${lng},${lat},${zoom}/750x400?access_token=${process.env.MAPBOX_TOKEN}`;
  }
}
```
- ★ 高德坐标是 `经度,纬度`(lng,lat)；Google 是 `纬度,经度`(lat,lng)——**顺序反了地图就飘到别的国家**，这是头号 bug
- ★ 高德用 **GCJ-02** 火星坐标，Google/Mapbox 用 **WGS-84**；跨源传坐标必须转换（见 §5）

## 4. 前端交互地图（条件加载 SDK，flavor 感知）

```dart
// lib/core/config/map_factory.dart —— 顶层禁止直接 import google_maps_flutter（cn 会串味）
Widget buildMap({required MapSource source, required LatLng center}) {
  switch (source) {
    case MapSource.amap:   return AmapWidget(center: center);      // amap_flutter_map
    case MapSource.google: return GoogleMapWidget(center: center); // 仅 overseas/ios 编译
    case MapSource.mapbox: return MapboxWidget(center: center);
  }
}
```
`pubspec.yaml`：
```yaml
dependencies:
  amap_flutter_map: ^3.x.x       # 高德（cn）
  amap_flutter_location: ^3.x.x  # 高德定位
  google_maps_flutter: ^2.x.x    # Google（overseas/ios）
  mapbox_maps_flutter: ^2.x.x    # Mapbox（可选）
```
- ★ 与推送/支付工厂同理：`google_maps_flutter` 只能在工厂内条件构造，顶层 import 会让 cn 包打入 Google native lib（`flutter-testing` §6.2 守卫会拦）
- H5 地图：高德 JS API（`AMAP_JS_KEY` + 安全密钥）/ Google JS（海外）,由 `getH5StyleVars` 同级注入正确 key

## 5. 坐标系转换（GCJ-02 ↔ WGS-84，中国特有）

中国大陆地图数据强制偏移(GCJ-02 火星坐标)。**规则**：
- 存储：统一存 **WGS-84**(GPS 原始/国际通用),入库前不偏移
- 展示：给高德时转 GCJ-02；给 Google/Mapbox 用 WGS-84
- 定位回填：高德定位 SDK 直接给 GCJ-02，若要入库转回 WGS-84
```typescript
// 用成熟库如 gcoord，别手写偏移算法
import gcoord from 'gcoord';
const gcj = gcoord.transform([lng, lat], gcoord.WGS84, gcoord.GCJ02);  // 存→高德展示
```
- ★ 港澳台/海外数据不做偏移(GCJ-02 只适用中国大陆边界内)
- ★ 只在"数据在中国大陆 + 用高德展示"时转换,别无脑全转

## 6. 定位权限（合规，尤其国内）

- ★ **按需申请**：进入需要定位的业务功能时才申请,禁止首启/普通表单提前弹(对应 `cn-android-flavor` 隐私合规规则)
- cn flavor：定位权限在 `cn/AndroidManifest.xml` 声明；不需要定位的页面别声明 `ACCESS_FINE_LOCATION`
- iOS：`NSLocationWhenInUseUsageDescription` 用到才写(对应 `ios-app-store` §4)
- ★ 不采集精确定位就别申请精确定位；能用城市级(粗定位)就用 `ACCESS_COARSE_LOCATION`
- 定位失败/拒绝要有兜底:手动选城市/输入地址,不能白屏

## 7. 地理编码 / 逆地理 / 地点检索（服务端代理）

前端不直接调第三方地图 API(key 泄漏 + 被墙),统一走后端：
```
POST /api/v1/map/geocode      { address, country } → { lat, lng, source }
POST /api/v1/map/reverse      { lat, lng, country } → { formattedAddress }
GET  /api/v1/map/place-search { keyword, country }  → [{ name, lat, lng }]
```
后端按 `country` 选高德 Web 服务 或 Google/Places(经中转),key 只在服务端。

## 8. 测试要点（挂进 flutter-testing）

- `resolveMapSource('CN')==='amap'`；港澳台/海外按 env 返回 google/mapbox
- 工厂按 flavor:cn 不构造 GoogleMapWidget(否则 native lib 串味)
- 坐标顺序:高德 lng,lat / Google lat,lng —— 断言 staticMapUrl 拼对
- GCJ-02 转换只在中国大陆数据发生

## 9. 自检模板

```
地图/定位改动：
源路由：（是否按数据 country 决策，非 IP/系统区域）
flavor：（cn 是否只用高德、未引入 Google SDK）
坐标：（顺序对不对 / 是否处理 GCJ-02↔WGS-84）
key 安全：（服务端 key 是否只在后端 / 前端 key 是否配安全域名）
中转：（Google 在华是否走海外节点）
定位权限：（是否按需申请 / 是否有拒绝兜底）
```

## 参考

- 配套 skill：`cn-android-flavor`（禁 Google → 高德唯一）、`overseas-android-google-play`（Google/Mapbox）、`nestjs-backend-conventions`（代理端点/env）、`flutter-coding-conventions` §18（条件加载工厂）、`flutter-testing` §6（flavor 守卫）
- 高德开放平台：https://lbs.amap.com/
- Google Maps Platform：https://developers.google.com/maps
- Mapbox：https://docs.mapbox.com/
- gcoord（坐标转换）：https://github.com/hujiulong/gcoord

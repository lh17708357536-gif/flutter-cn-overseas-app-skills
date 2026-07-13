import 'package:dio/dio.dart';

import '../../core/config/flavor_config.dart';

/// 健康检查 API 客户端 —— 演示"后端地址走 FlavorConfig，不硬编码"。
class HealthApi {
  HealthApi({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 请求后端 `/api/v1/health`，返回原始 JSON Map。
  ///
  /// 基址来自 [FlavorConfig.apiBaseUrl]（可被 --dart-define=API_BASE_URL 覆盖）。
  Future<Map<String, dynamic>> fetchHealth() async {
    final url = '${FlavorConfig.apiBaseUrl}/api/v1/health';
    final resp = await _dio.get<Map<String, dynamic>>(url);
    return resp.data ?? <String, dynamic>{};
  }
}

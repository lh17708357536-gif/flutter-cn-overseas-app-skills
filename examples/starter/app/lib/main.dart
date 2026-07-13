import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/flavor_config.dart';
import 'core/config/push_service_factory.dart';
import 'data/services/health_api.dart';

void main() {
  runApp(const ProviderScope(child: StarterApp()));
}

/// 应用根组件。
class StarterApp extends StatelessWidget {
  const StarterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '三 Flavor Starter',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

/// 首页：展示当前 Flavor、推送供应商，并可点击调后端健康检查。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 按当前 Flavor 装配的推送服务（stub）。
  final PushService _push = createPushService();
  final HealthApi _healthApi = HealthApi();

  String _healthText = '（未请求）';
  bool _loading = false;

  /// 请求后端健康检查并显示返回的 status。
  Future<void> _checkHealth() async {
    setState(() {
      _loading = true;
      _healthText = '请求中…';
    });
    try {
      final data = await _healthApi.fetchHealth();
      final status = data['status'] ?? data.toString();
      if (!mounted) return;
      setState(() => _healthText = 'status: $status');
    } catch (e) {
      if (!mounted) return;
      setState(() => _healthText = '请求失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('三 Flavor Starter')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _InfoRow(label: '当前 Flavor', value: FlavorConfig.current.name),
              const SizedBox(height: 8),
              _InfoRow(label: '推送供应商', value: _push.providerName),
              const SizedBox(height: 8),
              _InfoRow(label: '后端基址', value: FlavorConfig.apiBaseUrl),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _checkHealth,
                child: const Text('调用后端健康检查'),
              ),
              const SizedBox(height: 16),
              Text(_healthText, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一行"标签：值"展示。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$label：', style: const TextStyle(fontWeight: FontWeight.bold)),
        Flexible(child: Text(value)),
      ],
    );
  }
}

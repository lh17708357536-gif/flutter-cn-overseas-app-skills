// 最小冒烟测试：验证首页能渲染并显示关键信息。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:starter_app/main.dart';

void main() {
  testWidgets('首页显示当前 Flavor 与推送供应商', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: StarterApp()));

    // 标题与关键标签存在。
    expect(find.text('三 Flavor Starter'), findsWidgets);
    expect(find.textContaining('当前 Flavor'), findsOneWidget);
    expect(find.textContaining('推送供应商'), findsOneWidget);

    // 健康检查按钮存在。
    expect(find.text('调用后端健康检查'), findsOneWidget);
  });
}

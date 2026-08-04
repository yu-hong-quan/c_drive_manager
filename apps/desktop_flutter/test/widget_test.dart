import 'package:c_drive_manager/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows shell and switches feature pages', (tester) async {
    // The desktop app uses a fixed design window, so widget tests should render
    // against that same canvas instead of Flutter test's narrow default size.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 860);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const CDriveManagerApp());

    expect(find.text('C 盘管家'), findsOneWidget);
    expect(find.text('C 盘空间一目了然'), findsOneWidget);
    expect(find.text('开始扫描'), findsOneWidget);
    expect(find.text('清理计划'), findsOneWidget);

    await tester.tap(find.text('微信专清'));
    // 账号发现会跑异步 Process/文件系统，这里推进几帧即可看到页面骨架。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('微信专清'), findsWidgets);
    expect(find.text('预计可释放'), findsOneWidget);

    await tester.tap(find.text('隔离区'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('隔离占用'), findsOneWidget);
    expect(find.text('隔离记录'), findsOneWidget);
  });
}

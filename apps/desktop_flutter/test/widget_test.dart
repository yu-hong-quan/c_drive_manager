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

    expect(find.text('C盘管家'), findsOneWidget);
    expect(find.text('C 盘空间一目了然'), findsOneWidget);
    expect(find.text('开始安全扫描'), findsOneWidget);
    expect(find.text('系统临时文件'), findsOneWidget);

    await tester.tap(find.text('微信专清'));
    await tester.pumpAndSettle();

    expect(find.text('微信专清'), findsWidgets);
    expect(find.text('预计释放'), findsOneWidget);
  });
}

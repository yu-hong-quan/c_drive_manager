import 'package:c_drive_manager/src/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows shell and switches feature pages', (tester) async {
    await tester.pumpWidget(const CDriveManagerApp());

    expect(find.text('C盘管家'), findsOneWidget);
    expect(find.text('C 盘空间一目了然'), findsOneWidget);

    await tester.tap(find.text('微信专清'));
    await tester.pumpAndSettle();

    expect(find.text('微信专清'), findsWidgets);
    expect(find.text('预计释放'), findsOneWidget);
  });
}

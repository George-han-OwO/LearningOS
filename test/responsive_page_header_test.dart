import 'package:ai_study_os/design/app_theme.dart';
import 'package:ai_study_os/design/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long Library title keeps a readable width on a 320dp phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      CupertinoApp(
        theme: buildCupertinoTheme(),
        home: const AppPage(
          title: 'Georgehan Library',
          subtitle: '2 篇 Note · ChatGPT / 录音豆 / Outlook / QQ',
          actions: [Text('导出'), Text('Obsidian'), Text('手动补录'), Text('新建')],
          mobileActions: [Text('更多'), Text('新建')],
          child: SizedBox(height: 300),
        ),
      ),
    );
    await tester.pump();

    final titleSize = tester.getSize(find.text('Georgehan Library'));
    expect(titleSize.width, greaterThan(240));
    expect(titleSize.height, lessThan(80));
    expect(find.text('更多'), findsOneWidget);
    expect(find.text('手动补录'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

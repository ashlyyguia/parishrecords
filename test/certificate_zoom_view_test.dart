import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/screens/records/certificate_zoom_view.dart';

void main() {
  testWidgets('zoom in/out, fit and full screen controls', (tester) async {
    var fullscreen = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CertificateZoomView(
          aspectRatio: 148 / 210,
          pageBuilder: (_) => const ColoredBox(color: Colors.white),
          onFullscreen: () => fullscreen++,
        ),
      ),
    ));
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.zoom_in));
    await tester.pump();
    expect(find.text('125%'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.zoom_in));
    await tester.pump();
    expect(find.text('156%'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.zoom_out));
    await tester.pump();
    expect(find.text('125%'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.fit_screen_outlined));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.fullscreen));
    expect(fullscreen, 1);
  });
}

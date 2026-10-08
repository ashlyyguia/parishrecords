import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:parishrecord/widgets/ocr_scanning_view.dart';

/// Renders the OCR loading view (with a synthetic ruled "register" image) to
/// build/ocr_scanning_preview.png for a visual check, and checks the stage
/// text advances.
void main() {
  Uint8List fakeRegister() {
    final im = img.Image(width: 1600, height: 900);
    img.fill(im, color: img.ColorRgb8(236, 232, 222));
    for (var y = 120; y < 860; y += 30) {
      img.drawLine(im, x1: 60, y1: y, x2: 1540, y2: y, color: img.ColorRgb8(90, 90, 110));
    }
    for (final x in [60, 140, 420, 640, 790, 800, 960, 1130, 1350, 1540]) {
      img.drawLine(im, x1: x, y1: 120, x2: x, y2: 850, color: img.ColorRgb8(90, 90, 110));
    }
    return Uint8List.fromList(img.encodePng(im));
  }

  testWidgets('scanning view renders and steps through stages', (tester) async {
    final font = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await font.load();

    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    final bytes = fakeRegister();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: OcrScanningView(bytes: bytes, title: 'Reading the baptismal register…'),
        ),
      ),
    ));
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(OcrScanningView));
      await precacheImage(MemoryImage(bytes), ctx);
      await precacheImage(ResizeImage(MemoryImage(bytes), width: 1400), ctx);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 4200)); // sweep mid-way, stage 2
    expect(find.text('Reading the baptismal register…'), findsOneWidget);
    expect(find.text(OcrScanningView.defaultStages[1]), findsOneWidget);

    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build').createSync(recursive: true);
      File('build/ocr_scanning_preview.png').writeAsBytesSync(png!.buffer.asUint8List());
    });

    await tester.pumpWidget(const SizedBox()); // dispose timers
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin records page points Add Record (OCR) at the new route', () async {
    final source = await _read('lib/screens/admin/pages/records_page.dart');
    expect(
      source,
      contains("onPressed: () => context.push('/admin/records/ocr-baptism'),"),
    );
    expect(source, contains('Add Record (OCR)'));
  });

  test('router registers the new baptismal OCR route', () async {
    final source = await _read('lib/app/router.dart');
    expect(source, contains("path: '/admin/records/ocr-baptism'"));
    expect(
      source,
      contains(
        "builder: (context, state) => const BaptismalOcrScanPage(),",
      ),
    );
  });

  test('the legacy staff and admin OCR upload routes are left intact', () async {
    final source = await _read('lib/app/router.dart');
    expect(source, contains("path: '/staff/ocr/upload'"));
    expect(source, contains("path: '/admin/ocr/upload'"));
    expect(source, contains("builder: (context, state) => const StaffOcrUploadPage(),"));
  });
}

Future<String> _read(String path) async => File(path).readAsString();

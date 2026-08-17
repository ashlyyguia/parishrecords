import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/dev/ocr_fixture_dump.dart';
import 'package:parishrecord/services/register_ocr_scan_helper.dart';

void main() {
  test('buildFixtureJson emits schema-correct JSON', () {
    final json = buildFixtureJson(
      image: 'sample.jpg',
      recordType: 'baptism',
      page: 'left',
      flatText: 'hello',
      cells: const [
        OcrLineBox(text: '1', top: 100, left: 10, width: 15, height: 20),
      ],
    );
    final map = jsonDecode(json) as Map<String, dynamic>;
    expect(map['image'], 'sample.jpg');
    expect(map['recordType'], 'baptism');
    expect(map['page'], 'left');
    expect(map['flatText'], 'hello');
    expect(map['capturedWith'], 'mlkit-latin');
    expect((map['cells'] as List).first['text'], '1');
  });
}

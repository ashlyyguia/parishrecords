import 'package:flutter_test/flutter_test.dart';
import 'package:parishrecord/services/cloud_ocr_service.dart';

void main() {
  test('fromResponseJson maps data.cells to OcrLineBox list', () {
    final json = {
      'success': true,
      'data': {
        'text': 'ALBERTO',
        'cells': [
          {'text': 'ALBERTO', 'left': 120, 'top': 100, 'width': 80, 'height': 20},
        ],
      },
    };
    final r = CloudOcrResult.fromResponseJson(json)!;
    expect(r.text, 'ALBERTO');
    expect(r.cells, hasLength(1));
    expect(r.cells.first.text, 'ALBERTO');
    expect(r.cells.first.left, 120);
  });

  test('returns null when success is not true or data missing', () {
    expect(CloudOcrResult.fromResponseJson({'success': false}), isNull);
    expect(CloudOcrResult.fromResponseJson({'success': true}), isNull);
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:parishrecord/services/marriage_ocr_service.dart';

void main() {
  test('parses rows into RegisterMarriageEntry list', () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'scanId': 's1',
              'rotation': 0,
              'warnings': ['CONFIDENCE_UNAVAILABLE'],
              'rows': [
                {
                  'lineNo': '1',
                  'groom': {'name': 'M'},
                  'bride': {'name': 'A'},
                  'dateOfMarriage': '1994',
                },
              ],
            },
          }),
          200,
        ));
    final svc = MarriageOcrService(client: client);
    final scan = await svc.scan(scanId: 's1', bytes: Uint8List(3), idToken: 'tok');
    expect(scan.entries, hasLength(1));
    expect(scan.entries.first.groom.name, 'M');
    expect(scan.entries.first.bride.name, 'A');
    expect(scan.scanId, 's1');
    expect(scan.warnings, contains('CONFIDENCE_UNAVAILABLE'));
  });

  test('posts to the marriage scan URL', () async {
    late Uri calledUri;
    final client = MockClient((req) async {
      calledUri = req.url;
      return http.Response(
        jsonEncode({'success': true, 'data': {'scanId': 's1', 'rotation': 0, 'warnings': [], 'rows': []}}),
        200,
      );
    });
    await MarriageOcrService(client: client).scan(scanId: 's1', bytes: Uint8List(3), idToken: 'tok');
    expect(calledUri.path, endsWith('/ocr/marriage/scan'));
  });

  test('maps a SPREAD_UNREADABLE refusal to differentImage recovery', () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({'success': false, 'code': 'SPREAD_UNREADABLE', 'message': 'retake', 'detail': 'left page'}),
          422,
        ));
    final svc = MarriageOcrService(client: client);
    try {
      await svc.scan(scanId: 's1', bytes: Uint8List(3), idToken: 'tok');
      fail('expected a failure');
    } on MarriageOcrFailure catch (e) {
      expect(e.code, 'SPREAD_UNREADABLE');
      expect(e.recovery, OcrRecovery.differentImage);
      expect(e.detail, 'left page');
    }
  });
}
